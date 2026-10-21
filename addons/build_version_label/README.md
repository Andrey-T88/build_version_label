# Build Version Label

One build counter for the whole project. Every **Run Project (F5/F6)** in the editor and every
**export, on every platform**, is a build: the addon stamps its numbers into the package and
raises the number for the next one, so nobody has to remember to bump.

For each build it:

1. takes the pending numbers from `config/build_info.json` — the stamp the game reads,
2. pushes the same numbers into the export preset that is running, so the Play Store version
   code, the Windows file properties and the label in the game are one and the same number —
   **without a project reload**,
3. when the export is over, records the build and raises `export_presets.cfg` to the numbers
   the next build will carry.

An editor run does the same in one step *before* the game boots, so the `BuildVersionLabel` in
the running project already prints its own build number.

Tested on Godot **4.7.2** (anything Godot 4.x should work; the run hook needs 4.7 for the
pre-run callback, earlier versions fall back to the editor's playing flag).

## Install

1. Copy the whole `build_version_label/` folder into your project's `addons/` directory.
2. **Project → Project Settings → Plugins** (or **Project → Tools → Plugins**) and tick
   **Build Version Label**.
3. That is all. The addon creates `config/build_info.json` on the spot, and if an export preset
   already declares a `version/code`, that number is kept — enabling the addon never restarts a
   store counter Google Play already knows.

The addon adds no autoload and touches no scene, so enabling it cannot break an existing
project. Unchecking the plugin returns the project to its previous state.

## The two counting modes

**A build number that restarts with a new patch** — `builds_per_version = 9999`,
`on_limit_reached = Raise patch and restart the count`:

```
Version 1.0.0 (build 9998)
Version 1.0.0 (build 9999)   -> limit reached
Version 1.0.1 (build 1)
```

**A build number that just goes up forever** — `builds_per_version = 0`:

```
Version 1.1.3 (build 9999998)
Version 1.1.3 (build 9999999)
```

`on_limit_reached` also offers *raise minor*, *raise major* and *reset the code only*, and
`first_build` decides where a restarted count begins. `store_code_mode = Always rising` is the
pair for store uploads: the number you *see* may restart, while the `version/code` that goes to
the store keeps climbing.

## Settings

**Project → Project Settings → Build Version Label**

| Setting | Default | Meaning |
|---|---|---|
| `bump_on_run` | `true` | Every Run Project in the editor counts as a build. |
| `bump_on_export` | `true` | Every export, on any platform, counts as a build. |
| `builds_per_version` | `0` | How many builds one version may use. `0` = no limit. |
| `on_limit_reached` | raise patch | What happens after the last build of a version: keep counting, reset the code only, or raise patch / minor / major and restart. |
| `first_build` | `1` | The number a version starts at, and the very first build. |
| `store_code_mode` | same as build | `Always rising` keeps the store code monotonic when the displayed build restarts. |
| `sync_export_presets` | `true` | Mirror the numbers into every preset that declares version fields. |
| `seed_version_name` | `1.0.0` | Version name for the first stamp, when no preset supplies one. |
| `create_missing_stamp` | `true` | Create `config/build_info.json` when the plugin is enabled and the file is missing. |
| `display_format_preset` | `Version 1.2.0 (build 21)` | Dropdown that picks the label format. |
| `display_label_format` | `Version %s (build %d)` | Free-text format, used when the preset is **Custom**. `%s` = version name, `%d` = build code. |
| `fallback_version` | `0.0.0` | Shown before the first build created a stamp. |

The label format presets, in order:

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

## Show the version in your game

Add the custom node type **BuildVersionLabel** (it is a `Label`) to any scene — the main menu,
a pause screen, a splash. It reads the build stamp by itself; no code needed.

```
MainMenu (Control)
└── VersionLabel (BuildVersionLabel)
```

From your own splash or debug overlay:

```gdscript
var info := BuildVersion.read()          # {"version_name": "1.0.0", "version_code": 7, ...}
if not info.is_empty():
    print(BuildVersion.render(info))     # whatever format you picked in Project Settings
```

An exported package carries only the numbers of the build it is (`version_name`, `version_code`,
`store_code`, `total_builds`, `event`, `preset`, `updated`) — the pending numbers stay in the
project, so a package can never print a build that has not happened yet.

## Editor tools

- **Toolbar button** (canvas editor menu strip): `Version 1.0.0 (build 12)  ->  build 13`.
  - Left click — details: the last and the next build, the counting rule in effect, which events
    are counted, the store mode, and whether every export preset carries the pending numbers.
    It also sets a version by hand, which restarts the count for the new release line.
  - Right click — raise the pending build code without running or exporting anything.
- **Project → Tools → Build Version: raise the next build code** — the same manual bump.
- **Project → Tools → Build Version: details and set version** — the details dialog.

A manual bump is not a build: `total_builds` only moves when a run or an export really happened.

## How the numbers are decided

`config/build_info.json` holds the counter:

```
version_name / version_code / store_code   the build that just happened — what the label prints
next_version_name / next_version_code      what the next build gets
next_store_code                             the store number of the next build
total_builds                                every run and every export, since the addon was enabled
event / preset / updated                    what the last build was, and when
```

Why the preset file always holds the *next* build's numbers: a package's manifest is generated
from the export preset before a plugin can change anything, so the only way an export can ship
the right code is to have it already in place. The stamp inside the package is remapped during
the export, which is why both agree.

Two guards keep a number from being used twice or lost:

- the counter is written **after** an export ends, so cancelling an export does not burn a build;
- once a second the addon compares `export_presets.cfg` with the counter, and if the editor
  wrote a preset back to the build that already shipped — which it does, from its own in-memory
  copy, in the middle of a GUI export — it raises that preset back. A number you typed by hand
  is never reverted; the details dialog only reports it.

If the Export panel shows an old number, the value on disk is still the one the next export
uses; **Project → Reload Current Project** refreshes the panel.

## Files

```
addons/build_version_label/
├── plugin.cfg              # addon metadata, loaded by the plugin list
├── plugin.gd               # editor side: settings, run hook, custom type, toolbar, menu
├── export_plugin.gd        # export hook: numbers at the start, stamp at the end
├── build_version.gd        # paths, Project Settings, the state file, version arithmetic
├── build_version_label.gd  # the Label node
├── version_bump.gd         # the counter rules and the export_presets.cfg rewriting
├── README.md / LICENSE.md / CHANGELOG.md
tests/build_version_tests.gd  # headless tests for every rule above (in the demo repo)
```

`build_version.gd` and `version_bump.gd` are deliberately free of editor dependencies: they only
read, write and rewrite text, so a headless run can drive every rule without an export.

## License

MIT — see `LICENSE.md`.
