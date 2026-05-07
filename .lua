-- sound-replacer by lil2kki :3

local ROOT    = "sound-replacer"
local CFGPATH = ROOT .. "/" .. tostring(game.PlaceId) .. ".txt"

local function log(s)  print("[sound-replacer] " .. s) end
local function err(s)   warn("[sound-replacer] " .. s) end
local function nid(id) return tostring(id):match("%d+") or "" end
local function fpath(p) return (p:gsub("^%./", "")) end

if _G.SoundReplacer then
    SoundReplacer = _G.SoundReplacer
    log("already loaded, reusing existing instance")
    return
end

-- resolve source to final SoundId
local function resolve(source)
    source = source:match("^%s*(.-)%s*$")

    if source:match("^rbxassetid://") then
        return source
    end

    if source:match("^https?://") then
        local filename = ROOT .. "/" .. (source:match("[^/]+$") or "tmp.mp3")
        if not isfile(filename) then
            local ok, data = pcall(function() return game:HttpGet(source) end)
            if not ok then err("HttpGet failed: " .. source) return nil end
            writefile(filename, data)
        end
        local ok, asset = pcall(getcustomasset, filename)
        if not ok then err("getcustomasset failed: " .. filename) return nil end
        return asset
    end

    local path = fpath(source)
    if isfile(path) then
        local ok, asset = pcall(getcustomasset, path)
        if not ok then err("getcustomasset failed: " .. path) return nil end
        return asset
    end

    err("can't resolve: " .. source)
    return nil
end

local function parse()
    if not isfolder(ROOT) then makefolder(ROOT) end

    if not isfile(CFGPATH) then
        local defaultConfig = [[-- sound-replacer config for place ]] .. tostring(game.PlaceId) .. [[
--
-- ========== SETTINGS ==========
Enable full descendants scan = false
Full descendants scan at child = 
Enable log file = false
-- ===============================
--
-- format:
--   [name] {sourceId} - {file|url|rbxassetid}
--   name is ignored, just for your info
--
-- examples:
--   [lobby music]    107720742914927 - sound-replacer/lobby.mp3
--   [cream theme]    113685572917620 - https://example.com/cream.mp3
--   [round music]    135647549254666 - rbxassetid://1234567890
]]
        writefile(CFGPATH, defaultConfig)
        log("created config with default settings: " .. CFGPATH)
        -- Return empty replacements and default settings
        return {}, {
            ["Enable full descendants scan"] = "false",
            ["Full descendants scan at child"] = "",
            ["Enable log file"] = "false",
        }
    end

    local raw = readfile(CFGPATH)
    local replacements = {}
    local settings = {}

    for line in raw:gmatch("[^\n]+") do
        if line:match("^%s*%-%-.*=.*") then
            local settingLine = line:match("^%s*%-%-%s*(.-)%s*$") or ""
            local key, value = settingLine:match("^([^=]+)%s*=%s*(.*)$")
            if key and value then
                key = key:match("^%s*(.-)%s*$")
                value = value:match("^%s*(.-)%s*$")
                settings[key] = value
            end
        end

        if not line:match("^%s*%-%-") and not line:match("^%s*$") then
            local rest = line:match("^%s*%[.-%]%s*(.+)$") or line
            local id, source = rest:match("^%s*(%d+)%s*%-%s*(.+)$")
            if id and source then
                local asset = resolve(source)
                if asset then
                    replacements[id] = asset
                    log("loaded " .. id .. " <- " .. source)
                end
            else
                err("bad line: " .. line)
            end
        end
    end

    settings["Enable full descendants scan"] = settings["Enable full descendants scan"] or "false"
    settings["Full descendants scan at child"] = settings["Full descendants scan at child"] or ""
    settings["Enable log file"] = settings["Enable log file"] or "false"

    local n = 0; for _ in pairs(replacements) do n = n + 1 end
    log(n .. " replacements ready")
    return replacements, settings
end

local logpath = ROOT .. "/" .. tostring(game.PlaceId) .. "_log.txt"
local seen    = {}
local queue   = {}
local logEnabled = true

local function enqueue(sound)
    if not logEnabled then return end
    local id = nid(sound.SoundId)
    if id == "" or seen[id] then return end
    seen[id] = true
    local name = pcall(function() return sound:GetFullName() end)
        and sound:GetFullName() or tostring(sound)
    queue[#queue + 1] = "[" .. name .. "] " .. id
end

-- damn (dum) logger
local loggerTask
local function startLogger()
    if loggerTask then task.cancel(loggerTask) end
    if not logEnabled then return end
    loggerTask = task.spawn(function()
        if isfile(logpath) then
            for id in readfile(logpath):gmatch("%] (%d+)") do seen[id] = true end
        end
        while true do
            task.wait(2)
            if #queue == 0 then continue end
            local batch = queue; queue = {}
            local base = isfile(logpath) and readfile(logpath):gsub("\n+$", "") or ""
            local new  = table.concat(batch, "\n")
            pcall(writefile, logpath, (base ~= "" and base .. "\n" or "") .. new .. "\n")
        end
    end)
end

-- main
local hooked = setmetatable({}, {__mode = "k"})
local replacements = {}

local function hook(sound)
    if hooked[sound] then return end
    hooked[sound] = true
    enqueue(sound)

    local id = nid(sound.SoundId)
    if replacements[id] then
        sound.SoundId = replacements[id]
        -- log("hit " .. id .. " @ " .. sound:GetFullName())
    end

    sound:GetPropertyChangedSignal("SoundId"):Connect(function()
        enqueue(sound)
        local id_ = nid(sound.SoundId)
        local rep = replacements[id_]
        if rep and sound.SoundId ~= rep then
            sound.SoundId = rep
            -- log("rehit " .. id_ .. " @ " .. sound:GetFullName())
        end
    end)
end

-- scan
local fullScanEnabled = true
local scanChild = ""

local function hookall()
    task.spawn(function()
        local function step(v)
            if v:IsA("Sound") then pcall(hook, v) end
        end

        if fullScanEnabled then
            -- Full descendants scan
            if getinstances then
                for _, v in ipairs(getinstances()) do step(v) end
            else
                for _, v in ipairs(game:GetDescendants()) do step(v) end
            end
            log("initial full scan done")
        elseif scanChild ~= "" then
            -- Scan only the specified child subtree
            local child = game:FindFirstChild(scanChild)
            if child then
                local descendants = child:GetDescendants()
                table.insert(descendants, 1, child)
                for _, v in ipairs(descendants) do step(v) end
                log("initial scan of child '" .. scanChild .. "' done")
            else
                err("Full descendants scan at child: '" .. scanChild .. "' not found")
            end
        else
            log("initial scan skipped (full scan disabled, no child specified)")
        end
    end)
end

-- API xd
SoundReplacer = {}
SoundReplacer.replacements = replacements

function SoundReplacer.add(id, source)
    id = nid(tostring(id))
    if id == "" then err("add: bad id") return end
    local asset = resolve(tostring(source))
    if not asset then return end
    replacements[id] = asset
    log("add " .. id)
    for s in pairs(hooked) do
        pcall(function()
            if nid(s.SoundId) == id then s.SoundId = asset end
        end)
    end
end

function SoundReplacer.remove(id)
    id = nid(tostring(id))
    if replacements[id] then
        replacements[id] = nil; log("removed " .. id)
    else
        err("remove: not found " .. id)
    end
end

-- init
if not game:IsLoaded() then game.Loaded:Wait() end

local freshReplacements, settings = parse()
for k, v in pairs(freshReplacements) do replacements[k] = v end

fullScanEnabled = (settings["Enable full descendants scan"]:lower() == "true")
scanChild = settings["Full descendants scan at child"]
logEnabled = (settings["Enable log file"]:lower() == "true")

startLogger()
hookall()

game.DescendantAdded:Connect(function(v)
    if not v:IsA("Sound") then return end
    if v.SoundId ~= "" then
        pcall(hook, v)
    else
        local c; c = v:GetPropertyChangedSignal("SoundId"):Connect(function()
            c:Disconnect(); pcall(hook, v)
        end)
    end
end)

_G.SoundReplacer = SoundReplacer

log("ready! made by lil2kki~")
log("https://github.com/thaLILNIKKI/rbx-sound-replacer")
