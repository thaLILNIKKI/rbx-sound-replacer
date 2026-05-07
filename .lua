-- sound-replacer by lil2kki
-- config: sound-replacer/{placeId}.txt
--
-- format:
--   [name] {sourceId} - {file|url|rbxassetid}
--   name is ignored, just for your info
--
-- examples:
--   [lobby music]    107720742914927 - sound-replacer/lobby.mp3
--   [cream theme]    113685572917620 - https://example.com/cream.mp3
--   [round music]    135647549254666 - rbxassetid://1234567890
--
-- api:
--   SoundReplacer.add(id, source)        add replacement at runtime
--   SoundReplacer.remove(id)             remove replacement

local ROOT    = "sound-replacer"
local CFGPATH = ROOT .. "/" .. tostring(game.PlaceId) .. ".txt"

local function log(s)  print("[sound-replacer] " .. s) end
local function err(s)   warn("[sound-replacer] " .. s) end
local function nid(id) return tostring(id):match("%d+") or "" end
local function fpath(p) return (p:gsub("^%./", "")) end

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

-- parse config
local function parse()
    if not isfolder(ROOT) then makefolder(ROOT) end

    if not isfile(CFGPATH) then
        writefile(CFGPATH,
            "-- sound-replacer config for place " .. tostring(game.PlaceId) .. "\n" ..
			"--\n" ..
            "-- format:\n" ..
            "--   [name] {sourceId} - {file|url|rbxassetid}\n" ..
            "--   name is ignored, just for your info\n" ..
            "--\n" ..
            "-- examples:\n" ..
            "--   [lobby music]    107720742914927 - sound-replacer/lobby.mp3\n" ..
            "--   [cream theme]    113685572917620 - https://example.com/cream.mp3\n" ..
            "--   [round music]    135647549254666 - rbxassetid://1234567890\n"
        )
        log("created empty config: " .. CFGPATH)
        return {}
    end

    local out = {}
    local raw = readfile(CFGPATH)

    for line in raw:gmatch("[^\n]+") do
        if not line:match("^%s*%-%-") and not line:match("^%s*$") then
            local rest = line:match("^%s*%[.-%]%s*(.+)$") or line
            local id, source = rest:match("^%s*(%d+)%s*%-%s*(.+)$")
            if id and source then
                local asset = resolve(source)
                if asset then
                    out[id] = asset
                    log("loaded " .. id .. " <- " .. source)
                end
            else
                err("bad line: " .. line)
            end
        end
    end

    local n = 0; for _ in pairs(out) do n = n + 1 end
    log(n .. " replacements ready")
    return out
end

-- log
local logpath = ROOT .. "/" .. tostring(game.PlaceId) .. "_log.txt"
local seen    = {}
local queue   = {}

local function enqueue(sound)
    local id = nid(sound.SoundId)
    if id == "" or seen[id] then return end
    seen[id] = true
    local name = pcall(function() return sound:GetFullName() end)
        and sound:GetFullName() or tostring(sound)
    queue[#queue + 1] = "[" .. name .. "] " .. id
end

task.spawn(function()
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

local function hookall()
    task.spawn(function()
        local function step(v)
            if v:IsA("Sound") then pcall(hook, v) end
        end
		
        if getinstances then
            for _, v in ipairs(getinstances()) do step(v) end
        else
            for _, v in ipairs(game:GetDescendants()) do step(v) end
        end

        log("initial scan done")
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

local fresh = parse()
for k, v in pairs(fresh) do replacements[k] = v end

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

log("ready! made by lil2kki~")
log("https://github.com/thaLILNIKKI/rbx-sound-replacer")
