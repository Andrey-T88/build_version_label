@tool
extends EditorPlugin

## Registers the integration points of the addon:
##   1. Project Settings entries, added the moment the plugin is enabled.
##   2. An export hook that stamps the version into the build and advances the counter.
##   3. A custom `BuildVersionLabel` node type usable in any scene.
##   4. An editor toolbar button and a Project menu entry for manual control.

const CUSTOM_TYPE_NAME := "BuildVersionLabel"
const TOOLBAR_CONTAINER := CONTAINER_CANVAS_EDITOR_MENU
const MENU_ITEM_NAME := "Build Version: bump build code"
const BV := preload("res://addons/build_version_label/build_version.gd")
const Bump := preload("res://addons/build_version_label/version_bump.gd")

var _export_plugin: EditorExportPlugin
var _toolbar_button: Button


func _enter_tree() -> void:
	BV.register_settings()
	_export_plugin = preload("res://addons/build_version_label/export_plugin.gd").new()
	add_export_plugin(_export_plugin)
	add_custom_type(CUSTOM_TYPE_NAME, "Label",
		preload("res://addons/build_version_label/build_version_label.gd"), null)
	_add_toolbar_button()
	add_tool_menu_item(MENU_ITEM_NAME, _bump_manually)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM_NAME)
	_remove_toolbar_button()
	remove_custom_type(CUSTOM_TYPE_NAME)
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


func _add_toolbar_button() -> void:
	_toolbar_button = Button.new()
	_toolbar_button.flat = true
	_toolbar_button.tooltip_text = "Build Version Label\n" \
		+ "Left click: current version.\nRight click: raise the build code without exporting."
	_toolbar_button.text = _version_summary()
	_toolbar_button.pressed.connect(_show_version_dialog)
	_toolbar_button.gui_input.connect(_on_toolbar_gui_input)
	add_control_to_container(TOOLBAR_CONTAINER, _toolbar_button)


func _remove_toolbar_button() -> void:
	if _toolbar_button == null:
		return
	remove_control_from_container(TOOLBAR_CONTAINER, _toolbar_button)
	_toolbar_button.queue_free()
	_toolbar_button = null


func _on_toolbar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_bump_manually()
		_toolbar_button.accept_event()


func _bump_manually() -> void:
	var bumped := Bump.bump_next_versioned_preset(BV.PRESETS_PATH)
	if bumped.is_empty():
		printerr("Build Version Label: nothing to bump — add a version/code= line to an export preset first.")
	else:
		print("Build Version Label: manually bumped \"%s\" from %d to %d." % [
			str(bumped["preset"]), int(bumped["from"]), int(bumped["to"])])


func _version_summary() -> String:
	var info := BV.read()
	if info.is_empty():
		return "version: not built yet"
	return "v%s (build %d)" % [str(info.get("version_name", "?")), int(info.get("version_code", 0))]


func _show_version_dialog() -> void:
	var info := BV.read()
	var body := ""
	if info.is_empty():
		body = "No %s yet — the first export writes it.\n" % BV.BUILD_INFO_PATH
		body += "Until then BuildVersionLabel shows the fallback from Project Settings."
	else:
		body = "version_name: %s\n" % str(info.get("version_name", ""))
		body += "version_code: %d\n" % int(info.get("version_code", 0))
		body += "label format: %s\n" % BV.display_format()
		body += "\nRight-click the toolbar button to raise version_code without exporting."

	var dialog := AcceptDialog.new()
	dialog.title = "Build Version Label"
	dialog.ok_button_text = "Close"
	var label := Label.new()
	label.text = body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(380, 0)
	dialog.add_child(label)
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.popup_centered()
