package statussource

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"seryiza.local/river-zelbar-status/internal/model"
)

type fakeNMSettings struct{ *fakeProperties }

func (p *fakeNMSettings) GetSettings() (map[string]map[string]dbus.Variant, *dbus.Error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls++
	result := make(map[string]map[string]dbus.Variant)
	for section, values := range p.values {
		result[section] = make(map[string]dbus.Variant)
		for k, v := range values {
			result[section][k] = v
		}
	}
	return result, nil
}

func fakeNetworkSettings(t *testing.T, c *dbus.Conn, path dbus.ObjectPath, name string) *fakeNMSettings {
	t.Helper()
	p := &fakeNMSettings{&fakeProperties{values: make(map[string]map[string]dbus.Variant)}}
	p.put("connection", "id", name)
	if err := c.Export(p, path, nmSettings); err != nil {
		t.Fatal(err)
	}
	return p
}

func addressData(address string, prefix uint32) []map[string]dbus.Variant {
	return []map[string]dbus.Variant{{"address": dbus.MakeVariant(address), "prefix": dbus.MakeVariant(prefix)}}
}

func networkFixture(t *testing.T) (*privateBus, *dbus.Conn, *fakeProperties, *fakeProperties, *fakeProperties, *fakeProperties) {
	t.Helper()
	b := startBus(t, "")
	c := fakeService(t, b, nmService)
	root := fakeObject(t, c, nmPath, nmService, map[string]any{
		"Devices": []dbus.ObjectPath{"/dev/wlan"}, "ActiveConnections": []dbus.ObjectPath{},
		"WirelessEnabled": true, "WirelessHardwareEnabled": true,
	})
	dev := fakeObject(t, c, "/dev/wlan", nmDevice, map[string]any{
		"DeviceType": uint32(2), "State": uint32(100), "Interface": "wlan0",
		"ActiveConnection": dbus.ObjectPath("/"), "Ip4Config": dbus.ObjectPath("/ip/a"),
	})
	dev.put(nmWireless, "ActiveAccessPoint", dbus.ObjectPath("/ap/a"))
	ip := fakeObject(t, c, "/ip/a", nmService+".IP4Config", map[string]any{"AddressData": addressData("192.0.2.1", 24)})
	ap := fakeObject(t, c, "/ap/a", nmAP, map[string]any{"Strength": byte(19)})
	return b, c, root, dev, ip, ap
}

// The shared source publishes a map, so initial field order is unspecified.
func expectNetworkInitial(t *testing.T, sink *eventSink, network, wg string, warning bool) {
	t.Helper()
	want := map[model.Field]string{model.FieldNetwork: network, model.FieldWireGuard: wg}
	warned := false
	for range 2 {
		e := nextEvent(t, sink)
		warned = warned || e.Warning != nil
		found := false
		for field, value := range want {
			if e.Update != nil && e.Update.Key() == model.FieldUpdate(field, "").Key() {
				if eventValue(e, field) != value {
					t.Fatalf("field %v = %q, want %q", field, eventValue(e, field), value)
				}
				delete(want, field)
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("unexpected initial event %+v", e)
		}
	}
	if warned != warning {
		t.Fatalf("warning = %v, want %v", warned, warning)
	}
}

func TestDBusNetworkTransitions(t *testing.T) {
	b, c, root, dev, ip, ap := networkFixture(t)
	sink := runBusSource(t, b, NewNetworkManager().(*busSource))
	expectNetworkInitial(t, sink, "<20% wlan", "", false)
	initialRoot, initialDev, initialIP := root.count(), dev.count(), ip.count()
	change(t, c, ap, "/ap/a", nmAP, "Strength", byte(20), true)
	expectValue(t, sink, model.FieldNetwork, "")
	if root.count() != initialRoot || dev.count() != initialDev || ip.count() != initialIP {
		t.Fatal("strength change reread unrelated properties")
	}
	change(t, c, ap, "/ap/a", nmAP, "Strength", byte(100), false)
	quiet(t, sink)
	reads := ap.count()
	change(t, c, ap, "/ap/a", nmAP, "Frequency", uint32(5000), false)
	quiet(t, sink)
	if ap.count() != reads {
		t.Fatal("irrelevant signal caused reads")
	}
	change(t, c, ip, "/ip/a", nmService+".IP4Config", "AddressData", []map[string]dbus.Variant{}, true)
	expectValue(t, sink, model.FieldNetwork, "wlan0 (No IP)")
	change(t, c, dev, "/dev/wlan", nmDevice, "Interface", "wlan1", false)
	expectValue(t, sink, model.FieldNetwork, "wlan1 (No IP)")
	fakeObject(t, c, "/ip/b", nmService+".IP4Config", map[string]any{"AddressData": addressData("198.51.100.1", 32)})
	change(t, c, dev, "/dev/wlan", nmDevice, "Ip4Config", dbus.ObjectPath("/ip/b"), true)
	expectValue(t, sink, model.FieldNetwork, "")
	fakeObject(t, c, "/ap/b", nmAP, map[string]any{"Strength": byte(0)})
	change(t, c, dev, "/dev/wlan", nmWireless, "ActiveAccessPoint", dbus.ObjectPath("/ap/b"), true)
	expectValue(t, sink, model.FieldNetwork, "<20% wlan")
	reads = ap.count() + ip.count()
	change(t, c, ap, "/ap/a", nmAP, "Strength", "wrong but no longer watched", false)
	change(t, c, ip, "/ip/a", nmService+".IP4Config", "AddressData", "also irrelevant", false)
	quiet(t, sink)
	if ap.count()+ip.count() != reads {
		t.Fatal("removed dependency reread")
	}
	change(t, c, dev, "/dev/wlan", nmDevice, "State", uint32(30), false)
	expectValue(t, sink, model.FieldNetwork, "Disconnected")
	change(t, c, root, nmPath, nmService, "WirelessEnabled", false, true)
	expectValue(t, sink, model.FieldNetwork, "Wi-Fi disabled")
	change(t, c, root, nmPath, nmService, "WirelessEnabled", true, false)
	expectValue(t, sink, model.FieldNetwork, "Disconnected")
	change(t, c, root, nmPath, nmService, "WirelessHardwareEnabled", false, false)
	expectValue(t, sink, model.FieldNetwork, "Wi-Fi disabled")
	change(t, c, root, nmPath, nmService, "Devices", []dbus.ObjectPath{}, true)
	e := expectValue(t, sink, model.FieldNetwork, "network?")
	if e.Warning == nil {
		t.Fatal("empty list must warn")
	}
	change(t, c, root, nmPath, nmService, "Devices", []dbus.ObjectPath{"/dev/wlan"}, false)
	expectValue(t, sink, model.FieldNetwork, "Wi-Fi disabled")
}

func TestDBusNetworkSelection(t *testing.T) {
	b, c, root, dev, _, _ := networkFixture(t)
	eth := fakeObject(t, c, "/dev/eth", nmDevice, map[string]any{
		"DeviceType": uint32(1), "State": uint32(70), "Interface": "eth0",
		"ActiveConnection": dbus.ObjectPath("/"), "Ip4Config": dbus.ObjectPath("/"),
	})
	root.put(nmService, "Devices", []dbus.ObjectPath{"/dev/wlan", "/dev/eth"})
	sink := runBusSource(t, b, NewNetworkManager().(*busSource))
	expectNetworkInitial(t, sink, "<20% wlan", "", false)
	change(t, c, eth, "/dev/eth", nmDevice, "State", uint32(100), false)
	expectValue(t, sink, model.FieldNetwork, "eth0 (No IP)")
	change(t, c, eth, "/dev/eth", nmDevice, "Ip4Config", dbus.ObjectPath("/ip/a"), true)
	expectValue(t, sink, model.FieldNetwork, "")
	change(t, c, root, nmPath, nmService, "WirelessEnabled", false, false)
	quiet(t, sink) // Ethernet overrides disabled Wi-Fi.
	change(t, c, root, nmPath, nmService, "WirelessEnabled", true, false)
	quiet(t, sink)
	change(t, c, root, nmPath, nmService, "Devices", []dbus.ObjectPath{"/dev/wlan"}, false)
	expectValue(t, sink, model.FieldNetwork, "<20% wlan")
	change(t, c, dev, "/dev/wlan", nmDevice, "DeviceType", uint32(1), true)
	expectValue(t, sink, model.FieldNetwork, "")
	change(t, c, dev, "/dev/wlan", nmDevice, "Ip4Config", dbus.ObjectPath("/"), false)
	expectValue(t, sink, model.FieldNetwork, "wlan0 (No IP)")
	change(t, c, dev, "/dev/wlan", nmDevice, "State", uint32(70), false)
	quiet(t, sink) // Connecting without IPv4 retains the linked/no-IP state.
	change(t, c, dev, "/dev/wlan", nmDevice, "State", uint32(100), false)
	quiet(t, sink)
	eth.put(nmDevice, "Ip4Config", dbus.ObjectPath("/"))
	change(t, c, root, nmPath, nmService, "Devices", []dbus.ObjectPath{"/dev/wlan", "/dev/eth"}, false)
	expectValue(t, sink, model.FieldNetwork, "eth0 (No IP)")
	change(t, c, eth, "/dev/eth", nmDevice, "Interface", "zzz", false)
	expectValue(t, sink, model.FieldNetwork, "wlan0 (No IP)")
}

func TestDBusNetworkBadValues(t *testing.T) {
	for _, tc := range []struct {
		name, target, iface, property string
		value                         any
	}{
		{"devices type", "root", nmService, "Devices", []string{"/dev/wlan"}},
		{"empty devices", "root", nmService, "Devices", []dbus.ObjectPath{}},
		{"radio type", "root", nmService, "WirelessEnabled", "true"},
		{"hardware type", "root", nmService, "WirelessHardwareEnabled", uint32(1)},
		{"radio contradiction", "root", nmService, "WirelessEnabled", false},
		{"device type", "dev", nmDevice, "DeviceType", "wifi"},
		{"state type", "dev", nmDevice, "State", int32(100)},
		{"state range", "dev", nmDevice, "State", uint32(101)},
		{"interface empty", "dev", nmDevice, "Interface", ""},
		{"ip path type", "dev", nmDevice, "Ip4Config", "/ip/a"},
		{"ap path type", "dev", nmWireless, "ActiveAccessPoint", "/ap/a"},
		{"missing ap", "dev", nmWireless, "ActiveAccessPoint", dbus.ObjectPath("/")},
		{"strength type", "ap", nmAP, "Strength", uint32(10)},
		{"strength range", "ap", nmAP, "Strength", byte(101)},
		{"address data type", "ip", nmService + ".IP4Config", "AddressData", "192.0.2.1/24"},
		{"invalid address", "ip", nmService + ".IP4Config", "AddressData", addressData("bad", 24)},
		{"ipv6 in ipv4", "ip", nmService + ".IP4Config", "AddressData", addressData("::1", 24)},
		{"prefix range", "ip", nmService + ".IP4Config", "AddressData", addressData("192.0.2.1", 33)},
		{"missing prefix", "ip", nmService + ".IP4Config", "AddressData", []map[string]dbus.Variant{{"address": dbus.MakeVariant("192.0.2.1")}}},
		{"prefix type", "ip", nmService + ".IP4Config", "AddressData", []map[string]dbus.Variant{{"address": dbus.MakeVariant("192.0.2.1"), "prefix": dbus.MakeVariant(byte(24))}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b, _, root, dev, ip, ap := networkFixture(t)
			map[string]*fakeProperties{"root": root, "dev": dev, "ip": ip, "ap": ap}[tc.target].put(tc.iface, tc.property, tc.value)
			expectNetworkInitial(t, runBusSource(t, b, NewNetworkManager().(*busSource)), "network?", "", true)
		})
	}
}

func TestDBusNetworkProfileNames(t *testing.T) {
	b, c, root, _, _, _ := networkFixture(t)
	p := fakeNetworkSettings(t, c, "/settings/wg", "work: vpn")
	fakeObject(t, c, "/ac/wg", nmActive, map[string]any{
		"Type": "wireguard", "State": uint32(2), "Connection": dbus.ObjectPath("/settings/wg"), "Id": "stale name",
	})
	root.put(nmService, "ActiveConnections", []dbus.ObjectPath{"/ac/wg"})
	sink := runBusSource(t, b, NewNetworkManager().(*busSource))
	expectNetworkInitial(t, sink, "<20% wlan", "work: vpn", false)
	p.put("connection", "id", "renamed")
	if err := c.Emit("/settings/wg", nmSettings+".Updated"); err != nil {
		t.Fatal(err)
	}
	expectValue(t, sink, model.FieldWireGuard, "renamed")
	reads := p.count()
	if err := c.Emit("/settings/unrelated", nmSettings+".Updated"); err != nil {
		t.Fatal(err)
	}
	quiet(t, sink)
	if p.count() != reads {
		t.Fatal("unrelated settings update reread profile")
	}
	p.put("connection", "id", uint32(1))
	if err := c.Emit("/settings/wg", nmSettings+".Updated"); err != nil {
		t.Fatal(err)
	}
	expectNetworkInitial(t, sink, "network?", "", true)
	p.put("connection", "id", "recovered")
	if err := c.Emit("/settings/wg", nmSettings+".Updated"); err != nil {
		t.Fatal(err)
	}
	expectNetworkInitial(t, sink, "<20% wlan", "recovered", false)
}

func TestDBusNetworkBadSignalRecovery(t *testing.T) {
	b, c, _, _, _, ap := networkFixture(t)
	sink := runBusSource(t, b, NewNetworkManager().(*busSource))
	expectNetworkInitial(t, sink, "<20% wlan", "", false)
	change(t, c, ap, "/ap/a", nmAP, "Strength", uint32(20), false)
	if e := expectValue(t, sink, model.FieldNetwork, "network?"); e.Warning == nil {
		t.Fatal("bad signal must warn")
	}
	change(t, c, ap, "/ap/a", nmAP, "Strength", byte(20), true)
	expectValue(t, sink, model.FieldNetwork, "")
	quiet(t, sink)
}

func TestDBusNetworkNMCLIOrdering(t *testing.T) {
	for _, priority := range []string{"state", "external", "shared6", "shared4", "vpn", "default4", "default6", "addresses"} {
		t.Run(priority, func(t *testing.T) {
			b, c, root, wifi, _, _ := networkFixture(t)
			root.put(nmService, "Devices", []dbus.ObjectPath{"/dev/eth", "/dev/wlan"})
			fakeObject(t, c, "/dev/eth", nmDevice, map[string]any{
				"DeviceType": uint32(1), "State": uint32(100), "Interface": "eth0",
				"ActiveConnection": dbus.ObjectPath("/ac/eth"), "Ip4Config": dbus.ObjectPath("/"),
			})
			wifi.put(nmDevice, "ActiveConnection", dbus.ObjectPath("/ac/wifi"))
			acs := make(map[string]*fakeProperties)
			profiles := make(map[string]*fakeNMSettings)
			for _, name := range []string{"eth", "wifi"} {
				profiles[name] = fakeNetworkSettings(t, c, dbus.ObjectPath("/settings/"+name), name)
				acs[name] = fakeObject(t, c, dbus.ObjectPath("/ac/"+name), nmActive, map[string]any{
					"State": uint32(2), "StateFlags": uint32(0), "Connection": dbus.ObjectPath("/settings/" + name),
					"Vpn": false, "Default": false, "Default6": false,
					"Ip4Config": dbus.ObjectPath("/"), "Ip6Config": dbus.ObjectPath("/"),
				})
			}
			switch priority {
			case "state":
				acs["eth"].put(nmActive, "State", uint32(1))
			case "external":
				acs["eth"].put(nmActive, "StateFlags", uint32(128))
			case "shared6":
				profiles["wifi"].put("ipv6", "method", "shared")
			case "shared4":
				profiles["wifi"].put("ipv4", "method", "shared")
			case "vpn":
				acs["wifi"].put(nmActive, "Vpn", true)
			case "default4":
				acs["wifi"].put(nmActive, "Default", true)
			case "default6":
				acs["wifi"].put(nmActive, "Default6", true)
			case "addresses":
				acs["wifi"].put(nmActive, "Ip4Config", dbus.ObjectPath("/ip/a"))
			}
			sink := runBusSource(t, b, NewNetworkManager().(*busSource))
			expectNetworkInitial(t, sink, "<20% wlan", "", false)
			if priority == "default4" {
				change(t, c, acs["wifi"], "/ac/wifi", nmActive, "Default", false, true)
				expectValue(t, sink, model.FieldNetwork, "eth0 (No IP)")
				change(t, c, acs["wifi"], "/ac/wifi", nmActive, "Default", true, false)
				expectValue(t, sink, model.FieldNetwork, "<20% wlan")
			}
			if priority == "shared4" {
				profiles["wifi"].put("ipv4", "method", "auto")
				if err := c.Emit("/settings/wifi", nmSettings+".Updated"); err != nil {
					t.Fatal(err)
				}
				expectValue(t, sink, model.FieldNetwork, "eth0 (No IP)")
				profiles["wifi"].put("ipv4", "method", "shared")
				if err := c.Emit("/settings/wifi", nmSettings+".Updated"); err != nil {
					t.Fatal(err)
				}
				expectValue(t, sink, model.FieldNetwork, "<20% wlan")
			}
			// Changing membership discards all of the old device's dependencies.
			change(t, c, root, nmPath, nmService, "Devices", []dbus.ObjectPath{"/dev/eth"}, false)
			expectValue(t, sink, model.FieldNetwork, "eth0 (No IP)")
		})
	}
}
