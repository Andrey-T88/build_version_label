class_name BuildVersionBump
extends RefCounted

## Moves the build counter and writes it out: config/build_info.json (the stamp every platform
## reads) and export_presets.cfg (the numbers the store manifests ship with).
## Kept out of the editor classes on purpose — a headless run can drive every rule here against a
## copy of a file, and plugin.gd / export_plugin.gd only decide *when* to call it.
##
## Counter model, so runs and exports agree on one number:
##   next_version_*  the numbers the next build (run or export) gets, mirrored into the presets,
##   version_*       the numbers of the build that just happened — what the label prints,
##   store_code      the number written to version/code; either equal to the build code or always
##                   rising, which is what Google Play and the App Store demand.
## An export cannot change the version its own manifest carries (it is read before a plugin sees
## the export), therefore the preset file always holds the *next* build's numbers.

const BV := preload("res://addons/build_version_label/build_version.gd")

## Preset options mirrored from the counter. Only a line the preset already declares gets
## rewritten: inserting an option a platform does not know about would be a guess.
## "code" takes the store number, "name" the version name, "windows" the 4-part file version.
const FIELDS: Array[Dictionary] = [
	{"key": "version/code", "value": "code"},
	{"key": "version/name", "value": "name"},
	{"key": "application/product_version", "value": "name"},
	{"key": "application/file_version", "value": "windows"},
]

## The one rule the user picks in Project Settings: what the number after the last allowed
## build of a version looks like. Under the limit it is simply code + 1.
static func next_after(value_name: String, code: int, limit: int, component: String, first: int) -> Dictionary:
	if limit > 0 and code + 1 > limit:
		return {
			BV.KEY_NAME: value_name if component.is_empty() else BV.raise_component(value_name, component),
			BV.KEY_CODE: first,
			"limit_hit": true,
		}
	return {BV.KEY_NAME: value_name, BV.KEY_CODE: code + 1, "limit_hit": false}

## Settings snapshot the rules need, read once per commit so a test can drive the same path.
static func rules() -> Dictionary:
	return {
		"limit": maxi(0, BV.number(BV.SETTING_BUILDS_PER_VERSION)),
		"component": BV.limit_component(),
		"first": maxi(0, BV.number(BV.SETTING_FIRST_BUILD)),
		"store_rises": BV.number(BV.SETTING_STORE_MODE) == 1,
		"sync": BV.flag(BV.SETTING_SYNC_PRESETS),
		"seed_name": BV.text(BV.SETTING_SEED_NAME),
	}

## Creates the stamp file for a project that has none, so the very first run or export already
## prints a version. A version the developer typed into an export preset wins over the Project
## Settings seed, and its version/code becomes the number the first build carries — store numbers
## must not start over. No build is consumed here (total_builds stays 0).
static func ensure_state(preset_name := "", preset_code := 0, seed_name := "",
		cfg_path := BV.PRESETS_PATH, state_path := BV.BUILD_INFO_PATH) -> Dictionary:
	var existing := BV.load_state(state_path)
	if not existing.is_empty():
		return existing
	var r := rules()
	var base_name := str(r.seed_name)
	var base_code := int(r.first)
	var declared := first_versioned(cfg_path) if preset_name.is_empty() else read_preset(cfg_path, preset_name)
	if not seed_name.is_empty():
		base_name = seed_name
	elif not str(declared.get(BV.KEY_NAME, "")).is_empty():
		base_name = str(declared[BV.KEY_NAME])
	if int(declared.get(BV.KEY_CODE, -1)) > 0:
		base_code = int(declared[BV.KEY_CODE])
	if preset_code > 0:
		base_code = preset_code
	var state := {
		BV.KEY_NAME: base_name,
		BV.KEY_CODE: base_code,
		BV.KEY_STORE: base_code,
		BV.KEY_TOTAL: 0,
		BV.KEY_NEXT_NAME: base_name,
		BV.KEY_NEXT_CODE: base_code,
		BV.KEY_NEXT_STORE: base_code,
		BV.KEY_EVENT: "init",
		BV.KEY_PRESET: preset_name,
		BV.KEY_UPDATED: BV.utc_now(),
	}
	BV.save_state(state, state_path)
	if bool(r.sync):
		sync(cfg_path, base_name, base_code, base_code)
	return state

## The first preset that declares a version/code — the numbers a project without a stamp file
## should start from, so enabling the addon never resets a store counter.
static func first_versioned(cfg_path: String) -> Dictionary:
	var text := _read(cfg_path)
	for name: String in preset_names(text):
		if not _declares(text, name).has("version/code"):
			continue
		var declared := read_preset(cfg_path, name)
		declared["preset"] = name
		return declared
	return {}

## The numbers the build that starts right now should carry: the pending ones, seeded from an
## export preset when the project has no stamp yet. Writing nothing here is deliberate — an export
## that is cancelled must not eat a number, and the editor rewrites export_presets.cfg from its own
## memory in the middle of an export, so the counter is only safe to move once it is over.
static func build_numbers(preset_name := "", seed_name := "", seed_code := 0,
		cfg_path := BV.PRESETS_PATH, state_path := BV.BUILD_INFO_PATH) -> Dictionary:
	var r := rules()
	var state := BV.load_state(state_path)
	if state.is_empty():
		state = ensure_state(preset_name, seed_code, seed_name, cfg_path, state_path)
	var used_name := str(state[BV.KEY_NEXT_NAME])
	if used_name.is_empty():
		used_name = str(r.seed_name)
	var used_code := int(state[BV.KEY_NEXT_CODE])
	var used_store := int(state[BV.KEY_NEXT_STORE]) if bool(r.store_rises) else used_code
	return {BV.KEY_NAME: used_name, BV.KEY_CODE: used_code, BV.KEY_STORE: used_store}

## Records the build that just happened: the stamp prints these numbers, the pending ones move on,
## and export_presets.cfg is raised to what the next build will carry.
static func record_build(used: Dictionary, event: String, preset_name := "",
		cfg_path := BV.PRESETS_PATH, state_path := BV.BUILD_INFO_PATH) -> Dictionary:
	var r := rules()
	var state := BV.load_state(state_path)
	if state.is_empty():
		state = ensure_state(preset_name, int(used.get(BV.KEY_CODE, 0)), str(used.get(BV.KEY_NAME, "")),
			cfg_path, state_path)
	var used_name := str(used.get(BV.KEY_NAME, state[BV.KEY_NEXT_NAME]))
	var used_code := int(used.get(BV.KEY_CODE, state[BV.KEY_NEXT_CODE]))
	var used_store := int(used.get(BV.KEY_STORE, used_code))
	var nxt := next_after(used_name, used_code, int(r.limit), str(r.component), int(r.first))
	var next_store := int(nxt[BV.KEY_CODE]) if not bool(r.store_rises) else used_store + 1
	var record := {
		BV.KEY_NAME: used_name,
		BV.KEY_CODE: used_code,
		BV.KEY_STORE: used_store,
		BV.KEY_TOTAL: int(state[BV.KEY_TOTAL]) + 1,
		BV.KEY_NEXT_NAME: nxt[BV.KEY_NAME],
		BV.KEY_NEXT_CODE: nxt[BV.KEY_CODE],
		BV.KEY_NEXT_STORE: next_store,
		BV.KEY_EVENT: event,
		BV.KEY_PRESET: preset_name,
		BV.KEY_UPDATED: BV.utc_now(),
	}
	var written := BV.save_state(record, state_path)
	if bool(r.sync):
		sync(cfg_path, str(nxt[BV.KEY_NAME]), int(nxt[BV.KEY_CODE]), next_store)
	return {"used": {BV.KEY_NAME: used_name, BV.KEY_CODE: used_code, BV.KEY_STORE: used_store},
		"state": record, "written": written}

## Records one build — an editor run or an export — in a single step, and returns the numbers it
## got. The run hook uses this because the process that is about to boot must already find its own
## stamp on disk.
static func commit(event: String, preset_name := "", seed_name := "", seed_code := 0,
		cfg_path := BV.PRESETS_PATH, state_path := BV.BUILD_INFO_PATH) -> Dictionary:
	var used := build_numbers(preset_name, seed_name, seed_code, cfg_path, state_path)
	return record_build(used, event, preset_name, cfg_path, state_path)

## Manual bump (toolbar right click / Project menu): raises the number for the next build without
## pretending a build happened, so the label in the editor keeps showing the last real one.
static func advance_pending(cfg_path := BV.PRESETS_PATH, state_path := BV.BUILD_INFO_PATH) -> Dictionary:
	var r := rules()
	var state := BV.load_state(state_path)
	if state.is_empty():
		# Nothing was counted yet: start the record at the first build instead of pretending a
		# bump happened, so the developer's next run still prints build = first_build.
		state = ensure_state("", 0, "", cfg_path, state_path)
		return {"from": 0, "to": int(state[BV.KEY_NEXT_CODE]), "state": state, "written": true}
	var from_code := int(state[BV.KEY_NEXT_CODE])
	var from_name := str(state[BV.KEY_NEXT_NAME])
	var nxt := next_after(from_name, from_code, int(r.limit), str(r.component), int(r.first))
	var next_store := int(nxt[BV.KEY_CODE]) if not bool(r.store_rises) else int(state[BV.KEY_NEXT_STORE]) + 1
	state[BV.KEY_NEXT_NAME] = nxt[BV.KEY_NAME]
	state[BV.KEY_NEXT_CODE] = nxt[BV.KEY_CODE]
	state[BV.KEY_NEXT_STORE] = next_store
	state[BV.KEY_EVENT] = "manual"
	state[BV.KEY_UPDATED] = BV.utc_now()
	var written := BV.save_state(state, state_path)
	if bool(r.sync):
		sync(cfg_path, str(nxt[BV.KEY_NAME]), int(nxt[BV.KEY_CODE]), next_store)
	return {"from": from_code, "to": int(nxt[BV.KEY_CODE]), "state": state, "written": written}

## Sets the release version by hand: the build count restarts at first_build, which is what a new
## version line is supposed to look like. The store code keeps rising regardless, because a store
## never accepts a number it has already seen.
static func set_version(value_name: String, cfg_path := BV.PRESETS_PATH, state_path := BV.BUILD_INFO_PATH) -> Dictionary:
	var r := rules()
	var state := BV.load_state(state_path)
	if state.is_empty():
		state = {BV.KEY_NAME: value_name, BV.KEY_CODE: 0, BV.KEY_STORE: 0, BV.KEY_TOTAL: 0,
			BV.KEY_NEXT_NAME: value_name, BV.KEY_NEXT_CODE: 0, BV.KEY_NEXT_STORE: 0}
	var first := int(r.first)
	var previous_store := int(state[BV.KEY_NEXT_STORE])
	state[BV.KEY_NAME] = value_name
	state[BV.KEY_CODE] = 0
	state[BV.KEY_NEXT_NAME] = value_name
	state[BV.KEY_NEXT_CODE] = first
	state[BV.KEY_NEXT_STORE] = previous_store + 1 if bool(r.store_rises) else first
	state[BV.KEY_EVENT] = "set_version"
	state[BV.KEY_UPDATED] = BV.utc_now()
	BV.save_state(state, state_path)
	if bool(r.sync):
		sync(cfg_path, value_name, first, int(state[BV.KEY_NEXT_STORE]))
	return state

## Presets whose mirrored fields do not carry the given numbers. An empty array means the file and
## the counter agree. Used to notice the editor rewriting export_presets.cfg from its own copy —
## which leaves a preset behind with the numbers of the build that just happened.
static func out_of_sync(cfg_path: String, value_name: String, build_code: int, store_code: int) -> Array[String]:
	var text := _read(cfg_path)
	if text.is_empty():
		return []
	return rewrite(text, value_name, build_code, store_code).presets

## Rewrites export_presets.cfg so every preset carries the given numbers.
static func sync(cfg_path: String, value_name: String, build_code: int, store_code: int) -> Dictionary:
	var text := _read(cfg_path)
	if text.is_empty():
		return {"presets": [], "changed": false}
	var result := rewrite(text, value_name, build_code, store_code)
	var changed := str(result.text) != text
	if changed:
		var writer := FileAccess.open(cfg_path, FileAccess.WRITE)
		if writer == null:
			push_warning("Build Version Label: could not write %s (%s)" % [cfg_path, error_string(FileAccess.get_open_error())])
			return {"presets": [], "changed": false}
		writer.store_string(str(result.text))
		writer.close()
	return {"presets": result.presets, "changed": changed}

## Pure text work, safe to unit-test: returns the rewritten cfg plus the presets it touched.
## Anything the preset does not declare stays byte-for-byte as it was, line endings included.
static func rewrite(text: String, value_name: String, build_code: int, store_code: int,
		only_preset: String = "") -> Dictionary:
	var lines: PackedStringArray = text.split("\n")
	var touched: Array[String] = []
	var in_options := false
	var preset_name := ""
	var marked := false
	for index: int in lines.size():
		var line: String = lines[index]
		var trimmed := line.strip_edges()
		if trimmed.begins_with("[preset."):
			var header := trimmed.trim_prefix("[preset.").trim_suffix("]")
			in_options = header.ends_with(".options")
			if in_options:
				marked = false
			else:
				# "[preset.0]" holds the preset's own keys; "[preset.0.credentials]" holds signing.
				preset_name = ""
			continue
		if not in_options:
			if preset_name.is_empty() and trimmed.begins_with("name="):
				preset_name = bare(trimmed.trim_prefix("name="))
			continue
		if not only_preset.is_empty() and preset_name != only_preset:
			continue
		for field in FIELDS:
			var key := str(field.key)
			if not trimmed.begins_with(key + "="):
				continue
			var rendered := _field_value(str(field.value), value_name, build_code, store_code)
			if rendered.is_empty():
				continue
			var indent := line.substr(0, line.length() - line.lstrip(" \t").length())
			var ending := "\r" if line.ends_with("\r") else ""
			var fresh := indent + key + "=" + rendered + ending
			if fresh == line:
				continue
			lines[index] = fresh
			if not marked and not touched.has(preset_name):
				touched.append(preset_name)
			marked = true
	return {"text": "\n".join(lines), "presets": touched}

## The right-hand side for a field: bare int for codes, quoted for strings, "" to skip the line.
static func _field_value(kind: String, value_name: String, build_code: int, store_code: int) -> String:
	match kind:
		"code":
			return str(store_code)
		"name":
			return "\"%s\"" % value_name
		"windows":
			var fitted := BV.windows_version(value_name, store_code)
			return "\"%s\"" % fitted if not fitted.is_empty() else ""
	return ""

## Values a preset carries right now — used to warn when the editor's in-memory copy and the file
## disagree, which would make a manifest repeat a number.
static func read_preset(cfg_path: String, preset_name: String) -> Dictionary:
	var text := _read(cfg_path)
	if text.is_empty():
		return {}
	var in_options := false
	var in_wanted := false
	var out := {BV.KEY_NAME: "", BV.KEY_CODE: -1}
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("[preset."):
			in_options = trimmed.ends_with(".options]")
			if not in_options:
				in_wanted = false
			continue
		if not in_options:
			if trimmed.begins_with("name="):
				in_wanted = bare(trimmed.trim_prefix("name=")) == preset_name
			continue
		if not in_wanted:
			continue
		if trimmed.begins_with("version/code="):
			out[BV.KEY_CODE] = int(trimmed.trim_prefix("version/code="))
		elif trimmed.begins_with("version/name="):
			out[BV.KEY_NAME] = bare(trimmed.trim_prefix("version/name="))
	return out

## Presets that declare at least one mirrored option, for the toolbar dialog to list.
static func versioned_presets(cfg_path: String) -> Array[String]:
	var out: Array[String] = []
	var text := _read(cfg_path)
	for name: String in preset_names(text):
		var declared := _declares(text, name)
		if not declared.is_empty():
			out.append(name)
	return out

static func preset_names(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var in_meta := false
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("[preset."):
			# Sections read "[preset.0]", "[preset.0.options]", "[preset.0.credentials]";
			# the bare one holds the preset's own keys, including its name.
			in_meta = trimmed.trim_suffix("]").count(".") == 1
			continue
		if in_meta and trimmed.begins_with("name="):
			out.append(bare(trimmed.trim_prefix("name=")))
	return out

## Which mirrored keys one preset declares, so the report can say what actually got synced.
static func _declares(text: String, preset_name: String) -> Array[String]:
	var out: Array[String] = []
	var in_options := false
	var in_wanted := false
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("[preset."):
			in_options = trimmed.ends_with(".options]")
			if not in_options:
				in_wanted = false
			continue
		if not in_options:
			if trimmed.begins_with("name="):
				in_wanted = bare(trimmed.trim_prefix("name=")) == preset_name
			continue
		if not in_wanted:
			continue
		for field in FIELDS:
			var key := str(field.key)
			if trimmed.begins_with(key + "=") and not out.has(key):
				out.append(key)
	return out

static func bare(value: String) -> String:
	var out := value.strip_edges()
	if out.length() > 1 and out.begins_with("\"") and out.ends_with("\""):
		out = out.substr(1, out.length() - 2)
	return out

static func _read(cfg_path: String) -> String:
	var reader := FileAccess.open(cfg_path, FileAccess.READ)
	if reader == null:
		return ""
	var text := reader.get_as_text()
	reader.close()
	return text
