package statussource

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
)

type privateBus struct {
	address string
	cmd     *exec.Cmd
}

func startBus(t *testing.T, address string) *privateBus {
	t.Helper()
	if _, err := exec.LookPath("dbus-daemon"); err != nil {
		t.Skip("dbus-daemon required for private-bus integration tests")
	}
	if address == "" {
		dir, err := os.MkdirTemp("", "zelbar-bus-")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.RemoveAll(dir) })
		address = "unix:path=" + filepath.Join(dir, "bus")
	}
	cmd := exec.Command("dbus-daemon", "--config-file=testdata/dbus.conf", "--nofork", "--nopidfile", "--print-address=1", "--address="+address)
	cmd.Stderr = os.Stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	b := &privateBus{address: address, cmd: cmd}
	t.Cleanup(func() { b.stop() })
	line, err := bufio.NewReader(stdout).ReadString('\n')
	if err != nil {
		t.Fatalf("dbus startup: %v (%s)", err, line)
	}
	return b
}
func (b *privateBus) stop() {
	if b.cmd != nil {
		_ = b.cmd.Process.Kill()
		_ = b.cmd.Wait()
		b.cmd = nil
	}
}

type fakeProperties struct {
	mu            sync.Mutex
	values        map[string]map[string]dbus.Variant
	calls         int
	gate, entered chan struct{}
}

func (p *fakeProperties) Get(iface, name string) (dbus.Variant, *dbus.Error) {
	p.mu.Lock()
	v, ok := p.values[iface][name]
	p.calls++
	gate, entered := p.gate, p.entered
	p.gate, p.entered = nil, nil
	p.mu.Unlock()
	if entered != nil {
		close(entered)
		<-gate
	}
	if !ok {
		return dbus.Variant{}, dbus.NewError("org.freedesktop.DBus.Error.UnknownProperty", []any{name})
	}
	return v, nil
}

func (p *fakeProperties) put(iface, name string, v any) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.values[iface] == nil {
		p.values[iface] = make(map[string]dbus.Variant)
	}
	p.values[iface][name] = dbus.MakeVariant(v)
}
func (p *fakeProperties) count() int { p.mu.Lock(); defer p.mu.Unlock(); return p.calls }

func fakeService(t *testing.T, b *privateBus, name string) *dbus.Conn {
	t.Helper()
	c, err := dbus.Connect(b.address)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = c.Close() })
	reply, err := c.RequestName(name, dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		t.Fatalf("request name: %v/%v", reply, err)
	}
	return c
}

func fakeObject(t *testing.T, c *dbus.Conn, path dbus.ObjectPath, iface string, values map[string]any) *fakeProperties {
	t.Helper()
	p := &fakeProperties{values: make(map[string]map[string]dbus.Variant)}
	for name, v := range values {
		p.put(iface, name, v)
	}
	if err := c.Export(p, path, properties); err != nil {
		t.Fatal(err)
	}
	return p
}

func change(t *testing.T, c *dbus.Conn, p *fakeProperties, path dbus.ObjectPath, iface, name string, value any, invalid bool) {
	t.Helper()
	p.put(iface, name, value)
	values := map[string]dbus.Variant{}
	invalidated := []string{}
	if invalid {
		invalidated = append(invalidated, name)
	} else {
		values[name] = dbus.MakeVariant(value)
	}
	if err := c.Emit(path, properties+".PropertiesChanged", iface, values, invalidated); err != nil {
		t.Fatal(err)
	}
}

func runBusSource(t *testing.T, b *privateBus, s *busSource) *eventSink {
	t.Helper()
	s.address = b.address
	s.retry = 20 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	sink := &eventSink{events: make(chan engine.Event, 128)}
	done := make(chan error, 1)
	go func() { done <- s.Run(ctx, sink) }()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			if !errors.Is(err, context.Canceled) {
				t.Errorf("source exit: %v", err)
			}
		case <-time.After(time.Second):
			t.Error("source cancellation leaked")
		}
	})
	return sink
}

func expectValue(t *testing.T, sink *eventSink, field model.Field, value string) engine.Event {
	t.Helper()
	e := nextEvent(t, sink)
	if e.Update == nil || e.Update.Key() != model.FieldUpdate(field, "").Key() || eventValue(e, field) != value {
		t.Fatalf("event = %+v value %q, want %v=%q", e, eventValue(e, field), field, value)
	}
	return e
}

func quiet(t *testing.T, sink *eventSink) {
	t.Helper()
	select {
	case e := <-sink.events:
		t.Fatalf("unexpected event %+v", e)
	case <-time.After(70 * time.Millisecond):
	}
}

func TestDBusPowerTransitionsRecovery(t *testing.T) {
	b := startBus(t, "")
	c := fakeService(t, b, powerService)
	p := fakeObject(t, c, powerPath, powerService, map[string]any{"ActiveProfile": "power-saver"})
	sink := runBusSource(t, b, NewPowerSaver().(*busSource))
	expectValue(t, sink, model.FieldPowerSaver, "POWER SAVER")
	initial := p.count()
	quiet(t, sink)
	if p.count() != initial {
		t.Fatal("healthy polling")
	}
	change(t, c, p, powerPath, powerService, "ActiveProfile", "power-saver", false)
	quiet(t, sink)
	change(t, c, p, powerPath, powerService, "ActiveProfile", "balanced", true)
	expectValue(t, sink, model.FieldPowerSaver, "")
	change(t, c, p, powerPath, powerService, "ActiveProfile", "performance", false)
	quiet(t, sink)
	change(t, c, p, powerPath, powerService, "ActiveProfile", "power-saver", false)
	expectValue(t, sink, model.FieldPowerSaver, "POWER SAVER")
	if _, err := c.ReleaseName(powerService); err != nil {
		t.Fatal(err)
	}
	e := expectValue(t, sink, model.FieldPowerSaver, "")
	if e.Warning == nil || e.Warning.Class != engine.Nonfatal {
		t.Fatal("owner loss must warn nonfatally")
	}
	quiet(t, sink)
	if _, err := c.RequestName(powerService, dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
	expectValue(t, sink, model.FieldPowerSaver, "POWER SAVER")
	change(t, c, p, powerPath, powerService, "ActiveProfile", uint32(1), false)
	e = expectValue(t, sink, model.FieldPowerSaver, "")
	if e.Warning != nil {
		t.Fatal("warning was not throttled")
	}
	change(t, c, p, powerPath, powerService, "ActiveProfile", "power-saver", true)
	expectValue(t, sink, model.FieldPowerSaver, "POWER SAVER")
	b.stop()
	expectValue(t, sink, model.FieldPowerSaver, "")
	b2 := startBus(t, b.address)
	c2 := fakeService(t, b2, powerService)
	fakeObject(t, c2, powerPath, powerService, map[string]any{"ActiveProfile": "power-saver"})
	expectValue(t, sink, model.FieldPowerSaver, "POWER SAVER")
}

func TestDBusReadSignalRace(t *testing.T) {
	b := startBus(t, "")
	c := fakeService(t, b, powerService)
	p := fakeObject(t, c, powerPath, powerService, map[string]any{"ActiveProfile": "balanced"})
	gate, entered := make(chan struct{}), make(chan struct{})
	p.mu.Lock()
	p.gate, p.entered = gate, entered
	p.mu.Unlock()
	sink := runBusSource(t, b, NewPowerSaver().(*busSource))
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("initial Get missing")
	}
	change(t, c, p, powerPath, powerService, "ActiveProfile", "power-saver", true)
	// The signal is sent on the same service connection before releasing the old reply.
	close(gate)
	expectValue(t, sink, model.FieldPowerSaver, "POWER SAVER")
	quiet(t, sink)
}

func TestDBusWireGuard(t *testing.T) {
	b := startBus(t, "")
	c := fakeService(t, b, nmService)
	a, z := dbus.ObjectPath("/ac/a"), dbus.ObjectPath("/ac/z")
	root := fakeObject(t, c, nmPath, nmService, map[string]any{"ActiveConnections": []dbus.ObjectPath{z, a}})
	p := fakeObject(t, c, a, nmActive, map[string]any{"Type": "wireguard", "State": uint32(1), "Connection": dbus.ObjectPath("/settings/a")})
	q := fakeObject(t, c, z, nmActive, map[string]any{"Type": "wireguard", "State": uint32(2), "Connection": dbus.ObjectPath("/settings/z")})
	fakeNetworkSettings(t, c, "/settings/a", "alpha: work")
	profile := fakeNetworkSettings(t, c, "/settings/z", "zeta")
	s := &busSource{service: nmService, failure: map[model.Field]string{model.FieldWireGuard: ""}, snapshot: wireGuardSnapshot}
	sink := runBusSource(t, b, s)
	expectValue(t, sink, model.FieldWireGuard, "zeta")
	change(t, c, p, a, nmActive, "State", uint32(2), false)
	expectValue(t, sink, model.FieldWireGuard, "alpha: work | zeta")
	profile.put("connection", "id", "beta")
	if err := c.Emit("/settings/z", nmSettings+".Updated"); err != nil {
		t.Fatal(err)
	}
	expectValue(t, sink, model.FieldWireGuard, "alpha: work | beta")
	change(t, c, p, a, nmActive, "State", uint32(3), false)
	expectValue(t, sink, model.FieldWireGuard, "beta")
	change(t, c, q, z, nmActive, "Type", "vpn", false)
	expectValue(t, sink, model.FieldWireGuard, "")
	change(t, c, root, nmPath, nmService, "ActiveConnections", []dbus.ObjectPath{}, true)
	quiet(t, sink)
	if _, err := c.ReleaseName(nmService); err != nil {
		t.Fatal(err)
	}
	e := nextEvent(t, sink)
	if e.Warning == nil {
		t.Fatal("missing loss warning")
	}
	q.put(nmActive, "Type", "wireguard")
	root.put(nmService, "ActiveConnections", []dbus.ObjectPath{z})
	if _, err := c.RequestName(nmService, dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
	expectValue(t, sink, model.FieldWireGuard, "beta")
}

func TestDBusBadInitialProfile(t *testing.T) {
	for _, value := range []any{"", "unexpected", uint32(2)} {
		t.Run(fmt.Sprint(value), func(t *testing.T) {
			b := startBus(t, "")
			c := fakeService(t, b, powerService)
			fakeObject(t, c, powerPath, powerService, map[string]any{"ActiveProfile": value})
			e := expectValue(t, runBusSource(t, b, NewPowerSaver().(*busSource)), model.FieldPowerSaver, "")
			if e.Warning == nil {
				t.Fatal("missing invalid profile warning")
			}
		})
	}
}

func TestDBusInitiallyUnavailable(t *testing.T) {
	b := startBus(t, "")
	sink := runBusSource(t, b, NewPowerSaver().(*busSource))
	if e := expectValue(t, sink, model.FieldPowerSaver, ""); e.Warning == nil {
		t.Fatal("missing service must warn")
	}
	c := fakeService(t, b, powerService)
	fakeObject(t, c, powerPath, powerService, map[string]any{"ActiveProfile": "power-saver"})
	expectValue(t, sink, model.FieldPowerSaver, "POWER SAVER")
}

func TestDBusSignalMailboxIsBounded(t *testing.T) {
	key := propertyKey{powerPath, powerService, "ActiveProfile"}
	h := &busSignals{owner: ":1.1", watch: map[propertyKey]watchedProperty{key: {signature: "s"}}, wake: make(chan struct{}, 1)}
	signal := &dbus.Signal{Sender: h.owner, Path: powerPath, Name: properties + ".PropertiesChanged",
		Body: []any{powerService, map[string]dbus.Variant{"ActiveProfile": dbus.MakeVariant("balanced")}, []string{}}}
	for range 10000 {
		h.DeliverSignal("", "", signal)
	}
	if len(h.watch) != 1 || len(h.wake) != 1 || !h.watch[key].dirty || h.err != nil {
		t.Fatalf("signals did not coalesce: %+v", h)
	}
	signal.Body = []any{powerService, "wrong signature", []string{}}
	h.DeliverSignal("", "", signal)
	if h.err == nil {
		t.Fatal("malformed PropertiesChanged was accepted")
	}
}
