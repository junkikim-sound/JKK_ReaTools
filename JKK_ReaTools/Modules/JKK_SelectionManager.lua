--========================================================
-- @title JKK_SelectionManager
-- @author Junki Kim
-- @version 1.2.0
-- @noindex
--========================================================

local RPR = reaper
local M = {}

---------------------------------------------------------
-- User Configurable Detection Settings (ExtState)
---------------------------------------------------------
local EXT_SECTION = "JKK_SelectionManager"

local SETTINGS_DEFAULTS = {
    arrange_selects_track   = false, -- 어레인지 뷰 클릭 시에도 Track 모드로 전환할지 여부
    include_loop_points     = true,  -- Time Selection 외에 Loop Points도 타임 영역으로 인식
    ts_auto_targets_regions = true,  -- Time Selection 드래그 시 범위 내 리전/마커 자동 타겟
}

local function LoadBoolSetting(key, default)
    local val = RPR.GetExtState(EXT_SECTION, key)
    if val == "" then return default end
    return val == "1"
end

local settings = {
    arrange_selects_track   = LoadBoolSetting("arrange_selects_track", SETTINGS_DEFAULTS.arrange_selects_track),
    include_loop_points     = LoadBoolSetting("include_loop_points", SETTINGS_DEFAULTS.include_loop_points),
    ts_auto_targets_regions = LoadBoolSetting("ts_auto_targets_regions", SETTINGS_DEFAULTS.ts_auto_targets_regions),
}

function M.GetSettings()
    return settings
end

function M.SetSetting(key, value)
    if settings[key] == nil then return end
    settings[key] = value and true or false
    RPR.SetExtState(EXT_SECTION, key, settings[key] and "1" or "0", true)
end

function M.ResetSettings()
    for k, v in pairs(SETTINGS_DEFAULTS) do
        M.SetSetting(k, v)
    end
end

---------------------------------------------------------
-- Internal State
---------------------------------------------------------
local current_mode = "None" -- "Item" | "Track" | "Region/Marker" | "None"
local mode_focus_active = false
local is_mouse_down = false
local prev_mouse_down = false
local mouse_released = false

-- Arrange interaction tracking:
-- Capture the item under the mouse on mouse-down and keep that interaction
-- alive until mouse-up. This allows already-selected items to reactivate Item mode.
local mouse_press_item = nil
local mouse_press_area = "unknown"
local mouse_press_x, mouse_press_y = nil, nil
local item_interaction_active = false
local arrange_drag_pending = false
local arrange_drag_active = false
local arrange_drag_is_time_selection = false
local ARRANGE_DRAG_THRESHOLD = 4

local prev_item_sig = ""
local prev_track_sig = ""
local prev_ts_sig = ""
local prev_rm_sig = ""

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
        -- arrange 내부의 item/envelope이 아닌 순수 TCP/MCP 영역 판별
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

-- Returns the media item directly under the mouse cursor, if any.
-- GetThingFromPoint identifies the REAPER UI area; GetItemFromPoint identifies
-- the actual media item. Locked items are ignored because they cannot be selected.
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
    arrange_drag_is_time_selection = false
end

-- Capture the start of an Arrange interaction. A click on an item is an
-- Item interaction even when the item's selection state does not change.
local function BeginMouseInteraction(area)
    mouse_press_area = area
    mouse_press_item = nil
    mouse_press_x, mouse_press_y = nil, nil
    item_interaction_active = false
    arrange_drag_pending = false
    arrange_drag_active = false
    arrange_drag_is_time_selection = false

    if area ~= "arrange" then return end

    if RPR.GetMousePosition then
        mouse_press_x, mouse_press_y = RPR.GetMousePosition()
    end

    mouse_press_item = GetItemAtMousePosition()
    if mouse_press_item then
        item_interaction_active = true
    else
        -- A drag beginning on empty Arrange space may be a marquee selection.
        arrange_drag_pending = true
    end
end

-- Detect a marquee drag that starts on empty Arrange space. A small movement
-- threshold avoids treating an ordinary empty-space click as a drag selection.
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
-- Time Selection / Loop Points Helper
---------------------------------------------------------
local function GetActiveTimeRange()
    local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_end > ts_start then
        return ts_start, ts_end
    end
    if settings.include_loop_points then
        local lp_start, lp_end = RPR.GetSet_LoopTimeRange(false, true, 0, 0, false)
        if lp_end > lp_start then
            return lp_start, lp_end
        end
    end
    return 0, 0
end

---------------------------------------------------------
-- Selection Queries
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

    -- REAPER v7+ 네이티브 리전/마커 다중 선택 API 지원 시 우선 사용
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

function M.GetTimeSelectionRegionMarkers()
    local regions, markers = {}, {}
    local ts_start, ts_end = GetActiveTimeRange()
    if ts_end <= ts_start then return regions, markers end

    local _, num_markers, num_regions = RPR.CountProjectMarkers(0)
    local total = num_markers + num_regions

    for i = 0, total - 1 do
        local retval, is_region, pos, rgnend, name, markrgnindexnumber, color = RPR.EnumProjectMarkers3(0, i)
        if retval then
            local pm = RPR.GetProjectMarkerByIndex and RPR.GetProjectMarkerByIndex(0, i) or nil
            local hit = false
            if is_region then
                hit = (rgnend > ts_start and pos < ts_end)
            else
                hit = (pos >= ts_start and pos <= ts_end)
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
        if #sel_r == 0 and #sel_m == 0 and settings.ts_auto_targets_regions then
            sel_r, sel_m = M.GetTimeSelectionRegionMarkers()
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

    local ts_start, ts_end = GetActiveTimeRange()
    local ts_sig = string.format("%.6f|%.6f", ts_start, ts_end)

    local sel_r, sel_m = M.GetSelectedRegionMarkers()
    local rm_parts = { tostring(#sel_r), tostring(#sel_m) }
    for _, r in ipairs(sel_r) do rm_parts[#rm_parts + 1] = "R" .. tostring(r.index) end
    for _, m in ipairs(sel_m) do rm_parts[#rm_parts + 1] = "M" .. tostring(m.index) end
    local rm_sig = table.concat(rm_parts, ",")

    return items, tracks, sel_r, sel_m, ts_start, ts_end, item_sig, track_sig, ts_sig, rm_sig
end

function M.Update(is_imgui_focused)
    prev_mouse_down = is_mouse_down
    is_mouse_down = CheckLeftMouseDown()
    mouse_released = prev_mouse_down and not is_mouse_down
    local mouse_just_pressed = is_mouse_down and not prev_mouse_down

    local items, tracks, sel_r, sel_m, ts_start, ts_end,
          item_sig, track_sig, ts_sig, rm_sig = BuildSignatures()

    local items_changed = (item_sig ~= prev_item_sig)
    local tracks_changed = (track_sig ~= prev_track_sig)
    local ts_changed = (ts_sig ~= prev_ts_sig)
    local rm_changed = (rm_sig ~= prev_rm_sig)

    -- ImGui 창 내부 조작 중에는 기존 선택 모드를 유지하고,
    -- 내부에서 발생한 선택 변경은 다음 프레임에 새 입력으로 오인하지 않도록 동기화.
    if is_imgui_focused then
        prev_item_sig, prev_track_sig, prev_ts_sig, prev_rm_sig = item_sig, track_sig, ts_sig, rm_sig
        if mouse_released then
            ResetArrangeInteraction()
        end
        return current_mode, mode_focus_active
    end

    local area = GetMouseContextArea()

    -- 마우스 누름 시작 시점의 Arrange 대상을 캡처한다.
    if mouse_just_pressed then
        BeginMouseInteraction(area)
    end

    -- 빈 Arrange 영역에서 시작한 드래그가 Marquee Selection인지 감지한다.
    UpdateArrangeDrag()

    -- Arrange 드래그 중 Time Selection이 실제로 변했다면 Marquee가 아닌
    -- Time Selection 조작으로 기억하여 Item 모드로 오인하지 않는다.
    if arrange_drag_active and ts_changed and ts_end > ts_start then
        arrange_drag_is_time_selection = true
    end

    local item_interaction_detected = item_interaction_active
        or (arrange_drag_active and not arrange_drag_is_time_selection)

    -- 1. 직접적인 Region/Marker 선택 변경
    if rm_changed and (#sel_r > 0 or #sel_m > 0) then
        current_mode = "Region/Marker"
        mode_focus_active = true

    -- 2. Time Selection / Loop Points 변경 시 (룰러 또는 옵션 허용 시 Arrange)
    elseif ts_changed and ts_end > ts_start
        and (area == "ruler" or mouse_press_area == "ruler" or settings.ts_auto_targets_regions) then
        current_mode = "Region/Marker"
        mode_focus_active = true

    -- 3. Item 직접 조작 감지
    -- 선택 목록이 바뀌지 않은 기존 선택 Item의 클릭/드래그도 Item 모드로 전환한다.
    elseif item_interaction_detected and #items > 0 then
        current_mode = "Item"
        mode_focus_active = true

    -- 4. Item 선택 목록 변경
    elseif items_changed and #items > 0 then
        current_mode = "Item"
        mode_focus_active = true

    -- 5. Track 선택 변경 (TCP/MCP 클릭이거나, 유저 옵션에서 Arrange 클릭 허용 시)
    elseif tracks_changed and #tracks > 0
        and (area == "tcp" or mouse_press_area == "tcp" or settings.arrange_selects_track) then
        current_mode = "Track"
        mode_focus_active = true

    -- 6. 선택 변경 없이 기존 대상을 다시 클릭한 경우 포커스 복구
    elseif mouse_just_pressed then
        if area == "ruler" then
            local ts_r, ts_m = M.GetTimeSelectionRegionMarkers()
            if #sel_r > 0 or #sel_m > 0 or (settings.ts_auto_targets_regions and (#ts_r > 0 or #ts_m > 0)) or ts_end > ts_start then
                current_mode = "Region/Marker"
                mode_focus_active = true
            end
        elseif area == "tcp" and #tracks > 0 then
            current_mode = "Track"
            mode_focus_active = true
        elseif area == "arrange" then
            if #items == 0 then
                if settings.arrange_selects_track and #tracks > 0 then
                    current_mode = "Track"
                    mode_focus_active = true
                elseif current_mode == "Item" then
                    current_mode = "None"
                    mode_focus_active = false
                end
            end
        end
    end

    -- 현재 모드의 실제 대상이 모두 사라졌는지 검증.
    -- Item을 누르고 있는 중에는 REAPER가 선택 상태를 갱신하기 전일 수 있으므로
    -- 해당 마우스 조작이 끝날 때까지 일시적으로 None 처리하지 않는다.
    if current_mode == "Item" and #items == 0 then
        if not item_interaction_detected then
            current_mode = "None"
            mode_focus_active = false
        end
    elseif current_mode == "Track" and #tracks == 0 then
        current_mode = "None"
        mode_focus_active = false
    elseif current_mode == "Region/Marker" then
        local ts_r, ts_m = M.GetTimeSelectionRegionMarkers()
        local has_rm = (#sel_r > 0 or #sel_m > 0)
        local has_ts = (ts_end > ts_start) and (settings.ts_auto_targets_regions or #ts_r > 0 or #ts_m > 0)
        if not has_rm and not has_ts then
            current_mode = "None"
            mode_focus_active = false
        end
    end

    prev_item_sig, prev_track_sig, prev_ts_sig, prev_rm_sig = item_sig, track_sig, ts_sig, rm_sig

    -- Release 프레임까지는 이번 조작을 Item interaction으로 처리한 뒤 상태를 초기화한다.
    if mouse_released then
        ResetArrangeInteraction()
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