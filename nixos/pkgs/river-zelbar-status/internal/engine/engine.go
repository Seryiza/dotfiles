package engine

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sync"

	"seryiza.local/river-zelbar-status/internal/model"
)

type FaultClass uint8

const (
	Nonfatal FaultClass = iota
	Fatal
)

type Fault struct {
	Class  FaultClass
	Source string
	Err    error
}

func (fault *Fault) Error() string { return fmt.Sprintf("%s: %v", fault.Source, fault.Err) }
func (fault *Fault) Unwrap() error { return fault.Err }

type Event struct {
	Update  *model.Update
	Warning *Fault
}

type Sink interface {
	Publish(context.Context, Event) error
}

type Source interface {
	Run(context.Context, Sink) error
}

type Renderer interface {
	Run(context.Context, *Latest[[]byte]) error
}

type Formatter func(model.Snapshot) ([]byte, error)

// eventMailbox retains only the newest pending update for each typed state
// field. Its size is bounded by the closed model.Update key set.
type eventMailbox struct {
	mu      sync.Mutex
	pending map[model.UpdateKey]Event
	notify  chan struct{}
	fatal   chan *Fault
}

func newEventMailbox() *eventMailbox {
	return &eventMailbox{
		pending: make(map[model.UpdateKey]Event),
		notify:  make(chan struct{}, 1),
		fatal:   make(chan *Fault, 1),
	}
}

func (mailbox *eventMailbox) Publish(ctx context.Context, event Event) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if event.Warning != nil && event.Warning.Class == Fatal {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case mailbox.fatal <- event.Warning:
			return nil
		}
	}
	if event.Update == nil {
		if event.Warning != nil {
			log.Printf("river-zelbar-status: %v", event.Warning)
		}
		return nil
	}

	mailbox.mu.Lock()
	mailbox.pending[event.Update.Key()] = event
	mailbox.mu.Unlock()
	select {
	case mailbox.notify <- struct{}{}:
	default:
	}
	return nil
}

func (mailbox *eventMailbox) take() []Event {
	mailbox.mu.Lock()
	defer mailbox.mu.Unlock()
	events := make([]Event, 0, len(mailbox.pending))
	for key, event := range mailbox.pending {
		events = append(events, event)
		delete(mailbox.pending, key)
	}
	return events
}

type exit struct {
	component string
	err       error
}

// Run owns the complete source/renderer graph. Any component return is fatal
// unless the caller is already stopping the graph.
func Run(ctx context.Context, sources []Source, renderer Renderer, formatter Formatter) error {
	runCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	events := newEventMailbox()
	exits := make(chan exit, len(sources)+1)
	frames := NewLatest[[]byte]()

	initial, err := formatter(model.Snapshot{})
	if err != nil {
		return &Fault{Class: Fatal, Source: "formatter", Err: err}
	}
	frames.Store(initial)

	go func() { exits <- exit{component: "renderer", err: renderer.Run(runCtx, frames)} }()
	for index, source := range sources {
		index, source := index, source
		go func() {
			exits <- exit{component: fmt.Sprintf("source %d", index), err: source.Run(runCtx, events)}
		}()
	}

	total := len(sources) + 1
	consumed := 0
	var result error
	state := model.Snapshot{}

running:
	for {
		select {
		case <-ctx.Done():
			break running
		case fault := <-events.fatal:
			result = fault
			break running
		case stopped := <-exits:
			consumed++
			if ctx.Err() == nil {
				cause := stopped.err
				if cause == nil || errors.Is(cause, context.Canceled) {
					cause = errors.New("component exited")
				}
				result = &Fault{Class: Fatal, Source: stopped.component, Err: cause}
			}
			break running
		case <-events.notify:
			for _, event := range events.take() {
				if event.Warning != nil {
					log.Printf("river-zelbar-status: %v", event.Warning)
				}
				state = model.Reduce(state, *event.Update)
			}
			frame, formatErr := formatter(state)
			if formatErr != nil {
				result = &Fault{Class: Fatal, Source: "formatter", Err: formatErr}
				break running
			}
			frames.Store(frame)
		}
	}

	cancel()
	for consumed < total {
		<-exits
		consumed++
	}
	return result
}
