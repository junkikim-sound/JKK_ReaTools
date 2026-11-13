--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.9.92
-- @provides
--     [nomain] Modules/JKK_ReaTools_NEW_ItemTool.lua
--     [nomain] Modules/JKK_ReaTools_NEW_TrackTool.lua
--     [nomain] Modules/JKK_ReaTools_NEW_RenamerLite.lua
--     [nomain] Modules/JKK_ReaTools_NEW_ColorPaletteLite.lua
--     [nomain] Modules/JKK_SelectionManager.lua
--========================================================

local RPR = reaper
local ctx = RPR.ImGui_CreateContext("JKK_ReaTools")

---------------------------------------------------------
-- USER CONFIG: PANEL WIDTHS
---------------------------------------------------------
local PANEL_DEFAULT_WIDTHS = {
    A = 220, -- Project Memo
    B = 450, -- Controller
    C = 550, -- Rename / Take
    D = 550, -- Item Tools (items only)
    E = 500  -- Color
}

local PANEL_MIN_WIDTHS = {
    A = 160, -- Project Memo
    B = 280, -- Controller
    C = 428, -- Rename / Take
    D = 325, -- Item Tools
    E = 450  -- Color
}

local SPLITTER_WIDTH = 9
local WINDOW_MIN_WIDTH = 200
local WINDOW_MIN_HEIGHT = 150

---------------------------------------------------------
-- USER CONFIG: UI ZOOM
---------------------------------------------------------
local DESIGN_WINDOW_WIDTH = 1900
local DESIGN_WINDOW_HEIGHT = 440
local DESIGN_CONTENT_HEIGHT = 260
local BASE_FONT_SIZE = 13
local UI_SCALE_MIN = 0.2
local UI_SCALE_MAX = 2.0
local UI_SCALE_AUTO_MIN = 0.2

local UI_ZOOM_DEFAULTS = {
    auto = true,
    follow_height = true,
    size = 1.0
}

local zoom_state_section = "JKK_ReaTools_Zoom"
local function LoadZoomSetting(key, default)
    local value = RPR.GetExtState(zoom_state_section, key)
    if value == "" then return default end
    if type(default) == "boolean" then return value == "1" end
    return tonumber(value) or default
end

local ui_zoom = {
    auto = LoadZoomSetting("auto", UI_ZOOM_DEFAULTS.auto),
    follow_height = LoadZoomSetting("fit_height", UI_ZOOM_DEFAULTS.follow_height),
    size = LoadZoomSetting("size", UI_ZOOM_DEFAULTS.size)
}

local function SaveZoomSettings()
    RPR.SetExtState(zoom_state_section, "auto", ui_zoom.auto and "1" or "0", true)
    RPR.SetExtState(zoom_state_section, "fit_height", ui_zoom.follow_height and "1" or "0", true)
    RPR.SetExtState(zoom_state_section, "size", string.format("%.2f", ui_zoom.size), true)
end

JKK_UI_SCALE = 1.0
local ui_font_size = BASE_FONT_SIZE
local function S(value) return value * JKK_UI_SCALE end

local function UpdateUIScale(window_width, window_height, needed_width)
    if not window_width or not window_height
        or window_width <= 0 or window_height <= 0 then return end

    local auto_factor = 1.0
    if ui_zoom.auto then
        auto_factor = window_width / math.max(1, needed_width or DESIGN_WINDOW_WIDTH)
        if ui_zoom.follow_height then
            auto_factor = math.min(auto_factor, window_height / DESIGN_CONTENT_HEIGHT)
        end
        auto_factor = math.max(UI_SCALE_AUTO_MIN, auto_factor)
    end

    local raw = auto_factor * ui_zoom.size
    raw = math.max(UI_SCALE_MIN, math.min(UI_SCALE_MAX, raw))

    ui_font_size = math.max(6, math.floor(BASE_FONT_SIZE * raw * 2 + 0.5) / 2)
    JKK_UI_SCALE = ui_font_size / BASE_FONT_SIZE
end

---------------------------------------------------------
-- Shared Bottom Block Helper
---------------------------------------------------------
local lower_block_heights = {}

function JKK_DrawLowerBlock(draw_ctx, id, draw_fn)
    local _, gap = RPR.ImGui_GetStyleVar(draw_ctx, RPR.ImGui_StyleVar_ItemSpacing())
    gap = gap or S(6)
    local line_gap = math.ceil(gap)
    local start_y = math.ceil(RPR.ImGui_GetCursorPosY(draw_ctx))
    local _, avail_h = RPR.ImGui_GetContentRegionAvail(draw_ctx)
    local bottom_y = math.floor(RPR.ImGui_GetCursorPosY(draw_ctx) + avail_h)

    local own_h = lower_block_heights[id] or 0

    local sep_y = math.max(start_y, bottom_y - own_h - line_gap - 1)
    RPR.ImGui_SetCursorPosY(draw_ctx, sep_y)
    RPR.ImGui_Separator(draw_ctx)

    local block_y = math.max(sep_y + 1 + line_gap, bottom_y - own_h)
    RPR.ImGui_SetCursorPosY(draw_ctx, block_y)
    local result = draw_fn()

    local measured = RPR.ImGui_GetCursorPosY(draw_ctx) - gap - block_y
    lower_block_heights[id] = math.max(0, math.ceil(measured - 0.05))
    return result
end

---------------------------------------------------------
-- Module Loading
---------------------------------------------------------
local open = true
local prev_project_state_count = RPR.GetProjectStateChangeCount(0)
local current_project_state_count = prev_project_state_count

local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local installed_dir = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/"

local function ResolveModulePath(file_name)
    local local_path = script_dir .. "Modules/" .. file_name
    if script_dir ~= "" and RPR.file_exists(local_path) then return local_path end
    return installed_dir .. "Modules/" .. file_name
end

local theme_path = ResolveModulePath("JKK_Theme_Core.lua")
local Theme = (RPR.file_exists(theme_path) and dofile(theme_path)) or {
    ApplyTheme       = function() return 0, 0 end,
    PushButton       = function() end,
    PopButton        = function() end,
    PushText         = function() end,
    PopText          = function() end,
    PushFont         = function() end,
    PopFont          = function() end,
    GetColor         = function() return 0xEDEDEDFF end,
    GetSplitterColor = function() return 0x3C3C3CFF end,
    OpenEditor       = function() end,
}
local ApplyTheme = Theme.ApplyTheme

local function load_module(file_name)
    local full_path = ResolveModulePath(file_name)
    if not RPR.file_exists(full_path) then
        RPR.MB("Error: Module file not found at " .. full_path, "Module Load Error: File Not Found", 0)
        return nil
    end

    local status, result = pcall(dofile, full_path)
    if not status then
        RPR.MB(
            "Error executing module:\n" .. file_name .. "\n\nError Message:\n" .. tostring(result),
            "Module Execution Error",
            0
        )
        return nil
    end
    return result
end

-- SelectionManager를 가장 먼저 로드하여 하위 모듈들이 _G.JKK_SelectionManager를 공유하도록 보장
local sel_mgr              = load_module("JKK_SelectionManager.lua")
local item_module          = load_module("JKK_ReaTools_NEW_ItemTool.lua")
local track_module         = load_module("JKK_ReaTools_NEW_TrackTool.lua")
local renamer_lite_module  = load_module("JKK_ReaTools_NEW_RenamerLite.lua")
local color_palette_module = load_module("JKK_ReaTools_NEW_ColorPaletteLite.lua")

---------------------------------------------------------
-- Project Memo
---------------------------------------------------------
local project_note = ""
local last_project_ptr = nil

local function LoadProjectNote()
    local retval, saved_note = RPR.GetProjExtState(0, "JKK_ReaTools_Note", "project_note")
    if retval <= 0 then
        retval, saved_note = RPR.GetProjExtState(0, "JKK_ReaTools_Note", "Project_note")
    end
    project_note = (retval > 0) and saved_note or ""
end

LoadProjectNote()

---------------------------------------------------------
-- Selection Context (Powered by JKK_SelectionManager)
---------------------------------------------------------
local current_mode = "None"
local mode_focus_active = false
local focus_mouse_down = false
local focus_mouse_released = false
local latest_selection_signature = nil

local function IsCurrentModeActive()
    if not sel_mgr then return false end
    local _, active = sel_mgr.GetMode()
    return mode_focus_active and active
end

local function UpdateFocusMode(is_window_focused)
    if not sel_mgr then
        current_mode = "None"
        mode_focus_active = false
        return current_mode
    end

    local prev_down = focus_mouse_down
    current_mode, mode_focus_active = sel_mgr.Update(is_window_focused)
    focus_mouse_down = sel_mgr.IsMouseDown()
    focus_mouse_released = prev_down and not focus_mouse_down

    local items = sel_mgr.GetSelectedItems()
    local tracks = sel_mgr.GetSelectedTracks()
    local regions, markers = sel_mgr.GetSelectedRegionMarkers()
    local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local top_only_flag = RPR.GetExtState("JKK_Renamer_Shared", "top_level_only")
    if top_only_flag == "" then
        top_only_flag = RPR.GetExtState("JKK_SmartBatchRenamer", "top_level_only")
    end

    latest_selection_signature = table.concat({
        current_mode,
        tostring(mode_focus_active),
        tostring(#items), tostring(items[1]),
        tostring(#tracks), tostring(tracks[1]),
        tostring(#regions), tostring(#markers),
        tostring(ts_start), tostring(ts_end),
        tostring(top_only_flag)
    }, "|")

    return current_mode
end

---------------------------------------------------------
-- Top-Level Rename Count Helper
---------------------------------------------------------
local function CountTopLevelTargets(mode, list)
    if not list or #list == 0 then return 0 end

    -- RenamerLite가 최신 계산 결과를 노출하고 있으면 우선 사용
    if renamer_lite_module and type(renamer_lite_module.status_info) == "table" then
        local info = renamer_lite_module.status_info
        if info.mode == mode and info.total_count == #list then
            return info.top_level_only, info.rename_count
        end
    end

    -- 폴백: 직접 최상위(Top-Level) 개수 계산
    local top_only = (RPR.GetExtState("JKK_Renamer_Shared", "top_level_only") == "1")
        or (RPR.GetExtState("JKK_SmartBatchRenamer", "top_level_only") == "1")
    if not top_only then
        return false, #list
    end

    local selected_tracks = {}
    local item_tracks = {}
    for i, ptr in ipairs(list) do
        local tr = (mode == "Item") and RPR.GetMediaItem_Track(ptr) or ptr
        item_tracks[i] = tr
        if tr then selected_tracks[tr] = true end
    end

    local top_count = 0
    for i = 1, #list do
        local parent = item_tracks[i] and RPR.GetParentTrack(item_tracks[i])
        local has_selected_parent = false
        while parent do
            if selected_tracks[parent] then
                has_selected_parent = true
                break
            end
            parent = RPR.GetParentTrack(parent)
        end
        if not has_selected_parent then
            top_count = top_count + 1
        end
    end

    return true, top_count
end

---------------------------------------------------------
-- Selection Status Formatting & Display
---------------------------------------------------------
local function GetTargetTypeStr(target_type, pointer)
    if target_type == "Item" then
        local track = RPR.GetMediaItem_Track(pointer)
        if track and RPR.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
            return "Folder Item"
        end
        local take = RPR.GetActiveTake(pointer)
        if take then
            if RPR.TakeIsMIDI(take) then return "MIDI Item" end
            return "Audio Item"
        end
        return "Item"
    elseif target_type == "Track" then
        local depth = RPR.GetMediaTrackInfo_Value(pointer, "I_FOLDERDEPTH")
        local parent = RPR.GetParentTrack(pointer)
        if depth == 1 then return "Folder Track" end
        if parent then return "Child Track" end
        return "Track"
    end
    return target_type or "Unknown"
end

local function GetFirstItemName(item)
    if not item then return "Unnamed Item" end
    local take = RPR.GetActiveTake(item)
    if take then
        local retval, name = RPR.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        if retval and name and name ~= "" then return name end
        if RPR.GetTakeName then
            name = RPR.GetTakeName(take)
            if name and name ~= "" then return name end
        end
    end
    return "Unnamed Item"
end

local function GetFirstTrackName(track)
    if not track then return "Unnamed Track" end
    local _, name = RPR.GetTrackName(track)
    if name and name ~= "" then return name end
    return "Unnamed Track"
end

local STATUS_NAMES_MAX_BYTES = 2000

local function GetTargetNamesStr(mode)
    if not sel_mgr then return "" end
    local names, total_bytes, truncated = {}, 0, false
    local list = (mode == "Item") and sel_mgr.GetSelectedItems() or sel_mgr.GetSelectedTracks()
    local get_name = (mode == "Item") and GetFirstItemName or GetFirstTrackName

    for i, ptr in ipairs(list) do
        local name = get_name(ptr)
        names[#names + 1] = name
        total_bytes = total_bytes + #name + 2
        if total_bytes > STATUS_NAMES_MAX_BYTES and i < #list then
            truncated = true
            break
        end
    end
    local text = table.concat(names, ", ")
    if truncated then text = text .. ", ..." end
    return text
end

local function CaptureSelectionStatus()
    if not sel_mgr or not IsCurrentModeActive() then
        return "No Selection"
    end

    if current_mode == "Item" then
        local items = sel_mgr.GetSelectedItems()
        if #items > 0 then
            local item_type = GetTargetTypeStr("Item", items[1])
            local names_str = GetTargetNamesStr("Item")
            local top_only, rename_count = CountTopLevelTargets("Item", items)
            local rename_tag = (top_only and rename_count ~= #items)
                and string.format(" [Rename: %02d]", rename_count)
                or ""
            return string.format("Selected %02d Items%s (%s: ", #items, rename_tag, item_type), names_str, ")"
        end
    elseif current_mode == "Track" then
        local tracks = sel_mgr.GetSelectedTracks()
        if #tracks > 0 then
            local track_type = GetTargetTypeStr("Track", tracks[1])
            local names_str = GetTargetNamesStr("Track")
            local top_only, rename_count = CountTopLevelTargets("Track", tracks)
            local rename_tag = (top_only and rename_count ~= #tracks)
                and string.format(" [Rename: %02d]", rename_count)
                or ""
            return string.format("Selected %02d Tracks%s (%s: ", #tracks, rename_tag, track_type), names_str, ")"
        end
    elseif current_mode == "Region/Marker" then
        local regions, markers = sel_mgr.GetSelectedRegionMarkers()
        if #regions == 0 and #markers == 0 and sel_mgr.GetTimeSelectionRegionMarkers then
            regions, markers = sel_mgr.GetTimeSelectionRegionMarkers()
        end
        local total = #regions + #markers
        if total > 0 then
            local kind = (#regions > 0 and #markers > 0) and "Regions/Markers"
                or ((#regions > 0) and "Regions" or "Markers")
            local names = {}
            for _, r in ipairs(regions) do names[#names + 1] = (r.name ~= "" and r.name or "Unnamed") end
            for _, m in ipairs(markers) do names[#names + 1] = (m.name ~= "" and m.name or "Unnamed") end
            return string.format("Selected %02d %s (", total, kind), table.concat(names, ", "), ")"
        end
        local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if ts_end > ts_start then return "Timeline (Time Selection)" end
        return "Timeline"
    end

    return "No Selection"
end

local function FitTextToWidth(text, max_width)
    max_width = math.max(1, max_width or 1)
    local text_width = select(1, RPR.ImGui_CalcTextSize(ctx, text))
    if text_width <= max_width then return text end

    local ellipsis = "..."
    local ellipsis_width = select(1, RPR.ImGui_CalcTextSize(ctx, ellipsis))
    if ellipsis_width >= max_width then return ellipsis end

    local ok, char_count = pcall(utf8.len, text)
    if not ok or not char_count then
        local candidate = text
        while #candidate > 0 do
            candidate = candidate:sub(1, -2)
            if select(1, RPR.ImGui_CalcTextSize(ctx, candidate .. ellipsis)) <= max_width then
                return candidate .. ellipsis
            end
        end
        return ellipsis
    end

    local low, high, best = 0, char_count - 1, ellipsis
    while low <= high do
        local count = (low + high) // 2
        local byte_end = (count == 0) and 0 or (utf8.offset(text, count + 1) or (#text + 1)) - 1
        local candidate = text:sub(1, byte_end) .. ellipsis
        if select(1, RPR.ImGui_CalcTextSize(ctx, candidate)) <= max_width then
            best = candidate
            low = count + 1
        else
            high = count - 1
        end
    end
    return best
end

local selection_status_cache = nil
local committed_status_signature = nil
local pending_status_since = nil
local STATUS_RELEASE_FALLBACK_DELAY = 0.12

local function UpdateSelectionStatusCache()
    local live_prefix, live_name, live_suffix = CaptureSelectionStatus()
    local live_signature = table.concat({
        latest_selection_signature or "",
        live_prefix or "",
        live_name or "",
        live_suffix or ""
    }, "\30")

    local now = RPR.time_precise and RPR.time_precise() or os.clock()

    if selection_status_cache == nil then
        selection_status_cache = { live_prefix, live_name, live_suffix }
        committed_status_signature = live_signature
        pending_status_since = nil
        return
    end

    if live_signature ~= committed_status_signature and not pending_status_since then
        pending_status_since = now
    end

    if pending_status_since then
        local release_confirmed = focus_mouse_released
        local click_was_missed = not focus_mouse_down
            and (now - pending_status_since) >= STATUS_RELEASE_FALLBACK_DELAY

        if release_confirmed or click_was_missed then
            selection_status_cache = { live_prefix, live_name, live_suffix }
            committed_status_signature = live_signature
            pending_status_since = nil
        end
    end
end

local function BuildSelectionStatus()
    if selection_status_cache then
        return selection_status_cache[1], selection_status_cache[2], selection_status_cache[3]
    end
    return CaptureSelectionStatus()
end

local function DrawSelectionStatus()
    local prefix, selected_name, suffix = BuildSelectionStatus()
    local available_width = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
    local safe_width = math.max(1, available_width - S(200))

    Theme.PushText(ctx, "status")
    if selected_name == nil then
        RPR.ImGui_Text(ctx, FitTextToWidth(prefix, available_width))
    else
        local prefix_width = select(1, RPR.ImGui_CalcTextSize(ctx, prefix))
        local suffix_width = select(1, RPR.ImGui_CalcTextSize(ctx, suffix))
        local name_max_width = safe_width - prefix_width - suffix_width

        if name_max_width <= 1 then
            RPR.ImGui_Text(ctx, FitTextToWidth(prefix .. selected_name .. suffix, available_width))
        else
            selected_name = FitTextToWidth(selected_name, name_max_width)
            RPR.ImGui_Text(ctx, prefix)
            RPR.ImGui_SameLine(ctx, 0, 0)
            RPR.ImGui_Text(ctx, selected_name)
            RPR.ImGui_SameLine(ctx, 0, 0)
            RPR.ImGui_Text(ctx, suffix)
        end
    end
    Theme.PopText(ctx)
end

---------------------------------------------------------
-- Panels: Visibility, Order, Widths
---------------------------------------------------------
local panel_state_section = "JKK_ReaTools_Panels"
local panel_width_state_section = "JKK_ReaTools_PanelWidths"
local panel_ids = { "A", "B", "C", "D", "E" }

local panel_titles = {
    A = "Project Memo",
    B = "Controller",
    C = "Rename / Take",
    D = "Item Tools",
    E = "Color"
}

local PANEL_DEFAULT_VISIBLE = { A = true, B = true, C = true, D = true, E = true }

local function LoadPanelVisibility()
    local visible = {}
    for _, id in ipairs(panel_ids) do
        local saved = RPR.GetExtState(panel_state_section, "visible_" .. id)
        if saved == "" then
            visible[id] = PANEL_DEFAULT_VISIBLE[id]
        else
            visible[id] = saved == "1"
        end
    end
    return visible
end

local panel_visible = LoadPanelVisibility()

local function SavePanelVisibility()
    for _, id in ipairs(panel_ids) do
        RPR.SetExtState(panel_state_section, "visible_" .. id, panel_visible[id] and "1" or "0", true)
    end
end

local function LoadPanelBaseWidths()
    local base = {}
    for _, id in ipairs(panel_ids) do
        local value = tonumber(RPR.GetExtState(panel_width_state_section, "px_" .. id))
        base[id] = (value and value > 0) and value or PANEL_DEFAULT_WIDTHS[id]
    end
    return base
end

local panel_base_widths = LoadPanelBaseWidths()

local function SavePanelBaseWidths()
    for _, id in ipairs(panel_ids) do
        RPR.SetExtState(panel_width_state_section, "px_" .. id,
            string.format("%.1f", panel_base_widths[id]), true)
    end
end

local function LoadPanelOrder()
    local saved = RPR.GetExtState(panel_state_section, "order")
    local order, seen = {}, {}
    for id in (saved or ""):gmatch("[ABCDE]") do
        if not seen[id] then
            order[#order + 1] = id
            seen[id] = true
        end
    end
    for _, id in ipairs(panel_ids) do
        if not seen[id] then order[#order + 1] = id end
    end
    return order
end

local panel_order = LoadPanelOrder()

local function SavePanelOrder()
    RPR.SetExtState(panel_state_section, "order", table.concat(panel_order, ","), true)
end

local function SwapPanelOrder(source_id, target_id)
    if not source_id or not target_id or source_id == target_id then return end
    local source_index, target_index
    for i, id in ipairs(panel_order) do
        if id == source_id then source_index = i end
        if id == target_id then target_index = i end
    end
    if source_index and target_index then
        panel_order[source_index], panel_order[target_index] = panel_order[target_index], panel_order[source_index]
        SavePanelOrder()
    end
end

local function ResetLayout()
    panel_order = {}
    for i, id in ipairs(panel_ids) do panel_order[i] = id end
    SavePanelOrder()
    for _, id in ipairs(panel_ids) do
        panel_base_widths[id] = PANEL_DEFAULT_WIDTHS[id]
        panel_visible[id] = PANEL_DEFAULT_VISIBLE[id]
    end
    SavePanelBaseWidths()
    SavePanelVisibility()
end

local function GetVisiblePanelIds()
    local ids = {}
    for _, id in ipairs(panel_order) do
        if panel_visible[id] then
            ids[#ids + 1] = id
        end
    end
    return ids
end

local function ComputePanelWidths(ids, total_width)
    local widths, sum = {}, 0
    for _, id in ipairs(ids) do
        widths[id] = math.max(PANEL_MIN_WIDTHS[id], panel_base_widths[id]) * JKK_UI_SCALE
        sum = sum + widths[id]
    end
    local fill = (sum > 0) and (total_width / sum) or 1
    for _, id in ipairs(ids) do widths[id] = math.floor(widths[id] * fill) end
    return widths, fill
end

local design_width_cache = nil
local splitter_dragging = false

local function GetDesignWidth()
    if design_width_cache and splitter_dragging then return design_width_cache end
    local sum, count = 0, 0
    for _, id in ipairs(panel_ids) do
        if panel_visible[id] then
            sum = sum + math.max(PANEL_MIN_WIDTHS[id], panel_base_widths[id])
            count = count + 1
        end
    end
    if count == 0 then return DESIGN_WINDOW_WIDTH end
    design_width_cache = sum + SPLITTER_WIDTH * (count - 1) + 20
    return design_width_cache
end

local pending_panel_swap = nil

local function DrawPanelHeader(panel_id)
    local available_width = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
    local label = panel_titles[panel_id] .. "##PanelHeader_" .. panel_id

    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), 0x00000000)
    Theme.PushFont(ctx, JKK_UI_SCALE, "heading")
    Theme.PushText(ctx, "accent")
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), 0, 0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FrameBorderSize(), 0)

    local header_height = math.max(S(15), RPR.ImGui_GetTextLineHeight(ctx) + S(2))
    RPR.ImGui_Button(ctx, label, math.max(1, available_width), header_height)
    RPR.ImGui_PopStyleVar(ctx, 3)
    Theme.PopText(ctx)
    Theme.PopFont(ctx)
    RPR.ImGui_PopStyleColor(ctx, 3)

    if RPR.ImGui_IsItemHovered(ctx) then
        RPR.ImGui_SetTooltip(ctx, "Drag onto another panel title to swap their places.")
    end

    if RPR.ImGui_BeginDragDropSource(ctx) then
        RPR.ImGui_SetDragDropPayload(ctx, "JKK_REATOOLS_PANEL", panel_id)
        RPR.ImGui_Text(ctx, "Move " .. panel_titles[panel_id])
        RPR.ImGui_EndDragDropSource(ctx)
    end

    if RPR.ImGui_BeginDragDropTarget(ctx) then
        local accepted, payload = RPR.ImGui_AcceptDragDropPayload(ctx, "JKK_REATOOLS_PANEL", nil)
        if accepted and payload and payload ~= panel_id then
            pending_panel_swap = { payload, panel_id }
        end
        RPR.ImGui_EndDragDropTarget(ctx)
    end
end

local function DrawSplitter(index, left_id, right_id, fill, height, splitter_width)
    RPR.ImGui_InvisibleButton(ctx, "##JKK_Splitter_" .. index, splitter_width, height)
    local hovered = RPR.ImGui_IsItemHovered(ctx)
    local active = RPR.ImGui_IsItemActive(ctx)
    if hovered or active then
        RPR.ImGui_SetMouseCursor(ctx, RPR.ImGui_MouseCursor_ResizeEW())
    end

    local min_x, min_y = RPR.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = RPR.ImGui_GetItemRectMax(ctx)
    local line_x = math.floor((min_x + max_x) / 2) + 0.5
    local color = Theme.GetSplitterColor(active, hovered)
    RPR.ImGui_DrawList_AddLine(RPR.ImGui_GetWindowDrawList(ctx),
        line_x, min_y + S(4), line_x, max_y - S(4), color, active and 2 or 1)

    if active then
        local delta_x = RPR.ImGui_GetMouseDelta(ctx)
        if delta_x and delta_x ~= 0 then
            local delta = delta_x / (JKK_UI_SCALE * fill)
            local old_left = math.max(PANEL_MIN_WIDTHS[left_id], panel_base_widths[left_id])
            local new_left = math.max(PANEL_MIN_WIDTHS[left_id], old_left + delta)
            local applied = new_left - old_left
            local old_right = math.max(PANEL_MIN_WIDTHS[right_id], panel_base_widths[right_id])
            panel_base_widths[left_id] = new_left
            panel_base_widths[right_id] = math.max(PANEL_MIN_WIDTHS[right_id], old_right - applied)
        end
    end
    if RPR.ImGui_IsItemActivated(ctx) then splitter_dragging = true end
    if RPR.ImGui_IsItemDeactivated(ctx) then
        splitter_dragging = false
        SavePanelBaseWidths()
    end
    if hovered and not active then
        RPR.ImGui_SetTooltip(ctx, "Drag to resize")
    end
end

---------------------------------------------------------
-- Settings Popup & Top Bar
---------------------------------------------------------
local SETTINGS_POPUP_ID = "##JKK_ReaTools_Settings"

local function DrawSettingsPopup()
    if not RPR.ImGui_BeginPopup(ctx, SETTINGS_POPUP_ID) then
        return
    end

    -- 1. Selection & Range Detection
    RPR.ImGui_TextDisabled(ctx, "Selection & Range Detection")
    RPR.ImGui_Separator(ctx)

    local range_mode_items = { "Ignore", "Regions / Markers", "Items in Range" }

    RPR.ImGui_AlignTextToFramePadding(ctx)
    RPR.ImGui_Text(ctx, "Time Selection")
    RPR.ImGui_SameLine(ctx, S(115))
    RPR.ImGui_SetNextItemWidth(ctx, S(155))
    local ts_mode = sel_mgr and sel_mgr.GetTimeSelectionMode() or 1
    RPR.ImGui_SetNextWindowSizeConstraints(ctx, 0, S(80), 16384, 16384)
    if RPR.ImGui_BeginCombo(ctx, "##TimeSelDetectMode", range_mode_items[ts_mode + 1] or "Ignore", RPR.ImGui_ComboFlags_HeightLarge()) then
        for i, label in ipairs(range_mode_items) do
            local idx = i - 1
            if RPR.ImGui_Selectable(ctx, label, ts_mode == idx) and sel_mgr then
                sel_mgr.SetTimeSelectionMode(idx)
            end
        end
        RPR.ImGui_EndCombo(ctx)
    end
    if RPR.ImGui_IsItemHovered(ctx) then
        RPR.ImGui_SetTooltip(ctx, "Choose what to target when Time Selection changes:\n- Ignore: Do not change target mode\n- Regions / Markers: Target regions & markers inside range\n- Items in Range: Auto-select media items overlapping range")
    end

    RPR.ImGui_AlignTextToFramePadding(ctx)
    RPR.ImGui_Text(ctx, "Loop Points")
    RPR.ImGui_SameLine(ctx, S(115))
    RPR.ImGui_SetNextItemWidth(ctx, S(155))
    local loop_mode = sel_mgr and sel_mgr.GetLoopPointsMode() or 0
    RPR.ImGui_SetNextWindowSizeConstraints(ctx, 0, S(80), 16384, 16384)
    if RPR.ImGui_BeginCombo(ctx, "##LoopPointsDetectMode", range_mode_items[loop_mode + 1] or "Ignore", RPR.ImGui_ComboFlags_HeightLarge()) then
        for i, label in ipairs(range_mode_items) do
            local idx = i - 1
            if RPR.ImGui_Selectable(ctx, label, loop_mode == idx) and sel_mgr then
                sel_mgr.SetLoopPointsMode(idx)
            end
        end
        RPR.ImGui_EndCombo(ctx)
    end
    if RPR.ImGui_IsItemHovered(ctx) then
        RPR.ImGui_SetTooltip(ctx, "Choose what to target when Loop Points change:\n- Ignore: Do not change target mode\n- Regions / Markers: Target regions & markers inside loop\n- Items in Range: Auto-select media items overlapping loop")
    end

    if sel_mgr then
        local sel_settings = sel_mgr.GetSettings()
        local arr_changed, new_arr = RPR.ImGui_Checkbox(ctx, "Arrange Click Selects Track", sel_settings.arrange_selects_track)
        if arr_changed then
            sel_mgr.SetSetting("arrange_selects_track", new_arr)
        end
    end

    -- 2. Panels Visibility & Layout
    RPR.ImGui_Spacing(ctx)
    RPR.ImGui_TextDisabled(ctx, "Panels")
    RPR.ImGui_Separator(ctx)

    for i, id in ipairs(panel_ids) do
        local vis_changed, new_vis = RPR.ImGui_Checkbox(ctx, panel_titles[id] .. "##Vis_" .. id, panel_visible[id])
        if vis_changed then
            panel_visible[id] = new_vis
            SavePanelVisibility()
        end
        if i % 2 == 1 and i < #panel_ids then
            RPR.ImGui_SameLine(ctx, S(145))
        end
    end

    if RPR.ImGui_Button(ctx, "Reset Layout", S(110), 0) then
        ResetLayout()
    end

    -- 3. UI Zoom
    RPR.ImGui_Spacing(ctx)
    RPR.ImGui_TextDisabled(ctx, "UI Zoom")
    RPR.ImGui_Separator(ctx)

    local auto_changed, new_auto = RPR.ImGui_Checkbox(ctx, "Auto Fit Width", ui_zoom.auto)
    if auto_changed then
        ui_zoom.auto = new_auto
        SaveZoomSettings()
    end

    if ui_zoom.auto then
        RPR.ImGui_SameLine(ctx, S(145))
        local height_changed, new_height = RPR.ImGui_Checkbox(ctx, "Fit Height", ui_zoom.follow_height)
        if height_changed then
            ui_zoom.follow_height = new_height
            SaveZoomSettings()
        end
    end

    RPR.ImGui_AlignTextToFramePadding(ctx)
    RPR.ImGui_Text(ctx, "Scale")
    RPR.ImGui_SameLine(ctx, S(55))
    RPR.ImGui_SetNextItemWidth(ctx, S(145))
    local size_changed, new_size = RPR.ImGui_SliderDouble(ctx, "##UIZoomSize", ui_zoom.size, 0.5, 1.8, "%.2fx")
    if size_changed then
        ui_zoom.size = new_size
        SaveZoomSettings()
    end
    RPR.ImGui_SameLine(ctx, 0, S(6))
    if RPR.ImGui_Button(ctx, "Reset##ZoomReset", S(52), 0) then
        ui_zoom.auto = UI_ZOOM_DEFAULTS.auto
        ui_zoom.follow_height = UI_ZOOM_DEFAULTS.follow_height
        ui_zoom.size = UI_ZOOM_DEFAULTS.size
        SaveZoomSettings()
    end

    -- 4. Tools & Theme
    RPR.ImGui_Spacing(ctx)
    RPR.ImGui_TextDisabled(ctx, "Tools & Theme")
    RPR.ImGui_Separator(ctx)

    if RPR.ImGui_MenuItem(ctx, "Theme & Font Manager...") then
        if Theme and Theme.OpenEditor then
            Theme.OpenEditor()
        end
    end
    if RPR.ImGui_MenuItem(ctx, "Peak Display Settings...") then
        RPR.Main_OnCommand(42074, 0) -- Peaks: Show peaks display settings
    end
    if RPR.ImGui_MenuItem(ctx, "Open Project Directory") then
        local _, proj_path = RPR.EnumProjects(-1)
        if proj_path and proj_path ~= "" then
            if RPR.CF_LocateInExplorer then
                RPR.CF_LocateInExplorer(proj_path)
            else
                local is_win = RPR.GetOS():find("Win") ~= nil
                local is_mac = RPR.GetOS():find("OSX") ~= nil or RPR.GetOS():find("macOS") ~= nil
                local unsafe = is_win and '["%%\n^&|<>]' or '["\'`$\\\n]'
                if proj_path:find(unsafe) then
                    RPR.ShowMessageBox("경로에 보안상 허용되지 않은 특수문자가 포함되어 있습니다.", "오류", 0)
                elseif is_mac then
                    os.execute(('open -R "%s"'):format(proj_path))
                elseif is_win then
                    os.execute(('explorer /select,"%s"'):format(proj_path:gsub('/', '\\')))
                else
                    local dir = proj_path:match("^(.*)[/\\]")
                    if dir then os.execute(('xdg-open "%s"'):format(dir)) end
                end
            end
        else
            RPR.ShowMessageBox("현재 프로젝트가 아직 저장되지 않았습니다.", "알림", 0)
        end
    end

    RPR.ImGui_EndPopup(ctx)
end

local HOME_ACTION_HASH = "_RSdcfdfdea965740c8abfe7db7c4421aca369f442f"
local home_cmd_id_cache = nil
local home_cmd_checked_time = 0

local function GetValidHomeCommandId()
    local now = RPR.time_precise and RPR.time_precise() or os.clock()
    if home_cmd_id_cache ~= nil and (now - home_cmd_checked_time) < 2.0 then
        return home_cmd_id_cache
    end
    home_cmd_checked_time = now

    local cmd_id = RPR.NamedCommandLookup(HOME_ACTION_HASH)
    if not cmd_id or cmd_id == 0 then
        home_cmd_id_cache = 0
        return 0
    end

    local res_path = RPR.GetResourcePath()
    local kb_path = res_path .. "/reaper-kb.ini"
    local f = io.open(kb_path, "r")
    if f then
        local target_key = HOME_ACTION_HASH:gsub("^_", "")
        local script_rel_path = nil
        for line in f:lines() do
            if line:find(target_key, 1, true) then
                -- SCR 라인의 마지막 따옴표 안의 경로 추출
                script_rel_path = line:match('"([^"]+)"%s*$')
                break
            end
        end
        f:close()

        -- kb.ini에 기록이 없거나 경로가 비어있으면 숨김
        if not script_rel_path or script_rel_path == "" then
            home_cmd_id_cache = 0
            return 0
        end

        -- 절대 경로, 리소스 루트 기준 경로, Scripts/ 폴더 기준 경로 모두 확인
        local exists = RPR.file_exists(script_rel_path)
            or RPR.file_exists(res_path .. "/" .. script_rel_path)
            or RPR.file_exists(res_path .. "/Scripts/" .. script_rel_path)

        if not exists then
            home_cmd_id_cache = 0
            return 0
        end
    end

    home_cmd_id_cache = cmd_id
    return cmd_id
end

local function DrawTopBar()
    Theme.PushFont(ctx, JKK_UI_SCALE, "topbar")
    local home_cmd_id = GetValidHomeCommandId()
    if home_cmd_id ~= 0 then
        RPR.ImGui_SameLine(ctx, 0, S(4))
        Theme.PushButton(ctx, "highlight")
        if RPR.ImGui_SmallButton(ctx, "Home##JKK_HomeButton") then
            RPR.Main_OnCommand(home_cmd_id, 0)
        end
        Theme.PopButton(ctx)
    end

    RPR.ImGui_SameLine(ctx, 0, S(4))
    local memo_on = panel_visible.A
    if memo_on then
        Theme.PushButton(ctx, "confirm")
    end
    local memo_clicked = RPR.ImGui_SmallButton(ctx, "Memo##JKK_MemoToggle")
    if memo_on then
        Theme.PopButton(ctx)
    end
    if memo_clicked then
        panel_visible.A = not panel_visible.A
        SavePanelVisibility()
    end
    if RPR.ImGui_IsItemHovered(ctx) then
        RPR.ImGui_SetTooltip(ctx, memo_on and "Hide the Project Memo panel" or "Show the Project Memo panel")
    end

    RPR.ImGui_SameLine(ctx, 0, S(4))
    if RPR.ImGui_SmallButton(ctx, "Settings##JKK_SettingsButton") then
        RPR.ImGui_OpenPopup(ctx, SETTINGS_POPUP_ID)
    end
    DrawSettingsPopup()

    RPR.ImGui_SameLine(ctx, 0, S(10))
    DrawSelectionStatus()

    Theme.PopFont(ctx)
end

---------------------------------------------------------
-- Panel Drawers
---------------------------------------------------------
local function DrawPanelA()
    local available_width, available_height = RPR.ImGui_GetContentRegionAvail(ctx)
    local changed_note, new_note = RPR.ImGui_InputTextMultiline(
        ctx, "##proj_note", project_note,
        math.max(1, available_width), math.max(S(40), available_height)
    )
    if changed_note then project_note = new_note end
    if RPR.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        RPR.SetProjExtState(0, "JKK_ReaTools_Note", "project_note", project_note)
        RPR.SetProjExtState(0, "JKK_ReaTools_Note", "Project_note", project_note)
        if RPR.MarkProjectDirty then RPR.MarkProjectDirty(0) end
    end
end

local function DrawPanelB()
    RPR.ImGui_BeginDisabled(ctx, not IsCurrentModeActive())

    if current_mode == "Item" then
        if item_module and item_module.JKK_ItemTool_Draw then
            item_module.JKK_ItemTool_Draw(
                ctx,
                prev_project_state_count,
                current_project_state_count,
                "item",
                track_module
            )
        else
            RPR.ImGui_Text(ctx, "Item tools module is unavailable.")
        end
    elseif current_mode == "Track" then
        if track_module and track_module.JKK_TrackTool_Draw then
            track_module.JKK_TrackTool_Draw(ctx, "track")
        else
            RPR.ImGui_Text(ctx, "Track tools module is unavailable.")
        end
    elseif current_mode == "Region/Marker" then
        if track_module and track_module.JKK_TrackTool_DrawTimelineActions then
            track_module.JKK_TrackTool_DrawTimelineActions(ctx)
        else
            RPR.ImGui_Text(ctx, "Timeline tools module is unavailable.")
        end
    else
        if item_module and item_module.JKK_ItemTool_Draw then
            item_module.JKK_ItemTool_Draw(
                ctx,
                prev_project_state_count,
                current_project_state_count,
                "item",
                track_module
            )
        end
    end

    RPR.ImGui_EndDisabled(ctx)
end

local function DrawPanelC()
    local mode_active = IsCurrentModeActive()

    if renamer_lite_module and renamer_lite_module.JKK_RenamerLite_Draw then
        renamer_lite_module.JKK_RenamerLite_Draw(ctx, current_mode, mode_active)
    else
        RPR.ImGui_Text(ctx, "Renamer Lite module is unavailable.")
    end

    if current_mode == "Item" and item_module and item_module.JKK_ItemTool_DrawMetadata then
        JKK_DrawLowerBlock(ctx, "C", function()
            RPR.ImGui_BeginDisabled(ctx, not mode_active)
            item_module.JKK_ItemTool_DrawMetadata(ctx)
            RPR.ImGui_EndDisabled(ctx)
        end)
    end
end

local function DrawPanelD()
    if item_module and item_module.JKK_ItemTool_DrawEditingUtilities then
        local item_active = (current_mode == "Item") and IsCurrentModeActive()
        RPR.ImGui_BeginDisabled(ctx, not item_active)
        item_module.JKK_ItemTool_DrawEditingUtilities(ctx, item_active)
        RPR.ImGui_EndDisabled(ctx)
    else
        RPR.ImGui_Text(ctx, "Item editing utilities are unavailable.")
    end
end

local function DrawPanelE()
    if color_palette_module and color_palette_module.JKK_ColorPalette_Draw then
        color_palette_module.JKK_ColorPalette_Draw(ctx, current_mode, IsCurrentModeActive())
    else
        RPR.ImGui_Text(ctx, "Color module is unavailable.")
    end
end

local panel_drawers = {
    A = DrawPanelA,
    B = DrawPanelB,
    C = DrawPanelC,
    D = DrawPanelD,
    E = DrawPanelE
}

local function DrawPanels()
    local dock_bottom_safety = math.floor(S(6))
    local available_width, available_height = RPR.ImGui_GetContentRegionAvail(ctx)
    available_width = math.floor(available_width)
    local strip_height = math.max(1, math.floor(available_height) - dock_bottom_safety)

    local ids = GetVisiblePanelIds()
    if #ids == 0 then
        RPR.ImGui_TextDisabled(ctx, "All panels are hidden. Turn them on in Settings.")
        return
    end

    local splitter_width = math.max(5, math.floor(S(SPLITTER_WIDTH)))
    local splitters_total = splitter_width * (#ids - 1)
    local widths, fill = ComputePanelWidths(ids, available_width - splitters_total)

    local panel_height = strip_height
    local strip_flags = RPR.ImGui_WindowFlags_NoScrollbar() | RPR.ImGui_WindowFlags_NoScrollWithMouse()

    if not RPR.ImGui_BeginChild(ctx, "##JKK_PanelStrip", available_width, strip_height,
        RPR.ImGui_ChildFlags_None(), strip_flags) then
        return
    end

    for index, id in ipairs(ids) do
        RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_WindowPadding(), S(8), S(4))
        local panel_open = RPR.ImGui_BeginChild(ctx, "##JKK_Panel_" .. id, widths[id], panel_height,
            RPR.ImGui_ChildFlags_AlwaysUseWindowPadding(),
            RPR.ImGui_WindowFlags_NoScrollbar() | RPR.ImGui_WindowFlags_NoScrollWithMouse())
        RPR.ImGui_PopStyleVar(ctx, 1)
        if panel_open then
            DrawPanelHeader(id)
            panel_drawers[id]()
            RPR.ImGui_EndChild(ctx)
        end

        if index < #ids then
            RPR.ImGui_SameLine(ctx, 0, 0)
            DrawSplitter(index, id, ids[index + 1], fill, panel_height, splitter_width)
            RPR.ImGui_SameLine(ctx, 0, 0)
        end
    end

    RPR.ImGui_EndChild(ctx)

    if pending_panel_swap then
        SwapPanelOrder(pending_panel_swap[1], pending_panel_swap[2])
        pending_panel_swap = nil
    end
end

---------------------------------------------------------
-- Main UI Loop
---------------------------------------------------------
local function Main()
    prev_project_state_count = current_project_state_count
    current_project_state_count = RPR.GetProjectStateChangeCount(0)

    local current_project_ptr = RPR.EnumProjects(-1)
    if current_project_ptr ~= last_project_ptr then
        LoadProjectNote()
        last_project_ptr = current_project_ptr
    end

    RPR.ImGui_SetNextWindowSize(
        ctx, DESIGN_WINDOW_WIDTH, DESIGN_WINDOW_HEIGHT, RPR.ImGui_Cond_Once()
    )
    RPR.ImGui_SetNextWindowSizeConstraints(
        ctx, WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT, 16384, 16384
    )
    local style_pop_count, color_pop_count = ApplyTheme(ctx, JKK_UI_SCALE)

    local visible, open_flag = RPR.ImGui_Begin(
        ctx,
        "JKK_ReaTools",
        open,
        RPR.ImGui_WindowFlags_NoCollapse()
            | RPR.ImGui_WindowFlags_NoScrollbar()
            | RPR.ImGui_WindowFlags_NoScrollWithMouse()
    )

    if visible then
        local is_focused = RPR.ImGui_IsWindowFocused(ctx, RPR.ImGui_FocusedFlags_RootAndChildWindows())
        UpdateFocusMode(is_focused)
        UpdateSelectionStatusCache()

        local window_width, window_height = RPR.ImGui_GetWindowSize(ctx)
        UpdateUIScale(window_width, window_height, GetDesignWidth())

        Theme.PushFont(ctx, JKK_UI_SCALE, "base")
        RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing(), S(8), S(6))

        DrawTopBar()
        RPR.ImGui_Separator(ctx)
        DrawPanels()

        RPR.ImGui_PopStyleVar(ctx, 1)
        Theme.PopFont(ctx)
    else
        UpdateFocusMode(false)
        UpdateSelectionStatusCache()
    end

    RPR.ImGui_End(ctx)
    RPR.ImGui_PopStyleVar(ctx, style_pop_count)
    RPR.ImGui_PopStyleColor(ctx, color_pop_count)

    open = open_flag

    if open then
        if not RPR.ImGui_IsAnyItemActive(ctx) then
            if RPR.ImGui_IsKeyPressed(ctx, RPR.ImGui_Key_Space()) then
                RPR.Main_OnCommand(40044, 0)
            end
            if RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Ctrl())
                and RPR.ImGui_IsKeyPressed(ctx, RPR.ImGui_Key_Z()) then
                local redo = RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Shift())
                RPR.Main_OnCommand(redo and 40030 or 40029, 0)
            end
        end
        RPR.defer(Main)
    else
        if RPR.ImGui_DestroyContext then
            RPR.ImGui_DestroyContext(ctx)
        end
        return
    end
end

RPR.atexit(function()
    if item_module and item_module.JKK_ItemTool_Cleanup then
        pcall(item_module.JKK_ItemTool_Cleanup)
    end
end)

RPR.defer(Main)