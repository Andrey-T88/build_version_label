class_name BuildVersion
extends RefCounted

## Single source of truth for the build stamp: where it lives, which Project Settings the addon
## owns, how the counter state is read and written, and how a version string is parsed and raised.
## No editor classes are touched here, so a headless run can drive every rule (see tests/).
##
## The editor keeps its *state* in config/build_info.json (last build + the numbers the next build
## will get). An exported package gets a *runtime view* of that state — only the values of the build
## it carries — which is why every platform shows exactly the same version.

## The tracked placeholder: the export hook remaps its contents per build, so the file itself
## never has to be edited by hand apart from the counter the plugin maintains.
const BUILD_INFO_PATH := "res://config/build_info.json"
const PRESETS_PATH := "res://export_presets.cfg"

# --- Project Settings keys ---------------------------------------------------------------------
const SETTING_PRESET := "build_version_label/display_format_preset"
const SETTING_FORMAT := "build_version_label/display_label_format"
const SETTING_FALLBACK := "build_version_label/fallback_version"
const SETTING_BUMP_ON_RUN := "build_version_label/bump_on_run"
const SETTING_BUMP_ON_EXPORT := "build_version_label/bump_on_export"
const SETTING_BUILDS_PER_VERSION := "build_version_label/builds_per_version"
const SETTING_ON_LIMIT := "build_version_label/on_limit_reached"
const SETTING_FIRST_BUILD := "build_version_label/first_build"
const SETTING_STORE_MODE := "build_version_label/store_code_mode"
const SETTING_SYNC_PRESETS := "build_version_label/sync_export_presets"
const SETTING_SEED_NAME := "build_version_label/seed_version_name"
const SETTING_CREATE_STAMP := "build_version_label/create_missing_stamp"

const DEFAULT_PRESET := 0
const DEFAULT_FORMAT := "Version %s (build %d)"
const DEFAULT_FALLBACK := "0.0.0"
const DEFAULT_BUMP_ON_RUN := true
const DEFAULT_BUMP_ON_EXPORT := true
const DEFAULT_BUILDS_PER_VERSION := 0
const DEFAULT_ON_LIMIT := 2
const DEFAULT_FIRST_BUILD := 1
const DEFAULT_STORE_MODE := 0
const DEFAULT_SYNC_PRESETS := true
const DEFAULT_SEED_NAME := "1.0.0"
const DEFAULT_CREATE_STAMP := true

## Keys of the state file, in the order they are written.
const KEY_NAME := "version_name"
const KEY_CODE := "version_code"
const KEY_STORE := "store_code"
const KEY_TOTAL := "total_builds"
const KEY_NEXT_NAME := "next_version_name"
const KEY_NEXT_CODE := "next_version_code"
const KEY_NEXT_STORE := "next_store_code"
const KEY_EVENT := "event"
const KEY_PRESET := "preset"
const KEY_UPDATED := "updated"

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

## What happens once a version has used up builds_per_version builds. Positionally matched with
## ON_LIMIT_COMPONENTS, where "" means "leave version_name alone".
const ON_LIMIT_NAMES: Array[String] = [
	"Nothing — keep counting (1.1.3 build 9999999)",
	"Reset the build code only",
	"Raise patch and restart the count (1.0.0 build 9999 -> 1.0.1 build 1)",
	"Raise minor and restart the count (1.0.9 build 9999 -> 1.1.0 build 1)",
	"Raise major and restart the count (1.9.0 build 9999 -> 2.0.0 build 1)",
]
const ON_LIMIT_COMPONENTS: Array[String] = ["", "", "patch", "minor", "major"]

## Which number goes to the export presets (Google Play / App Store version code).
const STORE_MODE_NAMES: Array[String] = [
	"Same as the build code (resets with it)",
	"Always rising (store safe: the display build may reset)",
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
			"hint_text": "Shown before the first run or export created build_info.json.",
		},
		SETTING_BUMP_ON_RUN: {
			"type": TYPE_BOOL,
			"default": DEFAULT_BUMP_ON_RUN,
			"hint": PROPERTY_HINT_NONE,
			"hint_text": "Every Run Project (F5/F6) in the editor counts as a build.",
		},
		SETTING_BUMP_ON_EXPORT: {
			"type": TYPE_BOOL,
			"default": DEFAULT_BUMP_ON_EXPORT,
			"hint": PROPERTY_HINT_NONE,
			"hint_text": "Every export, on any platform, counts as a build.",
		},
		SETTING_BUILDS_PER_VERSION: {
			"type": TYPE_INT,
			"default": DEFAULT_BUILDS_PER_VERSION,
			"hint": PROPERTY_HINT_RANGE,
			"hint_text": "0,100000000,1",
		},
		SETTING_ON_LIMIT: {
			"type": TYPE_INT,
			"default": DEFAULT_ON_LIMIT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_text": ",".join(ON_LIMIT_NAMES),
		},
		SETTING_FIRST_BUILD: {
			"type": TYPE_INT,
			"default": DEFAULT_FIRST_BUILD,
			"hint": PROPERTY_HINT_RANGE,
			"hint_text": "0,1000000,1,or_greater",
		},
		SETTING_STORE_MODE: {
			"type": TYPE_INT,
			"default": DEFAULT_STORE_MODE,
			"hint": PROPERTY_HINT_ENUM,
			"hint_text": ",".join(STORE_MODE_NAMES),
		},
		SETTING_SYNC_PRESETS: {
			"type": TYPE_BOOL,
			"default": DEFAULT_SYNC_PRESETS,
			"hint": PROPERTY_HINT_NONE,
			"hint_text": "Mirror the counter into every export preset that already declares version fields.",
		},
		SETTING_SEED_NAME: {
			"type": TYPE_STRING,
			"default": DEFAULT_SEED_NAME,
			"hint": PROPERTY_HINT_NONE,
			"hint_text": "Version name used when the very first stamp is created and no preset supplies one.",
		},
		SETTING_CREATE_STAMP: {
			"type": TYPE_BOOL,
			"default": DEFAULT_CREATE_STAMP,
			"hint": PROPERTY_HINT_NONE,
			"hint_text": "Create config/build_info.json when the plugin is enabled and the file is missing.",
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

## The default the addon registered for a key, so a setting the project never saw still reads sane.
static func default_for(key: String) -> Variant:
	var all := settings()
	if not all.has(key):
		return null
	var spec: Dictionary = all[key]
	return spec.default

static func flag(key: String) -> bool:
	return bool(setting(key, default_for(key)))

static func number(key: String) -> int:
	return int(setting(key, default_for(key)))

static func text(key: String) -> String:
	return str(setting(key, default_for(key)))

## The format string actually in effect for BuildVersionLabel.
static func display_format() -> String:
	var idx := number(SETTING_PRESET)
	if idx < 0 or idx >= PRESET_FORMATS.size():
		idx = DEFAULT_PRESET
	var picked := PRESET_FORMATS[idx]
	if picked.is_empty():
		return text(SETTING_FORMAT)
	return picked

## The version component raised when a version runs out of builds, "" for "leave it alone".
static func limit_component() -> String:
	var idx := number(SETTING_ON_LIMIT)
	if idx < 0 or idx >= ON_LIMIT_COMPONENTS.size():
		idx = DEFAULT_ON_LIMIT
	return ON_LIMIT_COMPONENTS[idx]

## Reads the raw stamp file (works in an exported package too), or {} when there is none.
static func read(path: String = BUILD_INFO_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null:
		return {}
	var parsed: Variant = JSON.parse_string(reader.get_as_text())
	reader.close()
	return parsed if parsed is Dictionary else {}

## Reads the stamp and fills in whatever a file written by an older version of the addon lacks,
## so the counter can start from a plain {"version_name": ..., "version_code": ...}.
static func load_state(path: String = BUILD_INFO_PATH) -> Dictionary:
	var raw := read(path)
	if raw.is_empty():
		return {}
	var name := str(raw.get(KEY_NAME, ""))
	var code := int(raw.get(KEY_CODE, 0))
	var store := int(raw.get(KEY_STORE, code))
	var out := {
		KEY_NAME: name,
		KEY_CODE: code,
		KEY_STORE: store,
		KEY_TOTAL: int(raw.get(KEY_TOTAL, 0)),
		KEY_NEXT_NAME: str(raw.get(KEY_NEXT_NAME, name)),
		KEY_NEXT_CODE: int(raw.get(KEY_NEXT_CODE, code + 1 if code > 0 else 1)),
		KEY_NEXT_STORE: int(raw.get(KEY_NEXT_STORE, maxi(store, code) + 1)),
		KEY_EVENT: str(raw.get(KEY_EVENT, "")),
		KEY_PRESET: str(raw.get(KEY_PRESET, "")),
		KEY_UPDATED: str(raw.get(KEY_UPDATED, "")),
	}
	return out

## Writes the state file into the project. Editor only: a packaged build cannot write to res://,
## and never needs to — it carries the runtime view instead.
static func save_state(state: Dictionary, path: String = BUILD_INFO_PATH) -> bool:
	var dir := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir != OK and dir != ERR_ALREADY_EXISTS:
		push_warning("Build Version Label: could not create %s (%s)" % [path.get_base_dir(), error_string(dir)])
	var writer := FileAccess.open(path, FileAccess.WRITE)
	if writer == null:
		push_warning("Build Version Label: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	# Insertion order is the display order, so the file stays readable as a diff.
	var ordered := {
		KEY_NAME: state.get(KEY_NAME, ""),
		KEY_CODE: int(state.get(KEY_CODE, 0)),
		KEY_STORE: int(state.get(KEY_STORE, 0)),
		KEY_TOTAL: int(state.get(KEY_TOTAL, 0)),
		KEY_NEXT_NAME: state.get(KEY_NEXT_NAME, state.get(KEY_NAME, "")),
		KEY_NEXT_CODE: int(state.get(KEY_NEXT_CODE, 0)),
		KEY_NEXT_STORE: int(state.get(KEY_NEXT_STORE, 0)),
		KEY_EVENT: state.get(KEY_EVENT, ""),
		KEY_PRESET: state.get(KEY_PRESET, ""),
		KEY_UPDATED: state.get(KEY_UPDATED, utc_now()),
	}
	# sort_keys stays off so the file keeps the readable order above instead of alphabetical.
	writer.store_string(JSON.stringify(ordered, "\t", false) + "\n")
	writer.close()
	return true

## The only keys that belong in a package: the numbers of the build that carries this file.
static func runtime_view(state: Dictionary) -> Dictionary:
	return {
		KEY_NAME: state.get(KEY_NAME, ""),
		KEY_CODE: int(state.get(KEY_CODE, 0)),
		KEY_STORE: int(state.get(KEY_STORE, 0)),
		KEY_TOTAL: int(state.get(KEY_TOTAL, 0)),
		KEY_EVENT: state.get(KEY_EVENT, ""),
		KEY_PRESET: state.get(KEY_PRESET, ""),
		KEY_UPDATED: state.get(KEY_UPDATED, ""),
	}

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

## Splits "1.2.3-rc.1" into numbers plus the untouched suffix. Missing parts read as 0, so
## "1.0" is "1.0.0"; anything non numeric stops the head and becomes the tail.
static func parse_version(value: String) -> Dictionary:
	var cut := value.length()
	for i in value.length():
		var c := value[i]
		if c != "." and (c < "0" or c > "9"):
			cut = i
			break
	var head := value.substr(0, cut)
	var parts := head.split(".")
	var nums := [0, 0, 0]
	for i in mini(parts.size(), 3):
		nums[i] = int(parts[i])
	return {"major": nums[0], "minor": nums[1], "patch": nums[2], "tail": value.substr(cut)}

static func format_version(parts: Dictionary) -> String:
	return "%d.%d.%d%s" % [int(parts.major), int(parts.minor), int(parts.patch), str(parts.tail)]

## Raises one component and zeroes the ones below it, the way a release line is expected to move.
static func raise_component(value: String, component: String) -> String:
	if component != "major" and component != "minor" and component != "patch":
		return value
	var parts := parse_version(value)
	match component:
		"major":
			parts.major = int(parts.major) + 1
			parts.minor = 0
			parts.patch = 0
		"minor":
			parts.minor = int(parts.minor) + 1
			parts.patch = 0
		"patch":
			parts.patch = int(parts.patch) + 1
	return format_version(parts)

## Windows' VERSION_INFO struct holds four 16-bit numbers, so the file version of a desktop build
## is "<name>.<code>" — or empty when a component does not fit, in which case it is left alone.
static func windows_version(value_name: String, code: int) -> String:
	var parts := parse_version(value_name)
	var nums: Array = [int(parts.major), int(parts.minor), int(parts.patch), code]
	for n in nums:
		if int(n) < 0 or int(n) > 65535:
			return ""
	return "%d.%d.%d.%d" % [nums[0], nums[1], nums[2], nums[3]]

## UTC timestamp for the stamp; `Z` keeps it sortable and unambiguous.
static func utc_now() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		d.year, d.month, d.day, d.hour, d.minute, d.second,
	]
