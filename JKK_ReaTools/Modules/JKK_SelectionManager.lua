--========================================================
-- @title JKK_SelectionManager
-- @author Junki Kim
-- @noindex
--========================================================

local RPR = reaper

if _G.JKK_SelectionManager then
    return _G.JKK_SelectionManager
end

local M = {}

---------------------------------------------------------
-- Range Detection Mode Constants
---------------------------------------------------------
M.RANGE_IGNORE  = 0
M.RANGE_REGIONS = 1
M.RANGE_ITEMS   = 2

---------------------------------------------------------
-- User Configurable Detection Settings (ExtState)
---------------------------------------------------------
local EXT_SECTION   = "JKK_SelectionManager"
local STATE_SECTION = "JKK_SelectionManager_State"

local SETTINGS_DEFAULTS = {
    arrange_selects_track = false,          -- 어레인지 뷰 클릭 시에도 Track 모드로 전환할지 여부
    ts_detect_mode        = M.RANGE_REGIONS,-- Time Selection 감지 대상 (0: Ignore, 1: Regions/Markers, 2: Items in Range)
    loop_detect_mode      = M.RANGE_IGNORE, -- Loop Points 감지 대상 (0: Ignore, 1: Regions/Markers, 2: Items in Range)
}

local function LoadBoolSetting(key, default)
    local val = RPR.GetExtState(EXT_SECTION, key)
    if val == "" then return default end
    return val == "1"
end

local function LoadIntSetting(key, default)
    local val = tonumber(RPR.GetExtState(EXT_SECTION, key))
    if not val then return default end
    return math.max(0, math.min(2, math.floor(val)))
end

-- 기존 설정 마이그레이션 지원
local initial_ts_mode = tonumber(RPR.GetExtState(EXT_SECTION, "ts_detect_mode"))
if not initial_ts_mode then
    local legacy_ts = RPR.GetExtState(EXT_SECTION, "ts_auto_targets_regions")
    initial_ts_mode = (legacy_ts == "0") and M.RANGE_IGNORE or SETTINGS_DEFAULTS.ts_detect_mode
end

local initial_loop_mode = tonumber(RPR.GetExtState(EXT_SECTION, "loop_detect_mode"))
if not initial_loop_mode then
    local legacy_loop = RPR.GetExtState(EXT_SECTION, "include_loop_points")
    initial_loop_mode = (legacy_loop == "1") and M.RANGE_REGIONS or SETTINGS_DEFAULTS.loop_detect_mode
end

local settings = {
    arrange_selects_track = LoadBoolSetting("arrange_selects_track", SETTINGS_DEFAULTS.arrange_selects_track),
    ts_detect_mode        = math.max(0, math.min(2, math.floor(initial_ts_mode))),
    loop_detect_mode      = math.max(0, math.min(2, math.floor(initial_loop_mode))),
}

-- 하위 호환 필드 유지
settings.ts_auto_targets_regions = (settings.ts_detect_mode == M.RANGE_REGIONS)
settings.include_loop_points     = (settings.loop_detect_mode ~= M.RANGE_IGNORE)

function M.GetSettings()
    return settings
end

function M.SetSetting(key, value)
    if key == "arrange_selects_track" then
        settings.arrange_selects_track = value and true or false
        RPR.SetExtState(EXT_SECTION, key, settings.arrange_selects_track and "1" or "0", true)
    elseif key == "ts_detect_mode" then
        local mode = math.max(0, math.min(2, math.floor(tonumber(value) or 0)))
        settings.ts_detect_mode = mode
        settings.ts_auto_targets_regions = (mode == M.RANGE_REGIONS)
        RPR.SetExtState(EXT_SECTION, "ts_detect_mode", tostring(mode), true)
        RPR.SetExtState(EXT_SECTION, "ts_auto_targets_regions", settings.ts_auto_targets_regions and "1" or "0", true)
    elseif key == "loop_detect_mode" then
        local mode = math.max(0, math.min(2, math.floor(tonumber(value) or 0)))
        settings.loop_detect_mode = mode
        settings.include_loop_points = (mode ~= M.RANGE_IGNORE)
        RPR.SetExtState(EXT_SECTION, "loop_detect_mode", tostring(mode), true)
        RPR.SetExtState(EXT_SECTION, "include_loop_points", settings.include_loop_points and "1" or "0", true)
    elseif key == "ts_auto_targets_regions" then
        M.SetSetting("ts_detect_mode", value and M.RANGE_REGIONS or M.RANGE_IGNORE)
    elseif key == "include_loop_points" then
        M.SetSetting("loop_detect_mode", value and M.RANGE_REGIONS or M.RANGE_IGNORE)
    end
end

function M.GetTimeSelectionMode()
    return settings.ts_detect_mode
end

function M.SetTimeSelectionMode(mode)
    M.SetSetting("ts_detect_mode", mode)
end

function M.GetLoopPointsMode()
    return settings.loop_detect_mode
end

function M.SetLoopPointsMode(mode)
    M.SetSetting("loop_detect_mode", mode)
end

function M.ResetSettings()
    for k, v in pairs(SETTINGS_DEFAULTS) do
        M.SetSetting(k, v)
    end
end

---------------------------------------------------------
-- Internal State
---------------------------------------------------------
local current_mode = "Item" -- "Item" | "Track" | "Region/Marker" | "None"
local mode_focus_active = false
local active_range_source = "None" -- "None" | "Selection" | "TimeSelection" | "LoopPoints"

local is_mouse_down = false
local prev_mouse_down = false
local mouse_released = false

local mouse_press_item = nil
local mouse_press_area = "unknown"
local mouse_press_x, mouse_press_y = nil, nil
local item_interaction_active = false
local arrange_drag_pending = false
local arrange_drag_active = false
local arrange_drag_is_range_selection = false
local ARRANGE_DRAG_THRESHOLD = 4

local prev_item_sig = ""
local prev_track_sig = ""
local prev_track_count = 0
local prev_ts_sig = ""
local prev_loop_sig = ""
local prev_rm_sig = ""
local initialized = false

---------------------------------------------------------
-- Cross-Script Shared State (In-Memory ExtState)
---------------------------------------------------------
local function PublishSharedContext()
    RPR.SetExtState(STATE_SECTION, "mode", current_mode, false)
    RPR.SetExtState(STATE_SECTION, "active", mode_focus_active and "1" or "0", false)
    RPR.SetExtState(STATE_SECTION, "range_source", active_range_source, false)
end

local function RestoreSharedContext()
    local shared_mode = RPR.GetExtState(STATE_SECTION, "mode")
    local shared_active = RPR.GetExtState(STATE_SECTION, "active") == "1"
    local shared_src = RPR.GetExtState(STATE_SECTION, "range_source")

    if shared_mode == "Item" or shared_mode == "Track" or shared_mode == "Region/Marker" then
        current_mode = shared_mode
    end

    if not shared_active or shared_mode == "" or shared_mode == "None" then
        mode_focus_active = false
        return false
    end

    if shared_mode == "Item" and RPR.CountSelectedMediaItems(0) > 0 then
        current_mode = "Item"
        mode_focus_active = true
        active_range_source = (shared_src ~= "") and shared_src or "Selection"
        return true
    elseif shared_mode == "Track" and RPR.CountSelectedTracks(0) > 0 then
        current_mode = "Track"
        mode_focus_active = true
        active_range_source = "Selection"
        return true
    elseif shared_mode == "Region/Marker" then
        local sr, sm = M.GetSelectedRegionMarkers()
        local tr, tm = M.GetTimeSelectionRegionMarkers()
        local lr, lm = M.GetLoopRegionMarkers()
        if (#sr + #sm + #tr + #tm + #lr + #lm) > 0 then
            current_mode = "Region/Marker"
            mode_focus_active = true
            active_range_source = (shared_src ~= "") and shared_src or "Selection"
            return true
        end
    end
    return false
end

---------------------------------------------------------
-- Mouse & Window Hit-Testing
---------------------------------------------------------
local function CheckLeftMouseDown()
    if RPR.JS_Mouse_GetState then
        return (RPR.JS_Mouse_GetState(1) & 1) == 1
    end
    return false
end

local function GetMouseContextArea()
    if not RPR.GetMousePosition or not RPR.GetThingFromPoint then
        return "unknown"
    end
    local mx, my = RPR.GetMousePosition()
    local _, info = RPR.GetThingFromPoint(mx, my)
    info = tostring(info or ""):lower()

    if info:find("ruler") or info:find("marker") or info:find("region") then
        return "ruler"
    elseif info:find("tcp") or info:find("mcp") or info:find("track") then
        if info:find("arrange") then
            return "arrange"
        end
        return "tcp"
    elseif info:find("arrange") or info:find("item") or info:find("envelope") then
        return "arrange"
    elseif info:find("transport") then
        return "transport"
    end
    return "other"
end

local function GetItemAtMousePosition()
    if not RPR.GetMousePosition or not RPR.GetItemFromPoint then
        return nil
    end
    local mx, my = RPR.GetMousePosition()
    if not mx or not my then return nil end
    return RPR.GetItemFromPoint(mx, my, false)
end

local function ResetArrangeInteraction()
    mouse_press_item = nil
    mouse_press_area = "unknown"
    mouse_press_x, mouse_press_y = nil, nil
    item_interaction_active = false
    arrange_drag_pending = false
    arrange_drag_active = false
    arrange_drag_is_range_selection = false
end

local function BeginMouseInteraction(area)
    mouse_press_area = area
    mouse_press_item = nil
    mouse_press_x, mouse_press_y = nil, nil
    item_interaction_active = false
    arrange_drag_pending = false
    arrange_drag_active = false
    arrange_drag_is_range_selection = false

    if area ~= "arrange" then return end

    if RPR.GetMousePosition then
        mouse_press_x, mouse_press_y = RPR.GetMousePosition()
    end

    mouse_press_item = GetItemAtMousePosition()
    if mouse_press_item then
        item_interaction_active = true
    else
        arrange_drag_pending = true
    end
end

local function UpdateArrangeDrag()
    if not arrange_drag_pending or not is_mouse_down then return end
    if not mouse_press_x or not mouse_press_y or not RPR.GetMousePosition then return end

    local mx, my = RPR.GetMousePosition()
    if not mx or not my then return end

    local dx = mx - mouse_press_x
    local dy = my - mouse_press_y
    if (dx * dx + dy * dy) >= (ARRANGE_DRAG_THRESHOLD * ARRANGE_DRAG_THRESHOLD) then
        arrange_drag_active = true
        arrange_drag_pending = false
    end
end

---------------------------------------------------------
-- Selection Queries & Range Helpers
---------------------------------------------------------
function M.GetSelectedItems()
    local items = {}
    local count = RPR.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
        local item = RPR.GetSelectedMediaItem(0, i)
        if item then items[#items + 1] = item end
    end
    return items
end

function M.GetSelectedTracks()
    local tracks = {}
    local count = RPR.CountSelectedTracks(0)
    for i = 0, count - 1 do
        local track = RPR.GetSelectedTrack(0, i)
        if track then tracks[#tracks + 1] = track end
    end
    return tracks
end

function M.GetSelectedRegionMarkers()
    local regions, markers = {}, {}
    local _, num_markers, num_regions = RPR.CountProjectMarkers(0)
    local total = num_markers + num_regions

    if RPR.GetRegionOrMarkerInfo_Value and RPR.GetProjectMarkerByIndex then
        for i = 0, total - 1 do
            local pm = RPR.GetProjectMarkerByIndex(0, i)
            if pm then
                local selected = RPR.GetRegionOrMarkerInfo_Value(0, pm, "B_UISEL")
                if selected and selected > 0.5 then
                    local _, is_region, pos, rgnend, name, markrgnindexnumber, color = RPR.EnumProjectMarkers3(0, i)
                    local entry = {
                        pm = pm,
                        index = markrgnindexnumber,
                        enum_idx = i,
                        is_region = is_region,
                        pos = pos,
                        rgnend = rgnend,
                        name = name or "",
                        color = color or 0
                    }
                    if is_region then
                        regions[#regions + 1] = entry
                    else
                        markers[#markers + 1] = entry
                    end
                end
            end
        end
    end

    return regions, markers
end

local function GetRegionMarkersInBounds(range_start, range_end)
    local regions, markers = {}, {}
    if not range_start or not range_end or range_end <= range_start then
        return regions, markers
    end

    local _, num_markers, num_regions = RPR.CountProjectMarkers(0)
    local total = num_markers + num_regions
    local eps = 1e-6

    for i = 0, total - 1 do
        local retval, is_region, pos, rgnend, name, markrgnindexnumber, color = RPR.EnumProjectMarkers3(0, i)
        if retval then
            local pm = RPR.GetProjectMarkerByIndex and RPR.GetProjectMarkerByIndex(0, i) or nil
            local hit = false
            if is_region then
                hit = (rgnend > (range_start + eps) and pos < (range_end - eps))
            else
                hit = (pos >= (range_start - eps) and pos <= (range_end + eps))
            end

            if hit then
                local entry = {
                    pm = pm,
                    index = markrgnindexnumber,
                    enum_idx = i,
                    is_region = is_region,
                    pos = pos,
                    rgnend = rgnend,
                    name = name or "",
                    color = color or 0
                }
                if is_region then
                    regions[#regions + 1] = entry
                else
                    markers[#markers + 1] = entry
                end
            end
        end
    end

    return regions, markers
end

function M.GetTimeSelectionRegionMarkers()
    local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
    return GetRegionMarkersInBounds(ts_start, ts_end)
end

function M.GetLoopRegionMarkers()
    local lp_start, lp_end = RPR.GetSet_LoopTimeRange(false, true, 0, 0, false)
    return GetRegionMarkersInBounds(lp_start, lp_end)
end

local function SelectItemsInBounds(range_start, range_end)
    if not range_start or not range_end or range_end <= range_start then return 0 end
    local eps = 1e-6
    local count = RPR.CountMediaItems(0)
    local selected_count = 0

    RPR.PreventUIRefresh(1)
    RPR.SelectAllMediaItems(0, false)
    for i = 0, count - 1 do
        local item = RPR.GetMediaItem(0, i)
        if item then
            local pos = RPR.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = RPR.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = pos + len
            if pos < (range_end - eps) and item_end > (range_start + eps) then
                RPR.SetMediaItemSelected(item, true)
                selected_count = selected_count + 1
            end
        end
    end
    RPR.PreventUIRefresh(-1)
    RPR.UpdateArrange()
    return selected_count
end

function M.GetTargets()
    local targets = {}

    if current_mode == "Item" then
        for _, item in ipairs(M.GetSelectedItems()) do
            local take = RPR.GetActiveTake(item)
            local name = ""
            if take then
                local _, take_name = RPR.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                name = take_name or ""
            end
            targets[#targets + 1] = {
                type = "Item",
                item = item,
                track = RPR.GetMediaItem_Track(item),
                original_name = name
            }
        end
    elseif current_mode == "Track" then
        for _, track in ipairs(M.GetSelectedTracks()) do
            local _, track_name = RPR.GetTrackName(track)
            targets[#targets + 1] = {
                type = "Track",
                track = track,
                original_name = track_name or ""
            }
        end
    elseif current_mode == "Region/Marker" then
        local sel_r, sel_m = M.GetSelectedRegionMarkers()
        if #sel_r == 0 and #sel_m == 0 then
            if active_range_source == "LoopPoints" and settings.loop_detect_mode == M.RANGE_REGIONS then
                sel_r, sel_m = M.GetLoopRegionMarkers()
            elseif settings.ts_detect_mode == M.RANGE_REGIONS then
                sel_r, sel_m = M.GetTimeSelectionRegionMarkers()
            elseif settings.loop_detect_mode == M.RANGE_REGIONS then
                sel_r, sel_m = M.GetLoopRegionMarkers()
            end
        end
        for _, r in ipairs(sel_r) do
            targets[#targets + 1] = {
                type = "Region",
                pm = r.pm,
                index = r.index,
                is_region = true,
                pos = r.pos,
                rgnend = r.rgnend,
                color = r.color,
                original_name = r.name
            }
        end
        for _, m in ipairs(sel_m) do
            targets[#targets + 1] = {
                type = "Marker",
                pm = m.pm,
                index = m.index,
                is_region = false,
                pos = m.pos,
                rgnend = m.rgnend,
                color = m.color,
                original_name = m.name
            }
        end
    end

    return targets
end

---------------------------------------------------------
-- State Update Loop
---------------------------------------------------------
local function BuildSignatures()
    local items = M.GetSelectedItems()
    local item_parts = { tostring(#items) }
    for i = 1, #items do
        item_parts[#item_parts + 1] = tostring(items[i])
    end
    local item_sig = table.concat(item_parts, ",")

    local tracks = M.GetSelectedTracks()
    local track_parts = { tostring(#tracks) }
    for i = 1, #tracks do
        track_parts[#track_parts + 1] = tostring(tracks[i])
    end
    local track_sig = table.concat(track_parts, ",")

    local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local ts_sig = string.format("%.6f|%.6f", ts_start, ts_end)

    local loop_start, loop_end = RPR.GetSet_LoopTimeRange(false, true, 0, 0, false)
    local loop_sig = string.format("%.6f|%.6f", loop_start, loop_end)

    local sel_r, sel_m = M.GetSelectedRegionMarkers()
    local rm_parts = { tostring(#sel_r), tostring(#sel_m) }
    for _, r in ipairs(sel_r) do rm_parts[#rm_parts + 1] = "R" .. tostring(r.index) end
    for _, m in ipairs(sel_m) do rm_parts[#rm_parts + 1] = "M" .. tostring(m.index) end
    local rm_sig = table.concat(rm_parts, ",")

    return items, tracks, sel_r, sel_m,
           ts_start, ts_end, loop_start, loop_end,
           item_sig, track_sig, ts_sig, loop_sig, rm_sig
end

function M.Update(is_imgui_focused)
    -- 다른 스크립트에서 변경한 감지 설정 실시간 동기화
    local ext_ts = LoadIntSetting("ts_detect_mode", settings.ts_detect_mode)
    if ext_ts ~= settings.ts_detect_mode then
        settings.ts_detect_mode = ext_ts
        settings.ts_auto_targets_regions = (ext_ts == M.RANGE_REGIONS)
    end
    local ext_lp = LoadIntSetting("loop_detect_mode", settings.loop_detect_mode)
    if ext_lp ~= settings.loop_detect_mode then
        settings.loop_detect_mode = ext_lp
        settings.include_loop_points = (ext_lp ~= M.RANGE_IGNORE)
    end
    local ext_arr = LoadBoolSetting("arrange_selects_track", settings.arrange_selects_track)
    if ext_arr ~= settings.arrange_selects_track then
        settings.arrange_selects_track = ext_arr
    end

    prev_mouse_down = is_mouse_down
    is_mouse_down = CheckLeftMouseDown()
    mouse_released = prev_mouse_down and not is_mouse_down
    local mouse_just_pressed = is_mouse_down and not prev_mouse_down

    local items, tracks, sel_r, sel_m,
          ts_start, ts_end, loop_start, loop_end,
          item_sig, track_sig, ts_sig, loop_sig, rm_sig = BuildSignatures()
      local track_count = RPR.CountTracks(0)

    -- 스크립트 최초 실행 시(예: Renamer / ColorPalette 스탠드얼론 오픈 시) 이전 컨텍스트 복원
    if not initialized then
        initialized = true
        prev_item_sig, prev_track_sig, prev_ts_sig, prev_loop_sig, prev_rm_sig =
            item_sig, track_sig, ts_sig, loop_sig, rm_sig
        prev_track_count = track_count

        if not RestoreSharedContext() then
            if #items > 0 then
                current_mode = "Item"
                mode_focus_active = true
                active_range_source = "Selection"
            elseif #tracks > 0 then
                current_mode = "Track"
                mode_focus_active = true
                active_range_source = "Selection"
            elseif #sel_r > 0 or #sel_m > 0 then
                current_mode = "Region/Marker"
                mode_focus_active = true
                active_range_source = "Selection"
            elseif settings.ts_detect_mode == M.RANGE_REGIONS and ts_end > ts_start then
                local tr, tm = M.GetTimeSelectionRegionMarkers()
                if (#tr + #tm) > 0 then
                    current_mode = "Region/Marker"
                    mode_focus_active = true
                    active_range_source = "TimeSelection"
                end
            elseif settings.loop_detect_mode == M.RANGE_REGIONS and loop_end > loop_start then
                local lr, lm = M.GetLoopRegionMarkers()
                if (#lr + #lm) > 0 then
                    current_mode = "Region/Marker"
                    mode_focus_active = true
                    active_range_source = "LoopPoints"
                end
            end
        end

        PublishSharedContext()
        return current_mode, mode_focus_active
    end

    local items_changed  = (item_sig ~= prev_item_sig)
    local tracks_changed = (track_sig ~= prev_track_sig)
    local track_added    = (track_count > prev_track_count)
    local ts_changed     = (ts_sig ~= prev_ts_sig)
    local loop_changed   = (loop_sig ~= prev_loop_sig)
    local rm_changed     = (rm_sig ~= prev_rm_sig)

    local prev_mode_snapshot   = current_mode
    local prev_active_snapshot = mode_focus_active
    local prev_source_snapshot = active_range_source

    -- ImGui 창 내부 조작 중에는 기존 선택 모드를 유지하되,
    -- 외부(ReaTools 등)에서 공유 컨텍스트가 갱신되었다면 반영한다.
    if is_imgui_focused then
        prev_item_sig, prev_track_sig, prev_ts_sig, prev_loop_sig, prev_rm_sig =
            item_sig, track_sig, ts_sig, loop_sig, rm_sig
        prev_track_count = track_count
        if mouse_released then
            ResetArrangeInteraction()
        end
        return current_mode, mode_focus_active
    end

    local area = GetMouseContextArea()

    if mouse_just_pressed then
        BeginMouseInteraction(area)
    end

    UpdateArrangeDrag()

    if arrange_drag_active and ((ts_changed and ts_end > ts_start) or (loop_changed and loop_end > loop_start)) then
        arrange_drag_is_range_selection = true
    end

    local item_interaction_detected = item_interaction_active
        or (arrange_drag_active and not arrange_drag_is_range_selection)

    -- 1. 직접적인 Region/Marker 선택 변경
    if rm_changed and (#sel_r > 0 or #sel_m > 0) then
        current_mode = "Region/Marker"
        mode_focus_active = true
        active_range_source = "Selection"

    -- 2. Time Selection 변경 처리
    elseif ts_changed and settings.ts_detect_mode ~= M.RANGE_IGNORE then
        if ts_end > ts_start then
            if settings.ts_detect_mode == M.RANGE_REGIONS then
                current_mode = "Region/Marker"
                mode_focus_active = true
                active_range_source = "TimeSelection"
            elseif settings.ts_detect_mode == M.RANGE_ITEMS then
                local cnt = SelectItemsInBounds(ts_start, ts_end)
                items = M.GetSelectedItems()
                item_sig = table.concat({ tostring(#items) }, ",")
                if cnt > 0 then
                    current_mode = "Item"
                    mode_focus_active = true
                    active_range_source = "TimeSelection"
                else
                    mode_focus_active = false
                    active_range_source = "None"
                end
            end
        elseif active_range_source == "TimeSelection" then
            mode_focus_active = false
            active_range_source = "None"
        end

    -- 3. Loop Points 변경 처리
    elseif loop_changed and settings.loop_detect_mode ~= M.RANGE_IGNORE then
        if loop_end > loop_start then
            if settings.loop_detect_mode == M.RANGE_REGIONS then
                current_mode = "Region/Marker"
                mode_focus_active = true
                active_range_source = "LoopPoints"
            elseif settings.loop_detect_mode == M.RANGE_ITEMS then
                local cnt = SelectItemsInBounds(loop_start, loop_end)
                items = M.GetSelectedItems()
                item_sig = table.concat({ tostring(#items) }, ",")
                if cnt > 0 then
                    current_mode = "Item"
                    mode_focus_active = true
                    active_range_source = "LoopPoints"
                else
                    mode_focus_active = false
                    active_range_source = "None"
                end
            end
        elseif active_range_source == "LoopPoints" then
            mode_focus_active = false
            active_range_source = "None"
        end

    -- 4. Item 직접 조작 감지
    elseif item_interaction_detected and #items > 0 then
        current_mode = "Item"
        mode_focus_active = true
        active_range_source = "Selection"

    -- 5. Item 선택 목록 변경 (아이템이 1개 이상 선택된 경우에만)
    elseif items_changed and #items > 0 then
        current_mode = "Item"
        mode_focus_active = true
        active_range_source = "Selection"

    -- 6. Track 선택 변경 (새 트랙 생성 포함)
    elseif (tracks_changed or track_added) and #tracks > 0 then
        local clicked_in_tcp = (is_mouse_down or mouse_released)
            and (area == "tcp" or mouse_press_area == "tcp")
        if track_added or clicked_in_tcp or settings.arrange_selects_track then
            current_mode = "Track"
            mode_focus_active = true
            active_range_source = "Selection"
        elseif not settings.arrange_selects_track then
            mode_focus_active = false
            active_range_source = "None"
        end

    -- 7. 선택 변경 없이 기존 대상을 다시 클릭한 경우 포커스 복구
    elseif mouse_just_pressed then
        if area == "ruler" then
            local ts_r, ts_m = M.GetTimeSelectionRegionMarkers()
            local lp_r, lp_m = M.GetLoopRegionMarkers()
            if #sel_r > 0 or #sel_m > 0 then
                current_mode = "Region/Marker"
                mode_focus_active = true
                active_range_source = "Selection"
            elseif settings.ts_detect_mode == M.RANGE_REGIONS and (#ts_r > 0 or #ts_m > 0 or ts_end > ts_start) then
                current_mode = "Region/Marker"
                mode_focus_active = true
                active_range_source = "TimeSelection"
            elseif settings.loop_detect_mode == M.RANGE_REGIONS and (#lp_r > 0 or #lp_m > 0 or loop_end > loop_start) then
                current_mode = "Region/Marker"
                mode_focus_active = true
                active_range_source = "LoopPoints"
            end
        elseif area == "tcp" and #tracks > 0 then
            current_mode = "Track"
            mode_focus_active = true
            active_range_source = "Selection"
        elseif area == "arrange" then
            if #items == 0 then
                if settings.arrange_selects_track and #tracks > 0 then
                    current_mode = "Track"
                    mode_focus_active = true
                    active_range_source = "Selection"
                elseif current_mode == "Item" or (current_mode == "Track" and not settings.arrange_selects_track) then
                    mode_focus_active = false
                    active_range_source = "None"
                end
            end
        end
    end

    -- 8. 현재 모드의 실제 대상이 모두 사라졌는지 검증
    if current_mode == "Item" and #items == 0 then
        if not item_interaction_detected then
            mode_focus_active = false
            active_range_source = "None"
        end
    elseif current_mode == "Track" and #tracks == 0 then
        mode_focus_active = false
        active_range_source = "None"
    elseif current_mode == "Region/Marker" then
        local ts_r, ts_m = M.GetTimeSelectionRegionMarkers()
        local lp_r, lp_m = M.GetLoopRegionMarkers()
        local has_rm = (#sel_r > 0 or #sel_m > 0)
        local has_ts = (ts_end > ts_start) and (settings.ts_detect_mode == M.RANGE_REGIONS) and (#ts_r > 0 or #ts_m > 0 or active_range_source == "TimeSelection")
        local has_lp = (loop_end > loop_start) and (settings.loop_detect_mode == M.RANGE_REGIONS) and (#lp_r > 0 or #lp_m > 0 or active_range_source == "LoopPoints")
        if not has_rm and not has_ts and not has_lp then
            mode_focus_active = false
            active_range_source = "None"
        end
    end

    prev_item_sig, prev_track_sig, prev_ts_sig, prev_loop_sig, prev_rm_sig =
        item_sig, track_sig, ts_sig, loop_sig, rm_sig
    prev_track_count = track_count

    if mouse_released then
        ResetArrangeInteraction()
    end

    -- 상태가 변했으면 공유 메모리에 기록, 변하지 않았다면 다른 창이 갱신한 최신 공유 상태 확인
    if current_mode ~= prev_mode_snapshot
        or mode_focus_active ~= prev_active_snapshot
        or active_range_source ~= prev_source_snapshot then
        PublishSharedContext()
    else
        local ext_mode = RPR.GetExtState(STATE_SECTION, "mode")
        local ext_active = RPR.GetExtState(STATE_SECTION, "active") == "1"
        if ext_mode ~= "" and ext_mode ~= current_mode then
            RestoreSharedContext()
        elseif ext_mode == current_mode and ext_active ~= mode_focus_active then
            RestoreSharedContext()
        end
    end

    return current_mode, mode_focus_active
end

function M.GetMode()
    return current_mode, mode_focus_active
end

function M.IsMouseDown()
    return is_mouse_down
end

function M.WasMouseReleased()
    return mouse_released
end

_G.JKK_SelectionManager = M
return M