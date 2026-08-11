# Lunar Workspaces (Noctalia v5)

A workspace indicator widget for [Noctalia](https://github.com/noctalia-dev)
with moon-phase-style icons for focused, urgent, occupied, and empty
workspaces. Click a workspace to jump to it, scroll the widget to step
through workspaces. Supports **Hyprland** and **Niri**, auto-detected.

Port from [Lunar Workspaces V4](https://github.com/Niko-Cloud/Lunar-Workspace-Noctalia-Plugin)

## Features

- 🌕 🌟 🌗 🌙 Separate icon, size, and pill color per workspace state
  (focused / urgent / occupied / empty) emoji, image, (gif planned in the future)
- Fill or ghost pill style per state
- Click-to-switch and scroll-to-switch workspaces
- Three display modes: show all workspaces, only active/occupied ones, or
  all occupied plus one upcoming empty slot
- Live updates via compositor IPC (Hyprland socket / Niri event stream),
  with a periodic resync as a fallback

## Notes
- Currently noctalia.d.luau doesn't have the ability to render gif like 'AnimatedImage' in v4, so until the 
  Noctalia devs added the feature, gif animation does not work properly (only render still image)

## Requirements

- [Noctalia](https://github.com/noctalia-dev) with plugin support (API v3)
- Hyprland or Niri
- [`socat`](https://linux.die.net/man/1/socat) used for instant Hyprland
  updates; the widget still works without it via periodic polling

## Installation

```bash
mkdir -p ~/.local/share/noctalia/plugins/lunar-workspaces
cp -r ./* ~/.local/share/noctalia/plugins/lunar-workspaces/
```

Enable the plugin:

```bash
noctalia msg plugins list                          # confirm it's discovered
noctalia msg plugins enable yuki/lunar-workspaces
```

Then add the **Lunar Workspaces** widget from Noctalia's Add-widget picker,
or add it to your bar config manually:

```toml
type = "yuki/lunar-workspaces:lunar_workspaces"
```

## Configuration

| Setting | Description |
|---|---|
| Compositor | `auto`, `hyprland`, or `niri` |
| Workspace display mode | `all`, `active_occupied`, or `once` |
| Workspace count | Number of workspaces to track (1–20) |
| Icon (focused / urgent / occupied / empty) | Emoji or image/gif path per state |
| Size (focused / urgent / occupied / empty) | Icon size in px per state |
| Pill style (focused / urgent / occupied / empty) | `fill` or `ghost` |
| Pill color (focused / urgent / occupied / empty) | Theme color, shown when style is `fill` |

## Development

```bash
cd ~/.local/share/noctalia/plugins/lunar-workspaces
python3 -c "import tomllib; tomllib.load(open('plugin.toml','rb'))"  # validate manifest
```

Run Noctalia from a terminal (not autostarted) while testing so
`noctalia.log(...)` output and Luau errors print live. `.luau` file edits
hot-reload; `plugin.toml` changes require a restart.

## License

This project is licensed under the [MIT License](LICENSE).
