# Forever Backup Settings

A World of Warcraft: Forever addon that saves your character settings into named profiles and restores them on other characters — including new ones via a default profile.

## Features

- Save and restore named profiles
- Manual save, 5-minute auto-save, and save on logout/exit
- Dirty detection: shows when current settings differ from the saved profile
- Applies to new characters automatically when a default profile is set
- Combat-safe: queues an apply until combat ends
- In-game settings panel under **Options → AddOns → Forever Backup Settings**

## What gets saved

- **CVars** (audio, camera, UI scale, nameplates, auto-loot, etc. — curated whitelist)
- **Keybinds** (all bindings via `GetNumBindings`/`GetBinding`)
- **Action bars** (all 120 slots: spells, macros, items)
- **Addon list** (all installed addons, enabled or disabled)
- **Addon settings** (best-effort: `AddonName.."DB"` SavedVariables for enabled addons)

## Slash commands

| Command | What it does |
|---|---|
| `/fbs` or `/fbs save` | Save current settings to the last-used profile |
| `/fbs save <name>` | Save current settings under a profile name |
| `/fbs apply <name>` | Apply a saved profile |
| `/fbs list` | List profiles and the default profile |
| `/fbs default <name>` | Set the default profile for new characters |
| `/fbs dirty` | Check whether current settings differ from the saved profile |
| `/foreverbackupsettings` | Alias for `/fbs` |

## In-game panel

- Profile name field
- **Save** — save current settings under the typed name
- **Apply** — apply the typed profile
- **Set Default** — mark a profile as default for new characters
- Status line: last save/apply and dirty state

## Auto-save

- Every **5 minutes**, but only when settings are dirty
- On **logout/exit**
- Toggle with `ForeverBackupSettingsDB.autoSave` (default on)

## Addon settings behaviour

- Settings of **enabled** addons are captured at save time.
- **Disabled** addons cannot be read in-game. Use the Lua companion `tools/export_savedvars.lua` (reads WTF directly) to build an `exported` profile, then `/fbs apply exported`.
- On apply, if a saved addon is **not installed**, the addon tells you to install it.
- Reload the UI after restoring addon settings.

## Install

Copy the `ForeverBackupSettings` folder into:

```
World of Warcraft\_forever_\Interface\AddOns\
```

## Notes

- Interface: `16001` (WoW: Forever 1.60.1)
- SavedVariables: `ForeverBackupSettingsDB` (account-wide)
- Some CVars are secure and cannot be changed in combat.
- Full capture of disabled addons' SavedVariables requires an external tool (in-game Lua has no file access).
