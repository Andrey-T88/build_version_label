# Build Version Label

One build counter for the whole Godot project. Every **Run Project (F5/F6)** in the editor and
every **export, on any platform** is a build: its numbers go into the package, into the export
presets, and into the label in your game — and the next build's number is already ready.

```
Version 1.0.0 (build 12)     <- this run / this export
Version 1.0.0 (build 13)     <- the next one, already written into export_presets.cfg
```

Two ways to count, picked in Project Settings:

- `builds_per_version = 9999` with `on_limit_reached = Raise patch and restart the count`
  takes `1.0.0 (build 9999)` to `1.0.1 (build 1)`;
- `builds_per_version = 0` lets the build code rise without end: `1.1.3 (build 9999999)`.

`store_code_mode = Always rising` keeps the number Google Play and the App Store see monotonic
even when the displayed build restarts.

The full documentation — install, every setting, how the numbers are decided, the editor
tools — is in **[`addons/build_version_label/README.md`](addons/build_version_label/README.md)**.

## This repository

The repository root **is a runnable Godot 4.7 project**, so you can open it and try the addon:
`demo.tscn` prints the stamp held in `config/build_info.json` (a committed sample; your own
project does not need that file, the plugin creates it). The addon itself is
`addons/build_version_label/` — the only folder you have to copy.

```
build_version_label/            # this repo: open it in Godot to try the addon
├── demo.tscn                   # a BuildVersionLabel node plus a hint line
├── project.godot               # plugin enabled, all settings listed explicitly
├── config/build_info.json      # sample stamp so the demo prints without exporting
├── tests/build_version_tests.gd  # headless tests for the counting rules
└── addons/build_version_label/   # <- the addon
```

## Run the tests

```
godot --headless --path . --script res://tests/build_version_tests.gd
```

114 checks over the version arithmetic, the builds-per-version rules, the `export_presets.cfg`
rewriting (CRLF included), the state file, the two export phases and the manual bumps. Everything
runs against throwaway files under `user://`, so the demo's own stamp and preset file are never
touched; the process exits non-zero when an assertion fails.

## License

MIT — see `LICENSE.md`.
