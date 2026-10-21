class_name BuildVersion
extends RefCounted

## Single source of truth for where the build stamp lives and how it is read.

## Placeholder inside the project; the export hook remaps its contents per build,
## so the tracked file itself never has to be edited by hand.
const BUILD_INFO_PATH := "res://config/build_info.json"
const PRESETS_PATH := "res://export_presets.cfg"

const SETTING_PRESET := "build_version_label/display_format_preset"
const SETTING_FORMAT := "build_version_label/display_label_format"
const SETTING_FALLBACK := "build_version_label/fallback_version"

const DEFAULT_PRESET := 0
const DEFAULT_FORMAT := "Version %s (build %d)"
const DEFAULT_FALLBACK := "0.0.0"

## Dropdown choices for display_format_preset, shown in Project Settings as samples.
const PRESET_NAMES: Array[String] = [
	"Version 1.2.0 (build 21)",
	"v1.2.0 (21)",
	"1.2.0 (21)",
	"1.2.0+21",
	"1.2.0",
	"Custom — use display_label_format",
]

## Format for each preset, positionally matched with PRESET_NAMES. The empty entry hands
## control to display_label_format, so a project is never limited to this list.
const PRESET_FORMATS: Array[String] = [
	"Version %s (build %d)",
	"v%s (%d)",
	"%s (%d)",
	"%s+%d",
	"%s",
	"",
]

## Keys registered in Project Settings so a fresh copy of the addon offers them in the UI.
static func settings() -> Dictionary:
	return {
		SETTING_PRESET: {
			"type": TYPE_INT,
			"default": DEFAULT_PRESET,
			"hint": PROPERTY_HINT_ENUM,
			"hint_text": ",".join(PRESET_NAMES),
		},
		SETTING_FORMAT: {
			"type": TYPE_STRING,
			"default": DEFAULT_FORMAT,
			"hint": PROPERTY_HINT_NONE,
			"hint_text": "Used when display_format_preset is Custom. %s = version_name, %d = version_code.",
		},
		SETTING_FALLBACK: {
			"type": TYPE_STRING,
			"default": DEFAULT_FALLBACK,
			"hint": PROPERTY_HINT_NONE,
			"hint_text": "Shown before the first export created build_info.json.",
		},
	}

static func register_settings() -> void:
	var all := settings()
	for key: String in all:
		var spec: Dictionary = all[key]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, spec.default)
		ProjectSettings.set_initial_value(key, spec.default)
		ProjectSettings.add_property_info({
			"name": key,
			"type": spec.type,
			"hint": spec.hint,
			"hint_string": spec.hint_text,
		})

static func setting(key: String, fallback: Variant) -> Variant:
	return ProjectSettings.get_setting_with_override(key) if ProjectSettings.has_setting(key) else fallback

## The format string actually in effect for BuildVersionLabel.
static func display_format() -> String:
	var idx := int(setting(SETTING_PRESET, DEFAULT_PRESET))
	if idx < 0 or idx >= PRESET_FORMATS.size():
		idx = DEFAULT_PRESET
	var picked := PRESET_FORMATS[idx]
	if picked.is_empty():
		return str(setting(SETTING_FORMAT, DEFAULT_FORMAT))
	return picked


static func read(path: String = BUILD_INFO_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null:
		return {}
	var parsed: Variant = JSON.parse_string(reader.get_as_text())
	reader.close()
	return parsed if parsed is Dictionary else {}

## Renders the stamp through the format chosen in Project Settings.
static func render(info: Dictionary) -> String:
	return apply_format(display_format(), info)

## Godot's `%` prints an error and returns the raw format when the string ignores an
## argument ("%s" with two values), so only the placeholders actually present get passed.
static func apply_format(fmt: String, info: Dictionary) -> String:
	var args := []
	var i := 0
	while i < fmt.length() - 1:
		if fmt[i] != "%":
			i += 1
			continue
		match fmt[i + 1]:
			"s":
				args.append(str(info.get("version_name", "")))
			"d":
				args.append(int(info.get("version_code", 0)))
		i += 2
	return fmt % args
