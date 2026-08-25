package riverxkb

import (
	"reflect"
	"unsafe"

	"github.com/MatthiasKunnen/go-wayland/wayland/client"
)

// registerServerObject bridges event-created new_id objects until the pinned
// go-wayland runtime exposes registration under a server-supplied object ID.
// The generated dispatcher calls this before delivering the creation event.
func registerServerObject(ctx *client.Context, id uint32, proxy client.Proxy) {
	proxy.SetID(id)
	proxy.SetContext(ctx)

	contextValue := reflect.ValueOf(ctx).Elem()
	objectsField := contextValue.FieldByName("objects")
	objects := reflect.NewAt(objectsField.Type(), unsafe.Pointer(objectsField.UnsafeAddr())).Elem()
	if objects.IsNil() {
		objects.Set(reflect.MakeMap(objects.Type()))
	}
	objects.SetMapIndex(reflect.ValueOf(id), reflect.ValueOf(proxy))
}

func newInputDevice(ctx *client.Context, id uint32) *InputDevice {
	proxy := &InputDevice{}
	registerServerObject(ctx, id, proxy)
	return proxy
}

func newXkbKeyboard(ctx *client.Context, id uint32) *XkbKeyboard {
	proxy := &XkbKeyboard{}
	registerServerObject(ctx, id, proxy)
	return proxy
}
