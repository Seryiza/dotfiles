package engine

import (
	"context"
	"sync"
)

// Latest is a bounded latest-value mailbox. Store never queues more than one
// notification and replaces any value not yet consumed.
type Latest[T any] struct {
	mu     sync.Mutex
	value  T
	has    bool
	notify chan struct{}
}

func NewLatest[T any]() *Latest[T] {
	return &Latest[T]{notify: make(chan struct{}, 1)}
}

func (latest *Latest[T]) Store(value T) {
	latest.mu.Lock()
	latest.value = value
	latest.has = true
	latest.mu.Unlock()
	select {
	case latest.notify <- struct{}{}:
	default:
	}
}

func (latest *Latest[T]) Next(ctx context.Context) (T, bool) {
	var zero T
	select {
	case <-ctx.Done():
		return zero, false
	case <-latest.notify:
	}
	return latest.Load()
}

// Notify exposes the single coalesced wake-up to renderer adapters.
func (latest *Latest[T]) Notify() <-chan struct{} { return latest.notify }

func (latest *Latest[T]) Load() (T, bool) {
	latest.mu.Lock()
	defer latest.mu.Unlock()
	if !latest.has {
		var zero T
		return zero, false
	}
	return latest.value, true
}
