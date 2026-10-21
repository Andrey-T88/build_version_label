# Changelog

## 3.0.0

One counter for the whole project: builds are no longer an Android-export event.

- Every **Run Project (F5/F6)** in the editor counts as a build. `plugin.gd::_build()` records it
  before the project boots, so the label in the running game prints its own number; an
  `is_playing_scene()` check in `_process()` covers the paths that skip that hook (older engines,
  embedded play), with a cooldown so one run is never counted twice.
- Every **export, on any platform**, counts as a build — `_supports_platform()` no longer limits
  itself to Android. Desktop `application/file_version` / `product_version` and the mobile
  `version/code` / `version/name` all come from the same counter, so every export shows the same
  version.
- The counter now lives in `config/build_info.json` as state: the last build
  (`version_name`/`version_code`/`store_code`), the pending numbers of the next build
  (`next_*`), `total_builds`, and `event`/`preset`/`updated`. A package only ever receives the
  runtime view — the numbers of the build it is.
- Counting rules in Project Settings: `builds_per_version` plus `on_limit_reached` give both
  variants — `1.0.0 (build 9999)` -> `1.0.1 (build 1)`, or a build code that rises without end;
  `first_build` picks where a restarted count begins and `store_code_mode = Always rising` keeps
  the store code monotonic while the displayed build resets.
- The pending numbers are pushed into the **live export preset** at `_export_begin`, so a build
  exports the right version code without reloading the project — the manifest is generated from
  the preset object, and that is the only moment the editor hands one out.
- The counter is written in `_export_end()` instead of at the start: the editor rewrites
  `export_presets.cfg` from its own in-memory copy during a GUI export, which used to leave a
  preset one build behind the stamp. A cancelled export no longer consumes a number, and
  `Bump.build_numbers()` / `Bump.record_build()` split the two phases for that.
- Once a second the addon compares the preset file with the counter and repairs a preset the
  editor left on the previous build (`Bump.out_of_sync()`); a version typed by hand is reported
  in the details dialog instead of being silently reverted.
- New Project Settings: `bump_on_run`, `bump_on_export`, `builds_per_version`, `on_limit_reached`,
  `first_build`, `store_code_mode`, `sync_export_presets`, `seed_version_name`,
  `create_missing_stamp`.
- `export_presets.cfg` rewriting preserves everything else byte for byte, CRLF endings included,
  and skips Windows file versions whose components do not fit 16 bits.
- A stamp written by 2.x (two keys only) is read and completed on the fly: the next build
  continues from its `version_code`, so upgrading never restarts a store counter.
- Toolbar button now shows `last -> next`, the details dialog lists the rule in effect, the
  presets carrying version fields and their sync state, and can set a version by hand (which
  restarts the count).
- `tests/build_version_tests.gd`: 114 headless checks over the version arithmetic, the limit
  rules, the preset rewriting, the state file, the export/run phases and the manual bumps.

## 2.1.0

- New `display_format_preset` Project Setting: a dropdown of ready-made label formats
  (`Version 1.2.0 (build 21)`, `v1.2.0 (21)`, `1.2.0 (21)`, `1.2.0+21`, `1.2.0`, Custom).
- `display_label_format` now only applies when the preset is **Custom**, and any format may use
  just the placeholders it needs — `BuildVersion.apply_format()` passes only `%s`/`%d` values the
  string actually consumes, avoiding Godot's "not all arguments converted" formatting error that
  otherwise leaves the raw format string on screen.
- New `BuildVersion.render(info)` / `BuildVersion.display_format()` helpers, so game code does not
  have to repeat the format string.
- The toolbar dialog prints the format currently in effect.

## 2.0.0

- Addon is now project-agnostic: no `DuoStory` branding in plugin.cfg, export plugin name,
  or printed messages, so the folder can be copied straight into any project.
- New editor toolbar button showing the live build version. Left click opens a details
  dialog, right click bumps `version/code` without exporting.
- New **Project → Tools → Build Version: bump build code** menu entry (same manual bump).
- New Project Settings group `build_version_label` with `display_label_format` and
  `fallback_version`, registered automatically when the plugin is enabled.
- The build stamp is now added to the package directly during export, so a project using the
  addon no longer needs a placeholder `config/build_info.json` file to exist.
- `BuildVersionLabel` falls back to the configured `fallback_version` instead of a non-existent
  `application/config/version` setting, which is not defined in Godot 4.
- Split shared paths/helpers into `build_version.gd` and preset rewriting into `version_bump.gd`
  (`class_name BuildVersionBump`), so the file-editing logic is testable headless without an export.
- Added README.md, LICENSE.md (MIT), CHANGELOG.md for Asset Library publication.

## 1.1

- Embed version fields into `config/build_info.json` during Android export.
- Raise `version/code` for the next build; warn on a stale editor preset.
- Register the `BuildVersionLabel` custom node type.

## 1.0

- Initial export hook that reads the Android preset version and stamps it into the build.
