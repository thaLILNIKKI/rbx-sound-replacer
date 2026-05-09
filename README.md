![a](https://repository-images.githubusercontent.com/1230283309/5d4e9f2b-7d93-41ca-b640-d3e3aca1f959)
> made by [lil2kki](https://scriptblox.com/u/lil2kki) using ai and tested on **[xeno](https://discord.gg/xe-no)**

## install
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/thaLILNIKKI/rbx-sound-replacer/HEAD/.lua"))()
```

## what it does

replaces roblox sound ids at runtime - swap game music, sfx, or ambient sounds with your own files, urls, or other asset ids. works on newly added sounds too.

## config

after first run, a config file is created at:
```
sound-replacer/<PlaceId>.txt
```

open it and add your replacements:
```
-- ========== SETTINGS ==========
-- Descendants scan parent filter = Workspace,SoundService
-- Enable log file = true
-- ===============================

[lobby music]   107720742914927 - sound-replacer/lobby.mp3
[cream theme]   113685572917620 - https://example.com/cream.mp3
[round music]   135647549254666 - rbxassetid://1234567890
```

**format:** `[label] {soundId} - {source}`

| source type | example |
|---|---|
| local file | `sound-replacer/mysong.mp3` |
| url | `https://example.com/song.mp3` |
| rbxassetid | `rbxassetid://1234567890` |

## settings

| setting | default | description |
|---|---|---|
| `Descendants scan parent filter` | *(empty)* | comma-separated paths to scan on load, e.g. `Workspace,SoundService` - required for existing sounds |
| `Enable log file` | `false` | logs discovered sound ids to `<PlaceId>_log.txt` so you can find ids to replace |

## runtime api

```lua
-- add a replacement on the fly
SoundReplacer.add(soundId, source)

-- remove a replacement
SoundReplacer.remove(soundId)
```

## tips

- enable the log file first to discover what sound ids a game uses, then add your replacements
- local files go in the `sound-replacer/` folder in your executor's workspace
- the script is safe to re-inject - it reuses the existing instance
