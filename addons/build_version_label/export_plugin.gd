@tool
extends EditorExportPlugin

## Stamps the shared build counter into every export — any platform, not only Android — and lets
## BuildVersionBump raise the counter and mirror it into export_presets.cfg.
## Dependencies are preloaded rather than reached through their global class_name, so the hook
## keeps working even when the editor has not refreshed its global class cache yet.

const BV := preload("res://addons/build_version_label/build_version.gd")
const Bump := preload("res://addons/build_version_label/version_bump.gd")

## The runtime view of this build: what the packaged label prints.
var _view: Dictionary = {}
var _used: Dictionary = {}
var _preset_name := ""
var _counted := false


func _get_name() -> String:
	return "BuildVersionLabel"


func _supports_platform(_platform: EditorExportPlatform) -> bool:
	# One counter for the whole project, so desktop, Web and mobile all carry the same numbers.
	return true


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var preset := get_export_preset()
	_preset_name = preset.get_preset_name() if preset != null else ""
	var seed_name := ""
	var seed_code := 0
	if preset != null:
		seed_name = preset.get_version("version/name", false)
		# A desktop preset declares no version fields at all, and int(null) is an error in GDScript.
		var raw_code: Variant = preset.get("version/code")
		seed_code = int(raw_code) if raw_code != null else 0

	if BV.flag(BV.SETTING_BUMP_ON_EXPORT):
		# Only *which* numbers this build carries is decided here. The counter itself moves in
		# _export_end: the editor rewrites export_presets.cfg from its own copy in the middle of a
		# GUI export, and an export that gets cancelled should not burn a build number.
		_used = Bump.build_numbers(_preset_name, seed_name, seed_code)
		_counted = true
	else:
		# Counting is off: ship the numbers the project already holds, changing nothing.
		var state := BV.load_state()
		_used = BV.runtime_view(state) if not state.is_empty() else {
			BV.KEY_NAME: seed_name if not seed_name.is_empty() else BV.text(BV.SETTING_SEED_NAME),
			BV.KEY_CODE: seed_code,
			BV.KEY_STORE: seed_code,
		}
	# The package carries the numbers of the build it is, including the count this build will add
	# to the lifetime total — the stamp itself is only written once the export is over.
	var total := int(BV.load_state().get(BV.KEY_TOTAL, 0))
	_view = {
		BV.KEY_NAME: _used.get(BV.KEY_NAME, ""),
		BV.KEY_CODE: int(_used.get(BV.KEY_CODE, 0)),
		BV.KEY_STORE: int(_used.get(BV.KEY_STORE, 0)),
		BV.KEY_TOTAL: total + 1 if _counted else total,
		BV.KEY_EVENT: "export",
		BV.KEY_PRESET: _preset_name,
		BV.KEY_UPDATED: BV.utc_now(),
	}
	# The manifest of a mobile build and the properties of a desktop one are generated from the
	# preset object, and the editor's in-memory copy of that preset can lag behind the file the
	# counter already raised — so hand the preset the numbers this build carries. Without this the
	# package would ship a store code the in-game label does not show.
	if BV.flag(BV.SETTING_SYNC_PRESETS):
		_apply_to_preset(preset)
	print("Build Version Label: exporting %s (build %d) for preset \"%s\"." % [
		str(_view[BV.KEY_NAME]), int(_view[BV.KEY_CODE]), _preset_name])

	# Without the sync there is nothing to correct the preset with, so a preset that still holds
	# another store code really does ship a number the label in the package does not show.
	if not bool(BV.flag(BV.SETTING_SYNC_PRESETS)) and seed_code > 0 \
			and seed_code != int(_view[BV.KEY_CODE]):
		push_warning("Build Version Label: preset \"%s\" exports store code %d while this build is stamped %d. " % [
			_preset_name, seed_code, int(_view[BV.KEY_CODE])]
			+ "Turn build_version_label/sync_export_presets on, or set the number in the preset yourself.")

	# When the project carries no stamp file at all, the view has to be injected; when it does,
	# _export_file remaps that file, because adding it here as well would let the real file's
	# contents overwrite the stamp later in the export.
	if not FileAccess.file_exists(BV.BUILD_INFO_PATH):
		add_file(BV.BUILD_INFO_PATH, _payload(), true)


## The export is over and the editor is done with export_presets.cfg: now the counter can move.
func _export_end() -> void:
	if not _counted or _used.is_empty():
		return
	var result := Bump.record_build(_used, "export", _preset_name)
	if bool(result.written):
		var record: Dictionary = result.state
		print("Build Version Label: build %d recorded, the next one will be %d." % [
			int(_used[BV.KEY_CODE]), int(record[BV.KEY_NEXT_CODE])])
	_counted = false


## Pushes this build's numbers into the live export preset. Only a field the preset already
## declares is touched; a desktop preset with no version fields at all keeps its own defaults.
func _apply_to_preset(preset: EditorExportPreset) -> void:
	if preset == null:
		return
	var value_name := str(_view[BV.KEY_NAME])
	var store := int(_view[BV.KEY_STORE])
	var values := {
		"version/code": store,
		"version/name": value_name,
		"application/product_version": value_name,
		"application/file_version": BV.windows_version(value_name, store),
	}
	for key: String in values:
		var value: Variant = values[key]
		var current: Variant = preset.get(key)
		if current == null or value == null or str(value).is_empty():
			continue
		if str(current) == str(value):
			continue
		preset.set(key, value)
		print("Build Version Label: preset \"%s\" %s was %s, this export uses %s." % [
			_preset_name, key, str(current), str(value)])


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path != BV.BUILD_INFO_PATH or _view.is_empty():
		return
	add_file(path, _payload(), true)


func _payload() -> PackedByteArray:
	return JSON.stringify(_view, "\t", false).to_utf8_buffer()
