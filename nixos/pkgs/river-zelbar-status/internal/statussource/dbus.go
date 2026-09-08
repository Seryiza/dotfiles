package statussource

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/godbus/dbus/v5"
	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
)

const properties = "org.freedesktop.DBus.Properties"
const maxWatchedProperties = 4096

type propertyKey struct {
	path        dbus.ObjectPath
	iface, name string
}

type watchedProperty struct {
	signature string
	dirty     bool
}

// godbus's default signal handler can spawn a goroutine per blocked delivery.
// This handler retains only dirty bits for watched properties and one wakeup.
type busSignals struct {
	mu             sync.Mutex
	service, owner string
	watch          map[propertyKey]watchedProperty
	generation     uint64
	err            error
	wake           chan struct{}
}

func (h *busSignals) DeliverSignal(_ string, _ string, s *dbus.Signal) {
	h.mu.Lock()
	defer h.mu.Unlock()
	changed := false
	if s.Sender == "org.freedesktop.DBus" && s.Path == "/org/freedesktop/DBus" && s.Name == "org.freedesktop.DBus.NameOwnerChanged" {
		if len(s.Body) != 3 {
			return
		}
		name, ok := s.Body[0].(string)
		if !ok || name != h.service {
			return
		}
		_, oldOK := s.Body[1].(string)
		_, newOK := s.Body[2].(string)
		if !oldOK || !newOK {
			h.err = errors.New("invalid NameOwnerChanged signature")
		} else {
			h.err = errors.New("service owner changed")
		}
		changed = true
	} else if h.owner != "" && s.Sender == h.owner {
		if s.Name == properties+".PropertiesChanged" {
			// Ignore malformed signals on objects we do not consume.
			watched := false
			for key := range h.watch {
				if key.path == s.Path {
					watched = true
					break
				}
			}
			if !watched {
				return
			}
			if len(s.Body) != 3 {
				h.err = errors.New("invalid PropertiesChanged signature")
				changed = true
			} else {
				iface, a := s.Body[0].(string)
				values, b := s.Body[1].(map[string]dbus.Variant)
				invalid, c := s.Body[2].([]string)
				if !a || !b || !c {
					h.err = errors.New("invalid PropertiesChanged signature")
					changed = true
				} else {
					for key, entry := range h.watch {
						if key.path != s.Path || key.iface != iface {
							continue
						}
						v, dirty := values[key.name]
						if dirty && v.Signature().String() != entry.signature {
							h.err = fmt.Errorf("invalid signal type for %s.%s", iface, key.name)
						}
						for _, name := range invalid {
							if name == key.name {
								dirty = true
							}
						}
						if dirty {
							entry.dirty = true
							h.watch[key] = entry
							changed = true
						}
					}
				}
			}
		} else if s.Name == nmSettings+".Updated" || s.Name == nmSettings+".Removed" {
			key := propertyKey{s.Path, nmSettings, ""}
			if entry, ok := h.watch[key]; ok {
				entry.dirty = true
				h.watch[key] = entry
				changed = true
			}
		}
	}
	if changed {
		h.generation++
		select {
		case h.wake <- struct{}{}:
		default:
		}
	}
}

type busReader struct {
	conn    *dbus.Conn
	signals *busSignals
	cache   map[propertyKey]dbus.Variant
	used    map[propertyKey]bool
	ctx     context.Context
	err     error
}

func (r *busReader) get(key propertyKey, signature string) dbus.Variant {
	if r.err != nil {
		return dbus.Variant{}
	}
	r.used[key] = true
	r.signals.mu.Lock()
	if _, ok := r.signals.watch[key]; !ok {
		if len(r.signals.watch) >= maxWatchedProperties {
			r.err = errors.New("D-Bus object graph exceeds property limit")
		} else {
			r.signals.watch[key] = watchedProperty{signature: signature}
		}
	}
	r.signals.mu.Unlock()
	if r.err != nil {
		return dbus.Variant{}
	}
	if v, ok := r.cache[key]; ok {
		return v
	}
	var v dbus.Variant
	if key.iface == nmSettings && key.name == "" {
		var settings map[string]map[string]dbus.Variant
		r.err = r.conn.Object(r.signals.owner, key.path).CallWithContext(r.ctx, nmSettings+".GetSettings", dbus.FlagNoAutoStart).Store(&settings)
		v = dbus.MakeVariant(settings)
	} else {
		r.err = r.conn.Object(r.signals.owner, key.path).CallWithContext(r.ctx, properties+".Get", dbus.FlagNoAutoStart, key.iface, key.name).Store(&v)
	}
	if r.err == nil && v.Signature().String() != signature {
		r.err = fmt.Errorf("%s %s.%s: signature %s, want %s", key.path, key.iface, key.name, v.Signature(), signature)
	}
	if r.err == nil {
		r.cache[key] = v
	}
	return v
}

func busProperty[T any](r *busReader, path dbus.ObjectPath, iface, name string) T {
	var zero T
	v := r.get(propertyKey{path, iface, name}, dbus.SignatureOf(zero).String())
	if r.err != nil {
		return zero
	}
	value, ok := v.Value().(T)
	if !ok {
		r.err = fmt.Errorf("invalid value for %s.%s", iface, name)
		return zero
	}
	switch p := any(value).(type) {
	case string:
		if !utf8.ValidString(p) {
			r.err = errors.New("D-Bus string is not valid UTF-8")
		}
	case dbus.ObjectPath:
		if !p.IsValid() {
			r.err = errors.New("invalid object path")
		}
	case []dbus.ObjectPath:
		if len(p) > maxWatchedProperties {
			r.err = errors.New("D-Bus object list exceeds limit")
			return zero
		}
		for _, path := range p {
			if !path.IsValid() || path == "/" {
				r.err = errors.New("invalid object list path")
			}
		}
	}
	return value
}

type busSource struct {
	service  string
	failure  map[model.Field]string
	snapshot func(*busReader) map[model.Field]string
	// An address is only injected by private-bus tests. Empty uses the system bus.
	address string
	retry   time.Duration
}

func (s *busSource) Run(ctx context.Context, sink engine.Sink) error {
	last := make(map[model.Field]string)
	lastWarning := time.Time{}
	publish := func(values map[model.Field]string, cause error) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		var warning *engine.Fault
		if cause != nil {
			warning = throttledNonfatal(s.service, cause, time.Now(), &lastWarning)
		}
		for field, value := range values {
			if previous, ok := last[field]; ok && previous == value {
				continue
			}
			update := model.FieldUpdate(field, value)
			if err := sink.Publish(ctx, engine.Event{Update: &update, Warning: warning}); err != nil {
				return err
			}
			warning = nil
			last[field] = value
		}
		if warning != nil {
			return sink.Publish(ctx, engine.Event{Warning: warning})
		}
		return nil
	}
	for ctx.Err() == nil {
		err := s.session(ctx, publish)
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err := publish(s.failure, err); err != nil {
			return err
		}
		delay := s.retry
		if delay == 0 {
			delay = time.Second
		}
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
	}
	return ctx.Err()
}

func (s *busSource) session(ctx context.Context, publish func(map[model.Field]string, error) error) error {
	h := &busSignals{service: s.service, watch: make(map[propertyKey]watchedProperty), wake: make(chan struct{}, 1)}
	connCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	// Bound authentication/Hello too; WithContext closes the transport on cancel.
	timer := time.AfterFunc(5*time.Second, cancel)
	opts := []dbus.ConnOption{dbus.WithContext(connCtx), dbus.WithSignalHandler(h)}
	var conn *dbus.Conn
	var err error
	if s.address == "" {
		conn, err = dbus.ConnectSystemBus(opts...)
	} else {
		conn, err = dbus.Connect(s.address, opts...)
	}
	timer.Stop()
	if err != nil {
		return err
	}
	// Private connection close removes all bus matches and the handler together.
	defer conn.Close()
	connCtx = conn.Context()
	setup, stop := context.WithTimeout(connCtx, 5*time.Second)
	defer stop()
	if err := conn.AddMatchSignalContext(setup, dbus.WithMatchSender("org.freedesktop.DBus"), dbus.WithMatchInterface("org.freedesktop.DBus"), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, s.service)); err != nil {
		return err
	}
	if err := conn.AddMatchSignalContext(setup, dbus.WithMatchSender(s.service), dbus.WithMatchInterface(properties), dbus.WithMatchMember("PropertiesChanged")); err != nil {
		return err
	}
	if s.service == nmService {
		if err := conn.AddMatchSignalContext(setup, dbus.WithMatchSender(s.service), dbus.WithMatchInterface(nmSettings)); err != nil {
			return err
		}
	}
	var owner string
	if err := conn.BusObject().CallWithContext(setup, "org.freedesktop.DBus.GetNameOwner", 0, s.service).Store(&owner); err != nil {
		return err
	}
	h.mu.Lock()
	h.owner = owner
	h.mu.Unlock()
	r := &busReader{conn: conn, signals: h, cache: make(map[propertyKey]dbus.Variant)}
	for {
		if connCtx.Err() != nil {
			return connCtx.Err()
		}
		h.mu.Lock()
		generation, signalErr := h.generation, h.err
		for key, entry := range h.watch {
			if entry.dirty {
				delete(r.cache, key)
				entry.dirty = false
				h.watch[key] = entry
			}
		}
		select {
		case <-h.wake:
		default:
		}
		h.mu.Unlock()
		if signalErr != nil {
			return signalErr
		}
		r.used = make(map[propertyKey]bool)
		r.ctx, stop = context.WithTimeout(connCtx, 5*time.Second)
		values := s.snapshot(r)
		stop()
		h.mu.Lock()
		changed := h.generation != generation
		if !changed && r.err == nil {
			for key := range h.watch {
				if !r.used[key] {
					delete(h.watch, key)
					delete(r.cache, key)
				}
			}
		}
		h.mu.Unlock()
		// Never apply an old read over a signal received while that read was in flight.
		if changed {
			r.err = nil
			continue
		}
		if r.err != nil {
			return r.err
		}
		if err := publish(values, nil); err != nil {
			return err
		}
		select {
		case <-connCtx.Done():
			return connCtx.Err()
		case <-h.wake:
		}
	}
}
