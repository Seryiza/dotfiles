package statussource

import (
	"fmt"
	"net/netip"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/godbus/dbus/v5"
	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
)

const powerService = "org.freedesktop.UPower.PowerProfiles"
const powerPath dbus.ObjectPath = "/org/freedesktop/UPower/PowerProfiles"
const nmService = "org.freedesktop.NetworkManager"
const nmPath dbus.ObjectPath = "/org/freedesktop/NetworkManager"
const nmActive = nmService + ".Connection.Active"
const nmSettings = nmService + ".Settings.Connection"
const nmDevice = nmService + ".Device"
const nmWireless = nmDevice + ".Wireless"
const nmAP = nmService + ".AccessPoint"

func NewPowerSaver() engine.Source {
	return &busSource{service: powerService, failure: map[model.Field]string{model.FieldPowerSaver: ""}, snapshot: func(r *busReader) map[model.Field]string {
		profile := busProperty[string](r, powerPath, powerService, "ActiveProfile")
		value := ""
		switch profile {
		case "power-saver":
			value = "POWER SAVER"
		case "balanced", "performance":
		default:
			if r.err == nil {
				r.err = fmt.Errorf("unexpected power profile %q", profile)
			}
		}
		return map[model.Field]string{model.FieldPowerSaver: value}
	}}
}

func wireGuardSnapshot(r *busReader) map[model.Field]string {
	names := []string{}
	for _, path := range busProperty[[]dbus.ObjectPath](r, nmPath, nmService, "ActiveConnections") {
		kind := busProperty[string](r, path, nmActive, "Type")
		if kind != "wireguard" {
			continue
		}
		state := busProperty[uint32](r, path, nmActive, "State")
		if state > 4 && r.err == nil {
			r.err = fmt.Errorf("invalid active connection state %d", state)
		}
		if state == 2 {
			settingsPath := busProperty[dbus.ObjectPath](r, path, nmActive, "Connection")
			settings := busProperty[map[string]map[string]dbus.Variant](r, settingsPath, nmSettings, "")
			id := settings["connection"]["id"]
			name, ok := id.Value().(string)
			if (!ok || id.Signature().String() != "s" || name == "" || !utf8.ValidString(name)) && r.err == nil {
				r.err = fmt.Errorf("invalid WireGuard profile name at %s", settingsPath)
			}
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return map[model.Field]string{model.FieldWireGuard: strings.Join(names, " | ")}
}

func NewNetworkManager() engine.Source {
	return &busSource{
		service: nmService,
		failure: map[model.Field]string{model.FieldNetwork: "network?", model.FieldWireGuard: ""},
		snapshot: func(r *busReader) map[model.Field]string {
			values := wireGuardSnapshot(r)
			values[model.FieldNetwork] = networkSnapshot(r)
			return values
		},
	}
}

// AddressData is aa{sv}; validate every entry, not just the first address.
func networkAddresses(r *busReader, path dbus.ObjectPath, ipv6 bool) int {
	if path == "/" || r.err != nil {
		return 0
	}
	iface, bits := nmService+".IP4Config", uint32(32)
	if ipv6 {
		iface, bits = nmService+".IP6Config", 128
	}
	addresses := busProperty[[]map[string]dbus.Variant](r, path, iface, "AddressData")
	for _, entry := range addresses {
		address, a := entry["address"].Value().(string)
		prefix, p := entry["prefix"].Value().(uint32)
		ip, err := netip.ParseAddr(address)
		if !a || !p || entry["address"].Signature().String() != "s" || entry["prefix"].Signature().String() != "u" || prefix > bits || err != nil || ip.Is4() == ipv6 || ip.Zone() != "" {
			if r.err == nil {
				r.err = fmt.Errorf("invalid %s AddressData at %s", iface, path)
			}
			return 0
		}
	}
	return len(addresses)
}

func networkSnapshot(r *busReader) string {
	paths := busProperty[[]dbus.ObjectPath](r, nmPath, nmService, "Devices")
	wireless := busProperty[bool](r, nmPath, nmService, "WirelessEnabled")
	hardware := busProperty[bool](r, nmPath, nmService, "WirelessHardwareEnabled")
	if len(paths) == 0 && r.err == nil {
		r.err = fmt.Errorf("empty device status")
	}
	type device struct {
		path dbus.ObjectPath
		name string
		kind uint32
		rank [8]int
	}
	var devices []device
	for _, path := range paths {
		kind := busProperty[uint32](r, path, nmDevice, "DeviceType")
		state := busProperty[uint32](r, path, nmDevice, "State")
		name := busProperty[string](r, path, nmDevice, "Interface")
		if (state > 120 || state%10 != 0 || name == "") && r.err == nil {
			r.err = fmt.Errorf("invalid device state/interface at %s", path)
		}
		if (kind != 1 && kind != 2) || state < 40 || state > 100 {
			continue
		}
		d := device{path: path, name: name, kind: kind, rank: [8]int{-10, 0, 0, 0, 0, 0, 0, int(state)}}
		ac := busProperty[dbus.ObjectPath](r, path, nmDevice, "ActiveConnection")
		if ac != "/" && r.err == nil {
			state := busProperty[uint32](r, ac, nmActive, "State")
			flags := busProperty[uint32](r, ac, nmActive, "StateFlags")
			if state > 4 {
				r.err = fmt.Errorf("invalid active connection state %d", state)
				return "network?"
			}
			d.rank[0] = [5]int{0, 3, 4, 2, 1}[state]
			if flags&128 == 0 { // NM_ACTIVATION_STATE_FLAG_EXTERNAL
				d.rank[0] += 5
			}
			profile := busProperty[dbus.ObjectPath](r, ac, nmActive, "Connection")
			if profile != "/" {
				settings := busProperty[map[string]map[string]dbus.Variant](r, profile, nmSettings, "")
				for i, family := range []string{"ipv6", "ipv4"} {
					if v, exists := settings[family]["method"]; exists {
						method, ok := v.Value().(string)
						if (!ok || v.Signature().String() != "s") && r.err == nil {
							r.err = fmt.Errorf("invalid %s method at %s", family, profile)
						}
						if method == "shared" {
							d.rank[i+1] = 1
						}
					}
				}
			}
			for i, name := range []string{"Vpn", "Default", "Default6"} {
				if busProperty[bool](r, ac, nmActive, name) {
					d.rank[i+3] = 1
				}
			}
			ip4 := busProperty[dbus.ObjectPath](r, ac, nmActive, "Ip4Config")
			ip6 := busProperty[dbus.ObjectPath](r, ac, nmActive, "Ip6Config")
			d.rank[6] = networkAddresses(r, ip4, false) + networkAddresses(r, ip6, true)
		}
		devices = append(devices, d)
	}
	// nmcli 1.56.0: devices.c compare_devices + connections.c nmc_active_connection_cmp.
	// Active state (including external), shared IPv6/IPv4, VPN, defaults, address
	// count, device state descending; type description, interface, path ascending.
	sort.Slice(devices, func(i, j int) bool {
		a, b := devices[i], devices[j]
		for k := range a.rank {
			if a.rank[k] != b.rank[k] {
				return a.rank[k] > b.rank[k]
			}
		}
		if a.kind != b.kind {
			return a.kind < b.kind // "ethernet" before "wifi"
		}
		if a.name != b.name {
			return a.name < b.name
		}
		return a.path < b.path
	})
	if r.err != nil {
		return "network?"
	}
	if len(devices) == 0 {
		if !wireless || !hardware {
			return "Wi-Fi disabled"
		}
		return "Disconnected"
	}
	d := devices[0]
	if d.kind == 2 && (!wireless || !hardware) {
		r.err = fmt.Errorf("Wi-Fi is connected while radio is disabled")
		return "network?"
	}
	ip4 := busProperty[dbus.ObjectPath](r, d.path, nmDevice, "Ip4Config")
	if networkAddresses(r, ip4, false) == 0 {
		return d.name + " (No IP)"
	}
	if d.kind == 2 {
		ap := busProperty[dbus.ObjectPath](r, d.path, nmWireless, "ActiveAccessPoint")
		if ap == "/" && r.err == nil {
			r.err = fmt.Errorf("active Wi-Fi access point is missing")
		}
		strength := busProperty[byte](r, ap, nmAP, "Strength")
		if strength > 100 && r.err == nil {
			r.err = fmt.Errorf("invalid Wi-Fi strength %d", strength)
		}
		if strength < 20 {
			return "<20% wlan"
		}
	}
	return ""
}
