![a](https://repository-images.githubusercontent.com/1230283309/50e4a5c7-bb56-4e68-b3af-27028e2a80d1)

> made by [lil2kki](https://scriptblox.com/u/lil2kki) and tested on **[xeno](https://discord.gg/xe-no)**

## install

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/thaLILNIKKI/rbx-sound-replacer/HEAD/.lua"))()
```

## what it does

- replaces sounds by asset id — game-wide or scoped to a specific child
- supports `rbxassetid://`, http urls, and local files
- logs unknown sound ids to a file so you can find what to replace
- singleton — safe to loadstring multiple times, won't double-init
- live: catches sounds added after load too

drops a config file at `sound-replacer/<placeId>.txt` on first run. edit it, re-run.

## config

file lives at `sound-replacer/<placeId>.txt`

```
-- ========== SETTINGS ==========
Enable full descendants scan = false
Full descendants scan at child = Workspace
Enable log file = true
-- ===============================

[lobby music]    107720742914927 - sound-replacer/lobby.mp3
[cream theme]    113685572917620 - https://example.com/cream.mp3
[round music]    135647549254666 - rbxassetid://1234567890
```

**settings:**

| key | values | what |
|-----|--------|------|
| `Enable full descendants scan` | `true` / `false` | scan every instance in game (slow but thorough) |
| `Full descendants scan at child` | instance name | scan only that subtree, e.g. `Workspace` |
| `Enable log file` | `true` / `false` | write unknown sound ids to `<placeId>_log.txt` |

if both scan settings are off — only catches sounds added after load. probably fine for most games.

**sources:**

```
-- local file (put it in sound-replacer/ folder)
[name]   123456 - sound-replacer/mysound.mp3

-- remote url (gets downloaded and cached)
[name]   123456 - https://cdn.example.com/sound.ogg

-- roblox asset
[name]   123456 - rbxassetid://987654321
```

## api

after loadstring you get a global `SoundReplacer`:

```lua
-- add a replacement at runtime
SoundReplacer.add(107720742914927, "rbxassetid://1234567890")
SoundReplacer.add(107720742914927, "sound-replacer/local.mp3")
SoundReplacer.add(107720742914927, "https://example.com/sound.mp3")

-- remove one
SoundReplacer.remove(107720742914927)

-- raw table if you need it
SoundReplacer.replacements  -- { ["id"] = "resolvedAsset", ... }
```

## multiple scripts

singleton pattern - second loadstring returns the existing instance immediately, no rescan, no reinit:

```lua
-- script A
loadstring(game:HttpGet("..."))()
SoundReplacer.add(111, "rbxassetid://aaa")

-- script B, same session
loadstring(game:HttpGet("..."))()  -- no-op, reuses instance
SoundReplacer.add(222, "rbxassetid://bbb")  -- works fine
```

## find sound ids

enable the log file in settings. play the game. check `sound-replacer/<placeId>_log.txt` — every unique sound id that played gets written there with its full instance path.

## notes

- requires an executor with `getcustomasset`, `writefile`, `readfile`, `isfile`, `makefolder`
- http urls get downloaded once and cached locally
- `getinstances()` used when available (gets sounds outside game tree too)
- comments in config start with `--`, blank lines ignored
