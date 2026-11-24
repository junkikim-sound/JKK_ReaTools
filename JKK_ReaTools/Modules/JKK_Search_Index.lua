--========================================================
-- @title JKK_Search_Index
-- @author Junki Kim
-- @noindex
-- 검색 대상 인덱스 구축
--  * FX       : VST / VST3 / CLAP / JS (+ EnumInstalledFX로 LV2/DX/AU 등 보충)
--  * FX 메타  : Category / Developer (reaper-fxtags.ini), Folders(Tags) (reaper-fxfolders.ini)
--  * FX Chain / Track Template / Action / 최근 프로젝트
--  * 현재 프로젝트의 Track / Item / Marker / Region (변경 감지 시 자동 갱신)
-- 정적 소스는 코루틴으로 여러 프레임에 나눠 구축하여 창이 즉시 뜨도록 한다.
--========================================================

local RPR = reaper
local M = {}

-- 쿼리에서 순회하는 소스 순서 (= 기본 정렬 우선순위)
M.SOURCES = { "fx", "chain", "template", "action", "track", "item", "marker", "project" }

local RES = RPR.GetResourcePath()
local SEP = package.config:sub(1, 1) == "\\" and "\\" or "/"

----------------------------------------------------------
-- 문자열 유틸
----------------------------------------------------------
local function Lower(s) return (s or ""):lower() end
local function Trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- 플러그인 파일 키 정규화: 경로/GUID 제거, 공백·하이픈 등은 '_' 로 통일
-- "C:\...\WaveShell1-VST3 16.0_x64.vst3<536267238{...}" -> "waveshell1_vst3_16.0_x64.vst3<536267238"
local function NormKey(s)
    if not s or s == "" then return "" end
    s = s:gsub("{.*$", "")
    s = s:match("([^/\\]+)$") or s
    s = s:lower():gsub("[^%w%.<_]", "_")
    return s
end
M.NormKey = NormKey

local function FileExists(path)
    return path and RPR.file_exists(path)
end

local function JoinPath(a, b)
    if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
    return a .. "/" .. b
end

local function Basename(path)
    return (path or ""):match("([^/\\]+)$") or path
end

local function StripExt(name)
    return (name:gsub("%.[^%.]+$", ""))
end

-- "Name (Vendor)" -> "Name", "Vendor"
-- "ReaSynDr (Cockos) (4 out)" -> "ReaSynDr (4 out)", "Cockos"
local function SplitVendor(full)
    local base, vendor = full:match("^(.-)%s*%(([^()]*)%)%s*$")
    if not base or base == "" then return full, "" end
    local lv = vendor:lower()
    if lv:match("^%d+%s*out") or lv:match("^%d+%s*ch") or lv:match("^mono") or lv:match("^stereo")
        or lv:match("^%d+%->%d+") or lv:match("^%d+x%d+") then
        local b2, v2 = base:match("^(.-)%s*%(([^()]*)%)%s*$")
        if b2 and b2 ~= "" then return b2 .. " (" .. vendor .. ")", v2 end
        return full, ""
    end
    return base, vendor
end

local function ColorFromNative(native)
    if not native or native == 0 or (native & 0x1000000) == 0 then return nil end
    local r, g, b = RPR.ColorFromNative(native & 0xFFFFFF)
    return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

----------------------------------------------------------
-- 상태
----------------------------------------------------------
local lists = {}
local by_key = {}       -- 정적 항목 key -> entry
local dyn_by_key = {}   -- 프로젝트 항목 key -> entry
local lookup = {}       -- 정규화된 파일키/ident -> { entries }
local fx_dedupe = {}    -- "TYPE|full lower" -> entry
local fx_dedupe2 = {}   -- "TYPE|base lower" -> entry

M.categories = {}       -- 정렬된 { name, count, set }
M.developers = {}
M.folders = {}          -- { id, name, count, set }
M.version = 0
M.building = false
M.status = ""
M.error = nil

local builder = nil
local project_sig = nil
local last_project_check = -1

local function ResetStatic()
    for _, src in ipairs(M.SOURCES) do lists[src] = {} end
    by_key, dyn_by_key, lookup, fx_dedupe, fx_dedupe2 = {}, {}, {}, {}, {}
    M.categories, M.developers, M.folders = {}, {}, {}
    project_sig = nil
end

local function Bump() M.version = M.version + 1 end

local function AddLookup(key, e)
    if not key or key == "" then return end
    local t = lookup[key]
    if not t then t = {}; lookup[key] = t end
    for i = 1, #t do if t[i] == e then return end end
    t[#t + 1] = e
end

local function NewEntry(kind, name, detail, badge)
    local e = {
        kind   = kind,
        name   = name or "",
        detail = detail or "",
        badge  = badge or "",
    }
    e.lname = Lower(e.name)
    e.lsearch = Lower(e.name .. " " .. e.detail .. " " .. e.badge)
    return e
end

local function Register(list_name, e, dynamic)
    local list = lists[list_name]
    list[#list + 1] = e
    if dynamic then dyn_by_key[e.key] = e else by_key[e.key] = e end
end

local function SortList(list)
    table.sort(list, function(a, b)
        if a.lname == b.lname then return a.key < b.key end
        return a.lname < b.lname
    end)
end

-- 파일 전체를 줄 단위로 순회
local function EachLine(path, fn)
    local f = io.open(path, "r")
    if not f then return false end
    for line in f:lines() do
        fn((line:gsub("\r$", "")))
    end
    f:close()
    return true
end

-- 간단한 ini 파서: sections[section][key] = value
local function ReadIni(path)
    local sections, cur = {}, nil
    EachLine(path, function(line)
        local sec = line:match("^%[(.-)%]%s*$")
        if sec then
            cur = sections[sec] or {}
            sections[sec] = cur
        elseif cur then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k then cur[k] = v end
        end
    end)
    return sections
end

local function FirstExisting(names)
    for _, n in ipairs(names) do
        local p = JoinPath(RES, n)
        if FileExists(p) then return p end
    end
    return nil
end

----------------------------------------------------------
-- FX 항목 생성
----------------------------------------------------------
local function AddFX(ftype, inst, full, add_names, keys)
    full = Trim(full)
    if full == "" then return nil end
    local dkey = ftype .. "|" .. Lower(full)
    local e = fx_dedupe[dkey]
    if e then
        for _, k in ipairs(keys or {}) do AddLookup(k, e) end
        return e
    end

    local base, vendor = SplitVendor(full)
    e = NewEntry("fx", base, vendor, ftype .. (inst and "i" or ""))
    e.fx_type       = ftype
    e.is_instrument = inst and true or false
    e.full_name     = full
    e.vendor        = vendor
    e.add_names     = add_names
    e.categories    = {}
    e.folders       = {}
    e.key           = "fx:" .. ftype .. ":" .. full

    fx_dedupe[dkey] = e
    local k2 = ftype .. "|" .. Lower(base)
    if not fx_dedupe2[k2] then fx_dedupe2[k2] = e end
    Register("fx", e)
    for _, k in ipairs(keys or {}) do AddLookup(k, e) end
    return e
end

local function SetInstrument(e, inst)
    if inst and not e.is_instrument then
        e.is_instrument = true
        e.badge = e.fx_type .. "i"
    end
end

local function ParseVST()
    local os_name = RPR.GetOS() or ""
    local candidates = os_name:find("arm64") and
        { "reaper-vstplugins_arm64.ini", "reaper-vstplugins64.ini", "reaper-vstplugins.ini" } or
        { "reaper-vstplugins64.ini", "reaper-vstplugins_arm64.ini", "reaper-vstplugins.ini" }
    local path = FirstExisting(candidates)
    if not path then return end

    local in_cache = true
    EachLine(path, function(line)
        local sec = line:match("^%[(.-)%]")
        if sec then in_cache = (sec == "vstcache"); return end
        if not in_cache then return end

        local key, _, uid, name = line:match("^([^=]+)=([^,]*),([^,]*),(.*)$")
        if not key or not name or name == "" or name:sub(1, 1) == "<" then return end

        local inst = false
        if name:find("!!!VSTi", 1, true) then
            inst = true
            name = name:gsub("!!!VSTi", "")
        end
        name = Trim(name)
        if name == "" then return end

        local file = key:match("^[^<]+") or key
        local ext = Lower(file:match("%.([%w]+)$") or "")
        local ftype = (ext == "vst3") and "VST3" or "VST"
        local prefix = ftype .. (inst and "i" or "") .. ": "
        local add_names = { prefix .. name }
        if inst then add_names[#add_names + 1] = ftype .. ": " .. name end
        add_names[#add_names + 1] = name

        local keys = { NormKey(key), NormKey(file) }
        local uid_num = (uid or ""):match("^(%-?%d+)")
        if uid_num then keys[#keys + 1] = NormKey(file) .. "<" .. uid_num end

        local e = AddFX(ftype, inst, name, add_names, keys)
        if e then
            SetInstrument(e, inst)
            e.file_key = NormKey(key)
        end
    end)
end

local function ParseCLAP()
    local os_name = RPR.GetOS() or ""
    local candidates
    if os_name:find("Win") then
        candidates = { "reaper-clap-win64.ini", "reaper-clap-win-arm64.ini", "reaper-clap-win32.ini" }
    elseif os_name:find("OSX") or os_name:find("mac") then
        candidates = os_name:find("arm64") and
            { "reaper-clap-macos-arm64.ini", "reaper-clap-macos-aarch64.ini", "reaper-clap-macos-x86_64.ini" } or
            { "reaper-clap-macos-x86_64.ini", "reaper-clap-macos-arm64.ini" }
    else
        candidates = { "reaper-clap-linux-x86_64.ini", "reaper-clap-linux-aarch64.ini" }
    end
    local path = FirstExisting(candidates)
    if not path then return end

    local cur_file = ""
    EachLine(path, function(line)
        local sec = line:match("^%[(.-)%]")
        if sec then cur_file = sec; return end
        local id, flags, name = line:match("^([^=]+)=(%d+)|(.*)$")
        if not id or id == "_" or not name or name == "" then return end
        local inst = ((tonumber(flags) or 0) & 1) == 1
        local add_names = { (inst and "CLAPi: " or "CLAP: ") .. name }
        if inst then add_names[#add_names + 1] = "CLAP: " .. name end
        local e = AddFX("CLAP", inst, name, add_names, { Lower(id), NormKey(cur_file) })
        if e then SetInstrument(e, inst) end
    end)
end

local function ParseJS()
    local path = JoinPath(RES, "reaper-jsfx.ini")
    if not FileExists(path) then return end
    EachLine(path, function(line)
        local ident, name = line:match('^NAME%s+"([^"]+)"%s+"(.*)"%s*$')
        if not ident then ident, name = line:match('^NAME%s+(%S+)%s+"(.*)"%s*$') end
        if not ident or not name then return end
        name = Trim(name:gsub("^JS:%s*", ""))
        if name == "" then name = ident end
        local slash = ident:gsub("\\", "/")
        local keys = { "js:" .. Lower(slash), "js:" .. Lower((slash:gsub("%.jsfx$", ""))) }
        local e = AddFX("JS", false, name, { "JS:" .. ident, "JS: " .. name }, keys)
        if e then
            e.js_ident = ident
            if e.vendor == "" then
                local folder = slash:match("^(.*)/[^/]+$")
                if folder then
                    e.detail = folder
                    e.lsearch = Lower(e.name .. " " .. e.detail .. " " .. e.badge)
                end
            end
        end
    end)
end

-- REAPER가 실제로 보고하는 FX 목록으로 보충 (LV2 / DX / AU 등, 그리고 정식 표기 이름 확보)
local function ParseEnumInstalled()
    if not RPR.EnumInstalledFX then return end
    local i = 0
    while true do
        local ok, name, ident = RPR.EnumInstalledFX(i)
        if not ok then break end
        i = i + 1
        local prefix, rest = (name or ""):match("^([%w]+):%s*(.+)$")
        if prefix and rest then
            local ftype, inst = prefix, false
            if #prefix > 2 and prefix:sub(-1) == "i" then
                ftype = prefix:sub(1, -2); inst = true
            end
            if ftype == "VST2" then ftype = "VST" end
            local base_rest = Lower((SplitVendor(rest)))
            -- 1) 파일/ident 로 같은 플러그인인지 먼저 연결 (이름이 달라도 중복 생성 방지)
            local e, linked_by_ident = nil, false
            local id_slash = (ident or ""):gsub("\\", "/")
            for _, k in ipairs({ NormKey(ident or ""), Lower(ident or ""), "js:" .. Lower(id_slash),
                                 "js:" .. Lower((id_slash:gsub("%.jsfx$", ""))) }) do
                local hits = (k ~= "" and k ~= "js:") and lookup[k] or nil
                if hits then
                    for _, h in ipairs(hits) do
                        if h.fx_type == ftype and (#hits == 1 or Lower(h.full_name) == Lower(rest) or h.lname == base_rest) then
                            e = h; linked_by_ident = true; break
                        end
                    end
                end
                if e then break end
            end
            -- 2) 이름으로 연결
            if not e then e = fx_dedupe[ftype .. "|" .. Lower(rest)] end
            if e and linked_by_ident and Lower(e.full_name) ~= Lower(rest) then
                -- REAPER에서 이름을 바꾼 플러그인(vstrenames) 등은 REAPER 표기를 따른다
                local nb, nv = SplitVendor(rest)
                e.alt_name = e.name   -- 원래 이름으로도 검색되도록 보관
                e.name, e.lname = nb, Lower(nb)
                if nv ~= "" then e.vendor, e.detail = nv, nv end
            end
            if not e then
                local base, vendor = SplitVendor(rest)
                local cand = fx_dedupe2[ftype .. "|" .. Lower(base)]
                if cand and (cand.vendor == "" or cand.vendor == vendor) then e = cand end
            end
            local keys = { NormKey(ident or ""), Lower(ident or "") }
            if e then
                -- REAPER 정식 표기를 우선 시도 이름으로 (JS는 ident가 더 정확하므로 두 번째)
                local exists = false
                for _, n in ipairs(e.add_names) do if n == name then exists = true break end end
                if not exists then
                    table.insert(e.add_names, (ftype == "JS") and 2 or 1, name)
                end
                SetInstrument(e, inst)
                if e.vendor == "" then
                    local _, vendor = SplitVendor(rest)
                    if vendor ~= "" then e.vendor = vendor; e.detail = vendor end
                end
                for _, k in ipairs(keys) do AddLookup(k, e) end
            else
                local ne = AddFX(ftype, inst, rest, { name }, keys)
                if ne then SetInstrument(ne, inst) end
            end
        end
        if i % 400 == 0 then coroutine.yield() end
    end
end

----------------------------------------------------------
-- FX Chain / Track Template 파일 스캔
----------------------------------------------------------
local function ScanDir(root, rel, ext, out, depth)
    if depth > 10 then return end
    local dir = (rel == "") and root or JoinPath(root, rel)
    RPR.EnumerateFiles(dir, -1)
    local i = 0
    while true do
        local f = RPR.EnumerateFiles(dir, i)
        if not f then break end
        if Lower(f):sub(-#ext) == ext then
            out[#out + 1] = { rel = (rel == "") and f or (rel .. "/" .. f), file = f, folder = rel }
        end
        i = i + 1
    end
    RPR.EnumerateSubdirectories(dir, -1)
    i = 0
    while true do
        local d = RPR.EnumerateSubdirectories(dir, i)
        if not d then break end
        ScanDir(root, (rel == "") and d or (rel .. "/" .. d), ext, out, depth + 1)
        i = i + 1
    end
end

local function BuildChains()
    local root = JoinPath(RES, "FXChains")
    local files = {}
    ScanDir(root, "", ".rfxchain", files, 0)
    for _, f in ipairs(files) do
        local e = NewEntry("chain", StripExt(f.file), f.folder, "CHAIN")
        e.rel_path  = f.rel
        e.full_path = JoinPath(root, f.rel)
        e.add_names = { f.rel, (f.rel:gsub("/", SEP)), e.full_path }
        e.key = "chain:" .. Lower(f.rel)
        e.categories, e.folders = {}, {}
        Register("chain", e)
        AddLookup(NormKey(f.rel), e)
        AddLookup(Lower(f.rel), e)
    end
    SortList(lists.chain)
end

local function BuildTemplates()
    local root = JoinPath(RES, "TrackTemplates")
    local files = {}
    ScanDir(root, "", ".rtracktemplate", files, 0)
    for _, f in ipairs(files) do
        local e = NewEntry("template", StripExt(f.file), f.folder, "TEMPLATE")
        e.full_path = JoinPath(root, f.rel)
        e.key = "template:" .. Lower(f.rel)
        Register("template", e)
    end
    SortList(lists.template)
end

----------------------------------------------------------
-- FX 메타데이터: Category / Developer / Folders(Tags)
----------------------------------------------------------
local function LookupEntries(key)
    return lookup[NormKey(key)] or lookup[Lower(key)] or lookup["js:" .. Lower((key:gsub("\\", "/")))]
end

local function AddCategory(e, cat)
    cat = Trim(cat)
    if cat == "" then return end
    for _, c in ipairs(e.categories) do if c == cat then return end end
    e.categories[#e.categories + 1] = cat
end

local function ApplyCategorySection(sec)
    if not sec then return end
    for key, val in pairs(sec) do
        local entries = LookupEntries(key)
        if entries then
            for _, e in ipairs(entries) do
                if e.categories then
                    for cat in (val .. "|"):gmatch("([^|]*)|") do AddCategory(e, cat) end
                end
            end
        end
    end
end

local function ResolveFolderItem(item, typ)
    local slash = item:gsub("\\", "/")
    local cands = {}
    if typ == 2 then
        cands[#cands + 1] = "js:" .. Lower(slash)
        cands[#cands + 1] = "js:" .. Lower((slash:gsub("%.jsfx$", "")))
    end
    cands[#cands + 1] = NormKey(item)
    cands[#cands + 1] = Lower(item)
    cands[#cands + 1] = Lower(slash)
    cands[#cands + 1] = "js:" .. Lower(slash)
    for _, c in ipairs(cands) do
        if lookup[c] then return lookup[c] end
    end
    return nil
end

local function BuildMeta()
    -- Category / Developer
    local tags = ReadIni(JoinPath(RES, "reaper-fxtags.ini"))
    ApplyCategorySection(tags["category"])
    if tags["developer"] then
        for key, dev in pairs(tags["developer"]) do
            dev = Trim(dev)
            local entries = LookupEntries(key)
            if entries and dev ~= "" then
                for _, e in ipairs(entries) do
                    if e.kind == "fx" then e.vendor = dev; e.detail = dev end
                end
            end
        end
    end

    local folders_ini = ReadIni(JoinPath(RES, "reaper-fxfolders.ini"))
    ApplyCategorySection(folders_ini["category"])

    -- Folders (REAPER FX 브라우저에서 사용자가 정리한 폴더 = Tags)
    local fsec = folders_ini["Folders"]
    if fsec then
        local nb = tonumber(fsec["NbFolders"]) or 0
        for i = 0, nb - 1 do
            local id = fsec["Id" .. i]
            local name = fsec["Name" .. i]
            if id and name then
                local folder = { id = id, name = name, set = {}, count = 0 }
                local sec = folders_ini["Folder" .. id]
                if sec then
                    local n = tonumber(sec["Nb"]) or 0
                    for j = 0, n - 1 do
                        local item = sec["Item" .. j]
                        if item and item ~= "" then
                            local entries = ResolveFolderItem(item, tonumber(sec["Type" .. j]))
                            if entries then
                                for _, e in ipairs(entries) do
                                    if not folder.set[e] then
                                        folder.set[e] = true
                                        folder.count = folder.count + 1
                                        if e.folders then e.folders[#e.folders + 1] = name end
                                    end
                                end
                            end
                        end
                    end
                end
                M.folders[#M.folders + 1] = folder
            end
        end
    end

    -- VST3 버전이 있는 VST2 / 중복 표시용 플래그, 검색 문자열 갱신, 목록 집계
    local vst3_names = {}
    for _, e in ipairs(lists.fx) do
        if e.fx_type == "VST3" then vst3_names[e.lname] = true end
    end
    local cat_map, dev_map = {}, {}
    for _, e in ipairs(lists.fx) do
        if e.fx_type == "VST" and vst3_names[e.lname] then e.has_vst3_twin = true end
        e.lname = Lower(e.name)
        local extra = table.concat(e.categories, " ") .. " " .. table.concat(e.folders, " ")
            .. " " .. (e.alt_name or "")
        e.lsearch = Lower(e.name .. " " .. e.detail .. " " .. e.badge .. " " .. extra)
        for _, c in ipairs(e.categories) do
            local cm = cat_map[c]
            if not cm then cm = { name = c, count = 0, set = {} }; cat_map[c] = cm end
            cm.set[e] = true; cm.count = cm.count + 1
        end
        if e.vendor and e.vendor ~= "" then
            local dm = dev_map[e.vendor]
            if not dm then dm = { name = e.vendor, count = 0, set = {} }; dev_map[e.vendor] = dm end
            dm.set[e] = true; dm.count = dm.count + 1
        end
    end
    local function SortedValues(map)
        local arr = {}
        for _, v in pairs(map) do arr[#arr + 1] = v end
        table.sort(arr, function(a, b) return a.name:lower() < b.name:lower() end)
        return arr
    end
    M.categories = SortedValues(cat_map)
    M.developers = SortedValues(dev_map)
end

----------------------------------------------------------
-- Actions (Main section)
----------------------------------------------------------
local function BuildActions()
    if not RPR.kbd_enumerateActions or not RPR.SectionFromUniqueID then return end
    local section = RPR.SectionFromUniqueID(0)
    if not section then return end
    local list = {}
    local i = 0
    while true do
        local cmd, name = RPR.kbd_enumerateActions(section, i)
        if not cmd or cmd == 0 then break end
        i = i + 1
        if name and name ~= "" then
            local named = RPR.ReverseNamedCommandLookup(cmd)
            local e = NewEntry("action", name, "", "ACTION")
            e.cmd = cmd
            if named and named ~= "" then
                e.named = "_" .. named
                e.key = "action:" .. e.named
            else
                e.key = "action:" .. tostring(cmd)
            end
            list[#list + 1] = e
        end
        if i % 600 == 0 then
            M.status = string.format("Indexing actions... %d", i)
            coroutine.yield()
        end
    end
    SortList(list)
    for _, e in ipairs(list) do Register("action", e) end
end

----------------------------------------------------------
-- 최근 프로젝트 (REAPER.ini [Recent])
----------------------------------------------------------
local function BuildRecentProjects()
    local ini = RPR.get_ini_file and RPR.get_ini_file() or JoinPath(RES, "REAPER.ini")
    local ini_data = ReadIni(ini)
    local sec = ini_data["Recent"] or ini_data["recent"]
    if not sec then return end
    local arr = {}
    for k, v in pairs(sec) do
        local n = tonumber(k:match("^recent(%d+)$"))
        if n and v ~= "" then arr[#arr + 1] = { n = n, path = v } end
    end
    table.sort(arr, function(a, b) return a.n < b.n end)
    local seen = {}
    for _, p in ipairs(arr) do
        local key = Lower(p.path)
        if not seen[key] and FileExists(p.path) then
            seen[key] = true
            local folder = (p.path:match("^(.*)[/\\][^/\\]+$") or "")
            local e = NewEntry("project", StripExt(Basename(p.path)), Basename(folder), "PROJECT")
            e.full_path = p.path
            e.key = "project:" .. key
            Register("project", e)
        end
    end
end

----------------------------------------------------------
-- 프로젝트 항목 (Track / Item / Marker / Region)
----------------------------------------------------------
local MAX_ITEMS = 30000

local function ClearDynamic()
    lists.track, lists.item, lists.marker = {}, {}, {}
    dyn_by_key = {}
end

function M.RefreshProject(force, opts)
    opts = opts or {}
    local now = RPR.time_precise()
    if not force and (now - last_project_check) < 0.35 then return end
    last_project_check = now

    local proj = RPR.EnumProjects(-1)
    local flags = (opts.tracks and "T" or "") .. (opts.items and "I" or "") .. (opts.markers and "M" or "")
    local sig = tostring(proj) .. ":" .. tostring(RPR.GetProjectStateChangeCount(proj)) .. ":" .. flags
    if sig == project_sig then return end
    project_sig = sig

    ClearDynamic()
    local track_count = RPR.CountTracks(0)
    local item_total = 0

    for ti = 0, track_count - 1 do
        local tr = RPR.GetTrack(0, ti)
        local _, tname = RPR.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        local num = ti + 1
        local disp = (tname ~= "" and tname) or ("Track " .. num)

        if opts.tracks then
            local e = NewEntry("track", disp, "Track " .. num, "TRACK")
            e.track = tr
            e.guid  = RPR.GetTrackGUID(tr)
            e.color = ColorFromNative(RPR.GetTrackColor(tr))
            e.key   = "track:" .. e.guid
            Register("track", e, true)
        end

        if opts.items and item_total < MAX_ITEMS then
            local ic = RPR.CountTrackMediaItems(tr)
            for ii = 0, ic - 1 do
                local item = RPR.GetTrackMediaItem(tr, ii)
                local take = RPR.GetActiveTake(item)
                local iname = take and RPR.GetTakeName(take) or ""
                if iname == "" then
                    local _, notes = RPR.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
                    iname = (notes or ""):match("^[^\r\n]*") or ""
                end
                if iname ~= "" then
                    local _, guid = RPR.GetSetMediaItemInfo_String(item, "GUID", "", false)
                    local e = NewEntry("item", iname, disp, "ITEM")
                    e.item  = item
                    e.track = tr
                    e.guid  = guid
                    e.pos   = RPR.GetMediaItemInfo_Value(item, "D_POSITION")
                    local icol = RPR.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
                    if (not icol or icol == 0) and take then icol = RPR.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR") end
                    e.color = ColorFromNative(math.floor(icol or 0))
                    e.key   = "item:" .. guid
                    Register("item", e, true)
                    item_total = item_total + 1
                    if item_total >= MAX_ITEMS then break end
                end
            end
        end
    end

    if opts.markers then
        local i = 0
        while true do
            local retval, isrgn, pos, rgnend, name, idx, color = RPR.EnumProjectMarkers3(0, i)
            if not retval or retval == 0 then break end
            local kind = isrgn and "region" or "marker"
            local disp = (name ~= "" and name) or ((isrgn and "Region " or "Marker ") .. idx)
            local time_str = RPR.format_timestr_pos(pos, "", -1)
            local e = NewEntry(kind, disp, (isrgn and "R" or "M") .. idx .. "  " .. time_str, isrgn and "REGION" or "MARKER")
            e.pos, e.rgnend, e.index, e.is_region = pos, rgnend, idx, isrgn
            e.color = ColorFromNative(color)
            e.key = kind .. ":" .. idx
            Register("marker", e, true)
            i = i + 1
        end
    end

    SortList(lists.track)
    SortList(lists.marker)
    -- 아이템은 타임라인 순서가 더 자연스러우므로 이름 → 위치 순
    table.sort(lists.item, function(a, b)
        if a.lname == b.lname then return (a.pos or 0) < (b.pos or 0) end
        return a.lname < b.lname
    end)
    Bump()
end

----------------------------------------------------------
-- 빌드 제어
----------------------------------------------------------
local function BuildAll()
    M.status = "Indexing FX..."
    ParseVST();  coroutine.yield()
    ParseCLAP()
    ParseJS();   coroutine.yield()
    ParseEnumInstalled()
    BuildChains()
    SortList(lists.fx)
    BuildMeta()
    Bump(); coroutine.yield()

    M.status = "Indexing templates..."
    BuildTemplates()
    BuildRecentProjects()
    Bump(); coroutine.yield()

    M.status = "Indexing actions..."
    BuildActions()
    Bump()
    M.status = ""
end

function M.Rebuild()
    ResetStatic()
    M.error = nil
    M.building = true
    builder = coroutine.create(BuildAll)
    Bump()
end

-- 매 프레임 호출: budget(초) 만큼만 인덱싱 진행
function M.Step(budget)
    if not M.building or not builder then return end
    local t0 = RPR.time_precise()
    repeat
        local ok, err = coroutine.resume(builder)
        if not ok then
            M.error = tostring(err)
            M.building = false
            M.status = "Index error: " .. M.error
            break
        end
        if coroutine.status(builder) == "dead" then
            M.building = false
            builder = nil
            break
        end
    until (RPR.time_precise() - t0) > (budget or 0.012)
end

function M.GetList(name) return lists[name] or {} end

function M.Find(key)
    if not key then return nil end
    return by_key[key] or dyn_by_key[key]
end

function M.Count(name)
    local l = lists[name]
    return l and #l or 0
end

-- 항목 수 (사이드바 표시용)
function M.CountWhere(list_name, pred)
    local n = 0
    for _, e in ipairs(lists[list_name] or {}) do
        if pred(e) then n = n + 1 end
    end
    return n
end

ResetStatic()

return M
