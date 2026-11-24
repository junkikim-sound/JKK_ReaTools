--========================================================
-- @title JKK_Search_MediaBrowser
-- @author Junki Kim
-- @noindex
-- JKK Search → JKK MediaBrowser 연동
--  * JKK MediaBrowser의 검색 엔진 모듈을 그대로 불러와 사용
--      !  UCS   : <MB>/ui/search/ucs_popup.lua            (JKK_Renamer_UCSList 사용)
--      @  폴더  : <MB>/ui/panels/left/folder_search_aliases.lua
--               폴더 목록/별칭은 MediaBrowser가 내보내는
--               <REAPER>/Data/JKK_SearchBridge_Folders.tsv 에서 읽는다.
--  * 검색 요청은 MediaBrowser의 resident_bridge 로 전달
--      (실행 중이 아니면 실행, 숨겨져 있으면 다시 표시, 현재 탭에서 검색, 잠긴 필터 블록 유지)
--========================================================

local RPR = reaper
local M = {}

local RES = RPR.GetResourcePath():gsub("[/\\]+$", "")
local this_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""

local function Exists(p) return p and RPR.file_exists(p) end

-- JKK_MediaBrowser 폴더 찾기 (JKK_ReaTools/JKK_ReaTools/Modules/ → JKK_ReaTools/JKK_MediaBrowser/)
local MB_DIR = nil
for _, dir in ipairs({
    this_dir .. "../../JKK_MediaBrowser/",
    RES .. "/Scripts/JKK_ReaTools/JKK_MediaBrowser/",
    RES .. "/Scripts/JKK_MediaBrowser/",
}) do
    if Exists(dir .. "JKK_MediaBrowser_Core.lua") then MB_DIR = dir break end
end
M.MB_DIR = MB_DIR
M.FOLDERS_FILE = RES .. "/Data/JKK_SearchBridge_Folders.tsv"

local function LoadModule(rel)
    if not MB_DIR then return nil end
    local chunk = loadfile(MB_DIR .. rel)
    if not chunk then return nil end
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
    return nil
end

local Bridge = LoadModule("ui/shell/resident_bridge.lua")
local UCS = LoadModule("ui/search/ucs_popup.lua")
local Folder = LoadModule("ui/panels/left/folder_search_aliases.lua")

----------------------------------------------------------
-- 대체 구현 (MediaBrowser 미설치 시): 동일한 규칙
----------------------------------------------------------
if not UCS then
    local list = {}
    local chunk = loadfile(RES .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Renamer_UCSList.lua")
    if chunk then
        local ok, data = pcall(chunk)
        if ok and type(data) == "table" then list = data end
    end
    UCS = {}
    function UCS.match(text, limit)
        local fragment = tostring(text or ""):match("!([^!%s]*)$")
        if fragment == nil then return nil end
        local q = fragment:lower()
        local ranked = {}
        for _, item in ipairs(list) do
            local code = tostring(item.insert or ""):lower()
            local cat, sub = tostring(item.cat or ""):lower(), tostring(item.sub or ""):lower()
            local desc = tostring(item.desc or ""):lower()
            local score
            if q == "" then score = 1
            elseif code:sub(1, #q) == q then score = 500
            elseif cat:sub(1, #q) == q or sub:sub(1, #q) == q then score = 400
            elseif code:find(q, 1, true) then score = 300
            elseif cat:find(q, 1, true) or sub:find(q, 1, true) then score = 200
            elseif desc:find(q, 1, true) then score = 100 end
            if score then ranked[#ranked + 1] = { item = item, score = score } end
        end
        table.sort(ranked, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return tostring(a.item.insert) < tostring(b.item.insert)
        end)
        local out = {}
        for i = 1, math.min(#ranked, limit or 30) do out[#out + 1] = ranked[i].item end
        return out
    end
end

if not Folder then
    Folder = {}
    local function trim(x) return tostring(x or ""):match("^%s*(.-)%s*$") end
    function Folder.path_key(path) return (tostring(path or ""):gsub("\\", "/"):gsub("/+$", ""):lower()) end
    function Folder.fragment(text) return tostring(text or ""):match("^%s*@%s*(.-)%s*$") end
    function Folder.match(state, model, text)
        local term = Folder.fragment(text)
        if term == nil then return nil end
        local q = term:lower()
        local aliases = state.layout_profiles.folder_search_aliases
        local matches = {}
        for _, node in ipairs(model:get_folder_roots()) do
            local key = Folder.path_key(node.path)
            local alias = aliases[key] or ""
            local label, ali = tostring(node.name):lower(), alias:lower()
            local score
            if q == "" then score = 1
            elseif ali ~= "" and ali:sub(1, #q) == q then score = 500
            elseif label:sub(1, #q) == q then score = 400
            elseif ali ~= "" and ali:find(q, 1, true) then score = 300
            elseif label:find(q, 1, true) then score = 200
            elseif key:find(q, 1, true) then score = 100 end
            if score then
                matches[#matches + 1] = { label = trim(node.name), path = node.path, alias = alias, key = key, score = score }
            end
        end
        table.sort(matches, function(a, b)
            if (a.alias ~= "") ~= (b.alias ~= "") then return a.alias ~= "" end
            if a.score ~= b.score then return a.score > b.score end
            return a.key < b.key
        end)
        return matches
    end
end

-- JKK MediaBrowser 액션(사용자 리퍼에 설치되어 액션 목록에 등록되어 있는지)
M.MB_ACTION_ID = "_RSe6670e4a89d2c8e0fc347c2cb048d4e5b9b3bf7c"
local function ActionInstalled()
    if not RPR.NamedCommandLookup then return false end
    local ok, id = pcall(RPR.NamedCommandLookup, M.MB_ACTION_ID)
    return ok and type(id) == "number" and id ~= 0
end

-- 액션이 등록되어 있고 파일도 찾을 수 있을 때만 연동을 사용한다.
-- (없으면 JKK Search 는 원래부터 연동이 없던 것처럼 동작)
function M.Available() return MB_DIR ~= nil and Bridge ~= nil and ActionInstalled() end
function M.UsingMBEngine() return MB_DIR ~= nil end

----------------------------------------------------------
-- @ 폴더 목록 (MediaBrowser가 내보낸 파일)
----------------------------------------------------------
local folder_state = { layout_profiles = { folder_search_aliases = {} } }
local folder_roots = {}
local folder_model = { get_folder_roots = function() return folder_roots end }
local folders_loaded_at = -100
local folders_sig = nil
local revision = 0
function M.Revision() return revision end
function M.FolderCount() return #folder_roots end

local function LoadFolders(force)
    local now = RPR.time_precise()
    if not force and (now - folders_loaded_at) < 3 then return end
    folders_loaded_at = now
    local f = io.open(M.FOLDERS_FILE, "rb")
    if not f then
        if #folder_roots > 0 then folder_roots = {}; revision = revision + 1 end
        return
    end
    local data = f:read("a") or ""
    f:close()
    local sig = #data .. ":" .. data:sub(1, 64) .. data:sub(-64)
    if sig == folders_sig then return end
    folders_sig = sig
    local roots, aliases = {}, {}
    for line in data:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            local label, alias, path = line:match("^([^\t]*)\t([^\t]*)\t(.+)$")
            if path and path ~= "" then
                roots[#roots + 1] = { name = label, path = path, children = {} }
                if alias ~= "" then aliases[Folder.path_key(path)] = alias end
            end
        end
    end
    folder_roots = roots
    -- 새 테이블이어야 MB 엔진의 캐시가 무효화된다
    folder_state = { layout_profiles = { folder_search_aliases = aliases } }
    revision = revision + 1
end

function M.ReloadFolders() LoadFolders(true) end

----------------------------------------------------------
-- 검색어 모드 판정 / 제안 목록
----------------------------------------------------------
-- 반환: "folder" | "ucs" | nil
function M.Mode(query)
    if Folder.fragment(query) ~= nil then return "folder" end
    if tostring(query or ""):match("![^!%s]*$") then return "ucs" end
    return nil
end

-- 하이라이트에 쓸 검색 조각
function M.Term(query)
    local mode = M.Mode(query)
    if mode == "folder" then return Folder.fragment(query) or "" end
    if mode == "ucs" then return tostring(query):match("!([^!%s]*)$") or "" end
    return ""
end

local function Lower(s) return tostring(s or ""):lower() end

-- JKK Search 결과 행 형식으로 변환한 제안 목록
function M.Suggest(query)
    local mode = M.Mode(query)
    local out = {}
    if mode == "folder" then
        LoadFolders(false)
        local ok, matches = pcall(Folder.match, folder_state, folder_model, query)
        for _, m in ipairs(ok and matches or {}) do
            local alias = tostring(m.alias or "")
            local e = {
                kind = "mbfolder", mb = true, badge = "FOLDER",
                name = (alias ~= "") and (tostring(m.label) .. "   @" .. alias) or tostring(m.label),
                detail = tostring(m.path or ""),
                path = m.path, label = m.label, alias = alias,
                key = "mbfolder:" .. tostring(m.key or Folder.path_key(m.path)),
            }
            e.lname = Lower(e.name)
            out[#out + 1] = e
        end
    elseif mode == "ucs" then
        local ok, items = pcall(UCS.match, query, 400)
        for _, it in ipairs(ok and items or {}) do
            local e = {
                kind = "mbucs", mb = true, badge = "UCS",
                name = tostring(it.insert or ""),
                detail = tostring(it.cat or "") .. "  ›  " .. tostring(it.sub or ""),
                ucs = it,
                key = "mbucs:" .. tostring(it.insert or ""),
            }
            e.lname = Lower(e.name)
            out[#out + 1] = e
        end
    end
    return out, mode
end

----------------------------------------------------------
-- MediaBrowser로 보내기
----------------------------------------------------------
-- entry: 선택된 제안 행(@폴더/!UCS) 또는 nil(텍스트 그대로)
function M.BuildRequest(query, entry)
    query = tostring(query or ""):match("^%s*(.-)%s*$")
    if entry and entry.kind == "mbfolder" then
        return { kind = "folder", text = query, path = entry.path, label = entry.label, alias = entry.alias }
    elseif entry and entry.kind == "mbucs" then
        local it = entry.ucs or {}
        return { kind = "ucs", text = query, ucs_insert = it.insert, ucs_cat = it.cat, ucs_sub = it.sub }
    end
    local mode = M.Mode(query)
    if mode == "folder" then return { kind = "folder", text = query } end
    if mode == "ucs" then return { kind = "ucs", text = query } end
    return { kind = "text", text = query }
end

function M.Send(req)
    if not M.Available() then
        return false, "JKK MediaBrowser not found (expected next to JKK_ReaTools)"
    end
    if not req or ((req.text or "") == "" and not req.path and not req.ucs_insert) then
        return false, "Nothing to search"
    end
    local ok, success, why = pcall(Bridge.launch, RPR, MB_DIR .. "JKK_MediaBrowser_Core.lua", "search", req)
    if not ok then return false, "MediaBrowser error: " .. tostring(success) end
    if not success then return false, "MediaBrowser: " .. tostring(why) end
    local what = req.kind == "folder" and ("@" .. tostring(req.alias ~= "" and req.alias or req.label or req.text))
        or (req.kind == "ucs" and ("!" .. tostring(req.ucs_insert or req.text)))
        or ("\"" .. tostring(req.text) .. "\"")
    return true, "Searched " .. what .. " in Media Browser"
end

LoadFolders(true)

return M
