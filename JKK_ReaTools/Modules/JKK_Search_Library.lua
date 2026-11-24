--========================================================
-- @title JKK_Search_Library
-- @author Junki Kim
-- @noindex
-- 사용자 데이터 (파일 저장: <REAPER>/Data/)
--  * User Tags : 이름 + 항목 key 목록. 처음 한 번은 REAPER FX 브라우저 폴더를 가져와 초기화
--                JKK_Search_Tags.txt
--  * New FX    : 이전에 알고 있던 FX 목록과 비교해 새로 생긴 FX를 기록
--                JKK_Search_KnownFX.txt / JKK_Search_NewFX.txt
--========================================================

local RPR = reaper
local M = {}

local DATA_DIR   = RPR.GetResourcePath() .. "/Data"
local TAGS_FILE  = DATA_DIR .. "/JKK_Search_Tags.txt"
local KNOWN_FILE = DATA_DIR .. "/JKK_Search_KnownFX.txt"
local NEW_FILE   = DATA_DIR .. "/JKK_Search_NewFX.txt"

local revision = 0
function M.Revision() return revision end
local function Bump() revision = revision + 1 end

local function EnsureDir()
    if RPR.RecursiveCreateDirectory then RPR.RecursiveCreateDirectory(DATA_DIR, 0) end
end

local function ReadLines(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local out = {}
    for raw in f:lines() do
        out[#out + 1] = (raw:gsub("\r$", ""))
    end
    f:close()
    return out
end

local function WriteLines(path, lines)
    EnsureDir()
    local f = io.open(path, "w")
    if not f then return false end
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    return true
end

----------------------------------------------------------
-- User Tags
-- 파일 형식:  "#TAG<TAB>id<TAB>name"  다음 줄부터 항목 key 한 줄씩
----------------------------------------------------------
local tags = {}        -- { id, name, keys = {array}, set = {key=true} }
local next_id = 1
local tags_loaded_from_file = false

local function NewTag(name, keys)
    local t = { id = "t" .. next_id, name = name, keys = {}, set = {} }
    next_id = next_id + 1
    for _, k in ipairs(keys or {}) do
        if not t.set[k] then t.set[k] = true; t.keys[#t.keys + 1] = k end
    end
    return t
end

local function SaveTags()
    local lines = {}
    for _, t in ipairs(tags) do
        lines[#lines + 1] = "#TAG\t" .. t.id .. "\t" .. t.name
        for _, k in ipairs(t.keys) do lines[#lines + 1] = k end
    end
    WriteLines(TAGS_FILE, lines)
    Bump()
end

local function LoadTags()
    local lines = ReadLines(TAGS_FILE)
    tags = {}
    if not lines then return false end
    local cur = nil
    for _, line in ipairs(lines) do
        local id, name = line:match("^#TAG\t([^\t]*)\t(.*)$")
        if id then
            cur = { id = id, name = name, keys = {}, set = {} }
            tags[#tags + 1] = cur
            local n = tonumber(id:match("^t(%d+)$"))
            if n and n >= next_id then next_id = n + 1 end
        elseif cur and line ~= "" and not cur.set[line] then
            cur.set[line] = true
            cur.keys[#cur.keys + 1] = line
        end
    end
    return true
end

function M.Tags() return tags end

function M.FindTag(id)
    for i, t in ipairs(tags) do if t.id == id then return t, i end end
    return nil
end

local function UniqueName(base)
    local exists = {}
    for _, t in ipairs(tags) do exists[t.name] = true end
    if not exists[base] then return base end
    local n = 2
    while exists[base .. " " .. n] do n = n + 1 end
    return base .. " " .. n
end

function M.AddTag(name, keys)
    local t = NewTag(UniqueName(name or "New Tag"), keys)
    tags[#tags + 1] = t
    SaveTags()
    return t
end

function M.RenameTag(id, name)
    local t = M.FindTag(id)
    name = (name or ""):gsub("[\r\n\t]", " ")
    if not t or name == "" or name == t.name then return end
    t.name = UniqueName(name)
    SaveTags()
end

function M.DeleteTag(id)
    local _, i = M.FindTag(id)
    if i then table.remove(tags, i); SaveTags() end
end

function M.DuplicateTag(id)
    local t, i = M.FindTag(id)
    if not t then return nil end
    local copy = NewTag(UniqueName(t.name .. " copy"), t.keys)
    table.insert(tags, i + 1, copy)
    SaveTags()
    return copy
end

function M.MoveTag(id, delta)
    local t, i = M.FindTag(id)
    if not t then return end
    local j = math.max(1, math.min(#tags, i + delta))
    if i == j then return end
    table.remove(tags, i)
    table.insert(tags, j, t)
    SaveTags()
end

-- 반환: 새로 추가된 개수
function M.AddToTag(id, keys)
    local t = M.FindTag(id)
    if not t then return 0 end
    local added = 0
    for _, k in ipairs(keys) do
        if k and not t.set[k] then
            t.set[k] = true
            t.keys[#t.keys + 1] = k
            added = added + 1
        end
    end
    if added > 0 then SaveTags() end
    return added
end

function M.RemoveFromTag(id, keys)
    local t = M.FindTag(id)
    if not t then return end
    local rm = {}
    for _, k in ipairs(keys) do rm[k] = true end
    local out = {}
    for _, k in ipairs(t.keys) do if not rm[k] then out[#out + 1] = k end end
    t.keys, t.set = out, {}
    for _, k in ipairs(out) do t.set[k] = true end
    SaveTags()
end

function M.TagSet(id)
    local t = M.FindTag(id)
    return t and t.set or nil
end

-- 처음 실행 시(태그 파일 없음) REAPER FX 브라우저 폴더를 태그로 가져온다
function M.NeedsSeed() return not tags_loaded_from_file end

function M.SeedFromFolders(folders)
    if tags_loaded_from_file then return end
    tags_loaded_from_file = true
    tags = {}
    for _, f in ipairs(folders or {}) do
        local keys = {}
        for e in pairs(f.set or {}) do keys[#keys + 1] = e.key end
        table.sort(keys)
        tags[#tags + 1] = NewTag(f.name, keys)
    end
    SaveTags()
end

----------------------------------------------------------
-- New FX (새로 스캔된 플러그인)
----------------------------------------------------------
local known = nil         -- key -> true (nil = 파일 없음 = 첫 실행)
local new_list = {}       -- key 배열 (최신이 앞)
local new_set = {}

local function SaveNew()
    WriteLines(NEW_FILE, new_list)
    Bump()
end

local function LoadNew()
    local kl = ReadLines(KNOWN_FILE)
    if kl then
        known = {}
        for _, k in ipairs(kl) do if k ~= "" then known[k] = true end end
    end
    new_list, new_set = {}, {}
    for _, k in ipairs(ReadLines(NEW_FILE) or {}) do
        if k ~= "" and not new_set[k] then new_set[k] = true; new_list[#new_list + 1] = k end
    end
end

-- 인덱스 구축이 끝날 때마다 호출. 처음 보는 FX를 New 목록에 추가한다.
-- 반환: 이번에 새로 발견된 개수
function M.UpdateNew(fx_list)
    if not fx_list or #fx_list == 0 then return 0 end
    local first_run = (known == nil)
    known = known or {}
    local found = {}
    local all = {}
    for _, e in ipairs(fx_list) do
        all[#all + 1] = e.key
        if not first_run and not known[e.key] then found[#found + 1] = e.key end
        known[e.key] = true
    end
    table.sort(all)
    WriteLines(KNOWN_FILE, all)
    if #found > 0 then
        local merged = {}
        for _, k in ipairs(found) do
            if not new_set[k] then merged[#merged + 1] = k end
        end
        for _, k in ipairs(new_list) do merged[#merged + 1] = k end
        new_list, new_set = merged, {}
        for _, k in ipairs(new_list) do new_set[k] = true end
        SaveNew()
    end
    return #found
end

function M.NewSet() return new_set end
function M.NewCount() return #new_list end
function M.IsNew(key) return new_set[key] == true end

function M.ClearNew()
    new_list, new_set = {}, {}
    SaveNew()
end

----------------------------------------------------------
-- 초기 로드
----------------------------------------------------------
tags_loaded_from_file = LoadTags()
LoadNew()

return M
