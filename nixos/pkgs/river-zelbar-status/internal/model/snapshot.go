package model

// Snapshot is the complete status state. Sources publish typed Updates; only the
// formatter turns this data into Zelbar markup.
type Snapshot struct {
	Machi MachiState
	XKB   string

	OrgTimeblock string
	OrgClock     string
	Audio        string
	Network      string
	WireGuard    string
	Battery      string
	PowerSaver   string
	Clock        string
}

// MachiState is replaced atomically so fields from different snapshots cannot
// be rendered together. Source indices remain zero-based.
type MachiState struct {
	Valid          bool
	WorkspaceIndex int
	WorkspaceCount int
	PanelIndex     int
	PanelCount     int
	Mode           string
	WindowCount    int
	Title          string
}

type Field uint8

const (
	FieldXKB Field = iota
	FieldOrgTimeblock
	FieldOrgClock
	FieldAudio
	FieldNetwork
	FieldWireGuard
	FieldBattery
	FieldPowerSaver
	FieldClock
)

// Update is a closed set of state changes, rather than a plugin callback.
type Update struct {
	machi *MachiState
	field Field
	value string
}

type UpdateKey uint8

const UpdateKeyMachi UpdateKey = 0

func (update Update) Key() UpdateKey {
	if update.machi != nil {
		return UpdateKeyMachi
	}
	return UpdateKey(update.field) + 1
}

func MachiUpdate(value MachiState) Update { return Update{machi: &value} }

func FieldUpdate(field Field, value string) Update {
	return Update{field: field, value: value}
}

// Reduce returns a new snapshot with one typed update applied.
func Reduce(previous Snapshot, update Update) Snapshot {
	next := previous
	if update.machi != nil {
		next.Machi = *update.machi
		return next
	}

	switch update.field {
	case FieldXKB:
		next.XKB = update.value
	case FieldOrgTimeblock:
		next.OrgTimeblock = update.value
	case FieldOrgClock:
		next.OrgClock = update.value
	case FieldAudio:
		next.Audio = update.value
	case FieldNetwork:
		next.Network = update.value
	case FieldWireGuard:
		next.WireGuard = update.value
	case FieldBattery:
		next.Battery = update.value
	case FieldPowerSaver:
		next.PowerSaver = update.value
	case FieldClock:
		next.Clock = update.value
	}
	return next
}
