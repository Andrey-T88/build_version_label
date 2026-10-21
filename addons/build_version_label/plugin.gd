@tool
extends EditorPlugin

## Registers the integration points of the addon:
##   1. Project Settings entries, added the moment the plugin is enabled.
##   2. A run hook, so every Run Project (F5/F6) in the editor is counted as a build.
##   3. An export hook that stamps the counter into the package on every platform.
##   4. A custom `BuildVersionLabel` node type usable in any scene.
##   5. An editor toolbar button and Project menu entries for manual control.
## Dependencies are preloaded rather than reached through their global class_name, so everything
## keeps working even when the editor has not refreshed its global class cache yet.

const CUSTOM_TYPE_NAME := "BuildVersionLabel"
const TOOLBAR_CONTAINER := CONTAINER_CANVAS_EDITOR_MENU
const MENU_BUMP := "Build Version: raise the next build code"
const MENU_DETAILS := "Build Version: details and set version"

## One run must never be counted twice: the pre-run hook and the playing-flag backstop both fire
## for the same F5, so a bump for a run silences the other path for a moment.
const RUN_FALLBACK_WINDOW_MS := 3000

## How often the toolbar re-reads the stamp, so an export or an external edit shows up by itself.
const SUMMARY_PERIOD := 1.0

const BV := preload("res://addons/build_version_label/build_version.gd")
const Bump := preload("res://addons/build_version_label/version_bump.gd")

var _export_plugin: EditorExportPlugin
var _toolbar_button: Button
var _summary := ""
var _summary_wait := 0.0
var _was_playing := false
var _last_run_bump_ms := -1000000
var _dialog: AcceptDialog
var _dialog_info: Label
var _dialog_entry: LineEdit


func _enter_tree() -> void:
	BV.register_settings()
	_seed_stamp_if_missing()
	_export_plugin = preload("res://addons/build_version_label/export_plugin.gd").new()
	add_export_plugin(_export_plugin)
	add_custom_type(CUSTOM_TYPE_NAME, "Label",
		preload("res://addons/build_version_label/build_version_label.gd"), null)
	_add_toolbar_button()
	add_tool_menu_item(MENU_BUMP, _bump_manually)
	add_tool_menu_item(MENU_DETAILS, _show_version_dialog)
	_refresh_summary()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_DETAILS)
	remove_tool_menu_item(MENU_BUMP)
	_remove_toolbar_button()
	remove_custom_type(CUSTOM_TYPE_NAME)
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


## A project that never had a stamp still needs one before its first run, otherwise the label
## prints the fallback. The numbers come from an existing export preset when there is one, so
## enabling the addon never restarts a store counter that Google Play already knows.
func _seed_stamp_if_missing() -> void:
	if not BV.flag(BV.SETTING_CREATE_STAMP) or FileAccess.file_exists(BV.BUILD_INFO_PATH):
		return
	var state := Bump.ensure_state()
	if state.is_empty():
		push_warning("Build Version Label: could not create %s — the label keeps showing the fallback."
			% BV.BUILD_INFO_PATH)
		return
	print("Build Version Label: created %s at %s (build %d)." % [
		BV.BUILD_INFO_PATH, str(state[BV.KEY_NAME]), int(state[BV.KEY_CODE])])


## Called by the editor right before it launches the project, which is exactly when the stamp has
## to be on disk: the process that is about to boot reads it as its own build number.
## Returning false would abort the run, so this must always let it through. The return type is left
## untyped on purpose: Godot 4.7 types this hook as bool while earlier 4.x typed it as Error, and an
## untyped override keeps the plugin loading on both.
func _build():
	if BV.flag(BV.SETTING_BUMP_ON_RUN):
		_bump_for_run("pre-run hook")
	return true


func _process(delta: float) -> void:
	# Not every path that starts the project goes through _build() (embedded play, engines older
	# than 4.7), so the editor's own "is something playing" flag is kept as a backstop.
	if Engine.has_singleton("EditorInterface") and EditorInterface.has_method("is_playing_scene"):
		var playing := EditorInterface.is_playing_scene()
		if playing and not _was_playing and BV.flag(BV.SETTING_BUMP_ON_RUN) \
				and Time.get_ticks_msec() - _last_run_bump_ms > RUN_FALLBACK_WINDOW_MS:
			_bump_for_run("playing flag")
		_was_playing = playing
	_summary_wait -= delta
	if _summary_wait <= 0.0:
		_summary_wait = SUMMARY_PERIOD
		_refresh_summary()
		_heal_preset_sync()


## The editor keeps its own copy of export_presets.cfg and can rewrite the file in the middle of, or
## right after, an export — which puts a preset back on the numbers of the build that just shipped,
## one behind the counter. Only that exact signature is repaired: a number the developer typed by
## hand is left alone and merely reported, because silently reverting an edit is worse than a mismatch.
func _heal_preset_sync() -> void:
	if not BV.flag(BV.SETTING_SYNC_PRESETS):
		return
	var state := BV.load_state()
	if state.is_empty():
		return
	var next_name := str(state[BV.KEY_NEXT_NAME])
	var next_code := int(state[BV.KEY_NEXT_CODE])
	var next_store := int(state[BV.KEY_NEXT_STORE])
	var lagging := Bump.out_of_sync(BV.PRESETS_PATH, next_name, next_code, next_store)
	if lagging.is_empty():
		return
	var moved_on := Bump.out_of_sync(BV.PRESETS_PATH, str(state[BV.KEY_NAME]),
		int(state[BV.KEY_CODE]), int(state[BV.KEY_STORE]))
	var stale := []
	for preset: String in lagging:
		# A preset that also disagrees with the last build holds something else entirely.
		if not moved_on.has(preset):
			stale.append(preset)
	if stale.is_empty():
		return
	Bump.sync(BV.PRESETS_PATH, next_name, next_code, next_store)
	_toast("Build Version Label: %s was rewritten back to the previous build by the editor, " % ", ".join(stale)
		+ "the sync raised it to build %d again." % next_code)


func _bump_for_run(reason: String) -> void:
	_last_run_bump_ms = Time.get_ticks_msec()
	var result := Bump.commit("run")
	if not bool(result.written):
		return
	var used: Dictionary = result.used
	print("Build Version Label: this run is %s (build %d), counted by the %s." % [
		str(used[BV.KEY_NAME]), int(used[BV.KEY_CODE]), reason])
	_refresh_summary()


func _add_toolbar_button() -> void:
	_toolbar_button = Button.new()
	_toolbar_button.flat = true
	_toolbar_button.tooltip_text = "Build Version Label\n" \
		+ "Left click: details, current version and the rule in effect.\n" \
		+ "Right click: raise the build code without running or exporting."
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
	var raised := Bump.advance_pending()
	if not bool(raised.get("written", false)):
		printerr("Build Version Label: nothing raised — %s could not be written." % BV.BUILD_INFO_PATH)
		return
	print("Build Version Label: the next build is %d (was %d)." % [
		int(raised["to"]), int(raised["from"])])
	_refresh_summary()
	_refresh_dialog()


func _version_summary() -> String:
	var state := BV.load_state()
	if state.is_empty():
		return "version: not built yet"
	return "%s  ->  build %d" % [BV.render(state), int(state[BV.KEY_NEXT_CODE])]


## Rebuilds the toolbar text only when the numbers actually moved, so a per-second re-read of the
## stamp never repaints the editor toolbar.
func _refresh_summary() -> void:
	var fresh := _version_summary()
	if fresh == _summary:
		return
	_summary = fresh
	if _toolbar_button != null:
		_toolbar_button.text = _summary


func _details_text() -> String:
	var state := BV.load_state()
	var r := Bump.rules()
	var lines := []
	if state.is_empty():
		lines.append("No %s yet — the first run or export writes it." % BV.BUILD_INFO_PATH)
		lines.append("Until then BuildVersionLabel shows the fallback from Project Settings.")
	else:
		lines.append("Last build:      %s" % BV.render(state))
		lines.append("                 %s at %s" % [str(state[BV.KEY_EVENT]), str(state[BV.KEY_UPDATED])])
		lines.append("Next build:      %s (build %d, store code %d)" % [
			str(state[BV.KEY_NEXT_NAME]), int(state[BV.KEY_NEXT_CODE]), int(state[BV.KEY_NEXT_STORE])])
		lines.append("Builds counted:  %d" % int(state[BV.KEY_TOTAL]))
	lines.append("")
	lines.append("Label format:    %s" % BV.display_format())
	var per_version := int(r.limit)
	if per_version <= 0:
		lines.append("Builds per version: no limit — the build code just keeps rising.")
	else:
		var component := str(r.component)
		var what := "the version stays" if component.is_empty() else "raise %s" % component
		lines.append("Builds per version: %d, then %s and the count restarts at %d." % [
			per_version, what, int(r.first)])
	var modes := []
	if BV.flag(BV.SETTING_BUMP_ON_RUN):
		modes.append("every editor run")
	if BV.flag(BV.SETTING_BUMP_ON_EXPORT):
		modes.append("every export")
	lines.append("Counted as a build: %s." % (" and ".join(modes) if not modes.is_empty() else "nothing (manual only)"))
	lines.append("Store code: %s." % ("always rising" if bool(r.store_rises) else "same as the build code"))
	var presets := "synced into export_presets.cfg" if bool(r.sync) else "left alone (sync is off)"
	lines.append("Export presets:    %s" % presets)
	var versioned := Bump.versioned_presets(BV.PRESETS_PATH)
	if not versioned.is_empty():
		lines.append("Presets with version fields: %s" % ", ".join(versioned))
	if bool(r.sync) and not state.is_empty() and not versioned.is_empty():
		var lagging := Bump.out_of_sync(BV.PRESETS_PATH, str(state[BV.KEY_NEXT_NAME]),
			int(state[BV.KEY_NEXT_CODE]), int(state[BV.KEY_NEXT_STORE]))
		if lagging.is_empty():
			lines.append("                 every one of them carries the next build's numbers.")
		else:
			lines.append("                 out of sync: %s — a right-click bump or the next build re-syncs them."
				% ", ".join(lagging))
	return "\n".join(lines)


func _show_version_dialog() -> void:
	_close_dialog()
	_dialog = AcceptDialog.new()
	_dialog.title = "Build Version Label"
	_dialog.ok_button_text = "Close"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_dialog_info = Label.new()
	_dialog_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_info.custom_minimum_size = Vector2(460, 0)
	box.add_child(_dialog_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_dialog_entry = LineEdit.new()
	_dialog_entry.placeholder_text = "1.0.0"
	_dialog_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_dialog_entry)
	var set_button := Button.new()
	set_button.text = "Set version, restart the count"
	set_button.pressed.connect(_apply_version_from_dialog)
	row.add_child(set_button)
	box.add_child(row)
	var bump_button := Button.new()
	bump_button.text = "Raise the next build code"
	bump_button.pressed.connect(_bump_manually)
	box.add_child(bump_button)
	_dialog.add_child(box)
	add_child(_dialog)
	_dialog.confirmed.connect(_close_dialog)
	_refresh_dialog()
	_dialog.popup_centered()


func _refresh_dialog() -> void:
	if _dialog == null or _dialog_info == null:
		return
	_dialog_info.text = _details_text()
	var state := BV.load_state()
	_dialog_entry.text = str(state.get(BV.KEY_NAME, ""))


## AcceptDialog closes on confirmed, and the dialog is freed right away — both buttons above work
## without closing it, so the only teardown needed is dropping the references.
func _apply_version_from_dialog() -> void:
	var value_name := _dialog_entry.text.strip_edges()
	if value_name.is_empty():
		_toast("Build Version Label: a version name is required.")
		return
	Bump.set_version(value_name)
	_refresh_summary()
	_refresh_dialog()
	_toast("Build Version Label: version set to %s, the build count restarts." % value_name)


func _close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = null
	_dialog_info = null
	_dialog_entry = null


func _toast(message: String) -> void:
	prints(message)
	if not Engine.has_singleton("EditorInterface"):
		return
	if EditorInterface.has_method("get_editor_toaster"):
		var toaster: Object = EditorInterface.get_editor_toaster()
		if toaster != null and toaster.has_method("push_toast"):
			toaster.call("push_toast", message)
