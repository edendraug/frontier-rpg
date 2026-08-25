class_name OptionRow
extends Button

## One selectable row inside the dialogue window's ChoicesList. Root is
## a Button (not a Panel+Label) specifically so Godot's own UI focus
## system handles keyboard/gamepad navigation between options for
## free, and critically, so "no option is selected by default" falls
## out naturally - Godot never auto-focuses a Button unless something
## explicitly grabs focus for it, which nothing here does.
##
## Deliberately dumb: holds no dialogue logic of its own (doesn't know
## about DialogueOption, DialoguePlayer, or conditions). DialogueWindow
## decides which options exist and what their already_taken/tag values
## are; this just displays whatever it's told and reports back which
## option_id got pressed. All visual styling (fonts, colors, hover/
## focus states) lives in the .tscn, not here.

signal option_selected(option_id: String)

## How faded an already-taken option looks. Tunable here rather than
## baked into a specific color, since it's a plain alpha multiply over
## whatever normal styling is set in the editor.
const MUTED_ALPHA := 0.55

var option_id: String = ""

@onready var option_text_label: Label = %OptionText
@onready var condition_tag_label: Label = %ConditionTag


func _ready() -> void:
	pressed.connect(func(): option_selected.emit(option_id))


## tag: the auto-derived condition hint (e.g. "Natural Hunter") - pass
## "" for none. Which conditions actually produce a tag isn't decided
## yet (Section on character-sheet-relevant conditions, still open),
## so DialogueWindow may just pass "" for everything until that's
## settled - this node doesn't care where the string comes from.
func setup(p_option_id: String, text: String, tag: String, already_taken: bool) -> void:
	option_id = p_option_id
	option_text_label.text = text

	condition_tag_label.text = tag
	condition_tag_label.visible = not tag.is_empty()

	_set_muted(already_taken)


## Called once a selection has been made elsewhere in the same choice
## list, so the whole list can stay visible (not cleared) while the
## response line reveals, per DialogueWindow's design. Distinct from
## the already_taken muting above: that state is still meant to be
## clickable (a repeatable option you've picked before); this one
## genuinely shouldn't respond to anything anymore, since the
## conversation has already moved on - hence disabled = true here,
## which already_taken deliberately avoids.
func lock() -> void:
	disabled = true
	_set_muted(true)


## Fades just the text content, not the whole button via self_modulate -
## self_modulate would also fade the button's own background/border
## stylebox, making it look broken/disabled rather than "already read."
func _set_muted(muted: bool) -> void:
	var alpha := MUTED_ALPHA if muted else 1.0
	option_text_label.modulate.a = alpha
	condition_tag_label.modulate.a = alpha
