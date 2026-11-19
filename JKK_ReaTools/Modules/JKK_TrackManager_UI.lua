--========================================================
-- @title JKK_TrackManager_UI
-- @author Junki Kim
-- @noindex
-- Shared UI for JKK Track Manager and JKK ReaTools panel D.
--========================================================

local M = {}

function M.Create(options)
    options = options or {}
local RPR = reaper

----------------------------------------------------------------------
-- 📦 모듈 로드 (JKK_TrackManager_Core & JKK_Theme)
----------------------------------------------------------------------
local script_dir    = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local installed_dir = RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/"

local function ResolveModulePath(file_name)
    local candidates = {
        script_dir .. "Modules/" .. file_name,
        script_dir .. "modules/" .. file_name,
        script_dir .. "../Modules/" .. file_name,
        script_dir .. "../modules/" .. file_name,
        installed_dir .. "Modules/" .. file_name,
        RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/Modules/" .. file_name,
    }
    for _, path in ipairs(candidates) do
        if RPR.file_exists(path) then
            return path
        end
    end
    return script_dir .. "Modules/" .. file_name
end

local Core = options.core or dofile(ResolveModulePath("JKK_TrackManager_Core.lua"))

local theme_path = ResolveModulePath("JKK_Theme_Core.lua")
local Theme = options.theme or ((RPR.file_exists(theme_path) and dofile(theme_path)) or {
    ApplyTheme       = function() return 0, 0 end,
    PushButton       = function() end,
    PopButton        = function() end,
    PushText         = function() end,
    PopText          = function() end,
    PushFont         = function() end,
    PopFont          = function() end,
    GetColor         = function() return 0xEDEDEDFF end,
    GetSplitterColor = function() return 0x3C3C3CFF end,
})

----------------------------------------------------------------------
-- 📋 선언적 설정 및 상수
----------------------------------------------------------------------
local APP = {
    TITLE       = "JKK Track Manager",
    CTX_NAME    = "JKK_TrackManager_Ctx",
    UNDO_ACT    = "JKK Track Manager: Toggle Track Active",
    UNDO_PROP   = "JKK Track Manager: Modify Track Property",
    UNDO_RENAME = "JKK Track Manager: Rename Track",
}

local REAPER_CMD = {
    UNSELECT_ALL_TRACKS = 40297,
    SCROLL_TO_SELECTED  = 40913,
    TRANSPORT_PLAY_STOP = 40044,
    EDIT_UNDO           = 40029,
    EDIT_REDO           = 40030,
}

local UI_SCALE = 1.0

local LAYOUT = {
    DEFAULT_W           = 920,
    DEFAULT_H           = 540,
    MIN_W               = 540,
    MIN_H               = 260,
    -- A small safety pixel beside the list's vertical scrollbar.
    RIGHT_SCROLLBAR_PAD = 1,
    ROW_PAD_Y           = 4,
    HEADER_PAD_Y        = 4,
    INDENT_PER_DEPTH    = 16,
    FOLDER_BTN_W        = 20,
    FOLDER_BTN_GAP      = 4,
    SWATCH_SIZE         = 14,
    NAME_LEFT_PAD       = 6,
    NAME_RIGHT_PAD      = 8,
    GLOBAL_ITEM_GAP     = 6,
    FALLBACK_SCROLLBAR  = 14,
    SEL_INDICATOR_W     = 3,
}

-- USER CONFIG: TRACK MANAGER COLUMN WIDTHS
-- ratio: initial relative share of the available table width (not pixels)
-- min:   minimum preferred width in pixels, before the UI scale changes
-- max:   preferred maximum in pixels; 0 = unlimited
-- If a very narrow window cannot fit all minimum widths, every column scales
-- down proportionally instead of opening a horizontal scrollbar.
-- Extra space beyond the sum of finite maximums is assigned to Track Name.
local COLUMNS = {
    { id = "active", label = "Active",     short = "Act",   ratio = 0.085, min = 27, max = 70,  is_cb = true  },
    { id = "color",  label = "Color",      short = "Clr",   ratio = 0.060, min = 20, max = 60,  is_cb = false },
    { id = "no",     label = "No.",        short = "No.",   ratio = 0.060, min = 22, max = 60,  is_cb = false },
    { id = "name",   label = "Track Name", short = "Name",  ratio = 0.325, min = 74, max = 0,   is_cb = false },
    { id = "tcp",    label = "TCP",        short = "TCP",   ratio = 0.0783, min = 22, max = 55, is_cb = true  },
    { id = "mcp",    label = "MCP",        short = "MCP",   ratio = 0.0783, min = 22, max = 55, is_cb = true  },
    { id = "solo",   label = "Solo",       short = "Solo",  ratio = 0.0783, min = 22, max = 55, is_cb = true  },
    { id = "mute",   label = "Mute",       short = "Mute",  ratio = 0.0783, min = 22, max = 55, is_cb = true  },
    { id = "fx",     label = "FX",         short = "FX",    ratio = 0.0783, min = 22, max = 55, is_cb = true  },
    { id = "arm",    label = "Arm",        short = "Arm",   ratio = 0.0785, min = 22, max = 55, is_cb = true  },
}

----------------------------------------------------------------------
-- 🎨 동적 팔레트 구성
----------------------------------------------------------------------
local function RGBA(r, g, b, a)
    if RPR.ImGui_ColorConvertDouble4ToU32 then
        return RPR.ImGui_ColorConvertDouble4ToU32(r / 255.0, g / 255.0, b / 255.0, (a or 255) / 255.0)
    end
    return ((r & 0xFF) << 24) | ((g & 0xFF) << 16) | ((b & 0xFF) << 8) | ((a or 255) & 0xFF)
end

local function BlendRGBA(col1, col2, t, alpha_override_255)
    if RPR.ImGui_ColorConvertU32ToDouble4 and RPR.ImGui_ColorConvertDouble4ToU32 then
        local r1, g1, b1, a1 = RPR.ImGui_ColorConvertU32ToDouble4(col1)
        local r2, g2, b2, a2 = RPR.ImGui_ColorConvertU32ToDouble4(col2)
        local out_a = alpha_override_255 and (alpha_override_255 / 255.0) or (a1 + (a2 - a1) * t)
        return RPR.ImGui_ColorConvertDouble4ToU32(
            r1 + (r2 - r1) * t,
            g1 + (g2 - g1) * t,
            b1 + (b2 - b1) * t,
            math.max(0, math.min(1, out_a))
        )
    end
    return col1
end

local function IsDarkColor(col)
    if RPR.ImGui_ColorConvertU32ToDouble4 then
        local r, g, b = RPR.ImGui_ColorConvertU32ToDouble4(col)
        local lum = 0.299 * r + 0.587 * g + 0.114 * b
        return lum < 0.5
    end
    return true
end

local function BuildDynamicPalette()
    local base_bg     = Theme.GetColor("base_bg")
    local ctrl_bg     = Theme.GetColor("control_bg")
    local text_main   = Theme.GetColor("text_main")
    local accent_main = Theme.GetColor("accent_main")
    local text_status = Theme.GetColor("status")
    local row_border  = Theme.GetSplitterColor(false, false)

    local is_dark  = IsDarkColor(base_bg)
    local red_tint = is_dark and RGBA(235, 95, 95, 255) or RGBA(190, 45, 45, 255)

    return {
        base_bg        = base_bg,
        ctrl_bg        = ctrl_bg,
        accent_main    = accent_main,
        header_bg      = BlendRGBA(base_bg, ctrl_bg, 0.85, 255),
        row_odd        = BlendRGBA(base_bg, ctrl_bg, 0.12, 255),
        row_even       = BlendRGBA(base_bg, ctrl_bg, 0.38, 255),
        sel_active     = BlendRGBA(base_bg, accent_main, 0.34, 255),
        sel_inactive   = BlendRGBA(base_bg, accent_main, 0.18, 255),
        row_border     = row_border,
        text_main      = text_main,
        text_status    = text_status,
        text_muted     = BlendRGBA(text_main, base_bg, 0.45, 255),
        text_inactive  = BlendRGBA(text_main, red_tint, 0.62, 255),
        default_swatch = ctrl_bg,
    }
end

----------------------------------------------------------------------
-- 🔧 상태 변수 및 API 호환성 헬퍼
----------------------------------------------------------------------
local ctx = nil
local g_hide_tcp, g_hide_mcp = Core.GetHideFlags()

-- 다중 선택, 드래그 및 REAPER 선택 위치 스크롤 추적 상태
local anchor_track            = nil
local is_dragging             = false
local drag_mode               = nil -- "normal" | "shift"
local drag_start_track        = nil
local drag_ctrl               = false
local last_drag_hovered_idx   = nil
local pre_drag_selected       = {}
local prev_sel_sig            = ""
local prev_last_touched       = nil
local pending_scroll_to_track = nil
local internal_sel_lock       = false

-- 더블클릭 인라인 트랙 이름 수정 상태
local renaming_track       = nil
local rename_buffer        = ""
local rename_focus_pending = false

local has_disabled_api = (RPR.ImGui_BeginDisabled ~= nil and RPR.ImGui_EndDisabled ~= nil)

local function IsCtrlDown(draw_ctx)
    if RPR.ImGui_Mod_Ctrl and RPR.ImGui_IsKeyDown(draw_ctx, RPR.ImGui_Mod_Ctrl()) then return true end
    if RPR.ImGui_Key_LeftCtrl and RPR.ImGui_IsKeyDown(draw_ctx, RPR.ImGui_Key_LeftCtrl()) then return true end
    if RPR.ImGui_Key_RightCtrl and RPR.ImGui_IsKeyDown(draw_ctx, RPR.ImGui_Key_RightCtrl()) then return true end
    return false
end

local function IsShiftDown(draw_ctx)
    if RPR.ImGui_Mod_Shift and RPR.ImGui_IsKeyDown(draw_ctx, RPR.ImGui_Mod_Shift()) then return true end
    if RPR.ImGui_Key_LeftShift and RPR.ImGui_IsKeyDown(draw_ctx, RPR.ImGui_Key_LeftShift()) then return true end
    if RPR.ImGui_Key_RightShift and RPR.ImGui_IsKeyDown(draw_ctx, RPR.ImGui_Key_RightShift()) then return true end
    return false
end

local function GetScrollbarWidth(draw_ctx)
    if RPR.ImGui_GetStyleVar and RPR.ImGui_StyleVar_ScrollbarSize then
        local ok, val = pcall(RPR.ImGui_GetStyleVar, draw_ctx, RPR.ImGui_StyleVar_ScrollbarSize())
        if ok and type(val) == "number" and val > 0 then
            return val
        end
    end
    return LAYOUT.FALLBACK_SCROLLBAR
end

-- UTF-8 안전 말줄임 텍스트 계산
local function FitTextToWidth(draw_ctx, text, max_width)
    if max_width <= 0 then return "" end
    local text_width = select(1, RPR.ImGui_CalcTextSize(draw_ctx, text))
    if text_width <= max_width then return text end

    local ellipsis = "..."
    local ellipsis_width = select(1, RPR.ImGui_CalcTextSize(draw_ctx, ellipsis))
    if ellipsis_width > max_width then return "" end

    local ok, char_count = pcall(utf8.len, text)
    if not ok or not char_count then
        local candidate = text
        while #candidate > 0 do
            candidate = candidate:sub(1, -2)
            if select(1, RPR.ImGui_CalcTextSize(draw_ctx, candidate .. ellipsis)) <= max_width then
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
        if select(1, RPR.ImGui_CalcTextSize(draw_ctx, candidate)) <= max_width then
            best = candidate
            low = count + 1
        else
            high = count - 1
        end
    end
    return best
end

----------------------------------------------------------------------
-- ✏️ 트랙 이름 인라인 수정 헬퍼
----------------------------------------------------------------------
local function CancelTrackRename()
    renaming_track       = nil
    rename_buffer        = ""
    rename_focus_pending = false
end

local function BeginTrackRename(tr, raw_name)
    is_dragging           = false
    drag_mode             = nil
    last_drag_hovered_idx = nil

    renaming_track       = tr
    rename_buffer        = raw_name or ""
    rename_focus_pending = true
end

local function CommitTrackRename(tr, new_name)
    if tr and RPR.ValidatePtr2(0, tr, "MediaTrack*") and Core.IsTrackActive(tr) then
        local _, old_name = RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, "", false)
        if old_name ~= new_name then
            RPR.Undo_BeginBlock()
            RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, new_name, true)
            RPR.TrackList_AdjustWindows(false)
            RPR.UpdateArrange()
            RPR.Undo_EndBlock(APP.UNDO_RENAME, -1)
        end
    end
    CancelTrackRename()
end

----------------------------------------------------------------------
-- 🔄 다중 선택 대상 조회 및 전역 Solo/Mute 해제
----------------------------------------------------------------------
local function GetBatchTargetTracks(clicked_tr)
    local targets = {}
    if RPR.IsTrackSelected(clicked_tr) and RPR.CountSelectedTracks(0) > 1 then
        local num_tracks = RPR.CountTracks(0)
        for i = 0, num_tracks - 1 do
            local tr = RPR.GetTrack(0, i)
            if RPR.IsTrackSelected(tr) then
                targets[#targets + 1] = tr
            end
        end
    else
        targets[1] = clicked_tr
    end
    return targets
end

local function ClearAllTracksSolo()
    local num_tracks = RPR.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local tr = RPR.GetTrack(0, i)
        if RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SOLO) ~= 0 then
            RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SOLO, 0)
        end
    end
end

local function ClearAllTracksMute()
    local num_tracks = RPR.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local tr = RPR.GetTrack(0, i)
        if Core.IsTrackActive(tr) and RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.MUTE) ~= 0 then
            RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.MUTE, 0)
        end
    end
end

----------------------------------------------------------------------
-- 🌟 REAPER 선택 변경 감지 -> 앵커 동기화 및 위치 스크롤 예약
----------------------------------------------------------------------
local function SyncSelectionState()
    local num_tracks = RPR.CountTracks(0)
    local sel_tracks = {}
    local sel_ids = {}

    for i = 0, num_tracks - 1 do
        local tr = RPR.GetTrack(0, i)
        if RPR.IsTrackSelected(tr) then
            sel_tracks[#sel_tracks + 1] = tr
            sel_ids[#sel_ids + 1] = tostring(i)
        end
    end

    local sig = table.concat(sel_ids, ",")
    local last_touched = RPR.GetLastTouchedTrack()
    local sel_changed = (sig ~= prev_sel_sig)
    local touch_changed = (last_touched ~= prev_last_touched)

    if sel_changed or touch_changed then
        prev_sel_sig = sig
        prev_last_touched = last_touched

        if #sel_tracks == 1 then
            anchor_track = sel_tracks[1]
        elseif #sel_tracks > 1 then
            local anchor_still_selected = false
            for _, st in ipairs(sel_tracks) do
                if st == anchor_track then
                    anchor_still_selected = true
                    break
                end
            end
            if not anchor_still_selected then
                anchor_track = sel_tracks[1]
            end
        else
            anchor_track = nil
        end

        if not internal_sel_lock and not is_dragging and #sel_tracks > 0 then
            local scroll_target = nil
            if last_touched and RPR.IsTrackSelected(last_touched) then
                scroll_target = last_touched
            else
                scroll_target = sel_tracks[1]
            end
            pending_scroll_to_track = scroll_target
        end
    end

    internal_sel_lock = false
end

----------------------------------------------------------------------
-- 📐 동적 컬럼 레이아웃 및 렌더링 헬퍼
----------------------------------------------------------------------
local function ComputeColumnLayout(draw_ctx, start_x, avail_w)
    -- Header and body use the same column positions. The scrollbar is reserved
    -- inside the table width instead of forcing a fixed (760px) virtual canvas.
    local scrollbar_w = GetScrollbarWidth(draw_ctx)
    local usable_w = math.max(1, avail_w - scrollbar_w - LAYOUT.RIGHT_SCROLLBAR_PAD)
    local frame_h = RPR.ImGui_GetFrameHeight(draw_ctx)
    local widths, limits, pending = {}, {}, {}
    local minimum_total, ratio_total = 0, 0

    for i, col in ipairs(COLUMNS) do
        local minimum = col.min * UI_SCALE
        if col.is_cb then minimum = math.max(minimum, frame_h + 2) end
        if col.id == "color" then minimum = math.max(minimum, LAYOUT.SWATCH_SIZE + 4) end
        local maximum = (col.max and col.max > 0) and (col.max * UI_SCALE) or math.huge
        maximum = math.max(minimum, maximum)
        limits[i] = { minimum = minimum, maximum = maximum }
        minimum_total = minimum_total + minimum
        pending[i] = true
        ratio_total = ratio_total + math.max(0.0001, col.ratio or 1)
    end

    if usable_w < minimum_total then
        -- Even at the configured panel minimum, user zoom can exceed the
        -- physical space. Compress proportionally rather than scroll sideways.
        local k = usable_w / minimum_total
        for i = 1, #COLUMNS do widths[i] = limits[i].minimum * k end
    else
        local remaining = usable_w
        local remaining_ratio = ratio_total
        for _ = 1, #COLUMNS do
            local changed = false
            for i, col in ipairs(COLUMNS) do
                if pending[i] then
                    local ratio = math.max(0.0001, col.ratio or 1)
                    local requested = remaining * ratio / math.max(0.0001, remaining_ratio)
                    local limit = limits[i]
                    if requested < limit.minimum or requested > limit.maximum then
                        local clamped = math.max(limit.minimum, math.min(limit.maximum, requested))
                        widths[i] = clamped
                        remaining = remaining - clamped
                        remaining_ratio = remaining_ratio - ratio
                        pending[i] = false
                        changed = true
                    end
                end
            end
            if not changed then break end
        end
        for i, col in ipairs(COLUMNS) do
            if pending[i] then
                widths[i] = remaining * math.max(0.0001, col.ratio or 1) / math.max(0.0001, remaining_ratio)
            end
        end
        local used = 0
        for _, w in ipairs(widths) do used = used + w end
        -- Prefer filling the panel over leaving an empty right-hand gutter.
        widths[4] = widths[4] + usable_w - used
    end

    local map, cur_x = {}, start_x
    for i, col in ipairs(COLUMNS) do
        local w = math.max(1, widths[i])
        map[col.id] = {x = cur_x, w = w, label = col.label, short = col.short}
        cur_x = cur_x + w
    end
    return map
end

local function DrawCenteredHeader(draw_ctx, info)
    local available = math.max(0, info.w - 3)
    local label = info.label
    if select(1, RPR.ImGui_CalcTextSize(draw_ctx, label)) > available then
        label = info.short
    end
    if select(1, RPR.ImGui_CalcTextSize(draw_ctx, label)) > available then
        label = FitTextToWidth(draw_ctx, label, available)
    end
    local text_w = select(1, RPR.ImGui_CalcTextSize(draw_ctx, label))
    RPR.ImGui_SetCursorPosX(draw_ctx, info.x + math.max(0, (info.w - text_w) * 0.5))
    RPR.ImGui_Text(draw_ctx, label)
    if label ~= info.label and RPR.ImGui_IsItemHovered(draw_ctx) then
        RPR.ImGui_SetTooltip(draw_ctx, info.label)
    end
end

-- Toolbar layout: fixed-height row, labels vertically aligned to button frame.
-- The standalone-launch button hugs the right content edge in embedded mode.
local function DrawTopBar(draw_ctx, embedded, on_open)
    Theme.PushFont(draw_ctx, UI_SCALE, "topbar")

    local gap = LAYOUT.GLOBAL_ITEM_GAP * UI_SCALE
    local avail = math.max(1, select(1, RPR.ImGui_GetContentRegionAvail(draw_ctx)))
    local start_x = RPR.ImGui_GetCursorPosX(draw_ctx)
    local row_y = RPR.ImGui_GetCursorPosY(draw_ctx)
    local row_h = RPR.ImGui_GetFrameHeight(draw_ctx)
    local text_h = RPR.ImGui_GetTextLineHeight(draw_ctx)
    local check_w = row_h -- the square part of a checkbox without its label
    local check_gap = 4 * UI_SCALE
    local button_label = "Track Manager"
    local has_button = embedded and on_open ~= nil

    local function CheckboxWidth(label)
        return check_w + check_gap + select(1, RPR.ImGui_CalcTextSize(draw_ctx, label))
    end
    local function ButtonWidth(label)
        return 16 * UI_SCALE + select(1, RPR.ImGui_CalcTextSize(draw_ctx, label))
    end

    local tcp_label, mcp_label = "Hide in TCP when deactivated", "Hide in MCP when deactivated"
    local gaps = has_button and 2 or 1
    local function RequiredWidth()
        return CheckboxWidth(tcp_label) + CheckboxWidth(mcp_label)
            + (has_button and ButtonWidth(button_label) or 0) + gap * gaps
    end
    if RequiredWidth() > avail then
        tcp_label, mcp_label = "Hide in TCP", "Hide in MCP"
    end
    if RequiredWidth() > avail then
        tcp_label, mcp_label = "TCP", "MCP"
    end

    -- Text is rendered separately from the native checkbox square so its
    -- baseline is explicitly centered against the Track Manager button.
    -- Clicking either the square or its text toggles the same option.
    local function DrawToggle(id, label, current, pos_x)
        RPR.ImGui_SetCursorPosX(draw_ctx, pos_x)
        RPR.ImGui_SetCursorPosY(draw_ctx, row_y)
        local changed, new_value = RPR.ImGui_Checkbox(draw_ctx, "##" .. id, current)
        local text_x = pos_x + check_w + check_gap
        RPR.ImGui_SameLine(draw_ctx, 0, 0)
        RPR.ImGui_SetCursorPosX(draw_ctx, text_x)
        RPR.ImGui_SetCursorPosY(draw_ctx, row_y + math.max(0, (row_h - text_h) * 0.5))
        RPR.ImGui_Text(draw_ctx, label)
        if RPR.ImGui_IsItemClicked(draw_ctx, 0) then
            changed, new_value = true, not current
        end
        return changed, new_value
    end

    local cursor_x = start_x
    local changed_tcp, new_tcp = DrawToggle("JKK_GlobalHideTCP", tcp_label, g_hide_tcp, cursor_x)
    if changed_tcp then
        g_hide_tcp = new_tcp
        Core.SetHideFlags(g_hide_tcp, g_hide_mcp)
        Core.EnforceInactive(g_hide_tcp, g_hide_mcp)
    end
    cursor_x = cursor_x + CheckboxWidth(tcp_label) + gap
    RPR.ImGui_SameLine(draw_ctx, 0, 0)
    local changed_mcp, new_mcp = DrawToggle("JKK_GlobalHideMCP", mcp_label, g_hide_mcp, cursor_x)
    if changed_mcp then
        g_hide_mcp = new_mcp
        Core.SetHideFlags(g_hide_tcp, g_hide_mcp)
        Core.EnforceInactive(g_hide_tcp, g_hide_mcp)
    end

    if has_button then
        local used_by_checks = CheckboxWidth(tcp_label) + CheckboxWidth(mcp_label) + gap
        local remaining = math.max(1, avail - used_by_checks - gap)
        local btn_w = math.min(ButtonWidth(button_label), remaining)
        RPR.ImGui_SameLine(draw_ctx, 0, 0)
        RPR.ImGui_SetCursorPosX(draw_ctx, start_x + avail - btn_w)
        RPR.ImGui_SetCursorPosY(draw_ctx, row_y)
        Theme.PushButton(draw_ctx, "primary")
        if RPR.ImGui_Button(draw_ctx, button_label .. "##JKK_OpenTrackManager", btn_w, row_h) then
            on_open()
        end
        Theme.PopButton(draw_ctx)
        if RPR.ImGui_IsItemHovered(draw_ctx) then
            RPR.ImGui_SetTooltip(draw_ctx, "Open Track Manager in a standalone window")
        end
    end

    Theme.PopFont(draw_ctx)
end

local function DrawCellCheckbox(draw_ctx, id, value, col_info, disabled)
    local cb_size = RPR.ImGui_GetFrameHeight(draw_ctx)
    RPR.ImGui_SetCursorPosX(draw_ctx, col_info.x + (col_info.w - cb_size) * 0.5)

    if disabled and has_disabled_api then
        RPR.ImGui_BeginDisabled(draw_ctx, true)
    end

    local changed, new_val = RPR.ImGui_Checkbox(draw_ctx, id, value)

    if disabled and has_disabled_api then
        RPR.ImGui_EndDisabled(draw_ctx)
    end

    if disabled then
        return false, value
    end
    return changed, new_val
end

local function BuildVisibleRows()
    local num_tracks = RPR.CountTracks(0)
    local visible_rows = {}
    local track_to_vis_idx = {}
    local skip_depth = -1

    for i = 0, num_tracks - 1 do
        local tr = RPR.GetTrack(0, i)
        local depth = RPR.GetTrackDepth(tr)

        if skip_depth ~= -1 and depth <= skip_depth then
            skip_depth = -1
        end

        if skip_depth == -1 then
            local is_folder = (RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.FOLDER_DEPTH) == Core.FOLDER_STATE.IS_PARENT)
            local compact   = RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.FOLDER_COMP)
            if is_folder and compact == Core.FOLDER_STATE.COLLAPSED then
                skip_depth = depth
            end

            local vis_idx = #visible_rows + 1
            visible_rows[vis_idx] = {
                tr        = tr,
                track_idx = i,
                depth     = depth,
                is_folder = is_folder,
                compact   = compact,
                is_active = Core.IsTrackActive(tr),
                is_mute   = RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.MUTE) > 0,
            }
            track_to_vis_idx[tr] = vis_idx
        end
    end

    return visible_rows, track_to_vis_idx
end

local function ResolveAnchorVisIdx(visible_rows, track_to_vis_idx)
    if anchor_track and track_to_vis_idx[anchor_track] then
        return track_to_vis_idx[anchor_track]
    end
    for idx, row in ipairs(visible_rows) do
        if RPR.IsTrackSelected(row.tr) then
            anchor_track = row.tr
            return idx
        end
    end
    return nil
end

----------------------------------------------------------------------
-- 🖥️ GUI 메인 루프
----------------------------------------------------------------------

local function Draw(draw_ctx, draw_options)
    draw_options = draw_options or {}
    ctx = draw_ctx
    local embedded = draw_options.embedded == true
    UI_SCALE = draw_options.scale or 1.0

    g_hide_tcp, g_hide_mcp = Core.GetHideFlags()
    Core.EnforceInactive(g_hide_tcp, g_hide_mcp)
    SyncSelectionState()
    local palette = BuildDynamicPalette()
    if renaming_track and not RPR.ValidatePtr2(0, renaming_track, "MediaTrack*") then
        CancelTrackRename()
    end

        -- 1. Unified toolbar: checkboxes + standalone launcher, one line.
        DrawTopBar(ctx, embedded, draw_options.onOpenStandalone)

        -- No separator or extra spacing below the toolbar.
        -- 2. Responsive columns fit D's actual width, no horizontal wrapper.
        Theme.PushFont(ctx, UI_SCALE, "base")
        local avail_w = math.max(1, select(1, RPR.ImGui_GetContentRegionAvail(ctx)))
        local start_x = RPR.ImGui_GetCursorPosX(ctx)
        local col_map = ComputeColumnLayout(ctx, start_x, avail_w)

        -- 3. 고정 헤더 행
        local hdr_sx, hdr_sy = RPR.ImGui_GetCursorScreenPos(ctx)
        local hdr_h = RPR.ImGui_GetTextLineHeightWithSpacing(ctx) + LAYOUT.HEADER_PAD_Y
        local draw_list = RPR.ImGui_GetWindowDrawList(ctx)
        RPR.ImGui_DrawList_AddRectFilled(draw_list, hdr_sx, hdr_sy - 2, hdr_sx + avail_w, hdr_sy + hdr_h - 2, palette.header_bg)

        for idx, col in ipairs(COLUMNS) do
            if idx > 1 then
                RPR.ImGui_SameLine(ctx)
            end
            local info = col_map[col.id]
            if col.id == "name" then
                -- Left align Name when there is enough space, shorten otherwise.
                RPR.ImGui_SetCursorPosX(ctx, info.x + math.min(LAYOUT.NAME_LEFT_PAD, info.w * 0.08))
                local label = FitTextToWidth(ctx, info.label, math.max(0, info.w - LAYOUT.NAME_LEFT_PAD))
                RPR.ImGui_Text(ctx, label)
            else
                DrawCenteredHeader(ctx, info)
                if col.id == "active" and RPR.ImGui_IsItemHovered(ctx) then
                    RPR.ImGui_SetTooltip(ctx, "Click: Toggle Track Active\nCtrl + Click: Activate / Deactivate All Tracks")
                end
            end
        end

        -- 4. 스크롤 영역 내 트랙 리스트 (no footer divider/spacing)
        local list_visible = RPR.ImGui_BeginChild(ctx, "TrackListScroll", 0, 0)
        if list_visible then
            local child_draw    = RPR.ImGui_GetWindowDrawList(ctx)
            local child_avail_w = select(1, RPR.ImGui_GetContentRegionAvail(ctx))
            local row_h         = RPR.ImGui_GetFrameHeight(ctx) + LAYOUT.ROW_PAD_Y
            local num_tracks    = RPR.CountTracks(0)

            local visible_rows, track_to_vis_idx = BuildVisibleRows()

            -- REAPER에서 트랙이 선택되었을 때 해당 트랙 위치로 자동 스크롤 (접힌 폴더는 펼치지 않음)
            if pending_scroll_to_track then
                local target_tr = pending_scroll_to_track
                local target_vis_idx = track_to_vis_idx[target_tr]
                while not target_vis_idx and target_tr do
                    target_tr = RPR.GetParentTrack(target_tr)
                    if target_tr then
                        target_vis_idx = track_to_vis_idx[target_tr]
                    end
                end
                if target_vis_idx then
                    local target_top = (target_vis_idx - 1) * row_h
                    local target_bot = target_top + row_h
                    local scroll_y   = RPR.ImGui_GetScrollY(ctx)
                    local child_h    = RPR.ImGui_GetWindowHeight(ctx)

                    if child_h > 0 and (target_top < scroll_y or target_bot > (scroll_y + child_h)) then
                        local centered_scroll = math.max(0, target_top - (child_h - row_h) * 0.5)
                        RPR.ImGui_SetScrollY(ctx, centered_scroll)
                    end
                end
                pending_scroll_to_track = nil
            end

            for vis_idx, row in ipairs(visible_rows) do
                local tr          = row.tr
                local i           = row.track_idx
                local depth       = row.depth
                local is_folder   = row.is_folder
                local compact     = row.compact
                local is_active   = row.is_active
                local is_mute     = row.is_mute
                local is_selected = RPR.IsTrackSelected(tr)

                if renaming_track == tr and not is_active then
                    CancelTrackRename()
                end

                local row_sx, row_sy = RPR.ImGui_GetCursorScreenPos(ctx)
                row.y1 = row_sy
                row.y2 = row_sy + row_h

                -- 행 배경, 선택 인디케이터 바, 하단 구분선
                local bg_col = (vis_idx % 2 == 0) and palette.row_even or palette.row_odd
                if is_selected then
                    bg_col = is_active and palette.sel_active or palette.sel_inactive
                end
                RPR.ImGui_DrawList_AddRectFilled(child_draw, row_sx, row_sy, row_sx + child_avail_w, row_sy + row_h, bg_col)
                if is_selected then
                    RPR.ImGui_DrawList_AddRectFilled(child_draw, row_sx, row_sy, row_sx + LAYOUT.SEL_INDICATOR_W, row_sy + row_h, palette.accent_main)
                end
                RPR.ImGui_DrawList_AddLine(child_draw, row_sx, row_sy + row_h, row_sx + child_avail_w, row_sy + row_h, palette.row_border, 1.0)

                local base_y = RPR.ImGui_GetCursorPosY(ctx)
                local cb_y   = base_y + (LAYOUT.ROW_PAD_Y * 0.5)
                local text_y = base_y + (row_h - RPR.ImGui_GetTextLineHeight(ctx)) * 0.5

                -- [1] Active 체크박스 (Ctrl + Click 시 전체 트랙 일괄 활성화/비활성화)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)
                local changed_act, new_act = DrawCellCheckbox(ctx, "##act" .. i, is_active, col_map.active, false)
                if changed_act then
                    if renaming_track then
                        CancelTrackRename()
                    end
                    RPR.Undo_BeginBlock()
                    RPR.PreventUIRefresh(1)
                    if IsCtrlDown(ctx) then
                        Core.SetAllTracksActive(new_act, g_hide_tcp, g_hide_mcp)
                    else
                        for _, target_tr in ipairs(GetBatchTargetTracks(tr)) do
                            Core.ToggleTrackAndChildrenActive(target_tr, new_act, g_hide_tcp, g_hide_mcp)
                        end
                    end
                    RPR.TrackList_AdjustWindows(false)
                    RPR.UpdateArrange()
                    RPR.PreventUIRefresh(-1)
                    RPR.Undo_EndBlock(APP.UNDO_ACT, -1)
                end

                -- [2] Color 스와치
                RPR.ImGui_SameLine(ctx)
                local tr_color = RPR.GetTrackColor(tr)
                local rgba = palette.default_swatch
                if tr_color ~= 0 then
                    local r, g, b = RPR.ColorFromNative(tr_color)
                    rgba = RGBA(r, g, b, 255)
                end
                RPR.ImGui_SetCursorPosX(ctx, col_map.color.x + (col_map.color.w - LAYOUT.SWATCH_SIZE) * 0.5)
                RPR.ImGui_SetCursorPosY(ctx, base_y + (row_h - LAYOUT.SWATCH_SIZE) * 0.5)
                RPR.ImGui_ColorButton(ctx, "##col" .. i, rgba, RPR.ImGui_ColorEditFlags_NoTooltip() | RPR.ImGui_ColorEditFlags_NoPicker(), LAYOUT.SWATCH_SIZE, LAYOUT.SWATCH_SIZE)

                -- [3] No. (트랙 번호)
                RPR.ImGui_SameLine(ctx)
                local tr_num_int = math.floor(RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.NUMBER))
                local num_str = tostring(tr_num_int)
                local num_w = select(1, RPR.ImGui_CalcTextSize(ctx, num_str))
                RPR.ImGui_SetCursorPosX(ctx, col_map.no.x + (col_map.no.w - num_w) * 0.5)
                RPR.ImGui_SetCursorPosY(ctx, text_y)
                RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), is_active and palette.text_status or palette.text_inactive)
                RPR.ImGui_Text(ctx, num_str)
                RPR.ImGui_PopStyleColor(ctx, 1)

                -- [4] Track Name + 폴더 접기/펼치기 + 다중 선택 / 더블클릭 이름 수정
                RPR.ImGui_SameLine(ctx)
                local max_indent = math.max(0, col_map.name.w - LAYOUT.NAME_LEFT_PAD
                    - LAYOUT.NAME_RIGHT_PAD - LAYOUT.FOLDER_BTN_W - LAYOUT.FOLDER_BTN_GAP - 8)
                local indent_px   = math.min(depth * LAYOUT.INDENT_PER_DEPTH, max_indent)
                local cur_name_x  = col_map.name.x + LAYOUT.NAME_LEFT_PAD + indent_px
                local tcp_limit_x = col_map.tcp.x - LAYOUT.NAME_RIGHT_PAD

                RPR.ImGui_SetCursorPosX(ctx, cur_name_x)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)

                if is_folder then
                    local is_open = (compact ~= Core.FOLDER_STATE.COLLAPSED)
                    local arrow_label = (is_open and "▼" or "▶") .. "##fld" .. i
                    if RPR.ImGui_SmallButton(ctx, arrow_label) then
                        RPR.SetMediaTrackInfo_Value(tr, Core.TRACK_PROP.FOLDER_COMP, is_open and Core.FOLDER_STATE.COLLAPSED or Core.FOLDER_STATE.NORMAL)
                        RPR.TrackList_AdjustWindows(false)
                    end
                    RPR.ImGui_SameLine(ctx, 0, LAYOUT.FOLDER_BTN_GAP)
                else
                    RPR.ImGui_SetCursorPosX(ctx, cur_name_x + LAYOUT.FOLDER_BTN_W + LAYOUT.FOLDER_BTN_GAP)
                end

                local _, raw_name = RPR.GetSetMediaTrackInfo_String(tr, Core.TRACK_PROP.NAME, "", false)
                local tr_name = (raw_name ~= nil and raw_name ~= "") and raw_name or ("Track " .. num_str)
                local btn_x = RPR.ImGui_GetCursorPosX(ctx)
                local btn_w = math.max(1, tcp_limit_x - btn_x)

                if renaming_track == tr then
                    -- 인라인 트랙 이름 입력 모드
                    RPR.ImGui_SetCursorPosX(ctx, btn_x)
                    RPR.ImGui_SetCursorPosY(ctx, cb_y)
                    RPR.ImGui_SetNextItemWidth(ctx, math.max(1, btn_w))

                    local just_focused = false
                    if rename_focus_pending then
                        RPR.ImGui_SetKeyboardFocusHere(ctx)
                        rename_focus_pending = false
                        just_focused = true
                    end

                    local input_flags = RPR.ImGui_InputTextFlags_EnterReturnsTrue()
                        | RPR.ImGui_InputTextFlags_AutoSelectAll()
                    local enter_pressed, new_text = RPR.ImGui_InputText(ctx, "##rename_tr" .. i, rename_buffer, input_flags)
                    rename_buffer = new_text

                    if RPR.ImGui_IsKeyPressed(ctx, RPR.ImGui_Key_Escape()) then
                        CancelTrackRename()
                    elseif enter_pressed then
                        CommitTrackRename(tr, rename_buffer)
                    elseif not just_focused and RPR.ImGui_IsItemDeactivated(ctx) then
                        CommitTrackRename(tr, rename_buffer)
                    end
                else
                    -- 일반 트랙 이름 표시 및 클릭/더블클릭 히트 영역
                    RPR.ImGui_SetCursorPosY(ctx, base_y)
                    RPR.ImGui_InvisibleButton(ctx, "##row_hit" .. i, btn_w, row_h)

                    local hit_hovered = RPR.ImGui_IsItemHovered(ctx)
                    local double_clicked = hit_hovered and RPR.ImGui_IsMouseDoubleClicked(ctx, 0)

                    if double_clicked and is_active then
                        BeginTrackRename(tr, raw_name)
                    elseif RPR.ImGui_IsItemClicked(ctx, 0) then
                        local ctrl  = IsCtrlDown(ctx)
                        local shift = IsShiftDown(ctx)

                        internal_sel_lock = true
                        is_dragging = true
                        drag_ctrl = ctrl
                        last_drag_hovered_idx = vis_idx

                        local anchor_idx = ResolveAnchorVisIdx(visible_rows, track_to_vis_idx)

                        if shift and anchor_idx then
                            drag_mode = "shift"
                            local r1 = math.min(anchor_idx, vis_idx)
                            local r2 = math.max(anchor_idx, vis_idx)
                            if not ctrl then
                                RPR.Main_OnCommand(REAPER_CMD.UNSELECT_ALL_TRACKS, 0)
                            end
                            for k = r1, r2 do
                                RPR.SetTrackSelected(visible_rows[k].tr, true)
                            end
                        elseif ctrl then
                            drag_mode = "normal"
                            drag_start_track = tr
                            local new_sel = not RPR.IsTrackSelected(tr)
                            RPR.SetTrackSelected(tr, new_sel)
                            anchor_track = tr
                            if new_sel and RPR.CountSelectedTracks(0) == 1 and is_active then
                                RPR.Main_OnCommand(REAPER_CMD.SCROLL_TO_SELECTED, 0)
                            end
                        else
                            drag_mode = "normal"
                            drag_start_track = tr
                            RPR.Main_OnCommand(REAPER_CMD.UNSELECT_ALL_TRACKS, 0)
                            RPR.SetTrackSelected(tr, true)
                            anchor_track = tr
                            if is_active then
                                RPR.Main_OnCommand(REAPER_CMD.SCROLL_TO_SELECTED, 0)
                            end
                        end

                        pre_drag_selected = {}
                        for t_i = 0, num_tracks - 1 do
                            local t_ptr = RPR.GetTrack(0, t_i)
                            pre_drag_selected[t_ptr] = RPR.IsTrackSelected(t_ptr)
                        end
                    end

                    -- 트랙 이름 텍스트 렌더링 (TCP 체크박스 직전까지만 출력)
                    local text_start_x = btn_x + 2
                    local max_text_w   = math.max(0, tcp_limit_x - text_start_x)
                    local display_name = FitTextToWidth(ctx, tr_name, max_text_w)

                    if hit_hovered and display_name ~= tr_name then
                        RPR.ImGui_SetTooltip(ctx, tr_name)
                    end

                    RPR.ImGui_SameLine(ctx)
                    RPR.ImGui_SetCursorPosX(ctx, text_start_x)
                    RPR.ImGui_SetCursorPosY(ctx, text_y)

                    local name_color = palette.text_main
                    if not is_active then
                        name_color = palette.text_inactive
                    elseif is_mute then
                        name_color = palette.text_muted
                    end

                    RPR.ImGui_PushStyleColor(ctx, RPR.ImGui_Col_Text(), name_color)
                    RPR.ImGui_Text(ctx, display_name)
                    RPR.ImGui_PopStyleColor(ctx, 1)
                end

                -- 이하 6개 속성 체크박스 (비활성화 트랙은 조작 잠금)
                local lock_controls = (not is_active)

                -- [5] TCP
                RPR.ImGui_SameLine(ctx)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)
                local show_tcp = RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_TCP) > 0
                local changed_ttcp, new_ttcp = DrawCellCheckbox(ctx, "##tc" .. i, show_tcp, col_map.tcp, lock_controls)
                if changed_ttcp and is_active then
                    RPR.Undo_BeginBlock()
                    for _, target_tr in ipairs(GetBatchTargetTracks(tr)) do
                        if Core.IsTrackActive(target_tr) then
                            RPR.SetMediaTrackInfo_Value(target_tr, Core.TRACK_PROP.SHOW_TCP, new_ttcp and 1 or 0)
                        end
                    end
                    RPR.TrackList_AdjustWindows(false)
                    RPR.Undo_EndBlock(APP.UNDO_PROP, -1)
                end

                -- [6] MCP
                RPR.ImGui_SameLine(ctx)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)
                local show_mcp = RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SHOW_MCP) > 0
                local changed_tmcp, new_tmcp = DrawCellCheckbox(ctx, "##mc" .. i, show_mcp, col_map.mcp, lock_controls)
                if changed_tmcp and is_active then
                    RPR.Undo_BeginBlock()
                    for _, target_tr in ipairs(GetBatchTargetTracks(tr)) do
                        if Core.IsTrackActive(target_tr) then
                            RPR.SetMediaTrackInfo_Value(target_tr, Core.TRACK_PROP.SHOW_MCP, new_tmcp and 1 or 0)
                        end
                    end
                    RPR.TrackList_AdjustWindows(false)
                    RPR.Undo_EndBlock(APP.UNDO_PROP, -1)
                end

                -- [7] Solo (체크 상태에서 Ctrl+Click 시 전체 트랙 Solo 해제)
                RPR.ImGui_SameLine(ctx)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)
                local is_solo = RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.SOLO) > 0
                local changed_solo, new_solo = DrawCellCheckbox(ctx, "##so" .. i, is_solo, col_map.solo, lock_controls)
                if changed_solo and is_active then
                    RPR.Undo_BeginBlock()
                    if is_solo and IsCtrlDown(ctx) then
                        ClearAllTracksSolo()
                    else
                        for _, target_tr in ipairs(GetBatchTargetTracks(tr)) do
                            if Core.IsTrackActive(target_tr) then
                                RPR.SetMediaTrackInfo_Value(target_tr, Core.TRACK_PROP.SOLO, new_solo and 1 or 0)
                            end
                        end
                    end
                    RPR.Undo_EndBlock(APP.UNDO_PROP, -1)
                end

                -- [8] Mute (체크 상태에서 Ctrl+Click 시 전체 트랙 Mute 해제)
                RPR.ImGui_SameLine(ctx)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)
                local changed_mute, new_mute = DrawCellCheckbox(ctx, "##mt" .. i, is_mute, col_map.mute, lock_controls)
                if changed_mute and is_active then
                    RPR.Undo_BeginBlock()
                    if is_mute and IsCtrlDown(ctx) then
                        ClearAllTracksMute()
                    else
                        for _, target_tr in ipairs(GetBatchTargetTracks(tr)) do
                            if Core.IsTrackActive(target_tr) then
                                RPR.SetMediaTrackInfo_Value(target_tr, Core.TRACK_PROP.MUTE, new_mute and 1 or 0)
                            end
                        end
                    end
                    RPR.Undo_EndBlock(APP.UNDO_PROP, -1)
                end

                -- [9] FX
                RPR.ImGui_SameLine(ctx)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)
                local fx_count    = RPR.TrackFX_GetCount(tr)
                local has_fx      = (fx_count > 0)
                local fx_active   = is_active and has_fx and Core.AreAllTrackFXOnline(tr)
                local fx_disabled = lock_controls or (not has_fx)

                local changed_fx, new_fx = DrawCellCheckbox(ctx, "##fx" .. i, fx_active, col_map.fx, fx_disabled)
                if changed_fx and is_active and has_fx then
                    RPR.Undo_BeginBlock()
                    for _, target_tr in ipairs(GetBatchTargetTracks(tr)) do
                        if Core.IsTrackActive(target_tr) then
                            local t_fx_cnt = RPR.TrackFX_GetCount(target_tr)
                            for fx = 0, t_fx_cnt - 1 do
                                RPR.TrackFX_SetOffline(target_tr, fx, not new_fx)
                            end
                        end
                    end
                    RPR.Undo_EndBlock(APP.UNDO_PROP, -1)
                end

                -- [10] Arm
                RPR.ImGui_SameLine(ctx)
                RPR.ImGui_SetCursorPosY(ctx, cb_y)
                local is_rec = RPR.GetMediaTrackInfo_Value(tr, Core.TRACK_PROP.REC_ARM) > 0
                local changed_rec, new_rec = DrawCellCheckbox(ctx, "##rc" .. i, is_rec, col_map.arm, lock_controls)
                if changed_rec and is_active then
                    RPR.Undo_BeginBlock()
                    for _, target_tr in ipairs(GetBatchTargetTracks(tr)) do
                        if Core.IsTrackActive(target_tr) then
                            RPR.SetMediaTrackInfo_Value(target_tr, Core.TRACK_PROP.REC_ARM, new_rec and 1 or 0)
                        end
                    end
                    RPR.Undo_EndBlock(APP.UNDO_PROP, -1)
                end

                RPR.ImGui_SetCursorPosY(ctx, base_y + row_h)
            end

            -- 마지막 행에서 SetCursorPosY()만 호출한 상태로 EndChild()를 실행하면
            -- ReaImGui가 창 경계 확장을 거부한다. 실제 아이템을 제출해 경계를 확정한다.
            -- 행마다 Dummy를 넣으면 행 높이/스크롤 간격이 변하므로 목록 끝에서 한 번만 호출.
            if #visible_rows > 0 then
                RPR.ImGui_Dummy(ctx, 1, 1)
            end

            -- 마우스 드래그 다중 선택 (상·하 양방향 지원)
            if is_dragging then
                if RPR.ImGui_IsMouseDown(ctx, 0) and #visible_rows > 0 then
                    internal_sel_lock = true
                    local _, my = RPR.ImGui_GetMousePos(ctx)
                    local hovered_idx = nil

                    if my < visible_rows[1].y1 then
                        hovered_idx = 1
                    elseif my >= visible_rows[#visible_rows].y2 then
                        hovered_idx = #visible_rows
                    else
                        for idx, r_info in ipairs(visible_rows) do
                            if my >= r_info.y1 and my < r_info.y2 then
                                hovered_idx = idx
                                break
                            end
                        end
                    end

                    if hovered_idx and hovered_idx ~= last_drag_hovered_idx then
                        last_drag_hovered_idx = hovered_idx

                        if drag_mode == "shift" then
                            local anchor_idx = ResolveAnchorVisIdx(visible_rows, track_to_vis_idx)
                            if anchor_idx then
                                local r1 = math.min(anchor_idx, hovered_idx)
                                local r2 = math.max(anchor_idx, hovered_idx)
                                if not drag_ctrl then
                                    RPR.Main_OnCommand(REAPER_CMD.UNSELECT_ALL_TRACKS, 0)
                                end
                                for k = r1, r2 do
                                    RPR.SetTrackSelected(visible_rows[k].tr, true)
                                end
                            end
                        else
                            local start_idx = drag_start_track and track_to_vis_idx[drag_start_track]
                            if start_idx then
                                local r1 = math.min(start_idx, hovered_idx)
                                local r2 = math.max(start_idx, hovered_idx)
                                for t_i = 0, num_tracks - 1 do
                                    local t_ptr = RPR.GetTrack(0, t_i)
                                    local restore_sel = drag_ctrl and (pre_drag_selected[t_ptr] or false) or false
                                    RPR.SetTrackSelected(t_ptr, restore_sel)
                                end
                                for k = r1, r2 do
                                    RPR.SetTrackSelected(visible_rows[k].tr, true)
                                end
                            end
                        end
                    end
                else
                    is_dragging = false
                    drag_mode = nil
                    last_drag_hovered_idx = nil
                end
            end

        end
        RPR.ImGui_EndChild(ctx)

        Theme.PopFont(ctx)
end

return { Draw = Draw }
end

return M
