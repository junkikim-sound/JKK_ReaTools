--========================================================
-- @title JKK_Search_Actions
-- @author Junki Kim
-- @noindex
-- 검색 결과 실행
--  * FX / FX Chain : 현재 선택(트랙 or 아이템)을 감지해 즉시 삽입 후 FX 창 표시
--  * VSTi          : 선택이 없으면 MIDI 입력이 설정된 새 트랙을 만들어 삽입
--  * Action        : 즉시 실행
--  * Track Template: 트랙 생성
--  * Track / Item / Marker / Region : 선택 및 화면 이동
--  * Project       : 열기 (이미 열려 있으면 해당 탭으로 전환)
--========================================================

local M = {}

function M.Create(deps)
local RPR   = reaper
local Store = deps.store
local Sel   = deps.sel
local Undo  = deps.undo

local A = {}

local CMD = {
    SCROLL_SEL_TRACKS_INTO_VIEW = 40913,
    NEW_PROJECT_TAB             = 40859,
}

A.TARGET_MODES = {
    { id = "auto",     label = "Auto (current selection)" },
    { id = "tracks",   label = "Selected tracks" },
    { id = "items",    label = "Selected items (take FX)" },
    { id = "input",    label = "Track input FX" },
    { id = "master",   label = "Master track" },
    { id = "newtrack", label = "New track" },
}

local function UndoLabel(key, name)
    if Undo and Undo.Label then
        local ok, label = pcall(Undo.Label, key, name)
        if ok then return label end
    end
    return "JKK_Search: " .. tostring(name)
end

----------------------------------------------------------
-- 대상 감지 (JKK_SelectionManager 연동)
----------------------------------------------------------
local function TrackLabel(tr)
    local num = math.floor(RPR.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
    if num < 0 then return "Master Track" end
    return "Track " .. num
end

-- mode_override: 컨텍스트 메뉴 등에서 강제로 지정한 대상 모드
-- build: true면 실제 대상 목록(트랙/테이크)까지 구성
function A.ResolveTarget(mode_override, build)
    local mode = mode_override or Store.Get("target_mode")
    local item_count  = RPR.CountSelectedMediaItems(0)
    local track_count = RPR.CountSelectedTracks(0)

    if mode == "auto" then
        local sm_mode = Sel and Sel.GetMode and Sel.GetMode() or nil
        if sm_mode == "Item" and item_count > 0 then mode = "items"
        elseif sm_mode == "Track" and track_count > 0 then mode = "tracks"
        elseif item_count > 0 then mode = "items"
        elseif track_count > 0 then mode = "tracks"
        else mode = "none" end
    end

    local t = { mode = mode, tracks = {}, takes = {}, count = 0 }

    if mode == "tracks" or mode == "input" then
        t.count = track_count
        if track_count == 1 then
            local tr = RPR.GetSelectedTrack(0, 0)
            local _, name = RPR.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
            t.label = (mode == "input" and "Input FX · " or "") .. TrackLabel(tr)
            t.tooltip = name
        else
            t.label = (mode == "input" and "Input FX · " or "") .. track_count .. " Tracks"
        end
        if track_count == 0 then t.label = "No track selected" end
        if build then
            for i = 0, track_count - 1 do t.tracks[#t.tracks + 1] = RPR.GetSelectedTrack(0, i) end
        end
    elseif mode == "items" then
        t.count = item_count
        if item_count == 1 then
            local item = RPR.GetSelectedMediaItem(0, 0)
            local take = RPR.GetActiveTake(item)
            t.label = "1 Item"
            t.tooltip = take and RPR.GetTakeName(take) or nil
        else
            t.label = (item_count == 0) and "No item selected" or (item_count .. " Items")
        end
        if build then
            for i = 0, item_count - 1 do
                local item = RPR.GetSelectedMediaItem(0, i)
                local take = item and RPR.GetActiveTake(item)
                if take then t.takes[#t.takes + 1] = take end
            end
        end
    elseif mode == "master" then
        t.count = 1
        t.label = "Master Track"
        if build then t.tracks = { RPR.GetMasterTrack(0) } end
    elseif mode == "newtrack" then
        t.count = 1
        t.label = "New Track"
    else
        t.label = "No selection"
    end
    return t
end

-- 드래그 앤 드롭: 화면 좌표(native)의 아이템/트랙을 대상으로 변환
function A.TargetAtPoint(mx, my, e)
    if not (mx and my) then return nil end
    if e.kind ~= "template" and RPR.GetItemFromPoint then
        local item, take = RPR.GetItemFromPoint(mx, my, true)
        if item then
            take = take or RPR.GetActiveTake(item)
            if take then
                return { mode = "items", tracks = {}, takes = { take }, count = 1,
                         label = "Item · " .. (RPR.GetTakeName(take) or "") }
            end
        end
    end
    if RPR.GetTrackFromPoint then
        local tr = RPR.GetTrackFromPoint(mx, my)
        if tr then
            local _, name = RPR.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
            local label = TrackLabel(tr) .. ((name and name ~= "") and (" · " .. name) or "")
            return { mode = "tracks", tracks = { tr }, takes = {}, count = 1, label = label }
        end
    end
    if e.is_instrument then
        return { mode = "newtrack", tracks = {}, takes = {}, count = 1, label = "New Track" }
    end
    return nil
end

----------------------------------------------------------
-- FX 삽입 헬퍼
----------------------------------------------------------
local function AddToTrack(track, names, rec, inst)
    for _, nm in ipairs(names or {}) do
        local ok, idx = pcall(RPR.TrackFX_AddByName, track, nm, rec, inst)
        if ok and idx and idx >= 0 then return idx end
    end
    return -1
end

local function AddToTake(take, names, inst)
    for _, nm in ipairs(names or {}) do
        local ok, idx = pcall(RPR.TakeFX_AddByName, take, nm, inst)
        if ok and idx and idx >= 0 then return idx end
    end
    return -1
end

local function CreateTrack(name, arm_midi)
    local idx = RPR.CountTracks(0)
    local sel_count = RPR.CountSelectedTracks(0)
    if sel_count > 0 then
        local last = RPR.GetSelectedTrack(0, sel_count - 1)
        local num = math.floor(RPR.GetMediaTrackInfo_Value(last, "IP_TRACKNUMBER"))
        if num > 0 then idx = num end
    end
    RPR.InsertTrackAtIndex(idx, true)
    local tr = RPR.GetTrack(0, idx)
    if not tr then return nil end
    RPR.GetSetMediaTrackInfo_String(tr, "P_NAME", name or "", true)
    if arm_midi then
        -- MIDI: 모든 입력 장치 / 모든 채널, 모니터링 ON, 녹음 대기
        RPR.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 4096 | (63 << 5))
        RPR.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
        RPR.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
    end
    RPR.SetOnlyTrackSelected(tr)
    RPR.TrackList_AdjustWindows(false)
    return tr
end

local function ShowFX(show, is_chain)
    if not show then return end
    local mode = Store.Get("show_fx")
    if mode == "none" then return end
    local flag = (mode == "chain" or is_chain) and 1 or 3
    if show.take then
        RPR.TakeFX_Show(show.take, show.idx, flag)
    elseif show.track then
        local idx = show.idx
        if show.rec and idx < 0x1000000 then idx = idx | 0x1000000 end
        RPR.TrackFX_Show(show.track, idx, flag)
    end
end

function A.InsertFX(e, opts)
    opts = opts or {}
    local is_chain = (e.kind == "chain")
    -- opts.explicit: 드래그 앤 드롭으로 지정된 대상 { mode, tracks, takes, label }
    local target = opts.explicit or A.ResolveTarget(opts.target_mode, true)

    if target.mode == "none"
        or ((target.mode == "tracks" or target.mode == "input") and #target.tracks == 0)
        or (target.mode == "items" and #target.takes == 0) then
        if e.is_instrument then
            target = { mode = "newtrack", tracks = {}, takes = {}, label = "New Track" }
        else
            return false, "No track or item selected"
        end
    end

    local inst = (Store.Get("insert_pos") == "start") and -1000 or -1
    local ok_count = 0
    local show = nil
    local created = nil

    local nested = opts.nested
    if not nested then
        RPR.Undo_BeginBlock2(0)
        RPR.PreventUIRefresh(1)
    end

    if target.mode == "newtrack" then
        created = CreateTrack(e.name, e.is_instrument and Store.Get("arm_instrument_track"))
        if created then target.tracks = { created } end
    end

    if target.mode == "items" then
        for _, take in ipairs(target.takes) do
            local before = RPR.TakeFX_GetCount(take)
            local idx = AddToTake(take, e.add_names, inst)
            if idx >= 0 then
                ok_count = ok_count + 1
                if not show then
                    show = { take = take, idx = is_chain and ((inst == -1) and before or 0) or idx }
                end
            end
        end
    else
        local rec = (target.mode == "input")
        for _, tr in ipairs(target.tracks) do
            local before = rec and RPR.TrackFX_GetRecCount(tr) or RPR.TrackFX_GetCount(tr)
            local idx = AddToTrack(tr, e.add_names, rec, inst)
            if idx >= 0 then
                ok_count = ok_count + 1
                if not show then
                    local first = is_chain and ((inst == -1) and before or 0) or (idx & 0xFFFFFF)
                    show = { track = tr, idx = first, rec = rec }
                end
            end
        end
    end

    if ok_count == 0 and created then
        RPR.DeleteTrack(created)
    end

    if nested then
        if ok_count == 0 then return false, "Could not insert: " .. e.name end
        return true, "Inserted " .. e.name, show
    end

    RPR.PreventUIRefresh(-1)
    local key = is_chain and "search.insert_fx_chain"
        or (created and e.is_instrument and "search.insert_instrument_track")
        or "search.insert_fx"
    RPR.Undo_EndBlock2(0, UndoLabel(key, e.name), -1)
    RPR.TrackList_AdjustWindows(false)
    RPR.UpdateArrange()

    if ok_count == 0 then
        return false, "Could not insert: " .. e.name
    end
    ShowFX(show, is_chain)
    return true, string.format("Inserted %s on %s", e.name, target.label or "target")
end

-- 여러 FX를 한 번에 삽입 (Undo 1회, FX 창은 첫 대상의 FX 체인으로 표시)
function A.InsertFXList(list, opts)
    opts = opts or {}
    if #list == 1 then return A.InsertFX(list[1], opts) end
    if #list == 0 then return false, "Nothing to insert" end

    local target = opts.explicit or A.ResolveTarget(opts.target_mode, true)
    local first_inst = nil
    for _, e in ipairs(list) do if e.is_instrument then first_inst = e break end end
    if target.mode == "none"
        or ((target.mode == "tracks" or target.mode == "input") and #target.tracks == 0)
        or (target.mode == "items" and #target.takes == 0) then
        if not first_inst then return false, "No track or item selected" end
        target = { mode = "newtrack", tracks = {}, takes = {}, label = "New Track" }
    end

    RPR.Undo_BeginBlock2(0)
    RPR.PreventUIRefresh(1)
    local created = nil
    if target.mode == "newtrack" then
        local name = first_inst and first_inst.name or list[1].name
        created = CreateTrack(name, first_inst and Store.Get("arm_instrument_track"))
        target = { mode = "tracks", tracks = { created }, takes = {}, label = "New Track" }
    end

    local ok_count, first_show = 0, nil
    for _, e in ipairs(list) do
        local ok, _, show = A.InsertFX(e, { explicit = target, nested = true })
        if ok then
            ok_count = ok_count + 1
            first_show = first_show or show
        end
    end
    if ok_count == 0 and created then RPR.DeleteTrack(created) end

    RPR.PreventUIRefresh(-1)
    RPR.Undo_EndBlock2(0, UndoLabel("search.insert_fx_multi", tostring(ok_count)), -1)
    RPR.TrackList_AdjustWindows(false)
    RPR.UpdateArrange()

    if ok_count == 0 then return false, "Could not insert the selected FX" end
    ShowFX(first_show, true)
    return true, string.format("Inserted %d FX on %s", ok_count, target.label or "target")
end

-- REAPER의 "새 플러그인 스캔" 액션을 이름으로 찾아 실행 (고정 ID가 없으므로)
local SCAN_PATTERNS = { "scan for new plug", "re%-scan.*for new", "rescan.*plug", "re%-scan.*plug" }
function A.ScanForNewPlugins(action_list)
    for _, pat in ipairs(SCAN_PATTERNS) do
        for _, e in ipairs(action_list or {}) do
            if e.lname:find(pat) and not e.lname:find("clear cache", 1, true) then
                A.RunAction(e)
                return true, e.name
            end
        end
    end
    return false, nil
end

----------------------------------------------------------
-- 기타 실행
----------------------------------------------------------
function A.RunAction(e)
    local cmd = e.cmd
    if e.named then
        local c = RPR.NamedCommandLookup(e.named)
        if c and c ~= 0 then cmd = c end
    end
    if not cmd or cmd == 0 then return false, "Action not found: " .. e.name end
    RPR.Main_OnCommand(cmd, 0)
    return true, "Ran: " .. e.name
end

function A.InsertTemplate(e, opts)
    if not RPR.file_exists(e.full_path) then return false, "Template not found: " .. e.name end
    -- 드롭한 트랙 바로 아래에 삽입되도록 해당 트랙을 선택
    local ex = opts and opts.explicit
    if ex and ex.tracks and ex.tracks[1] then RPR.SetOnlyTrackSelected(ex.tracks[1]) end
    RPR.Main_openProject(e.full_path)
    return true, "Inserted template: " .. e.name
end

local function FindTrackByGUID(guid)
    for i = 0, RPR.CountTracks(0) - 1 do
        local tr = RPR.GetTrack(0, i)
        if RPR.GetTrackGUID(tr) == guid then return tr end
    end
    return nil
end

local function FindItemByGUID(guid)
    if RPR.BR_GetMediaItemByGUID then
        local it = RPR.BR_GetMediaItemByGUID(0, guid)
        if it then return it end
    end
    for i = 0, RPR.CountMediaItems(0) - 1 do
        local it = RPR.GetMediaItem(0, i)
        local _, g = RPR.GetSetMediaItemInfo_String(it, "GUID", "", false)
        if g == guid then return it end
    end
    return nil
end

function A.SelectTrack(e)
    local tr = e.track
    if not (tr and RPR.ValidatePtr2(0, tr, "MediaTrack*")) then tr = FindTrackByGUID(e.guid) end
    if not tr then return false, "Track not found: " .. e.name end
    RPR.SetOnlyTrackSelected(tr)
    if RPR.SetMixerScroll then RPR.SetMixerScroll(tr) end
    RPR.Main_OnCommand(CMD.SCROLL_SEL_TRACKS_INTO_VIEW, 0)
    return true, "Selected " .. e.name
end

function A.SelectItem(e)
    local item = e.item
    if not (item and RPR.ValidatePtr2(0, item, "MediaItem*")) then item = FindItemByGUID(e.guid) end
    if not item then return false, "Item not found: " .. e.name end
    local tr = RPR.GetMediaItem_Track(item)
    RPR.PreventUIRefresh(1)
    RPR.SelectAllMediaItems(0, false)
    RPR.SetMediaItemSelected(item, true)
    if tr then RPR.SetOnlyTrackSelected(tr) end
    RPR.PreventUIRefresh(-1)
    RPR.SetEditCurPos(RPR.GetMediaItemInfo_Value(item, "D_POSITION"), true, false)
    RPR.Main_OnCommand(CMD.SCROLL_SEL_TRACKS_INTO_VIEW, 0)
    RPR.UpdateArrange()
    return true, "Selected item " .. e.name
end

function A.GoToMarker(e)
    RPR.SetEditCurPos(e.pos or 0, true, true)
    return true, "Moved to " .. e.name
end

function A.OpenProject(e)
    if not RPR.file_exists(e.full_path) then return false, "Project not found: " .. e.name end
    -- 이미 열려 있는 탭이면 전환
    local i = 0
    while true do
        local proj, fn = RPR.EnumProjects(i)
        if not proj then break end
        if fn and fn:lower() == e.full_path:lower() then
            RPR.SelectProjectInstance(proj)
            return true, "Switched to " .. e.name
        end
        i = i + 1
    end
    if Store.Get("project_new_tab") then
        RPR.Main_OnCommand(CMD.NEW_PROJECT_TAB, 0)
    end
    RPR.Main_openProject(e.full_path)
    return true, "Opened " .. e.name
end

----------------------------------------------------------
-- 디스패처
----------------------------------------------------------
function A.Execute(e, opts)
    if not e then return false, "Nothing selected" end
    local ok, msg
    local kind = e.kind
    if kind == "fx" or kind == "chain" then ok, msg = A.InsertFX(e, opts)
    elseif kind == "action" then ok, msg = A.RunAction(e)
    elseif kind == "template" then ok, msg = A.InsertTemplate(e, opts)
    elseif kind == "track" then ok, msg = A.SelectTrack(e)
    elseif kind == "item" then ok, msg = A.SelectItem(e)
    elseif kind == "marker" or kind == "region" then ok, msg = A.GoToMarker(e)
    elseif kind == "project" then ok, msg = A.OpenProject(e)
    else ok, msg = false, "Unknown entry" end
    if ok then Store.PushRecent(e.key) end
    return ok, msg
end

-- 다중 선택 실행: FX/Chain은 한 번에 삽입, Action/Template은 순서대로 실행
function A.ExecuteMany(list, opts)
    if not list or #list == 0 then return false, "Nothing selected" end
    if #list == 1 then return A.Execute(list[1], opts) end
    local fx, others = {}, {}
    for _, e in ipairs(list) do
        if e.kind == "fx" or e.kind == "chain" then fx[#fx + 1] = e else others[#others + 1] = e end
    end
    local any_ok, msgs = false, {}
    if #fx > 0 then
        local ok, msg = A.InsertFXList(fx, opts)
        if ok then
            any_ok = true
            for i = #fx, 1, -1 do Store.PushRecent(fx[i].key) end
        end
        msgs[#msgs + 1] = msg
    end
    local ran = 0
    for _, e in ipairs(others) do
        if e.kind == "action" or e.kind == "template" then
            if A.Execute(e, opts) then ran = ran + 1; any_ok = true end
        end
    end
    if ran > 0 then msgs[#msgs + 1] = string.format("Ran %d item%s", ran, ran == 1 and "" or "s") end
    return any_ok, table.concat(msgs, "  ·  ")
end

-- 실행 버튼에 표시할 동사
function A.VerbFor(e)
    if not e then return "Run" end
    local k = e.kind
    if k == "fx" or k == "chain" then return "Insert" end
    if k == "action" then return "Run" end
    if k == "template" then return "Insert" end
    if k == "project" then return "Open" end
    if k == "track" or k == "item" then return "Select" end
    return "Go to"
end

return A
end

return M
