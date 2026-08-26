@tool
extends EditorPlugin

## Registers the Dialogue Graph Editor as a top-level main-screen mode,
## alongside 2D/3D/Script/Game/AssetLib (Dialogue Graph Editor design
## doc, Section 2 - "a single EditorPlugin main-screen tab"). This file
## only owns plugin lifecycle/registration; all actual tab content
## lives on MainPanel (main_panel.gd) so this stays a thin shell as the
## tool grows across later stages (canvas, sidebar, Actor form, Preset
## tabs).
##
## Stage 2 of the implementation plan: prove the tab registers and
## appears. MainPanel is currently a placeholder - no canvas, no
## sidebar yet.

const MainPanelScript := preload("res://addons/dialogue_graph_editor/main_panel.gd")

var _main_panel: Control


func _enter_tree() -> void:
	_main_panel = MainPanelScript.new()
	EditorInterface.get_editor_main_screen().add_child(_main_panel)
	_make_visible(false)  # hidden until the user actually switches to this tab


func _exit_tree() -> void:
	if _main_panel != null:
		_main_panel.queue_free()
		_main_panel = null


func _has_main_screen() -> bool:
	return true


func _make_visible(next_visible: bool) -> void:
	if _main_panel != null:
		_main_panel.visible = next_visible


## Short label shown on the main-screen switcher next to 2D/3D/Script/
## Game/AssetLib. "Dialogue" chosen for brevity to match that
## convention - adjust if a longer/clearer label reads better in
## practice once it's visible in the actual editor.
func _get_plugin_name() -> String:
	return "Dialogue"


func _get_plugin_icon() -> Texture2D:
	# Placeholder - reuses a built-in editor icon until a real one is
	# authored for this tool.
	return EditorInterface.get_editor_theme().get_icon(&"Node", &"EditorIcons")
