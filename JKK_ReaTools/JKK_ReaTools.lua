--========================================================
-- @title JKK_ReaTools
-- @author Junki Kim
-- @version 0.9.86
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
-- Default panel widths in pixels at 100% zoom. User-adjusted widths are stored
-- in ExtState. When the window is wider than all panels together, the extra
-- space is shared proportionally; when it is narrower, the strip scrolls.
local PANEL_DEFAULT_WIDTHS = {
    A = 220, -- Project Memo
    B = 330, -- Controller
    C = 420, -- Rename / Take
    D = 430, -- Item Tools (items only)
    E = 240  -- Color
}

-- Minimum widths (pixels at 100% zoom). A panel is never drawn narrower than
-- this, so its controls cannot overlap; when the window is too narrow for all
-- visible panels, a horizontal scrollbar appears instead.
local PANEL_MIN_WIDTHS = {
    A = 160, -- Project Memo
    B = 280, -- Controller
    C = 390, -- Rename / Take
    D = 380, -- Item Tools
    E = 150  -- Color
}

-- Width of the draggable divider between panels (pixels at 100% zoom).
local SPLITTER_WIDTH = 9

-- Main window minimum size (pixels). These values can be adjusted independently
-- from the individual panel minimum widths above.
local WINDOW_MIN_WIDTH = 200
local WINDOW_MIN_HEIGHT = 150

---------------------------------------------------------
-- USER CONFIG: UI ZOOM
---------------------------------------------------------
-- The whole UI (fonts, buttons, paddings) is zoomed uniformly so the layout
-- keeps the same proportions at any window size. The window size below is the
-- reference at which the zoom factor is exactly 1.0 (the original design size).
local DESIGN_WINDOW_WIDTH = 1900
local DESIGN_WINDOW_HEIGHT = 440
local BASE_FONT_SIZE = 13
-- Hard limits of the final zoom factor. Below ~0.6 text becomes unreadable.
local UI_SCALE_MIN = 0.2
local UI_SCALE_MAX = 2.0
local UI_SCALE_AUTO_MIN = 0.2

-- Defaults for the zoom settings shown in the Settings popup. The user's choices are
-- saved in ExtState and override these values.
local UI_ZOOM_DEFAULTS = {
    auto = true,          -- follow the window width
    follow_height = true, -- also shrink when the window is too short for the rows
    size = 1.0            -- personal size multiplier (1.0 = 100%)
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

-- Published as a global so the modules loaded with dofile() share the factor.
JKK_UI_SCALE = 1.0
local ui_font_size = BASE_FONT_SIZE
local function S(value) return value * JKK_UI_SCALE end

---------------------------------------------------------
-- Shared bottom block
---------------------------------------------------------
-- Panels pin a block of controls to the bottom of their cell, below a
-- separator line. Each block is measured when it is drawn, and every separator
-- is placed at the height of the tallest block, so the lines and the last rows
-- of all panels share one baseline. Published as a global for the modules.
local lower_block_heights = {}

function JKK_DrawLowerBlock(draw_ctx, id, draw_fn)
    -- FIX (screen shaking): every position here is a whole pixel. With
    -- fractional positions ImGui snapped the widgets to the pixel grid, the
    -- measured height then differed by a fraction each frame, and the block
    -- kept jumping up and down by one pixel.
    local _, gap = RPR.ImGui_GetStyleVar(draw_ctx, RPR.ImGui_StyleVar_ItemSpacing())
    gap = gap or S(6)
    local line_gap = math.ceil(gap)
    local start_y = math.ceil(RPR.ImGui_GetCursorPosY(draw_ctx))
    local _, avail_h = RPR.ImGui_GetContentRegionAvail(draw_ctx)
    local bottom_y = math.floor(RPR.ImGui_GetCursorPosY(draw_ctx) + avail_h)

    local own_h = lower_block_heights[id] or 0
    local zone_h = own_h
    for _, h in pairs(lower_block_heights) do zone_h = math.max(zone_h, h) end

    -- Separator: aligned across panels, but never above the content above it.
    local sep_y = math.max(start_y, bottom_y - zone_h - line_gap - 1)
    RPR.ImGui_SetCursorPosY(draw_ctx, sep_y)
    RPR.ImGui_Separator(draw_ctx)

    -- Block: bottom-aligned; a shorter block leaves its gap under the line.
    local block_y = math.max(sep_y + 1 + line_gap, bottom_y - own_h)
    RPR.ImGui_SetCursorPosY(draw_ctx, block_y)
    local result = draw_fn()

    local measured = RPR.ImGui_GetCursorPosY(draw_ctx) - gap - block_y
    lower_block_heights[id] = math.max(0, math.ceil(measured - 0.05))
    return result
end

-- Height (pixels at 100% zoom) the tallest panel needs: status line, panel
-- title and the eight control rows of the Controller.
local DESIGN_CONTENT_HEIGHT = 260

local function UpdateUIScale(window_width, window_height, needed_width)
    if not window_width or not window_height
        or window_width <= 0 or window_height <= 0 then return end

    -- Uniform zoom: the factor is chosen so that all enabled panels fit the
    -- window exactly. Resizing the window (corner drag or docker size) scales
    -- the whole UI and keeps every proportion; panels do not stretch apart.
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

    -- Snap to half-pixel font sizes: text stays crisp and the font atlas is
    -- not asked for a new size on every pixel of a window drag.
    ui_font_size = math.max(6, math.floor(BASE_FONT_SIZE * raw * 2 + 0.5) / 2)
    JKK_UI_SCALE = ui_font_size / BASE_FONT_SIZE
end

local open = true
local prev_project_state_count = RPR.GetProjectStateChangeCount(0)
local current_project_state_count = prev_project_state_count

-- Modules are loaded from the folder next to this script first, so a copy of
-- the tool can run side by side with the installed one. The installed
-- location is kept as a fallback.
local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local installed_dir = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/"

local function ResolveModulePath(file_name)
    local local_path = script_dir .. "Modules/" .. file_name
    if script_dir ~= "" and RPR.file_exists(local_path) then return local_path end
    return installed_dir .. "Modules/" .. file_name
end

local theme_path = ResolveModulePath("JKK_Theme.lua")
local ApplyTheme = (RPR.file_exists(theme_path) and dofile(theme_path).ApplyTheme)
    or function() return 0, 0 end

---------------------------------------------------------
-- Module Loading
---------------------------------------------------------
local function load_module(file_name)
    local path = file_name
    local full_path = ResolveModulePath(file_name)
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

local item_module = load_module("JKK_ReaTools_NEW_ItemTool.lua")
local track_module = load_module("JKK_ReaTools_NEW_TrackTool.lua")
local renamer_lite_module = load_module("JKK_ReaTools_NEW_RenamerLite.lua")
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
-- Selection Context
-- Mirrors JKK_Renamer's UpdateFocusMode / GetTargetTypeStr logic.
---------------------------------------------------------
-- FIX: the scan below walks every marker/region in the project and used to
-- run up to ~10 times per frame (signature, mode checks, status line, panels).
-- It is now executed once per defer frame and the result is shared.
local frame_counter = 0
local region_marker_cache_frame = -1
local region_marker_cache_regions, region_marker_cache_markers = {}, {}

local function ScanSelectedRegionMarkerData()
    local regions, markers = {}, {}
    if not (RPR.GetNumRegionsOrMarkers and RPR.GetRegionOrMarker and RPR.GetRegionOrMarkerInfo_Value) then
        return regions, markers
    end

    local marker_count, region_count = RPR.GetNumRegionsOrMarkers(0)
    local total = (marker_count or 0) + (region_count or 0)

    -- 1순위: 직접 클릭된(선택된) 마커/리전 감지
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

    -- 2순위: 선택된 게 없다면 타임셀렉션 영역 안의 마커/리전 감지
    if #regions == 0 and #markers == 0 then
        local ts_start, ts_end = RPR.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if ts_end > ts_start then
            local idx = 0
            while true do
                local retval, is_region, pos, region_end, name = RPR.EnumProjectMarkers3(0, idx)
                if retval == 0 then break end
                if is_region then
                    if pos < ts_end and region_end > ts_start then
                        regions[#regions + 1] = { pointer = nil, name = name or "" }
                    end
                elseif pos >= ts_start and pos <= ts_end then
                    markers[#markers + 1] = { pointer = nil, name = name or "" }
                end
                idx = idx + 1
            end
        end
    end

    return regions, markers
end

local function GetSelectedRegionMarkerData()
    if region_marker_cache_frame ~= frame_counter then
        region_marker_cache_regions, region_marker_cache_markers = ScanSelectedRegionMarkerData()
        region_marker_cache_frame = frame_counter
    end
    return region_marker_cache_regions, region_marker_cache_markers
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
            -- TCP(트랙 패널)를 직접 클릭한 경우에만 Track 모드 진입
            if mouse_down_track or track_selection_changed or RPR.CountSelectedTracks(0) > 0 then
                current_mode = "Track"
                mode_focus_active = true
            end
        elseif mouse_down_context == "Timeline" then
            current_mode = "Region/Marker"
            mode_focus_active = true
        else
            -- Arrange 영역 및 트랙 아래 빈 공간:
            -- 아이템이 1개 이상 선택되어 있으면 Item, 없으면 무조건 No Selection (mode_focus_active = false)
            if RPR.CountSelectedMediaItems(0) > 0 then
                current_mode = "Item"
                mode_focus_active = true
            else
                mode_focus_active = false
            end
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

-- FIX: the status line can only show a few hundred characters, so stop
-- collecting names once the text is far longer than any window can display.
-- Previously every selected item/track name was fetched on every frame.
local STATUS_NAMES_MAX_BYTES = 2000

local function GetTargetNamesStr(mode)
    local names, total_bytes, truncated = {}, 0, false
    local count, get_name = 0, nil
    if mode == "Item" then
        count = RPR.CountSelectedMediaItems(0)
        get_name = function(i) return GetFirstItemName(RPR.GetSelectedMediaItem(0, i)) end
    elseif mode == "Track" then
        count = RPR.CountSelectedTracks(0)
        get_name = function(i) return GetFirstTrackName(RPR.GetSelectedTrack(0, i)) end
    end
    for i = 0, count - 1 do
        local name = get_name(i)
        names[#names + 1] = name
        total_bytes = total_bytes + #name + 2
        if total_bytes > STATUS_NAMES_MAX_BYTES and i < count - 1 then
            truncated = true
            break
        end
    end
    local text = table.concat(names, ", ")
    if truncated then text = text .. ", ..." end
    return text
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

    -- FIX: the rendered width grows with the number of characters, so the
    -- longest prefix that fits is found by binary search. The previous linear
    -- scan measured the whole string once per character on every frame.
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

-- Read the live REAPER selection. This function is intentionally separate
-- from BuildSelectionStatus so the UI can display a committed snapshot instead
-- of following REAPER's mouse-down selection immediately.
local function CaptureSelectionStatus()
    local item_count = RPR.CountSelectedMediaItems(0)
    local track_count = RPR.CountSelectedTracks(0)

    if current_mode == "Item" and IsCurrentModeActive() and item_count > 0 then
        local item = RPR.GetSelectedMediaItem(0, 0)
        local item_type = GetTargetTypeStr("Item", item)
        local names_str = GetTargetNamesStr("Item")
        return string.format("Selected %02d Items (%s: ", item_count, item_type), names_str, ")"
    elseif current_mode == "Track" and IsCurrentModeActive() and track_count > 0 then
        local track = RPR.GetSelectedTrack(0, 0)
        local track_type = GetTargetTypeStr("Track", track)
        local names_str = GetTargetNamesStr("Track")
        return string.format("Selected %02d Tracks (%s: ", track_count, track_type), names_str, ")"
    elseif current_mode == "Region/Marker" and IsCurrentModeActive() then
        local regions, markers = GetSelectedRegionMarkerData()
        local total = #regions + #markers
        if total > 0 then
            local kind = (#regions > 0 and #markers > 0) and "Regions/Markers"
                or ((#regions > 0) and "Regions" or "Markers")

            local names = {}
            for _, r in ipairs(regions) do names[#names + 1] = (r.name ~= "" and r.name or "Unnamed") end
            for _, m in ipairs(markers) do names[#names + 1] = (m.name ~= "" and m.name or "Unnamed") end
            local names_str = table.concat(names, ", ")

            return string.format("Selected %02d %s (", total, kind), names_str, ")"
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

    -- 우측 200px 여백 확보 (원하는 여백 수치로 조절 가능)
    local safe_width = math.max(1, available_width - S(200))

    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), 0xBFC5CCFF)
    if selected_name == nil then
        RPR.ImGui_Text(ctx, FitTextToWidth(prefix, available_width))
    else
        local prefix_width = select(1, RPR.ImGui_CalcTextSize(ctx, prefix))
        local suffix_width = select(1, RPR.ImGui_CalcTextSize(ctx, suffix))

        -- 이름이 그려질 수 있는 최대 픽셀 너비
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
    RPR.ImGui_PopStyleColor(ctx)
end

---------------------------------------------------------
-- Panels: visibility, order, widths
---------------------------------------------------------
-- Panels are drawn side by side as child windows with draggable splitters in
-- between. Each panel always gets at least its minimum width, so controls can
-- never overlap; when the window is too narrow for all visible panels, a
-- horizontal scrollbar appears instead.
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

-- Panels shown by default. Hidden panels can be turned on in Settings.
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

-- Panel widths in pixels at 100% zoom (new "px_" keys; the old weight-based
-- keys are ignored).
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

-- Only the panels that make sense for the current selection are shown:
-- Item Tools appears for items only.
local function GetVisiblePanelIds()
    local ids = {}
    for _, id in ipairs(panel_order) do
        if panel_visible[id] then
            ids[#ids + 1] = id
        end
    end
    return ids
end

-- Every panel has its own width (never below its minimum). If the window is
-- wider than all panels together, the spare room is shared proportionally
-- ("fill" > 1). If it is narrower, the widths are kept and the strip scrolls.
local function ComputePanelWidths(ids, total_width)
    -- Every panel, Color included, keeps the same share of the window: spare
    -- room is handed out in proportion to the panel widths.
    local widths, sum = {}, 0
    for _, id in ipairs(ids) do
        widths[id] = math.max(PANEL_MIN_WIDTHS[id], panel_base_widths[id]) * JKK_UI_SCALE
        sum = sum + widths[id]
    end
    local fill = (sum > 0) and (total_width / sum) or 1
    for _, id in ipairs(ids) do widths[id] = math.floor(widths[id] * fill) end
    return widths, fill
end

-- Width (pixels at 100% zoom) that all enabled panels need side by side. Item
-- Tools is counted even while hidden, so the zoom does not jump when the
-- selection changes between items and tracks.
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
    -- Keep the visible label clean; the panel letter is only used internally
    -- for drag/drop identity and the ImGui ID.
    local label = panel_titles[panel_id] .. "##PanelHeader_" .. panel_id

    -- Flat, compact header that doubles as the drag handle for reordering.
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), 0x00000000)
    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), 0xE3DB8EFF)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FramePadding(), 0, 0)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
    RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_FrameBorderSize(), 0)
    RPR.ImGui_Button(ctx, label, math.max(1, available_width), S(15))
    RPR.ImGui_PopStyleVar(ctx, 3)
    RPR.ImGui_PopStyleColor(ctx, 4)
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

-- Draggable divider between two panels. Moving it trades width between the
-- two neighbours only; neither can go below its minimum.
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
    local color = active and 0x068FC3FF or (hovered and 0x6A6A6AFF or 0x3C3C3CFF)
    RPR.ImGui_DrawList_AddLine(RPR.ImGui_GetWindowDrawList(ctx),
        line_x, min_y + S(4), line_x, max_y - S(4), color, active and 2 or 1)

    if active then
        local delta_x = RPR.ImGui_GetMouseDelta(ctx)
        if delta_x and delta_x ~= 0 then
            -- FIX: the divider always responds. The left panel grows or shrinks
            -- with the mouse; the right panel gives up the same amount until it
            -- reaches its minimum, after which the strip simply gets wider.
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
-- Settings popup (zoom, panels, layout, project shortcuts)
---------------------------------------------------------
local SETTINGS_POPUP_ID = "##JKK_ReaTools_Settings"

local function DrawSettingsPopup()
    if not RPR.ImGui_BeginPopup(ctx, SETTINGS_POPUP_ID) then return end

    RPR.ImGui_TextDisabled(ctx, "Panels")
    local panels_changed = false
    for _, id in ipairs(panel_ids) do
        local changed, value = RPR.ImGui_Checkbox(ctx, panel_titles[id] .. "##Show_" .. id, panel_visible[id])
        if changed then panel_visible[id] = value; panels_changed = true end
        if id == "D" and RPR.ImGui_IsItemHovered(ctx) then
            RPR.ImGui_SetTooltip(ctx, "Shown only while items are the active selection.")
        end
    end
    if panels_changed then SavePanelVisibility() end
    if RPR.ImGui_Button(ctx, "Reset Layout##JKK_ResetLayout") then ResetLayout() end
    if RPR.ImGui_IsItemHovered(ctx) then
        RPR.ImGui_SetTooltip(ctx, "Default panels, order and widths.")
    end

    RPR.ImGui_Separator(ctx)
    RPR.ImGui_TextDisabled(ctx, "UI Zoom")
    local zoom_changed = false
    local value_changed, new_value

    value_changed, new_value = RPR.ImGui_Checkbox(ctx, "Auto", ui_zoom.auto)
    if value_changed then ui_zoom.auto = new_value; zoom_changed = true end
    if RPR.ImGui_IsItemHovered(ctx) then
        RPR.ImGui_SetTooltip(ctx, "Zoom the whole UI so all panels fit the window.\nOff: fixed size, set by the slider.")
    end
    RPR.ImGui_SameLine(ctx)
    RPR.ImGui_BeginDisabled(ctx, not ui_zoom.auto)
    value_changed, new_value = RPR.ImGui_Checkbox(ctx, "Fit height", ui_zoom.follow_height)
    if value_changed then ui_zoom.follow_height = new_value; zoom_changed = true end
    if RPR.ImGui_IsItemHovered(ctx, RPR.ImGui_HoveredFlags_AllowWhenDisabled()) then
        RPR.ImGui_SetTooltip(ctx, "Also shrink when the window is too short for the rows.")
    end
    RPR.ImGui_EndDisabled(ctx)

    -- Applied on release so the popup does not resize under the mouse.
    RPR.ImGui_SetNextItemWidth(ctx, S(140))
    local percent = math.floor((ui_zoom.pending_size or ui_zoom.size) * 100 + 0.5)
    value_changed, new_value = RPR.ImGui_SliderInt(ctx, "##JKK_UIZoomSize", percent, 60, 200, "Size %d%%")
    if value_changed then ui_zoom.pending_size = new_value / 100 end
    if RPR.ImGui_IsItemDeactivated(ctx) and ui_zoom.pending_size then
        ui_zoom.size = ui_zoom.pending_size
        ui_zoom.pending_size = nil
        zoom_changed = true
    end
    if RPR.ImGui_IsItemClicked(ctx, 1) then
        ui_zoom.size = UI_ZOOM_DEFAULTS.size
        ui_zoom.pending_size = nil
        zoom_changed = true
    end
    if RPR.ImGui_IsItemHovered(ctx) then
        RPR.ImGui_SetTooltip(ctx, "Personal size on top of the automatic zoom.\nRight-click: 100%")
    end
    RPR.ImGui_SameLine(ctx)
    RPR.ImGui_TextDisabled(ctx, string.format("%.1fpx", ui_font_size))
    if RPR.ImGui_Button(ctx, "Reset Zoom##JKK_ResetZoom") then
        ui_zoom.auto = UI_ZOOM_DEFAULTS.auto
        ui_zoom.follow_height = UI_ZOOM_DEFAULTS.follow_height
        ui_zoom.size = UI_ZOOM_DEFAULTS.size
        ui_zoom.pending_size = nil
        zoom_changed = true
    end
    if zoom_changed then SaveZoomSettings() end

    RPR.ImGui_Separator(ctx)
    if RPR.ImGui_MenuItem(ctx, "Peaks Display Settings") then
        RPR.Main_OnCommand(42074, 0)
    end
    if RPR.ImGui_MenuItem(ctx, "Open Project Directory") then
        local command_id = RPR.NamedCommandLookup("_S&M_OPEN_PRJ_PATH")
        if command_id ~= 0 then
            RPR.Main_OnCommand(command_id, 0)
        else
            RPR.ShowMessageBox("해당 커스텀/SWS 액션을 찾을 수 없습니다.", "오류", 0)
        end
    end

    RPR.ImGui_EndPopup(ctx)
end

-- Status line with the Settings button on its right end.
local function DrawTopBar()
    -- Buttons sit at the left end of the status line so they can never be
    -- pushed out of view: [Home] [Memo] [Settings]  status text...
    local home_cmd_id = RPR.NamedCommandLookup("_RS7df81f4a0eea01208f22396bdf933be8c6a3fa28")
    if home_cmd_id ~= 0 then
        RPR.ImGui_SameLine(ctx, 0, S(4))
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), 0xFFEA70FF)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), 0xFFE048FF)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), 0xE5CB3BFF)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), 0x053359FF)

        if RPR.ImGui_SmallButton(ctx, "Home##JKK_HomeButton") then
            RPR.Main_OnCommand(home_cmd_id, 0)
        end

        RPR.ImGui_PopStyleColor(ctx, 4)
    end
    RPR.ImGui_SameLine(ctx, 0, S(4))
    local memo_on = panel_visible.A
    if memo_on then
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Button(), 0x24866FFF)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
        RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_ButtonActive(), 0x1F735FFF)
    end
    local memo_clicked = RPR.ImGui_SmallButton(ctx, "Memo##JKK_MemoToggle")
    if memo_on then RPR.ImGui_PopStyleColor(ctx, 3) end
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
end

---------------------------------------------------------
-- Panel A: Project Memo
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
        -- FIX: project ext state lives in the .rpp file, but writing it does not
        -- flag the project as modified, so the memo was silently lost when the
        -- project was closed without another change.
        if RPR.MarkProjectDirty then RPR.MarkProjectDirty(0) end
    end
end

---------------------------------------------------------
-- Panel B: Context Controller / Actions
---------------------------------------------------------
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
    end

    RPR.ImGui_EndDisabled(ctx)
end

---------------------------------------------------------
-- Panel C: Rename (all modes) + Take settings (items only)
---------------------------------------------------------
local function DrawPanelC()
    local mode_active = IsCurrentModeActive()

    if renamer_lite_module and renamer_lite_module.JKK_RenamerLite_Draw then
        renamer_lite_module.JKK_RenamerLite_Draw(
            ctx, current_mode, mode_active, renamer_input_font
        )
    else
        RPR.ImGui_Text(ctx, "Renamer Lite module is unavailable.")
    end

    -- Take Channel / Pitch Mode / Item Info only apply to items, so they are
    -- only shown in Item mode. They sit in the shared bottom block, so their
    -- separator and last row line up with Item Tools.
    if current_mode == "Item" and item_module and item_module.JKK_ItemTool_DrawMetadata then
        JKK_DrawLowerBlock(ctx, "C", function()
            RPR.ImGui_BeginDisabled(ctx, not mode_active)
            item_module.JKK_ItemTool_DrawMetadata(ctx)
            RPR.ImGui_EndDisabled(ctx)
        end)
    end
end

---------------------------------------------------------
-- Panel D: Item Editing Utilities (items only)
---------------------------------------------------------
local function DrawPanelD()
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
-- Panel E: Color (wheel + recent colors)
---------------------------------------------------------
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
    -- FIX (screen shaking): every size is a whole pixel. Fractional sizes made
    -- the content overflow by less than a pixel, so scrollbars kept appearing
    -- and disappearing and the panels jumped.
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
    local content_width = splitters_total
    for _, id in ipairs(ids) do content_width = content_width + widths[id] end

    -- Leave room for the horizontal scrollbar only when it is needed.
    local needs_scroll = false
    local panel_height = strip_height
    local strip_flags = RPR.ImGui_WindowFlags_NoScrollbar() | RPR.ImGui_WindowFlags_NoScrollWithMouse()

    -- Scrollbars are disabled entirely unless the panels really do not fit.
    local strip_flags = needs_scroll
        and RPR.ImGui_WindowFlags_HorizontalScrollbar()
        or (RPR.ImGui_WindowFlags_NoScrollbar() | RPR.ImGui_WindowFlags_NoScrollWithMouse())
    -- FIX (crash while dragging): in ReaImGui, BeginChild returns false when the
    -- child is not visible (e.g. scrolled out of view) and EndChild must then
    -- NOT be called. Contents and EndChild are now inside the "if".
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
-- Main UI
---------------------------------------------------------
local function Main()
    frame_counter = frame_counter + 1
    -- FIX: keep the previous frame's count. It was only set once at startup, so
    -- Item Tools treated every frame as a project change and the Stretch slider
    -- snapped back to 1.0 whenever it was released.
    prev_project_state_count = current_project_state_count
    current_project_state_count = RPR.GetProjectStateChangeCount(0)

    local current_project_ptr = RPR.EnumProjects(-1)
    if current_project_ptr ~= last_project_ptr then
        LoadProjectNote()
        last_project_ptr = current_project_ptr
    end

    UpdateFocusMode()
    UpdateSelectionStatusCache()

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
        -- Derive the zoom factor from the real window size (floating or docked)
        -- before anything is drawn, so every size below uses the same factor.
        local window_width, window_height = RPR.ImGui_GetWindowSize(ctx)
        UpdateUIScale(window_width, window_height, GetDesignWidth())

        RPR.ImGui_PushFont(ctx, font, ui_font_size)
        RPR.ImGui_PushStyleVar(ctx, RPR.ImGui_StyleVar_ItemSpacing(), S(8), S(6))

        DrawTopBar()
        RPR.ImGui_Separator(ctx)
        DrawPanels()

        RPR.ImGui_PopStyleVar(ctx, 1)
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
            -- FIX: Ctrl+Shift+Z used to match both branches and ran Undo and
            -- Redo in the same frame, which cancelled out. Only one runs now.
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

-- FIX: remove the red Guide preview items of Item Tools when the script stops;
-- they used to stay in the project.
RPR.atexit(function()
    if item_module and item_module.JKK_ItemTool_Cleanup then
        pcall(item_module.JKK_ItemTool_Cleanup)
    end
end)

RPR.defer(Main)
