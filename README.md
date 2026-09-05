# skal.bar

Omarchy status bar plugin: Bartender-style hidden widget drawers, Noctalia-style appearance control, native system tray, built-in settings GUI.

Runs inside `omarchy-shell`. Nothing in `/usr/share` is modified.

## Features

- Hidden widget **drawers per section** — widgets slide out of the tray/chevron, Bartender-style
- Per-region **reveal mode** (hover / toggle) and **indicator icon** (arrows rotate, dots/bars crossfade to ✕)
- Appearance: height, float margin, corner radius, background color/opacity, widget gap, edge padding, position
- **Native tray** with drawer, pinned icons, item menus — chevron doubles as the reveal toggle
- **Custom logo** on the menu widget (glyph, font, size, color, image)
- **Settings GUI**: SUPER+ALT+B or right-click blank bar space
- Window tops track bar geometry + Hyprland gaps automatically

## Install

Requires [Omarchy](https://omarchy.org).

```bash
omarchy plugin add https://github.com/outcrop-labs/skal-bar.git --enable --yes
omarchy bar use skal.bar
```

Optional keybind in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + B", "Bar settings", "omarchy-shell shell toggle skal.bar")
```

Right-click any blank bar space also opens settings.

## Config

All keys live under `bar` in `~/.config/omarchy/shell.json`. Hot-reloads on save.

```json
{
  "bar": {
    "id": "skal.bar",
    "position": "top",
    "height": 32,
    "margin": 6,
    "radius": 14,
    "backgroundColor": "",
    "backgroundOpacity": 0.9,
    "widgetSpacing": 4,
    "edgePadding": 8,
    "traySection": "right",
    "hiddenReveal": "hover",
    "hiddenRevealByRegion": { "center": "click" },
    "revealIcons": { "left": "❯" },
    "layout": {
      "left":   [ { "id": "omarchy.menu" }, { "id": "omarchy.workspaces" } ],
      "center": [ { "id": "omarchy.clock" } ],
      "right":  [ { "id": "omarchy.audio", "hidden": "hover" }, { "id": "omarchy.power" } ]
    }
  }
}
```

### Widget hidden states

| Value | Behavior |
|---|---|
| `"shown"` | default — always visible |
| `"hover"` | hidden until the region is revealed |
| `"always"` | never shown |

`"hidden": true` = `"hover"`.

### Per-region keys

- `hiddenRevealByRegion.<section>` — `"hover"` or `"click"` (falls back to `hiddenReveal`)
- `revealIcons.<section>` — `› ‹ ❯ ❮ ▸ ◂ ▾ ▴ ⋯ ≡`

### Tray

`traySection` — `left` / `right` / `none`. Pinned/hidden tray items persist under `bar.tray`.

### Logo

Settings for any cloned menu widget entry: `logo`, `logoFont`, `logoSize`, `logoColor`, `logoImage`.

```json
{ "id": "your.menu", "logo": "󰣇", "logoFont": "Symbols Nerd Font" }
```

## License

MIT © Outcrop Labs
