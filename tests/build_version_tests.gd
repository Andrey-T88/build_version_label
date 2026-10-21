extends SceneTree

## Headless tests for the counter rules and the export_presets.cfg rewriting.
##
##     godot --headless --path . --script tests/build_version_tests.gd
##
## Everything runs against throwaway files in user://, so the demo project's own stamp and preset
## file are never touched. Exits non-zero when an assertion fails, which is what CI looks at.

const BV := preload("res://addons/build_version_label/build_version.gd")
const Bump := preload("res://addons/build_version_label/version_bump.gd")

## A two-preset project: desktop (no version fields, but Windows file/product version) and mobile
## (the store fields). Mirrors what a real export_presets.cfg looks like.
const FIXTURE := """[preset.0]

name="Windows Desktop"
platform="Windows Desktop"

[preset.0.options]

binary_format/architecture="x86_64"
application/file_version=""
application/product_version=""
export_filter="all_resources"

[preset.1]

name="Android"
platform="Android"

[preset.1.options]

version/code=1
version/name=""
package/unique_name="com.example.game"
"""

var _checks := 0
var _fails := 0


func _initialize() -> void:
	_test_version_math()
	_test_limit_rules()
	_test_preset_rewrite()
	_test_state_file()
	_test_commit_sequence()
	_test_store_rising()
	_test_export_matches_run()
	_test_export_phases()
	_test_manual_paths()
	print("Build Version Label tests: %d checks, %d failed." % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# --- assertions -------------------------------------------------------------------------------

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_fails += 1
	printerr("FAIL: %s" % label)


func _expect_eq(actual: Variant, wanted: Variant, label: String) -> void:
	_expect(actual == wanted, "%s — got %s, wanted %s" % [label, str(actual), str(wanted)])


# --- fixtures ----------------------------------------------------------------------------------

## A private directory for one test, emptied first so a previous run cannot leak numbers into it.
func _workspace(name: String) -> String:
	var dir := "user://bvl_tests/%s" % name
	DirAccess.make_dir_recursive_absolute(dir)
	var entries := DirAccess.open(dir)
	if entries != null:
		entries.list_dir_begin()
		var entry := entries.get_next()
		while entry != "":
			if not entries.current_is_dir():
				entries.remove(entry)
			entry = entries.get_next()
		entries.list_dir_end()
	var cfg := "%s/export_presets.cfg" % dir
	_write(cfg, FIXTURE)
	return dir


func _write(path: String, text: String) -> void:
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(text)
	writer.close()


func _read(path: String) -> String:
	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null:
		return ""
	var text := reader.get_as_text()
	reader.close()
	return text


## The defaults the addon registers, so a test only has to name what it changes.
func _settings(overrides: Dictionary = {}) -> void:
	var all := BV.settings()
	for key: String in all:
		ProjectSettings.set_setting(key, all[key].default)
	for key: String in overrides:
		ProjectSettings.set_setting(key, overrides[key])


# --- tests -------------------------------------------------------------------------------------

func _test_version_math() -> void:
	_settings()
	_expect_eq(BV.parse_version("1.0.0").patch, 0, "parse 1.0.0 patch")
	_expect_eq(BV.parse_version("1.2").minor, 2, "parse 1.2 minor")
	_expect_eq(BV.parse_version("7").major, 7, "parse 7 major")
	_expect_eq(BV.parse_version("1.0.0-rc.1").tail, "-rc.1", "parse keeps the suffix")
	_expect_eq(BV.raise_component("1.0.0", "patch"), "1.0.1", "raise patch")
	_expect_eq(BV.raise_component("1.0.9", "minor"), "1.1.0", "raise minor zeroes the patch")
	_expect_eq(BV.raise_component("1.9.0", "major"), "2.0.0", "raise major zeroes the rest")
	_expect_eq(BV.raise_component("1.0.0-rc.1", "patch"), "1.0.1-rc.1", "raise keeps the suffix")
	_expect_eq(BV.raise_component("1.0.0", ""), "1.0.0", "no component leaves it alone")
	_expect_eq(BV.windows_version("1.2.3", 45), "1.2.3.45", "windows file version")
	_expect_eq(BV.windows_version("1.2.3", 100000), "", "a code above 16 bits does not fit")


func _test_limit_rules() -> void:
	# Variant B: never reset, the number just grows.
	var never := Bump.next_after("1.1.3", 9999999, 0, "", 1)
	_expect_eq(never[BV.KEY_CODE], 10000000, "no limit keeps counting")
	_expect_eq(never[BV.KEY_NAME], "1.1.3", "no limit never touches the version")
	_expect_eq(bool(never.limit_hit), false, "no limit never reports a hit")
	# Variant A: 1.0.0 build 9999 -> 1.0.1 build 1.
	var patch := Bump.next_after("1.0.0", 9999, 9999, "patch", 1)
	_expect_eq(patch[BV.KEY_NAME], "1.0.1", "the limit raises the patch")
	_expect_eq(patch[BV.KEY_CODE], 1, "the limit restarts the count at first_build")
	_expect_eq(bool(patch.limit_hit), true, "the limit reports a hit")
	_expect_eq(Bump.next_after("1.0.0", 9998, 9999, "patch", 1)[BV.KEY_CODE], 9999,
		"the last allowed build is still counted normally")
	var minor := Bump.next_after("1.0.9", 3, 3, "minor", 1)
	_expect_eq(minor[BV.KEY_NAME], "1.1.0", "the limit can raise the minor")
	var keep := Bump.next_after("1.0.0", 3, 3, "", 0)
	_expect_eq(keep[BV.KEY_NAME], "1.0.0", "reset only leaves the version alone")
	_expect_eq(keep[BV.KEY_CODE], 0, "reset only honours first_build = 0")


func _test_preset_rewrite() -> void:
	_settings()
	var result := Bump.rewrite(FIXTURE, "1.2.0", 13, 13)
	var text := str(result.text)
	var lines := text.split("\n")
	_expect(text.contains("version/code=13"), "the store code is written")
	_expect(text.contains("version/name=\"1.2.0\""), "the version name is written")
	_expect(text.contains("application/product_version=\"1.2.0\""), "the product version is written")
	_expect(text.contains("application/file_version=\"1.2.0.13\""), "the windows file version is written")
	_expect(text.contains("package/unique_name=\"com.example.game\""), "unrelated options survive")
	_expect(text.contains("export_filter=\"all_resources\""), "option order survives")
	_expect_eq(result.presets.size(), 2, "both presets declare mirrored fields")
	_expect_eq(text.replace("version/code=13", "").count("version/code"), 0,
		"a code line is never duplicated")
	# Line endings of a CRLF file must survive byte for byte.
	var crlf := FIXTURE.replace("\n", "\r\n")
	var kept := str(Bump.rewrite(crlf, "1.2.0", 7, 7).text)
	_expect_eq(kept.count("\r\n"), crlf.count("\r\n"), "CRLF endings are preserved")
	_expect(kept.contains("version/code=7\r\n"), "the rewritten line keeps its CRLF")
	# Nothing to change means nothing reported.
	var again := Bump.rewrite(str(result.text), "1.2.0", 13, 13)
	_expect_eq(again.presets.size(), 0, "an already synced file changes no preset")
	# A file without any mirrored field is left completely alone.
	var plain := Bump.rewrite("[preset.0]\n\nname=\"Linux\"\n\n[preset.0.options]\n\nbinary_format/architecture=\"x86_64\"\n", "1.0.0", 4, 4)
	_expect_eq(plain.presets.size(), 0, "a preset without version fields is skipped")
	_expect_eq(str(plain.text).count("binary_format"), 1, "its own options are untouched")


func _test_state_file() -> void:
	_settings()
	var dir := _workspace("state")
	var state_path := "%s/build_info.json" % dir
	_expect_eq(BV.load_state(state_path), {}, "no file means no state")
	# The shape an older release of the addon wrote: two keys, nothing else.
	_write(state_path, "{\"version_name\": \"1.0.0\", \"version_code\": 3}")
	var legacy := BV.load_state(state_path)
	_expect_eq(legacy[BV.KEY_NEXT_CODE], 4, "a legacy stamp continues from its code")
	_expect_eq(legacy[BV.KEY_NEXT_NAME], "1.0.0", "a legacy stamp keeps the name")
	_expect_eq(legacy[BV.KEY_TOTAL], 0, "a legacy stamp has counted nothing yet")
	BV.save_state(legacy, state_path)
	var round := BV.load_state(state_path)
	_expect_eq(round[BV.KEY_NEXT_CODE], 4, "the state survives a write/read round trip")
	_expect_eq(round[BV.KEY_NAME], "1.0.0", "the version name survives")
	var written := _read(state_path)
	_expect(written.find("\"version_name\"") < written.find("\"next_version_name\""),
		"the state file keeps a readable key order instead of sorting alphabetically")
	var view := BV.runtime_view(round)
	_expect_eq(view.has(BV.KEY_NEXT_CODE), false, "a package never carries the next build's numbers")
	_expect_eq(view.has(BV.KEY_NAME), true, "a package carries the version name")
	# A project that already set a version in its preset should not start from the seed setting.
	_settings({BV.SETTING_SEED_NAME: "2.5.0"})
	var from_preset := Bump.ensure_state("Android", 0, "", dir + "/export_presets.cfg", "%s/fresh.json" % dir)
	_expect_eq(from_preset[BV.KEY_NAME], "2.5.0", "a version-less preset falls back to the seed")
	_expect_eq(from_preset[BV.KEY_CODE], 1, "the first build starts at first_build")
	_expect_eq(from_preset[BV.KEY_TOTAL], 0, "creating the stamp counts no build")


func _test_commit_sequence() -> void:
	# The user's variant A: three builds per version, then raise the patch and restart at 1.
	_settings({
		BV.SETTING_BUILDS_PER_VERSION: 3,
		BV.SETTING_ON_LIMIT: 2,
		BV.SETTING_FIRST_BUILD: 1,
		BV.SETTING_SEED_NAME: "1.0.0",
	})
	var dir := _workspace("sequence")
	var cfg := "%s/export_presets.cfg" % dir
	var state_path := "%s/build_info.json" % dir
	var wanted := [
		["1.0.0", 1], ["1.0.0", 2], ["1.0.0", 3],
		["1.0.1", 1], ["1.0.1", 2], ["1.0.1", 3], ["1.0.2", 1],
	]
	for i in wanted.size():
		var result := Bump.commit("run", "", "", 0, cfg, state_path)
		var used: Dictionary = result.used
		_expect_eq([str(used[BV.KEY_NAME]), int(used[BV.KEY_CODE])], [wanted[i][0], wanted[i][1]],
			"build %d of the sequence" % (i + 1))
		var record: Dictionary = result.state
		_expect_eq(int(record[BV.KEY_TOTAL]), i + 1, "every build is counted")
		# The label in the running game reads exactly the numbers of that build.
		_expect_eq(BV.render(BV.runtime_view(record)), "Version %s (build %d)" % [wanted[i][0], wanted[i][1]],
			"the stamp prints the build it carries")
	# The preset file must always hold the numbers of the *next* build, because an export cannot
	# change the manifest it is already writing.
	var file := _read(cfg)
	var after := BV.load_state(state_path)
	var next_code := int(after[BV.KEY_NEXT_CODE])
	_expect(file.contains("version/code=%d" % next_code), "the preset carries the next build's code")
	_expect(file.contains("version/name=\"%s\"" % str(after[BV.KEY_NEXT_NAME])),
		"the preset carries the next build's version")


func _test_store_rising() -> void:
	# Same reset rule, but the store number keeps climbing so a store never sees a repeat.
	_settings({
		BV.SETTING_BUILDS_PER_VERSION: 2,
		BV.SETTING_ON_LIMIT: 2,
		BV.SETTING_STORE_MODE: 1,
		BV.SETTING_SEED_NAME: "1.0.0",
	})
	var dir := _workspace("store")
	var cfg := "%s/export_presets.cfg" % dir
	var state_path := "%s/build_info.json" % dir
	var first := Bump.commit("export", "Android", "", 0, cfg, state_path)
	_expect_eq(int(first.state[BV.KEY_STORE]), 1, "the first build takes store code 1")
	var second := Bump.commit("export", "Android", "", 0, cfg, state_path)
	_expect_eq(int(second.used[BV.KEY_CODE]), 2, "the second build is build 2")
	var third := Bump.commit("export", "Android", "", 0, cfg, state_path)
	_expect_eq([str(third.used[BV.KEY_NAME]), int(third.used[BV.KEY_CODE])], ["1.0.1", 1],
		"the limit restarts the displayed build")
	_expect_eq(int(third.used[BV.KEY_STORE]), 3, "the store code ignores the restart")
	_expect(_read(cfg).contains("version/code=%d" % int(third.state[BV.KEY_NEXT_STORE])),
		"the preset gets the rising store code")
	_expect_eq(int(third.state[BV.KEY_NEXT_STORE]), 4, "the next store code is ready")


func _test_export_matches_run() -> void:
	# The whole point: one counter for the project, so every platform and every editor run print
	# the same version line instead of each preset keeping its own numbers.
	_settings({BV.SETTING_BUILDS_PER_VERSION: 0, BV.SETTING_SEED_NAME: "3.1.4"})
	var dir := _workspace("match")
	var cfg := "%s/export_presets.cfg" % dir
	var state_path := "%s/build_info.json" % dir
	var run := Bump.commit("run", "", "", 0, cfg, state_path)
	var android := Bump.commit("export", "Android", "9.9.9", 77, cfg, state_path)
	var desktop := Bump.commit("export", "Windows Desktop", "9.9.9", 77, cfg, state_path)
	_expect_eq(str(android.used[BV.KEY_NAME]), "3.1.4", "a stamp already in progress ignores the preset seed")
	_expect_eq(int(android.used[BV.KEY_CODE]), int(run.state[BV.KEY_NEXT_CODE]),
		"the export takes the number the run left pending")
	_expect_eq([str(run.used[BV.KEY_NAME]), int(run.used[BV.KEY_CODE])], ["3.1.4", 1], "the run is build 1")
	_expect_eq(int(android.used[BV.KEY_CODE]), 2, "the first export is build 2")
	_expect_eq(int(desktop.used[BV.KEY_CODE]), 3, "the second export is build 3, on another platform")
	_expect_eq(str(desktop.used[BV.KEY_NAME]), str(run.used[BV.KEY_NAME]),
		"the version name does not depend on the platform")
	_expect_eq(BV.render(BV.runtime_view(run.state)), "Version 3.1.4 (build 1)",
		"the label prints the build the stamp carries")
	_expect_eq(int(desktop.state[BV.KEY_TOTAL]), 3, "all three events counted one build each")
	# Both presets in the file must now hold the same pending number — that is what makes the
	# Android manifest and the desktop properties agree with the in-game label.
	var file := _read(cfg)
	var pending := int(BV.load_state(state_path)[BV.KEY_NEXT_CODE])
	_expect_eq(file.count("version/code=%d" % pending), 1, "the mobile preset holds the pending code")
	_expect_eq(file.count("application/product_version=\"3.1.4\""), 1, "the desktop preset holds the same version")
	_expect(not file.contains("version/code=1\n"), "no preset keeps its old number")
	# Seeding from a preset that already has a store number must not restart it.
	var seeded_dir := _workspace("seeded")
	var seeded_state := "%s/build_info.json" % seeded_dir
	_write("%s/export_presets.cfg" % seeded_dir,
		FIXTURE.replace("version/code=1", "version/code=42").replace("version/name=\"\"", "version/name=\"2.0.0\""))
	var seeded := Bump.commit("export", "Android", "2.0.0", 42, "%s/export_presets.cfg" % seeded_dir, seeded_state)
	_expect_eq([str(seeded.used[BV.KEY_NAME]), int(seeded.used[BV.KEY_CODE])], ["2.0.0", 42],
		"the first export ships the numbers the developer set")
	_expect_eq(int(BV.load_state(seeded_state)[BV.KEY_NEXT_CODE]), 43, "the next build continues from 42")


## The two export phases the plugin splits an export into, and the run that follows it.
func _test_export_phases() -> void:
	# An export decides its numbers at the very start (its manifest is already being written by then)
	# but records them only when it is over: the editor rewrites export_presets.cfg from its own
	# memory during the export, and a cancelled export must not eat a number.
	_settings({BV.SETTING_BUILDS_PER_VERSION: 0, BV.SETTING_SEED_NAME: "1.0.0"})
	var dir := _workspace("phases")
	var cfg := "%s/export_presets.cfg" % dir
	var state_path := "%s/build_info.json" % dir
	var begin := Bump.build_numbers("Android", "", 0, cfg, state_path)
	_expect_eq([str(begin[BV.KEY_NAME]), int(begin[BV.KEY_CODE])], ["1.0.0", 1],
		"the export starts at the number the preset declares")
	_expect_eq(int(Bump.build_numbers("Android", "", 0, cfg, state_path)[BV.KEY_CODE]), 1,
		"asking twice for the same build changes nothing")
	var pending := BV.load_state(state_path)
	_expect_eq(int(pending[BV.KEY_TOTAL]), 0, "an export that has not finished counted no build")
	_expect(_read(cfg).contains("version/code=1"), "the preset keeps the number of the build in progress")
	# The developer hits Cancel: record_build() never runs, so the next attempt starts from the same
	# number instead of skipping one.
	var retry := Bump.build_numbers("Android", "", 0, cfg, state_path)
	_expect_eq(int(retry[BV.KEY_CODE]), int(begin[BV.KEY_CODE]),
		"a cancelled export leaves its number to the next one")
	var after: Dictionary = Bump.record_build(begin, "export", "Android", cfg, state_path).state
	_expect_eq(int(after[BV.KEY_TOTAL]), 1, "the finished export counted one build")
	_expect_eq(int(after[BV.KEY_NEXT_CODE]), 2, "the next build is pending")
	_expect(_read(cfg).contains("version/code=2"), "the preset was raised only once the export was over")
	# A run afterwards continues the same counter — and its stamp already carries its own numbers,
	# because the pre-run hook records before the project boots.
	var run := Bump.commit("run", "", "", 0, cfg, state_path)
	_expect_eq(int(run.used[BV.KEY_CODE]), 2, "the run takes build 2, right after the export")
	_expect_eq(BV.render(BV.runtime_view(run.state)), "Version 1.0.0 (build 2)",
		"the stamp a run leaves on disk prints that run")
	_expect(_read(cfg).contains("version/code=3"), "the preset holds the number of the next build")
	# The lag the editor can leave behind is detectable: a file that matches the counter reports
	# nothing, a preset sitting on the build that just shipped reports itself — and only that preset.
	_expect_eq(Bump.out_of_sync(cfg, "1.0.0", 3, 3).size(), 0, "an in-sync file reports nothing")
	_write(cfg, _read(cfg).replace("version/code=3", "version/code=2"))
	var lagged := Bump.out_of_sync(cfg, "1.0.0", 3, 3)
	_expect_eq(lagged.size(), 1, "a preset one build behind is reported")
	_expect_eq(lagged.has("Android"), true, "and it is the mobile preset that lagged")
	_expect_eq(Bump.out_of_sync(cfg, "1.0.0", 2, 2).has("Android"), false,
		"the lagging preset matches the previous build, which is what makes it repairable")
	Bump.sync(cfg, "1.0.0", 3, 3)
	_expect_eq(Bump.out_of_sync(cfg, "1.0.0", 3, 3).size(), 0, "re-syncing clears the lag")


func _test_manual_paths() -> void:
	_settings({BV.SETTING_BUILDS_PER_VERSION: 5, BV.SETTING_ON_LIMIT: 2, BV.SETTING_SEED_NAME: "1.0.0"})
	var dir := _workspace("manual")
	var cfg := "%s/export_presets.cfg" % dir
	var state_path := "%s/build_info.json" % dir
	var raised := Bump.advance_pending(cfg, state_path)
	_expect_eq(int(raised["to"]), 1, "raising from nothing lands on first_build")
	_expect_eq(bool(raised.written), true, "the stamp was written")
	Bump.advance_pending(cfg, state_path)
	var third := Bump.advance_pending(cfg, state_path)
	_expect_eq(int(third["to"]), 3, "manual bumps move the pending number")
	var record := BV.load_state(state_path)
	_expect_eq(int(record[BV.KEY_TOTAL]), 0, "a manual bump is not a build")
	_expect_eq(int(record[BV.KEY_CODE]), 1, "the last real build is untouched by a manual bump")
	# The limit applies to manual bumps too, so 5 builds per version cannot be walked past.
	# Three more bumps land on 4, 5 and then the restart.
	for i in 3:
		Bump.advance_pending(cfg, state_path)
	var over := BV.load_state(state_path)
	_expect_eq([str(over[BV.KEY_NEXT_NAME]), int(over[BV.KEY_NEXT_CODE])], ["1.0.1", 1],
		"manual bumps honour the builds-per-version rule")
	# Setting a version restarts the count for the new release line.
	var set := Bump.set_version("2.0.0", cfg, state_path)
	_expect_eq(str(set[BV.KEY_NEXT_NAME]), "2.0.0", "the new version is pending")
	_expect_eq(int(set[BV.KEY_NEXT_CODE]), 1, "the count restarts for the new version")
	var built := Bump.commit("run", "", "", 0, cfg, state_path)
	_expect_eq([str(built.used[BV.KEY_NAME]), int(built.used[BV.KEY_CODE])], ["2.0.0", 1],
		"the next build prints the version that was set")
	_expect(_read(cfg).contains("version/name=\"2.0.0\""), "the presets show the version that was set")
