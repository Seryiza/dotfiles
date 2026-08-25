package riverxkb

import (
	"testing"

	"github.com/MatthiasKunnen/go-wayland/wayland/client"
)

func TestGeneratedDispatchRegistersServerCreatedObjects(t *testing.T) {
	ctx := &client.Context{}
	manager := &InputManager{}
	manager.SetContext(ctx)
	var device *InputDevice
	manager.SetInputDeviceHandler(func(event InputManagerInputDeviceEvent) { device = event.Id })
	data := make([]byte, 4)
	client.PutUint32(data, 0xff000001)
	manager.Dispatch(1, 0, data)
	if device == nil || device.ID() != 0xff000001 || ctx.GetProxy(device.ID()) != device {
		t.Fatalf("input device was not registered under server ID: %#v", device)
	}

	config := &XkbConfig{}
	config.SetContext(ctx)
	var keyboard *XkbKeyboard
	config.SetXkbKeyboardHandler(func(event XkbConfigXkbKeyboardEvent) { keyboard = event.Id })
	client.PutUint32(data, 0xff000002)
	config.Dispatch(1, 0, data)
	if keyboard == nil || keyboard.ID() != 0xff000002 || ctx.GetProxy(keyboard.ID()) != keyboard {
		t.Fatalf("XKB keyboard was not registered under server ID: %#v", keyboard)
	}
}
