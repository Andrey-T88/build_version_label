# Changelog

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
