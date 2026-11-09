--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.9.82
-- @provides
--     [nomain] Modules/JKK_ReaTools_NEW_ItemTool.lua
--     [nomain] Modules/JKK_ReaTools_NEW_TrackTool.lua
--     [nomain] Modules/JKK_ReaTools_NEW_RenamerLite.lua
--     [nomain] Modules/JKK_ReaTools_NEW_ColorPaletteLite.lua
--     [nomain] Modules/JKK_Theme.lua
--========================================================

local RPR = reaper
local ctx = RPR.ImGui_CreateContext("JKK_ReaTools")

local font = RPR.ImGui_CreateFont("Arial", 24)
RPR.ImGui_Attach(ctx, font)
local renamer_input_font = RPR.ImGui_CreateFont("Arial", 16)
RPR.ImGui_Attach(ctx, renamer_input_font)

---------------------------------------------------------
-- USER CONFIG: PANEL WIDTHS
---------------------------------------------------------
-- Default widths are relative stretch weights. User-adjusted widths are
-- stored in ExtState and restored when the script is reopened.
local PANEL_DEFAULT_WIDTHS = {
    A = 0.90, -- Project Memo
    B = 1.00, -- Controller
    C = 0.95, -- Renamer / Take Settings
    D = 1.25, -- Item Tools
    E = 0.55, -- Color Palette
    F = 0.45  -- Empty Workspace
}

-- Minimum widths are pixel-based lower limits enforced by invisible anchors.
-- Increase these values when a panel should not be shrinkable below a size.
local PANEL_MIN_WIDTHS = {
    A = 280, -- Project Memo
    B = 360, -- Controller
    C = 430, -- Renamer + Take Channel / Item Info
    D = 560, -- Item Editing Utilities
    E = 250, -- Color Palette
    F = 200  -- Empty Workspace
}

-- Main window minimum size (pixels). These values can be adjusted independently
-- from the individual panel minimum widths above.
local WINDOW_MIN_WIDTH = 2200
local WINDOW_MIN_HEIGHT = 360

local open = true
local prev_project_state_count = RPR.GetProjectStateChangeCount(0)
local current_project_state_count = prev_project_state_count

local theme_path = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Theme.lua"
local ApplyTheme = (RPR.file_exists(theme_path) and dofile(theme_path).ApplyTheme)
    or function() return 0, 0 end

---------------------------------------------------------
-- Module Loading
---------------------------------------------------------
local function load_module(path)
    local full_path = RPR.GetResourcePath() .. path
    if not RPR.file_exists(full_path) then
        RPR.MB("Error: Module file not found at " .. full_path, "Module Load Error: File Not Found", 0)
        return nil
    end

    local status, result = pcall(dofile, full_path)
    if not status then
        RPR.MB(
            "Error executing module:\n" .. path .. "\n\nError Message:\n" .. tostring(result),
            "Module Execution Error",
            0
        )
        return nil
    end
    return result
end

local item_module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_ReaTools_NEW_ItemTool.lua")
local track_module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_ReaTools_NEW_TrackTool.lua")
local renamer_lite_module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_ReaTools_NEW_RenamerLite.lua")
local color_palette_module = load_module("/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_ReaTools_NEW_ColorPaletteLite.lua")

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
-- Selection Context
-- Mirrors JKK_Renamer's UpdateFocusMode / GetTargetTypeStr logic.
---------------------------------------------------------
local function GetSelectedRegionMarkerData()
    local regions, markers = {}, {}
    if not (RPR.GetNumRegionsOrMarkers and RPR.GetRegionOrMarker and RPR.GetRegionOrMarkerInfo_Value) then
        return regions, markers
    end

    local marker_count, region_count = RPR.GetNumRegionsOrMarkers(0)
    local total = (marker_count or 0) + (region_count or 0)
    for idx = 0, total - 1 do
        local pointer = RPR.GetRegionOrMarker(0, idx, "")
        if pointer and RPR.GetRegionOrMarkerInfo_Value(0, pointer, "B_UISEL") > 0 then
            local is_region = RPR.GetRegionOrMarkerInfo_Value(0, pointer, "B_ISREGION") == 1
            local _, name = RPR.GetSetRegionOrMarkerInfo_String(0, pointer, "P_NAME", "", false)
            local entry = { pointer = pointer, name = name or "" }
            if is_region then
                regions[#regions + 1] = entry
            else
                markers[#markers + 1] = entry
            end
        end
    end
    return regions, markers
end

local function HasSelectedRegionOrMarker()
    local regions, markers = GetSelectedRegionMarkerData()
    return (#regions > 0) or (#markers > 0)
end

-- current_mode remembers the last focused tool group. It is deliberately
-- not reset when the current selection disappears; mode_focus_active controls
-- whether that remembered UI is enabled or shown in its disabled state.
-- Start with Item Tools visible but disabled until a real Item selection is made.
local current_mode = "Item"
local mode_focus_active = false
local last_ts_start, last_ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
local last_item_ptr = RPR.GetSelectedMediaItem(0, 0)
local last_track_ptr = RPR.GetSelectedTrack(0, 0)
local last_cursor_ctx = RPR.GetCursorContext and RPR.GetCursorContext() or -1
local last_item_selection_signature = ""
local last_track_selection_signature = ""
local last_region_marker_signature = ""
local last_left_mouse_down = false
local mouse_down_context = nil
local mouse_down_track = nil
local mouse_down_item = nil

-- Mouse state shared with the delayed selection-status display.
local focus_mouse_down = false
local focus_mouse_released = false
local latest_selection_signature = nil

local function GetItemSelectionSignature()
    local parts = {}
    for i = 0, RPR.CountSelectedMediaItems(0) - 1 do
        local item = RPR.GetSelectedMediaItem(0, i)
        if item then
            local _, guid = RPR.GetSetMediaItemInfo_String(item, "GUID", "", false)
            parts[#parts + 1] = guid or tostring(item)
        end
    end
    return table.concat(parts, ",")
end

local function GetTrackSelectionSignature()
    local parts = {}
    for i = 0, RPR.CountSelectedTracks(0) - 1 do
        local track = RPR.GetSelectedTrack(0, i)
        if track then parts[#parts + 1] = RPR.GetTrackGUID(track) or tostring(track) end
    end
    return table.concat(parts, ",")
end

local function GetRegionMarkerSelectionSignature()
    local regions, markers = GetSelectedRegionMarkerData()
    local parts = {}
    for _, item in ipairs(regions) do parts[#parts + 1] = "R:" .. tostring(item.pointer) .. ":" .. item.name end
    for _, item in ipairs(markers) do parts[#parts + 1] = "M:" .. tostring(item.pointer) .. ":" .. item.name end
    return table.concat(parts, "|")
end

-- Snapshot the opening state so a pre-existing selection or the mouse pointer
-- location cannot activate a tool just by opening/hovering over JKK_ReaTools.
last_item_selection_signature = GetItemSelectionSignature()
last_track_selection_signature = GetTrackSelectionSignature()
last_region_marker_signature = GetRegionMarkerSelectionSignature()

local function GetMouseAreaContext()
    if not (RPR.GetMousePosition and RPR.GetThingFromPoint) then
        return nil, nil, nil, ""
    end

    local mouse_x, mouse_y = RPR.GetMousePosition()
    local hit_track, info = RPR.GetThingFromPoint(mouse_x, mouse_y)
    info = (info or ""):lower()

    -- Only the TCP is allowed to activate Track Tools. Arrange-track lanes
    -- deliberately return "arrange" and must never be treated as TCP tracks.
    if info:match("^tcp") then
        return "Track", hit_track, nil, info
    end

    if info == "arrange" or info:match("^arrange[%.:_]?") then
        local hit_item = RPR.GetItemFromPoint
            and RPR.GetItemFromPoint(mouse_x, mouse_y, false)
            or nil
        return "Arrange", nil, hit_item, info
    end

    if info:find("ruler", 1, true) or info:find("timeline", 1, true)
        or info:find("marker", 1, true) or info:find("region", 1, true) then
        return "Timeline", nil, nil, info
    end

    return nil, nil, nil, info
end

local function GetLeftMouseState()
    -- Poll the actual left-button state and expose all three transitions.
    -- Selection/mode updates are intentionally handled on RELEASE, not PRESS.
    if not RPR.JS_Mouse_GetState then
        last_left_mouse_down = false
        return false, false, false
    end

    local state = RPR.JS_Mouse_GetState(1) or 0
    local is_down = (state & 1) ~= 0
    local pressed = is_down and not last_left_mouse_down
    local released = not is_down and last_left_mouse_down

    last_left_mouse_down = is_down
    return pressed, is_down, released
end

local function HasSelectionForMode(mode)
    if mode == "Item" then
        return RPR.CountSelectedMediaItems(0) > 0
    elseif mode == "Track" then
        return RPR.CountSelectedTracks(0) > 0
    elseif mode == "Region/Marker" then
        if HasSelectedRegionOrMarker() then return true end
        local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
        return ts_end > ts_start
    end
    return false
end

local function IsCurrentModeActive()
    return mode_focus_active and HasSelectionForMode(current_mode)
end

local function UpdateFocusMode()
    -----------------------------------------------------
    -- Read the current REAPER selection state.
    -----------------------------------------------------
    local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local time_selection_changed =
        ts_start ~= last_ts_start or ts_end ~= last_ts_end

    local current_item_ptr = RPR.GetSelectedMediaItem(0, 0)
    local current_track_ptr = RPR.GetSelectedTrack(0, 0)
    local item_signature = GetItemSelectionSignature()
    local track_signature = GetTrackSelectionSignature()
    local region_signature = GetRegionMarkerSelectionSignature()

    local item_selection_changed =
        item_signature ~= last_item_selection_signature
    local track_selection_changed =
        track_signature ~= last_track_selection_signature
    local region_selection_changed =
        region_signature ~= last_region_marker_signature

    local cursor_ctx = RPR.GetCursorContext and RPR.GetCursorContext() or -1

    -----------------------------------------------------
    -- Mouse edge detection.
    -----------------------------------------------------
    local left_pressed, left_down, left_released = GetLeftMouseState()
    local hit_context, hit_track, hit_item = GetMouseAreaContext()

    -- Expose the sampled mouse state to the selection-status cache.
    focus_mouse_down = left_down
    focus_mouse_released = left_released

    -- This signature is sampled every frame. The display cache below decides
    -- when the newly observed state is allowed to become visible.
    latest_selection_signature = table.concat({
        item_signature,
        track_signature,
        region_signature,
        tostring(ts_start),
        tostring(ts_end)
    }, "\30")

    -----------------------------------------------------
    -- MOUSE DOWN: remember the gesture origin ONLY.
    -- Do not change current_mode or mode_focus_active here.
    -----------------------------------------------------
    if left_pressed then
        mouse_down_context = hit_context
        mouse_down_track = hit_track
        mouse_down_item = hit_item
    end

    -----------------------------------------------------
    -- MOUSE UP: commit the final selection and change mode.
    -----------------------------------------------------
    if left_released then
        if mouse_down_context == "Track" then
            -- A TCP click selects the Track tool group, including when
            -- the clicked track was already selected.
            if mouse_down_track or track_selection_changed
                or RPR.CountSelectedTracks(0) > 0 then
                current_mode = "Track"
                mode_focus_active = true
            end

        elseif mouse_down_context == "Arrange" then
            -- A direct item click or a marquee selection both activate Item.
            if mouse_down_item
                or (item_selection_changed
                    and RPR.CountSelectedMediaItems(0) > 0) then
                current_mode = "Item"
                mode_focus_active = true
            else
                -- Clicking empty Arrange space deactivates the current tools.
                mode_focus_active = false
            end

        elseif mouse_down_context == "Timeline" then
            current_mode = "Region/Marker"
            mode_focus_active = true
        end

        -- Region/marker and time-selection changes are committed on release.
        if time_selection_changed then
            current_mode = "Region/Marker"
            mode_focus_active = true
        elseif region_selection_changed and HasSelectedRegionOrMarker() then
            current_mode = "Region/Marker"
            mode_focus_active = true
        end

        -- Clear the captured gesture only after processing the release.
        mouse_down_context = nil
        mouse_down_track = nil
        mouse_down_item = nil

    -----------------------------------------------------
    -- NO MOUSE GESTURE: allow keyboard-driven selection
    -- changes to update the mode immediately.
    -----------------------------------------------------
    elseif not left_down and not left_pressed then
        if item_selection_changed
            and RPR.CountSelectedMediaItems(0) > 0 then
            current_mode = "Item"
            mode_focus_active = true
        end

        if track_selection_changed
            and RPR.CountSelectedTracks(0) > 0 then
            current_mode = "Track"
            mode_focus_active = true
        end

        if time_selection_changed then
            current_mode = "Region/Marker"
            mode_focus_active = true
        elseif region_selection_changed and HasSelectedRegionOrMarker() then
            current_mode = "Region/Marker"
            mode_focus_active = true
        end
    end

    -----------------------------------------------------
    -- Without JS_ReaScriptAPI, mouse down/up cannot be
    -- detected. Keep the previous selection-change fallback.
    -----------------------------------------------------
    if not RPR.JS_Mouse_GetState then
        if item_selection_changed
            and RPR.CountSelectedMediaItems(0) > 0 then
            current_mode = "Item"
            mode_focus_active = true
        end
    end

    -----------------------------------------------------
    -- IMPORTANT: do not update snapshots while the mouse
    -- is held. This preserves the before-click state until
    -- the release frame, where the final state is compared.
    -----------------------------------------------------
    if not left_down then
        last_ts_start = ts_start
        last_ts_end = ts_end

        last_item_ptr = current_item_ptr
        last_track_ptr = current_track_ptr
        last_cursor_ctx = cursor_ctx

        last_item_selection_signature = item_signature
        last_track_selection_signature = track_signature
        last_region_marker_signature = region_signature
    end

    -- If the active selection for the remembered mode has disappeared,
    -- keep the layout visible but disable its controls.
    if not HasSelectionForMode(current_mode) then
        mode_focus_active = false
    end

    return current_mode
end

-- Establish initial mode only from the actual mouse hit target, not merely
-- from whatever REAPER happens to have selected in the background.
UpdateFocusMode()

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

    for count = char_count - 1, 0, -1 do
        local byte_end = (count == 0) and 0 or (utf8.offset(text, count + 1) or (#text + 1)) - 1
        local candidate = text:sub(1, byte_end) .. ellipsis
        if select(1, RPR.ImGui_CalcTextSize(ctx, candidate)) <= max_width then
            return candidate
        end
    end
    return ellipsis
end

-- Read the live REAPER selection. This function is intentionally separate
-- from BuildSelectionStatus so the UI can display a committed snapshot instead
-- of following REAPER's mouse-down selection immediately.
local function CaptureSelectionStatus()
    local item_count = RPR.CountSelectedMediaItems(0)
    local track_count = RPR.CountSelectedTracks(0)

    if current_mode == "Item" and IsCurrentModeActive() and item_count > 0 then
        local item = RPR.GetSelectedMediaItem(0, 0)
        local item_type = GetTargetTypeStr("Item", item)
        return string.format("Selected %02d Items (%s: ", item_count, item_type),
            GetFirstItemName(item), ")"
    elseif current_mode == "Track" and IsCurrentModeActive() and track_count > 0 then
        local track = RPR.GetSelectedTrack(0, 0)
        local track_type = GetTargetTypeStr("Track", track)
        return string.format("Selected %02d Tracks (%s: ", track_count, track_type),
            GetFirstTrackName(track), ")"
    elseif current_mode == "Region/Marker" and IsCurrentModeActive() then
        local regions, markers = GetSelectedRegionMarkerData()
        local total = #regions + #markers
        if total > 0 then
            local first = regions[1] or markers[1]
            local kind = (#regions > 0 and #markers > 0) and "Regions/Markers"
                or ((#regions > 0) and "Regions" or "Markers")
            return string.format("Selected %02d %s (", total, kind),
                first.name ~= "" and first.name or "Unnamed", ")"
        end
        local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if ts_end > ts_start then return "Timeline (Time Selection)" end
        return "Timeline"
    end

    return "No Selection"
end

-- Cache the selection-status line and only refresh it after mouse release.
-- A short fallback delay handles fast clicks that begin and end between two
-- defer cycles, which JS_Mouse_GetState polling can otherwise miss.
local selection_status_cache = nil
local committed_status_signature = nil
local pending_status_since = nil
local STATUS_RELEASE_FALLBACK_DELAY = 0.12

local function UpdateSelectionStatusCache()
    local live_prefix, live_name, live_suffix = CaptureSelectionStatus()
    local live_signature = table.concat({
        latest_selection_signature or "",
        current_mode or "",
        tostring(mode_focus_active),
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

    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), 0xBFC5CCFF)
    if selected_name == nil then
        RPR.ImGui_Text(ctx, FitTextToWidth(prefix, available_width))
    else
        local prefix_width = select(1, RPR.ImGui_CalcTextSize(ctx, prefix))
        local suffix_width = select(1, RPR.ImGui_CalcTextSize(ctx, suffix))
        local name_width = available_width - prefix_width - suffix_width

        if name_width <= 1 then
            RPR.ImGui_Text(ctx, FitTextToWidth(prefix .. selected_name .. suffix, available_width))
        else
            selected_name = FitTextToWidth(selected_name, name_width)
            RPR.ImGui_Text(ctx, prefix)
            RPR.ImGui_SameLine(ctx, 0, 0)
            RPR.ImGui_Text(ctx, selected_name)
            RPR.ImGui_SameLine(ctx, 0, 0)
            RPR.ImGui_Text(ctx, suffix)
        end
    end
    RPR.ImGui_PopStyleColor(ctx)
end

---------------------------------------------------------
-- Panel Order Persistence / Drag Reordering
---------------------------------------------------------
local panel_state_section = "JKK_ReaTools_Panels"
local panel_width_state_section = "JKK_ReaTools_PanelWidths"
local panel_ids = { "A", "B", "C", "D", "E", "F" }

local function LoadPanelWidthWeights()
    local weights, total = {}, 0
    for _, id in ipairs(panel_ids) do
        local value = tonumber(RPR.GetExtState(panel_width_state_section, "width_" .. id))
        if value and value > 0 then
            weights[id] = value
            total = total + value
        end
    end

    -- If any panel has no saved value, keep the complete default layout.
    if total <= 0 then
        for id, value in pairs(PANEL_DEFAULT_WIDTHS) do weights[id] = value end
        return weights
    end

    for _, id in ipairs(panel_ids) do
        if not weights[id] then
            for default_id, value in pairs(PANEL_DEFAULT_WIDTHS) do
                weights[default_id] = value
            end
            return weights
        end
    end
    return weights
end

local panel_width_weights = LoadPanelWidthWeights()
local last_panel_widths = nil
local panel_widths_dirty = false

local function SavePanelWidthWeights(widths)
    local total = 0
    for _, id in ipairs(panel_ids) do total = total + (widths[id] or 0) end
    if total <= 0 then return end

    for _, id in ipairs(panel_ids) do
        local weight = (widths[id] or 0) / total * #panel_ids
        panel_width_weights[id] = weight
        RPR.SetExtState(panel_width_state_section, "width_" .. id, string.format("%.6f", weight), true)
    end
end
local panel_titles = {
    A = "Project Memo",
    B = "Controller",
    C = "Renamer / Take Settings",
    D = "Item Tools",
    E = "Color Palette",
    F = ""
}
local function LoadPanelOrder()
    local saved = RPR.GetExtState(panel_state_section, "order")
    local order, seen = {}, {}
    for id in (saved or ""):gmatch("[ABCDEF]") do
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

local pending_panel_swap = nil

local function DrawPanelHeader(panel_id)
    local available_width = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
    -- Keep the visible label clean; the panel letter is only used internally
    -- for drag/drop identity and the ImGui ID.
    local label = " " .. panel_titles[panel_id] .. "##PanelHeader_" .. panel_id

    -- Flat, compact header: transparent in normal/hover/active states, with
    -- the same gold text color as the global Selected status line.
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), 0xE3DB8EFF)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), 4, 0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FrameBorderSize(), 0)
    RPR.ImGui_Button(ctx, label, math.max(56, available_width), 15)
    RPR.ImGui_PopStyleVar(ctx, 3)
    RPR.ImGui_PopStyleColor(ctx, 4)

    if RPR.ImGui_BeginDragDropSource and RPR.ImGui_SetDragDropPayload and RPR.ImGui_EndDragDropSource
        and RPR.ImGui_BeginDragDropSource(ctx) then
        RPR.ImGui_SetDragDropPayload(ctx, "JKK_REATOOLS_PANEL", panel_id)
        RPR.ImGui_Text(ctx, "Move Panel " .. panel_id)
        RPR.ImGui_EndDragDropSource(ctx)
    end

    if RPR.ImGui_BeginDragDropTarget and RPR.ImGui_AcceptDragDropPayload and RPR.ImGui_EndDragDropTarget
        and RPR.ImGui_BeginDragDropTarget(ctx) then
        local accepted, payload = RPR.ImGui_AcceptDragDropPayload(ctx, "JKK_REATOOLS_PANEL", nil)
        if accepted and payload and payload ~= panel_id then
            pending_panel_swap = { payload, panel_id }
        end
        RPR.ImGui_EndDragDropTarget(ctx)
    end
end

---------------------------------------------------------
-- Panel A: Project Memo
---------------------------------------------------------
local function DrawPanelA()
    -- Keep the panel wide enough for both footer shortcuts, using an anchor
    -- before the flexible memo field so no invisible item is placed below them.
    local peaks_width = select(1, RPR.ImGui_CalcTextSize(ctx, "Peaks Display Settings"))
    local directory_width = select(1, RPR.ImGui_CalcTextSize(ctx, "Open Project Directory"))
    local memo_min_width = math.max(
        PANEL_MIN_WIDTHS.A,
        math.max(peaks_width, directory_width) + 26
    )
    RPR.ImGui_Dummy(ctx, memo_min_width, 1)
    local available_width, available_height = RPR.ImGui_GetContentRegionAvail(ctx)
    available_width = math.max(1, available_width)

    -- The note pad consumes the flexible space; the two shortcut buttons reserve
    -- a fixed footer and therefore remain attached to the bottom of the window.
    local button_height = 22
    local vertical_spacing = 6 -- matches the main window ItemSpacing Y
    local shortcut_footer_height = button_height * 2 + vertical_spacing * 2
    local note_height = math.max(60, available_height - shortcut_footer_height)

    local changed_note, new_note = RPR.ImGui_InputTextMultiline(
        ctx, "##proj_note", project_note, available_width, note_height
    )
    if changed_note then project_note = new_note end
    if RPR.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        RPR.SetProjExtState(0, "JKK_ReaTools_Note", "project_note", project_note)
        RPR.SetProjExtState(0, "JKK_ReaTools_Note", "Project_note", project_note)
    end

    local shortcut_width = math.max(1, select(1, RPR.ImGui_GetContentRegionAvail(ctx)))
    if RPR.ImGui_Button(ctx, "Peaks Display Settings", shortcut_width, 22) then
        RPR.Main_OnCommand(42074, 0)
    end
    if RPR.ImGui_Button(ctx, "Open Project Directory", shortcut_width, 22) then
        local command_id = RPR.NamedCommandLookup("_S&M_OPEN_PRJ_PATH")
        if command_id ~= 0 then
            RPR.Main_OnCommand(command_id, 0)
        else
            RPR.ShowMessageBox("해당 커스텀/SWS 액션을 찾을 수 없습니다.", "오류", 0)
        end
    end

end

---------------------------------------------------------
-- Panel B: Context Controller / Actions
---------------------------------------------------------
local function DrawPanelB()
    -- Enforce the minimum width before drawing; avoid a trailing dummy under
    -- the bottom-anchored action buttons.
    RPR.ImGui_Dummy(ctx, PANEL_MIN_WIDTHS.B, 1)
    if current_mode == "None" then
        RPR.ImGui_Text(ctx, "Select an item, track, or timeline area to show its tools.")
    else
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
        end

        RPR.ImGui_EndDisabled(ctx)
    end
end

---------------------------------------------------------
-- Panel C: Renamer + Take Channel / Item Info
---------------------------------------------------------
local renamer_properties_button_width = 0

local function DrawPanelC()
    RPR.ImGui_Dummy(ctx, PANEL_MIN_WIDTHS.C, 1)
    local mode_active = IsCurrentModeActive()
    local panel_width = select(1, RPR.ImGui_GetContentRegionAvail(ctx))

    -- A 2:1 metadata table gives the Properties button one third of the panel.
    -- The metadata renderer returns its exact cell width after the first frame;
    -- that value is then reused by Open Renamer so their right-side buttons match.
    local estimated_properties_width = math.max(70, panel_width / 3 - 16)
    local open_button_width = (renamer_properties_button_width > 0)
        and renamer_properties_button_width or estimated_properties_width

    if renamer_lite_module and renamer_lite_module.JKK_RenamerLite_Draw then
        renamer_lite_module.JKK_RenamerLite_Draw(
            ctx, current_mode, mode_active, renamer_input_font, open_button_width
        )
    else
        RPR.ImGui_Text(ctx, "Renamer Lite module is unavailable.")
    end

    if item_module and item_module.JKK_ItemTool_DrawMetadata then
        -- Reserve the lower part of Panel C for Take Channel / Pitch Mode and
        -- Item Info. The Renamer remains at the top while metadata follows the
        -- window bottom as the user resizes the script vertically.
        local cursor_y = RPR.ImGui_GetCursorPosY(ctx)
        local _, available_height = RPR.ImGui_GetContentRegionAvail(ctx)
        local frame_height = RPR.ImGui_GetFrameHeight(ctx)
        local text_height = RPR.ImGui_GetTextLineHeight(ctx)
        local spacing_y = 6
        local metadata_height = math.max(
            frame_height * 3 + spacing_y * 2,
            text_height * 3 + spacing_y * 3 + 22
        ) + 6 -- reserves the visible bottom margin below Properties
        local divider_height = spacing_y * 2 + 1
        local flexible_gap = math.max(0, available_height - metadata_height - divider_height)
        RPR.ImGui_SetCursorPosY(ctx, cursor_y + flexible_gap)

        RPR.ImGui_Spacing(ctx)
        RPR.ImGui_Separator(ctx)
        RPR.ImGui_Spacing(ctx)

        local item_active = current_mode == "Item" and mode_active
        RPR.ImGui_BeginDisabled(ctx, not item_active)
        local actual_properties_width = item_module.JKK_ItemTool_DrawMetadata(ctx)
        RPR.ImGui_EndDisabled(ctx)
        if actual_properties_width and actual_properties_width > 0 then
            renamer_properties_button_width = actual_properties_width
        end
    end

end

---------------------------------------------------------
-- Panel D: Item Editing Utilities
---------------------------------------------------------
local function DrawPanelD()
    RPR.ImGui_Dummy(ctx, PANEL_MIN_WIDTHS.D, 1)
    if item_module and item_module.JKK_ItemTool_DrawEditingUtilities then
        local item_active = current_mode == "Item" and IsCurrentModeActive()
        RPR.ImGui_BeginDisabled(ctx, not item_active)
        item_module.JKK_ItemTool_DrawEditingUtilities(ctx, item_active)
        RPR.ImGui_EndDisabled(ctx)
    else
        RPR.ImGui_Text(ctx, "Item editing utilities are unavailable.")
    end
end

---------------------------------------------------------
-- Panel E: Additional Resizable Workspace
---------------------------------------------------------
local function DrawPanelE()
    RPR.ImGui_Dummy(ctx, PANEL_MIN_WIDTHS.E, 1)
    if color_palette_module and color_palette_module.JKK_ColorPalette_Draw then
        color_palette_module.JKK_ColorPalette_Draw(
            ctx,
            current_mode,
            IsCurrentModeActive()
        )
    else
        RPR.ImGui_Text(ctx, "Color Palette module is unavailable.")
    end
end

---------------------------------------------------------
-- Panel F: Empty Resizable Workspace (no header)
---------------------------------------------------------
local function DrawPanelF()
    -- Keep the invisible width anchor at the top so the column retains its
    -- minimum width. The footer button is positioned at the very bottom of
    -- the full-height table cell, with no extra Dummy spacing.
    RPR.ImGui_Dummy(ctx, PANEL_MIN_WIDTHS.F, 1)

    local footer_cursor_y = RPR.ImGui_GetCursorPosY(ctx)
    local _, footer_available_y = RPR.ImGui_GetContentRegionAvail(ctx)
    local footer_button_height = 1
    RPR.ImGui_SetCursorPosY(
        ctx,
        footer_cursor_y + math.max(0, footer_available_y - footer_button_height)
    )

    -- A 1x1 button with transparent normal/hover/active colors and an
    -- ID-only label: it creates an actual ImGui item without visible content.
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), 0x00000000)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), 0, 0)
    RPR.ImGui_Button(ctx, "##JKK_Panel_Footer_Anchor", 1, footer_button_height)
    RPR.ImGui_PopStyleVar(ctx, 1)
    RPR.ImGui_PopStyleColor(ctx, 3)
end

local panel_drawers = {
    A = DrawPanelA,
    B = DrawPanelB,
    C = DrawPanelC,
    D = DrawPanelD,
    E = DrawPanelE,
    F = DrawPanelF
}

---------------------------------------------------------
-- Main UI
---------------------------------------------------------
local function Main()
    current_project_state_count = RPR.GetProjectStateChangeCount(0)

    local current_project_ptr = RPR.EnumProjects(-1)
    if current_project_ptr ~= last_project_ptr then
        LoadProjectNote()
        last_project_ptr = current_project_ptr
    end

    UpdateFocusMode()
    UpdateSelectionStatusCache()

    RPR.ImGui_SetNextWindowSize(ctx, 1900, 440, RPR.ImGui_Cond_Once())
    RPR.ImGui_SetNextWindowSizeConstraints(
        ctx, WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT, 16384, 16384
    )
    local style_pop_count, color_pop_count = ApplyTheme(ctx)

    local visible, open_flag = RPR.ImGui_Begin(
        ctx,
        "JKK_ReaTools",
        open,
        RPR.ImGui_WindowFlags_NoCollapse()
            | RPR.ImGui_WindowFlags_NoScrollbar()
            | RPR.ImGui_WindowFlags_NoScrollWithMouse()
    )

    if visible then
        RPR.ImGui_PushFont(ctx, font, 13)
        RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_CellPadding(), 14, 0)
        RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing(), 8, 6)

        -- The selection summary is global: it is not a child of any A/B/C/D/E panel.
        DrawSelectionStatus()
        RPR.ImGui_Separator(ctx)

        local panel_table_flags = RPR.ImGui_TableFlags_Resizable()
            | RPR.ImGui_TableFlags_BordersInnerV()
            | RPR.ImGui_TableFlags_SizingStretchProp()

        -- Outer table: wraps the complete A-F panel table.
        -- No border flags are used, so the outer table has no visible borders
        -- without changing the border colors used by the inner panel table.
        local outer_table_flags = RPR.ImGui_TableFlags_SizingStretchProp()

        -- The outer cell has no padding. The inner panel table restores its own padding.
        RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_CellPadding(), 0, 0)

        local dock_bottom_safety = 8
        local panel_table_height = math.max(
            1,
            select(2, RPR.ImGui_GetContentRegionAvail(ctx)) - dock_bottom_safety
        )

        local current_panel_widths = {}

        -----------------------------------------------------
        -- OUTER TABLE
        -----------------------------------------------------
        if RPR.ImGui_BeginTable(
            ctx,
            "JKK_ReaTools_OuterTable",
            1,
            outer_table_flags,
            0,
            panel_table_height
        ) then
            RPR.ImGui_TableSetupColumn(
                ctx,
                "##JKK_OuterColumn",
                RPR.ImGui_TableColumnFlags_WidthStretch()
            )

            RPR.ImGui_TableNextRow(ctx)
            RPR.ImGui_TableNextColumn(ctx)

            -------------------------------------------------
            -- INNER PANEL TABLE (A-F)
            -------------------------------------------------
            RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_CellPadding(), 14, 0)

            if RPR.ImGui_BeginTable(
                ctx,
                "JKK_ReaTools_PanelTable_v0980",
                6,
                panel_table_flags,
                0,
                panel_table_height
            ) then
                for _, panel_id in ipairs(panel_order) do
                    RPR.ImGui_TableSetupColumn(
                        ctx,
                        panel_titles[panel_id] .. "##Panel_" .. panel_id,
                        RPR.ImGui_TableColumnFlags_WidthStretch(),
                        panel_width_weights[panel_id] or PANEL_DEFAULT_WIDTHS[panel_id]
                    )
                end

                for _, panel_id in ipairs(panel_order) do
                    RPR.ImGui_TableNextColumn(ctx)

                    local cell_width = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
                    current_panel_widths[panel_id] = cell_width

                    if panel_id ~= "F" then
                        DrawPanelHeader(panel_id)
                    end

                    panel_drawers[panel_id]()
                end

                RPR.ImGui_EndTable(ctx)

                ---------------------------------------------
                -- PANEL WIDTH CHANGE DETECTION
                ---------------------------------------------
                if last_panel_widths then
                    for _, id in ipairs(panel_ids) do
                        if math.abs(
                            (current_panel_widths[id] or 0)
                            - (last_panel_widths[id] or 0)
                        ) > 1.5 then
                            panel_widths_dirty = true
                            break
                        end
                    end
                end

                last_panel_widths = current_panel_widths

                ---------------------------------------------
                -- SAVE PANEL WIDTHS
                ---------------------------------------------
                -- Wait until the mouse is released before saving the final divider positions.
                if panel_widths_dirty and not RPR.ImGui_IsMouseDown(ctx, 0) then
                    SavePanelWidthWeights(current_panel_widths)
                    panel_widths_dirty = false
                end
            end -- Inner Panel Table

            -- Restore the inner table's cell padding before ending the outer table.
            RPR.ImGui_PopStyleVar(ctx, 1)

            RPR.ImGui_EndTable(ctx)
        end -- Outer Table

        -- Restore the outer table's cell padding.
        RPR.ImGui_PopStyleVar(ctx, 1)

        if pending_panel_swap then
            SwapPanelOrder(pending_panel_swap[1], pending_panel_swap[2])
            pending_panel_swap = nil
        end

        RPR.ImGui_PopStyleVar(ctx, 2)
        RPR.ImGui_PopFont(ctx)
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
                RPR.Main_OnCommand(40029, 0)
            end
            if RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Ctrl())
                and RPR.ImGui_IsKeyDown(ctx, RPR.ImGui_Mod_Shift())
                and RPR.ImGui_IsKeyPressed(ctx, RPR.ImGui_Key_Z()) then
                RPR.Main_OnCommand(40030, 0)
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

RPR.defer(Main)
