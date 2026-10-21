class_name BuildVersionBump
extends RefCounted

## Rewrites version/code in export_presets.cfg. Kept out of the export plugin so it can be
## tested without an editor: the plugin only decides when to call it.
## Only the matched preset's line changes — every other byte of the file stays put,
## including line endings.

static func advance(cfg_path: String, preset_name: String, code: int) -> bool:
	var reader := FileAccess.open(cfg_path, FileAccess.READ)
	if reader == null:
		push_warning("Build Version Label: could not read %s (%s)" % [cfg_path, error_string(FileAccess.get_open_error())])
		return false
	var text := reader.get_as_text()
	reader.close()
	var updated := rewritten(text, preset_name, code)
	if updated == text:
		return false
	var writer := FileAccess.open(cfg_path, FileAccess.WRITE)
	if writer == null:
		push_warning("Build Version Label: could not write %s" % cfg_path)
		return false
	writer.store_string(updated)
	writer.close()
	return true


static func rewritten(text: String, preset_name: String, code: int) -> String:
	var lines: PackedStringArray = text.split("\n")
	var in_options := false
	var in_wanted := false
	var changed := false
	for index: int in lines.size():
		var line: String = lines[index]
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
		if in_wanted and trimmed.begins_with("version/code="):
			var indent := line.substr(0, line.length() - line.lstrip(" \t").length())
			var ending := "\r" if line.ends_with("\r") else ""
			lines[index] = indent + "version/code=%d" % code + ending
			changed = true
	if not changed:
		push_warning("Build Version Label: export_presets.cfg has no version/code for preset \"%s\" — nothing raised." % preset_name)
		return text
	return "\n".join(lines)


static func bare(value: String) -> String:
	var out := value.strip_edges()
	if out.length() > 1 and out.begins_with("\"") and out.ends_with("\""):
		out = out.substr(1, out.length() - 2)
	return out


## The code the file carries right now, or -1 when the preset has none.
static func current_code(cfg_path: String, preset_name: String) -> int:
	var text := _read(cfg_path)
	if text.is_empty():
		return -1
	return _code_in(text, preset_name)


## Manual bump used by the toolbar button: raises the first preset that declares
## a version/code, since that is the one the developer exports.
static func bump_next_versioned_preset(cfg_path: String) -> Dictionary:
	var text := _read(cfg_path)
	if text.is_empty():
		return {}
	for name: String in _preset_names(text):
		var code := _code_in(text, name)
		if code < 0:
			continue
		if advance(cfg_path, name, code + 1):
			return {"preset": name, "from": code, "to": code + 1}
	return {}


static func _read(cfg_path: String) -> String:
	var reader := FileAccess.open(cfg_path, FileAccess.READ)
	if reader == null:
		return ""
	var text := reader.get_as_text()
	reader.close()
	return text


static func _preset_names(text: String) -> PackedStringArray:
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


static func _code_in(text: String, preset_name: String) -> int:
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
		if in_wanted and trimmed.begins_with("version/code="):
			return int(trimmed.trim_prefix("version/code="))
	return -1
