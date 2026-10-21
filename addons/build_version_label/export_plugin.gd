@tool
extends EditorExportPlugin

## Stamps the export preset's version into the build and advances the counter so the
## next export always gets a fresh version_code.
## Dependencies are preloaded rather than reached through their global class_name, so the
## hook keeps working even when the editor has not refreshed its global class cache yet.

const BV := preload("res://addons/build_version_label/build_version.gd")
const Bump := preload("res://addons/build_version_label/version_bump.gd")

var _version_name := ""
var _version_code := 0


func _get_name() -> String:
	return "BuildVersionLabel"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var preset := get_export_preset()
	if preset == null:
		push_warning("Build Version Label: export preset was not available; keeping the default menu label.")
		return

	_version_name = preset.get_version("version/name", false)
	_version_code = int(preset.get("version/code"))
	if _version_name.is_empty():
		_version_name = "1.0.0"

	# The AndroidManifest is already written from the preset by the time a plugin sees the
	# export, so the file is advanced for the next run: no two builds ship the same version_code.
	var preset_name: String = preset.get_preset_name()
	var file_code := Bump.current_code(BV.PRESETS_PATH, preset_name)
	if file_code > _version_code:
		push_warning("Build Version Label: the editor holds a stale preset — the file already says %d "
			% file_code + "while this build runs under %d. Reload the project or the code will repeat."
			% _version_code)
	var next := maxi(file_code, _version_code) + 1
	if Bump.advance(BV.PRESETS_PATH, preset_name, next):
		print("Build Version Label: this build is %d, export_presets.cfg raised to %d" % [_version_code, next])

	# When the project carries no placeholder build_info.json, the stamp has to be injected.
	# When it does carry one, _export_file remaps that file instead: adding it here as well
	# would let the real file's contents overwrite the stamp later in the export.
	if not FileAccess.file_exists(BV.BUILD_INFO_PATH):
		add_file(BV.BUILD_INFO_PATH, _payload(), true)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path != BV.BUILD_INFO_PATH:
		return
	add_file(path, _payload(), true)


func _payload() -> PackedByteArray:
	return JSON.stringify({
		"version_name": _version_name,
		"version_code": _version_code,
	}).to_utf8_buffer()
