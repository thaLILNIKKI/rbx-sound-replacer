-- sound-replacer by lil2kki :3

local ROOT    = "sound-replacer"
local CFGPATH = ROOT .. "/" .. tostring(game.PlaceId) .. ".txt"

local function log(s) print("[sound-replacer] " .. s) end
local function err(s)  warn("[sound-replacer] " .. s) end
local function nid(id) return tostring(id):match("%d+") or "" end
local function fpath(p) return (p:gsub("^%./", "")) end

if _G.SoundReplacer then
    SoundReplacer = _G.SoundReplacer
    log("already loaded, reusing existing instance")
    return
end

-- resolve

local resolveCache = {}

local function resolve(source)
    source = source:match("^%s*(.-)%s*$")

    if resolveCache[source] then return resolveCache[source] end

    local asset
    if source:match("^rbxassetid://") then
        asset = source
    elseif source:match("^https?://") then
        local filename = ROOT .. "/" .. (source:match("[^/]+$") or "tmp.mp3")
        if not isfile(filename) then
            local ok, data = pcall(function() return game:HttpGet(source) end)
            if not ok then err("HttpGet failed: " .. source) return nil end
            writefile(filename, data)
        end
        local ok, a = pcall(getcustomasset, filename)
        if not ok then err("getcustomasset failed: " .. filename) return nil end
        asset = a
    else
        local path = fpath(source)
        if isfile(path) then
            local ok, a = pcall(getcustomasset, path)
            if not ok then err("getcustomasset failed: " .. path) return nil end
            asset = a
        else
            err("can't resolve: " .. source)
            return nil
        end
    end

    resolveCache[source] = asset
    return asset
end

-- config parse

local function parse()
    if not isfolder(ROOT) then makefolder(ROOT) end

    if not isfile(CFGPATH) then
        local defaultConfig = "-- sound-replacer config for place " .. tostring(game.PlaceId) .. "\n"
            .. "--\n"
            .. "-- ========== SETTINGS ==========\n"
            .. "-- Enable full descendants scan = false\n"
            .. "-- Descendants scan parent filter = \n"
            .. "-- Enable log file = false\n"
            .. "-- ===============================\n"
            .. "--\n"
            .. "-- format:\n"
            .. "--   [name] {sourceId} - {file|url|rbxassetid}\n"
            .. "--\n"
            .. "-- examples:\n"
            .. "--   [lobby music]    107720742914927 - sound-replacer/lobby.mp3\n"
            .. "--   [cream theme]    113685572917620 - https://example.com/cream.mp3\n"
            .. "--   [round music]    135647549254666 - rbxassetid://1234567890\n"
        writefile(CFGPATH, defaultConfig)
        log("created config: " .. CFGPATH)
        return {}, {
            ["Enable full descendants scan"]    = "false",
            ["Descendants scan parent filter"]  = "",
            ["Enable log file"]                 = "false",
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
                settings[key:match("^%s*(.-)%s*$")] = value:match("^%s*(.-)%s*$")
            end
        elseif not line:match("^%s*%-%-") and not line:match("^%s*$") then
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

    settings["Enable full descendants scan"]   = settings["Enable full descendants scan"]   or "false"
    settings["Descendants scan parent filter"] = settings["Descendants scan parent filter"] or ""
    settings["Enable log file"]                = settings["Enable log file"]                or "false"

    local n = 0; for _ in pairs(replacements) do n = n + 1 end
    log(n .. " replacements ready")
    return replacements, settings
end

-- logger

local logpath    = ROOT .. "/" .. tostring(game.PlaceId) .. "_log.txt"
local seenIds    = {}
local queue      = {}
local logEnabled = false

local function enqueue(id)
    if not logEnabled or id == "" or seenIds[id] then return end
    seenIds[id] = true
    queue[#queue + 1] = id
end

local loggerTask
local function startLogger()
    if loggerTask then task.cancel(loggerTask) end
    if not logEnabled then return end

    loggerTask = task.spawn(function()
        if isfile(logpath) then
            for id in readfile(logpath):gmatch("%] (%d+)") do seenIds[id] = true end
        end
        while true do
            task.wait(3)
            if #queue == 0 then continue end
            local batch = queue; queue = {}
            local base = isfile(logpath) and readfile(logpath):gsub("\n+$", "") or ""
            local lines = {}
            for _, id in ipairs(batch) do
                lines[#lines + 1] = id
            end
            pcall(writefile, logpath, (base ~= "" and base .. "\n" or "") .. table.concat(lines, "\n") .. "\n")
        end
    end)
end

-- hooking

-- weak table <3
local hooked      = setmetatable({}, { __mode = "k" })
local replacements = {}

local function applyReplacement(sound)
    local id = nid(sound.SoundId)
    enqueue(id)
    local rep = replacements[id]
    if rep and sound.SoundId ~= rep then
        sound.SoundId = rep
    end
end

local function hook(sound)
    if hooked[sound] then return end
    hooked[sound] = true

    applyReplacement(sound)

    local propConn
    propConn = sound:GetPropertyChangedSignal("SoundId"):Connect(function()
        applyReplacement(sound)
    end)

    local ancConn
    ancConn = sound.AncestryChanged:Connect(function()
        if not sound.Parent then
            propConn:Disconnect()
            ancConn:Disconnect()
            hooked[sound] = nil
        end
    end)
end

-- scan

local function getInstanceByPath(path)
    local current = game
    for part in (path .. "."):gmatch("(.-)%.") do
        if part ~= "" then
            current = current:FindFirstChild(part)
            if not current then return nil end
        end
    end
    return current
end

local fullScanEnabled  = false
local parentFilterList = {}

local function hookall()
    task.spawn(function()
        if fullScanEnabled then
            local list = getinstances and getinstances() or game:GetDescendants()
            local BATCH = 200
            for i = 1, #list, BATCH do
                for j = i, math.min(i + BATCH - 1, #list) do
                    local v = list[j]
                    if v:IsA("Sound") then pcall(hook, v) end
                end
                task.wait()
            end
            log("full scan done")
        elseif #parentFilterList > 0 then
            for _, rawPath in ipairs(parentFilterList) do
                local path = rawPath:match("^%s*(.-)%s*$")
                if path ~= "" then
                    local parent = getInstanceByPath(path)
                    if parent then
                        local desc = parent:GetDescendants()
                        local BATCH = 200
                        for i = 1, #desc, BATCH do
                            for j = i, math.min(i + BATCH - 1, #desc) do
                                local v = desc[j]
                                if v:IsA("Sound") then pcall(hook, v) end
                            end
                            task.wait()
                        end
                        if parent:IsA("Sound") then pcall(hook, parent) end
                        log("scanned: " .. path)
                    else
                        err("parent not found: " .. path)
                    end
                end
            end
        else
            log("scan skipped")
        end
    end)
end

-- api

SoundReplacer = {}
SoundReplacer.replacements = replacements

function SoundReplacer.add(id, source)
    id = nid(tostring(id))
    if id == "" then err("add: bad id") return end
    local asset = resolve(tostring(source))
    if not asset then return end
    replacements[id] = asset
    log("add " .. id)
    -- patching already fucked sounds
    for sound in pairs(hooked) do
        pcall(function()
            if nid(sound.SoundId) == id then sound.SoundId = asset end
        end)
    end
end

function SoundReplacer.remove(id)
    id = nid(tostring(id))
    if replacements[id] then
        replacements[id] = nil
        log("removed " .. id)
    else
        err("remove: not found " .. id)
    end
end

-- init.

if not game:IsLoaded() then game.Loaded:Wait() end

local freshReplacements, settings = parse()
for k, v in pairs(freshReplacements) do replacements[k] = v end

fullScanEnabled = (settings["Enable full descendants scan"]:lower() == "true")
local filterStr = settings["Descendants scan parent filter"] or ""
parentFilterList = {}
for part in filterStr:gmatch("[^,]+") do
    local trimmed = part:match("^%s*(.-)%s*$")
    if trimmed ~= "" then table.insert(parentFilterList, trimmed) end
end
logEnabled = (settings["Enable log file"]:lower() == "true")

startLogger()
hookall()

game.DescendantAdded:Connect(function(v)
    if not v:IsA("Sound") then return end
    if v.SoundId ~= "" then
        pcall(hook, v)
    else
        local c; c = v:GetPropertyChangedSignal("SoundId"):Connect(function()
            if v.SoundId ~= "" then
                c:Disconnect()
                pcall(hook, v)
            end
        end)
    end
end)

_G.SoundReplacer = SoundReplacer

log("ready! made by lil2kki~")
log("https://github.com/thaLILNIKKI/rbx-sound-replacer")
