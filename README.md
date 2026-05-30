# Pandora

Windower addon that automatically opens chests, coffers, and aurum strongboxes in **Odyssey** (Sheol A / B / C) and **Sortie**. 

WARNING: Uses packet based position manipulation.

## Is it safe?
Probably not.

## Install

1. Place the `Pandora` folder in `Windower4/addons/`.
2. In-game: `//lua load Pandora`.

## Commands (`//pandora` or `//pd`)

### Odyssey

| Command | Description |
|---|---|
| `//pd a <1-7> [a\|b\|c] [solo]` | Loot a **Sheol A** floor |
| `//pd b <1-6> [a\|b\|c] [solo]` | Loot a **Sheol B** floor |
| `//pd c <1-4> [a\|b\|c] [solo]` | Loot a **Sheol C** floor |

- `a` = chests only, `b` = coffers only, `c` = aurum strongboxes only. Omit to run all three waves in sequence (solo mode).
- **Party mode is the default** — The floor's chests are split across your party so everyone opens a different one at the same time. Add `solo` to open everything on the current character alone (not recommended due to slow speed).
- **Pandora must be loaded on all characters in the party to make use of the party loot feature.**
- In party mode, run each tier separately as it spawns:
  ```
  //pd c 1 a       open the F1 chests
  //pd c 1 b       then the F1 coffers
  //pd c 1 c       then the F1 aurum strongboxes
  ```

### Sortie

| Command | Description |
|---|---|
| `//pd sortie on` / `off` | Toggle ambient auto-open of nearby Sortie chests |
| `//pd sortie range <n>` | Optionally set scan range in yalms (default 50) |
| `//pd sortie reset` | Clear opened-chest history (this session) |

When enabled, any known chest/casket/coffer/aurum within range is opened automatically. Sortie auto-open settings are saved **per character**.

### General

| Command | Description |
|---|---|
| `//pd stop` | Cancel any Odyssey loot in progress |
| `//pd delay <seconds>` | Delay between Odyssey opens (default 3s) |
| `//pd status` | Show current state |
| `//pd help` | Command list |

## Notes
- Odyssey loot stops automatically if you run out of **izzat** at any point in the sequence.
- Party distribution for Odyssey loot function utilizes IPC.