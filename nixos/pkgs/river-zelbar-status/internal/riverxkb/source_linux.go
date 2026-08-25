//go:build linux

package riverxkb

import (
	"context"
	"errors"
	"fmt"

	"github.com/MatthiasKunnen/go-wayland/wayland/client"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
)

type keyboardState struct {
	pending   *string
	committed *string
}

// Tracker applies River's layout/done/remove batches and publishes the
// aggregate layout through the status Source seam.
type Tracker struct {
	sink        engine.Sink
	layoutNames []string
	keyboards   map[uint32]*keyboardState
}

func NewTracker(sink engine.Sink, layoutNames []string) *Tracker {
	return &Tracker{
		sink:        sink,
		layoutNames: append([]string(nil), layoutNames...),
		keyboards:   make(map[uint32]*keyboardState),
	}
}

func (tracker *Tracker) Add(id uint32) {
	tracker.keyboards[id] = &keyboardState{}
}

func (tracker *Tracker) Layout(id, index uint32) error {
	keyboard, ok := tracker.keyboards[id]
	if !ok {
		return fmt.Errorf("layout for unknown XKB keyboard %d", id)
	}
	if uint64(index) >= uint64(len(tracker.layoutNames)) {
		return fmt.Errorf("XKB layout index %d is outside configured layouts", index)
	}
	name := tracker.layoutNames[index]
	keyboard.pending = &name
	return nil
}

func (tracker *Tracker) Done(ctx context.Context, id uint32) error {
	keyboard, ok := tracker.keyboards[id]
	if !ok {
		return fmt.Errorf("done for unknown XKB keyboard %d", id)
	}
	if keyboard.pending != nil {
		value := *keyboard.pending
		keyboard.committed = &value
		keyboard.pending = nil
	}
	return tracker.publish(ctx)
}

func (tracker *Tracker) Remove(ctx context.Context, id uint32) error {
	if _, ok := tracker.keyboards[id]; !ok {
		return fmt.Errorf("remove for unknown XKB keyboard %d", id)
	}
	delete(tracker.keyboards, id)
	return tracker.publish(ctx)
}

func (tracker *Tracker) publish(ctx context.Context) error {
	layout := ""
	hasCommittedLayout := false
	for _, keyboard := range tracker.keyboards {
		if keyboard.committed == nil {
			continue
		}
		if !hasCommittedLayout {
			layout = *keyboard.committed
			hasCommittedLayout = true
			continue
		}
		if layout != *keyboard.committed {
			layout = "mixed"
			break
		}
	}
	update := model.FieldUpdate(model.FieldXKB, layout)
	return tracker.sink.Publish(ctx, engine.Event{Update: &update})
}

type Source struct{}

func NewSource() *Source { return &Source{} }

type advertisedGlobal struct {
	name    uint32
	version uint32
}

func (source *Source) Run(ctx context.Context, sink engine.Sink) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	display, err := client.Connect("")
	if err != nil {
		return fmt.Errorf("connect to Wayland: %w", err)
	}
	connection := display.Context()
	defer connection.Close()

	registry, err := display.GetRegistry()
	if err != nil {
		return fmt.Errorf("get Wayland registry: %w", err)
	}
	var inputGlobal, xkbGlobal *advertisedGlobal
	var eventErr error
	setEventErr := func(err error) {
		if err != nil && eventErr == nil {
			eventErr = err
		}
	}
	display.SetErrorHandler(func(event client.DisplayErrorEvent) {
		setEventErr(fmt.Errorf("Wayland protocol error %d: %s", event.Code, event.Message))
	})
	registry.SetGlobalHandler(func(event client.RegistryGlobalEvent) {
		global := &advertisedGlobal{name: event.Name, version: event.Version}
		switch event.Interface {
		case InputManagerInterfaceName:
			inputGlobal = global
		case XkbConfigInterfaceName:
			xkbGlobal = global
		}
	})
	registry.SetGlobalRemoveHandler(func(event client.RegistryGlobalRemoveEvent) {
		if (inputGlobal != nil && event.Name == inputGlobal.name) || (xkbGlobal != nil && event.Name == xkbGlobal.name) {
			setEventErr(errors.New("required River XKB global was removed"))
		}
	})
	if err := display.Roundtrip(); err != nil {
		return fmt.Errorf("discover River XKB globals: %w", err)
	}
	if inputGlobal == nil || inputGlobal.version < 2 {
		return errors.New("required river_input_manager_v1 version 2 global is unavailable")
	}
	if xkbGlobal == nil || xkbGlobal.version < 2 {
		return errors.New("required river_xkb_config_v1 version 2 global is unavailable")
	}

	tracker := NewTracker(sink, []string{"us", "ru"})
	devices := make(map[uint32]*InputDevice)
	manager := NewInputManager(connection)
	manager.SetFinishedHandler(func(InputManagerFinishedEvent) {
		setEventErr(errors.New("River input manager stopped unexpectedly"))
	})
	manager.SetInputDeviceHandler(func(event InputManagerInputDeviceEvent) {
		device := event.Id
		devices[device.ID()] = device
		device.SetRemovedHandler(func(InputDeviceRemovedEvent) {
			delete(devices, device.ID())
			setEventErr(device.Destroy())
		})
	})
	if err := registry.Bind(inputGlobal.name, InputManagerInterfaceName, 2, manager); err != nil {
		return fmt.Errorf("bind River input manager: %w", err)
	}

	config := NewXkbConfig(connection)
	config.SetFinishedHandler(func(XkbConfigFinishedEvent) {
		setEventErr(errors.New("River XKB config stopped unexpectedly"))
	})
	config.SetXkbKeyboardHandler(func(event XkbConfigXkbKeyboardEvent) {
		keyboard := event.Id
		tracker.Add(keyboard.ID())
		keyboard.SetInputDeviceHandler(func(event XkbKeyboardInputDeviceEvent) {
			if _, ok := devices[event.Device.ID()]; !ok {
				setEventErr(fmt.Errorf("XKB keyboard %d references unknown input device %d", keyboard.ID(), event.Device.ID()))
			}
		})
		keyboard.SetLayoutHandler(func(event XkbKeyboardLayoutEvent) {
			setEventErr(tracker.Layout(keyboard.ID(), event.Index))
		})
		keyboard.SetDoneHandler(func(XkbKeyboardDoneEvent) {
			setEventErr(tracker.Done(ctx, keyboard.ID()))
		})
		keyboard.SetRemovedHandler(func(XkbKeyboardRemovedEvent) {
			setEventErr(tracker.Remove(ctx, keyboard.ID()))
			setEventErr(keyboard.Destroy())
		})
	})
	if err := registry.Bind(xkbGlobal.name, XkbConfigInterfaceName, 2, config); err != nil {
		return fmt.Errorf("bind River XKB config: %w", err)
	}
	if err := display.Roundtrip(); err != nil {
		return fmt.Errorf("receive initial River XKB state: %w", err)
	}
	if eventErr != nil {
		return eventErr
	}

	stopped := make(chan struct{})
	defer close(stopped)
	go func() {
		select {
		case <-ctx.Done():
			_ = connection.Close()
		case <-stopped:
		}
	}()
	for {
		if err := connection.Dispatch(); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return fmt.Errorf("Wayland disconnect: %w", err)
		}
		if eventErr != nil {
			return eventErr
		}
	}
}
