# Build Version Label

Keep every build of your Godot game tagged with a version you never have to remember to bump.

On each Android export the addon:

1. reads `version/name` and `version/code` from the export preset,
2. embeds them into `config/build_info.json` inside the exported package,
3. raises `version/code` in `export_presets.cfg` by one, so the next export is always a
   different build and Google Play never rejects a repeated version code.

At runtime a `BuildVersionLabel` node prints the same values in any scene with no script of
its own. The editor gets a toolbar button showing the current version and a Project menu
entry that bumps the build code without exporting.

Tested on Godot **4.7.2** (should work on any Godot 4.x with Android export).

## Install

1. Copy the whole `build_version_label/` folder into your project's `addons/` directory.
2. **Project → Project Settings → Plugins** (or **Project → Tools → Plugins**) and tick
   **Build Version Label**.
3. Enable the Android export preset's version fields:
   **Project → Export → <your preset> → Android → Version Code** and **Version Name**.
   The addon only changes `version/code`; `version/name` stays yours to set.
4. Done. Nothing else to create — the addon writes the build stamp into the package itself,
   so you do **not** need a `config/build_info.json` file in your project.

The addon adds no autoloads and touches no scene, so enabling it cannot break an existing
project. Unchecking the plugin returns the project to its previous state.

## Show the version in your game

Add the custom node type **BuildVersionLabel** (it is a `Label`) to any scene — the main menu,
a pause screen, a splash. It reads the build stamp by itself; no code needed.

```
MainMenu (Control)
└── VersionLabel (BuildVersionLabel)
```

Outside the editor (e.g. your own splash or debug overlay) you can read the same data from code:

```gdscript
var info := BuildVersion.read()          # {"version_name": "1.0.0", "version_code": 7}
if not info.is_empty():
    print(BuildVersion.render(info))     # whatever format you picked in Project Settings
```

Before the first export there is no stamp yet, so `BuildVersionLabel` shows the
`fallback_version` from Project Settings instead of an empty label.

## Settings

**Project → Project Settings → Build Version Label**

| Setting | Default | Meaning |
|---|---|---|
| `display_format_preset` | `Version 1.2.0 (build 21)` | Dropdown that picks the label format (see the table below). |
| `display_label_format` | `Version %s (build %d)` | Free-text format, used only when the preset is **Custom**. `%s` = version name, `%d` = version code. |
| `fallback_version` | `0.0.0` | Shown before the first build created `build_info.json`. |

All three are read live, so changing the format updates the label the next time it refreshes.

The presets exist so the common shapes are one click away:

| Preset | Prints |
|---|---|
| `Version 1.2.0 (build 21)` | `Version 1.2.0 (build 21)` |
| `v1.2.0 (21)` | `v1.2.0 (21)` |
| `1.2.0 (21)` | `1.2.0 (21)` |
| `1.2.0+21` | `1.2.0+21` |
| `1.2.0` | `1.2.0` |
| `Custom — use display_label_format` | whatever `display_label_format` says |

A format only has to use the placeholders it wants: `1.2.0` from `%s` alone is fine, and so is
`build %d` — the addon passes only the values the string actually consumes, because Godot's `%`
operator errors out (and prints the raw format) when an argument goes unused.

## Editor tools

- **Toolbar button** (canvas editor menu strip): shows `v<name> (build <code>)`.
  - Left click — a dialog with the current version info and the format in effect.
  - Right click — raises `version/code` of the first preset that has one, without exporting.
- **Project → Tools → Build Version: bump build code** — the same manual bump from the menu.

The manual bump is handy when you rebuild the same version repeatedly during testing and want
the Play Console to see distinct build numbers.

## How it decides the numbers

`version_name` is never touched — that is your release version. Only the numeric code advances,
and it advances past whichever is higher of "the preset the editor is exporting" and "the value
currently in `export_presets.cfg`". That guard matters: if the editor still holds a stale copy of
`export_presets.cfg` in memory (a known Godot behavior after an external edit), the plugin warns
and keeps the file's higher value instead of reusing a number.

If you export, get a warning about a stale preset, and then reload the project
(**Project → Reload Current Project**), the conflict disappears.

## Files

```
addons/build_version_label/
├── plugin.cfg              # addon metadata, loaded by the plugin list
├── plugin.gd               # editor side: settings, custom type, toolbar, menu
├── export_plugin.gd        # export hook: stamp + advance
├── build_version.gd        # shared paths, Project Settings keys, format choice, read() helper
├── build_version_label.gd  # the Label node
├── version_bump.gd         # pure export_presets.cfg rewriting (testable offline)
├── README.md / LICENSE.md / CHANGELOG.md
```

`version_bump.gd` is deliberately free of editor dependencies: it only reads and rewrites text,
so you can unit-test it in a headless run without an export.

## License

MIT — see `LICENSE.md`.
