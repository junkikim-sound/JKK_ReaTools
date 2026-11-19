--========================================================
-- @title JKK_ReaTools_NEW_TrackTool
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper

-- UI zoom factor published by JKK_ReaTools (1.0 = original design size).
local function S(v) return v * (JKK_UI_SCALE or 1) end

-- JKK_ReaTools가 먼저 로드한 SelectionManager 참조 (단독 로드 시 폴백 포함)
local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local sel_path = script_dir .. "JKK_SelectionManager.lua"
if not reaper.file_exists(sel_path) then
    sel_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_SelectionManager.lua"
end
local sel_mgr = _G.JKK_SelectionManager or (reaper.file_exists(sel_path) and dofile(sel_path))

-- Start slider undo blocks on first value change; close on release.
local slider_undo_open = false
local function SliderUndoBegin()
    if not slider_undo_open then
        reaper.Undo_BeginBlock()
        slider_undo_open = true
    end
end
local function SliderUndoEnd(ctx, description)
    if slider_undo_open and reaper.ImGui_IsItemDeactivated(ctx) then
        reaper.Undo_EndBlock(description, -1)
        slider_undo_open = false
    end
end

------------------------------------------------------------
-- Track Controller State
------------------------------------------------------------
local MAX_DB = 12.0
local MIN_DB = -100.0

local volume_db = 0.0
local pan_val = 0.0
local width_val = 1.0
local track_channels = 2

-- 프로젝트 전체 적용 여부를 저장하는 변수
local apply_all_tracks = (reaper.GetExtState("JKK_TrackTool", "apply_all_tracks") == "1")

local function ReadSelectedTrackValues()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return end

    local linear_vol = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
    volume_db = (linear_vol > 0)
        and (20.0 * math.log(linear_vol) / math.log(10))
        or MIN_DB
    volume_db = math.max(MIN_DB, math.min(volume_db, MAX_DB))

    pan_val = reaper.GetMediaTrackInfo_Value(track, "D_PAN")
    width_val = reaper.GetMediaTrackInfo_Value(track, "D_WIDTH")
    track_channels = reaper.GetMediaTrackInfo_Value(track, "I_NCHAN") or track_channels
end

ReadSelectedTrackValues()

------------------------------------------------------------
-- Track Value Actions
------------------------------------------------------------
local function Action_SetSelectedTracksVolume(value)
    local count = reaper.CountSelectedTracks(0)
    for i = 0, count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", value)
    end
end

local function Action_RoundTracksVolumeToHalfDB(all_tracks)
    local count = all_tracks and reaper.CountTracks(0) or reaper.CountSelectedTracks(0)
    if count == 0 then return end

    reaper.Undo_BeginBlock()
    for i = 0, count - 1 do
        local track = all_tracks and reaper.GetTrack(0, i) or reaper.GetSelectedTrack(0, i)
        if track then
            local current_vol = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
            if current_vol > 0 then
                local db = 20 * math.log(current_vol, 10)
                local rounded_db = math.floor(db * 2 + 0.5) / 2
                local new_vol = 10 ^ (rounded_db / 20.0)
                if math.abs(current_vol - new_vol) > 0.0001 then
                    reaper.SetMediaTrackInfo_Value(track, "D_VOL", new_vol)
                end
            end
        end
    end
    reaper.Undo_EndBlock(all_tracks and "Round All Tracks Volume to 0.5dB" or "Round Selected Tracks Volume to 0.5dB", -1)
end

local function Action_SetSelectedTracksPan(value)
    local count = reaper.CountSelectedTracks(0)
    for i = 0, count - 1 do
        reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, i), "D_PAN", value)
    end
end

local function Action_SetSelectedTracksWidth(value)
    local count = reaper.CountSelectedTracks(0)
    for i = 0, count - 1 do
        reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, i), "D_WIDTH", value)
    end
end

local function Action_SetTrackChannels(num_channels)
    local count = reaper.CountSelectedTracks(0)
    if count == 0 then return end

    reaper.Undo_BeginBlock()
    for i = 0, count - 1 do
        reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, i), "I_NCHAN", num_channels)
    end
    reaper.Undo_EndBlock("Set Track Channels", -1)
end

-- Offset of the selected tracks' main (Master/Parent) audio output.
-- Preserve each track's C_MAINSEND_NCH (0 = all track channels); this control
-- chooses the destination position, not the width of the parent send.
-- When a destination exceeds the parent's existing channel count, expand it
-- so the newly assigned output is actually audible/routable.
local MAX_PARENT_OUTPUT_CHANNELS = 64 -- keep the physical routing safety limit unchanged
local MAX_VISIBLE_OUTPUT_CHANNEL = 10 -- only offer destinations through channel 10

local function GetParentOutputWidth(track)
    local send_nch = math.floor((reaper.GetMediaTrackInfo_Value(track, "C_MAINSEND_NCH") or 0) + 0.5)
    if send_nch > 0 then return send_nch end
    return math.max(1, math.floor((reaper.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2) + 0.5))
end

local function Action_SetParentOutputOffset(channel_offset)
    local count = reaper.CountSelectedTracks(0)
    if count == 0 then return end
    channel_offset = math.max(0, math.floor(channel_offset))

    reaper.Undo_BeginBlock()
    local updated = false
    for i = 0, count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            local old = reaper.GetMediaTrackInfo_Value(track, "C_MAINSEND_OFFS") or 0
            if math.floor(old + 0.5) ~= channel_offset then
                reaper.SetMediaTrackInfo_Value(track, "C_MAINSEND_OFFS", channel_offset)
                updated = true
            end
            local parent = reaper.GetParentTrack(track) or reaper.GetMasterTrack(0)
            if parent then
                local required = channel_offset + GetParentOutputWidth(track)
                local available = reaper.GetMediaTrackInfo_Value(parent, "I_NCHAN") or 2
                if required <= MAX_PARENT_OUTPUT_CHANNELS and required > available then
                    -- REAPER tracks use an even internal channel count.
                    reaper.SetMediaTrackInfo_Value(parent, "I_NCHAN", math.ceil(required / 2) * 2)
                    updated = true
                end
            end
        end
    end
    reaper.Undo_EndBlock("Set Track Master/Parent Output Channels", updated and -1 or 0)
    if updated then reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange() end
end

------------------------------------------------------------
-- Track Actions
------------------------------------------------------------
local function DeleteEmptyTracksAndFolders()
    local function IsTrackUnused(track)
        if reaper.CountTrackMediaItems(track) > 0 then return false end
        if reaper.GetTrackNumSends(track, -1) > 0 then return false end
        if reaper.GetTrackNumSends(track, 0) > 0 then return false end
        if reaper.GetTrackNumSends(track, 1) > 0 then return false end
        if reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1 then return false end
        if reaper.CountTrackEnvelopes(track) > 0 then return false end
        return true
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local saved_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        saved_tracks[#saved_tracks + 1] = reaper.GetSelectedTrack(0, i)
    end

    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks

    local track_count = reaper.CountTracks(0)
    for i = track_count - 1, 0, -1 do
        local track = reaper.GetTrack(0, i)
        local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        if folder_depth == 1 then
            local child_used = false
            local depth = reaper.GetTrackDepth(track)
            local track_idx = i + 1

            while track_idx < track_count do
                local child = reaper.GetTrack(0, track_idx)
                local child_depth = reaper.GetTrackDepth(child)
                if child_depth <= depth then break end

                if not reaper.IsTrackSelected(child) then
                    child_used = true
                    break
                end
                track_idx = track_idx + 1
            end

            if not child_used then
                reaper.SetTrackSelected(track, IsTrackUnused(track))
            end
        else
            reaper.SetTrackSelected(track, IsTrackUnused(track))
        end
    end

    reaper.Main_OnCommand(40005, 0) -- Remove selected tracks
    for _, track in ipairs(saved_tracks) do
        if reaper.ValidatePtr(track, "MediaTrack*") then
            reaper.SetTrackSelected(track, true)
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("JKK: Delete Unused Tracks", -1)
end

local function Action_SetSelectedTracksAutomationMode(mode_idx)
    local count = reaper.CountSelectedTracks(0)
    if count == 0 then return end

    reaper.Undo_BeginBlock()
    for i = 0, count - 1 do
        reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, i), "I_AUTOMODE", mode_idx)
    end
    reaper.Undo_EndBlock("Set Selected Tracks Automation Mode", -1)
end

------------------------------------------------------------
-- Timeline: Delete Regions Overlapping Time Selection
------------------------------------------------------------
local function GetTimeSelection()
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_time == end_time then return nil end
    return start_time, end_time
end

local function GetOverlappingRegions()
    local start_time, end_time = GetTimeSelection()
    if not start_time then return nil end

    local _, marker_count, region_count = reaper.CountProjectMarkers(0)
    local total = marker_count + region_count
    local regions = {}

    for i = 0, total - 1 do
        local retval, is_region, pos, region_end, name, index = reaper.EnumProjectMarkers3(0, i)
        if retval and is_region and region_end > start_time and pos < end_time then
            regions[#regions + 1] = {
                index = index,
                pos = pos,
                region_end = region_end,
                name = name
            }
        end
    end
    return regions
end

local function DeleteOverlappingRegions()
    local regions = GetOverlappingRegions()
    if not regions or #regions == 0 then return end

    reaper.Undo_BeginBlock()
    for i = #regions, 1, -1 do
        reaper.DeleteProjectMarker(0, regions[i].index, true)
    end
    reaper.Undo_EndBlock("Delete Selected Regions", -1)
    reaper.UpdateArrange()
end

------------------------------------------------------------
-- UI: Track Controller
------------------------------------------------------------
local function db_to_slider_pos(db)
    if db <= 0 then
        return ((db + 100.0) * 0.75) / 100.0
    end
    return 0.75 + (db / MAX_DB) * 0.25
end

local function slider_pos_to_db(pos)
    if pos <= 0.75 then
        return (pos / 0.75) * 100.0 + MIN_DB
    end
    return ((pos - 0.75) / 0.25) * MAX_DB
end

-- A fixed, non-scrolling popup instead of BeginCombo. ReaImGui's combo
-- HeightLargest is only a size hint: its popup may still create a scrollbar.
-- These two short lists must NEVER scroll, even when the popup is open.
local function DrawCenteredChannelCombo(ctx, id, preview, entries, selected_index, width)
    local r = reaper
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local frame_h = r.ImGui_GetFrameHeight(ctx)
    local label = '##channel_popup_button_' .. id
    local popup_id = '##channel_popup_' .. id

    -- Use the normal frame colors, not the accent/button theme colors.
    local colors = {
        {r.ImGui_Col_Button(), r.ImGui_GetColor(ctx, r.ImGui_Col_FrameBg())},
        {r.ImGui_Col_ButtonHovered(), r.ImGui_GetColor(ctx, r.ImGui_Col_FrameBgHovered())},
        {r.ImGui_Col_ButtonActive(), r.ImGui_GetColor(ctx, r.ImGui_Col_FrameBgActive())},
    }
    for _, color in ipairs(colors) do
        r.ImGui_PushStyleColor(ctx, color[1], color[2])
    end
    local clicked = r.ImGui_Button(ctx, label, width, frame_h)
    r.ImGui_PopStyleColor(ctx, #colors)
    if clicked and #entries > 0 then r.ImGui_OpenPopup(ctx, popup_id) end

    -- Center the selected text in the preview area, with a separate arrow.
    -- This paint does not add another ImGui widget or change the hitbox.
    local text = tostring(preview or '')
    local preview_w = math.max(1, width - frame_h * 0.70)
    local text_w, text_h = r.ImGui_CalcTextSize(ctx, text)
    local text_x = x + math.max(S(2), (preview_w - text_w) * 0.5)
    local text_y = y + math.max(0, (frame_h - text_h) * 0.5)
    local color = r.ImGui_GetColor(ctx, r.ImGui_Col_Text())
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddText(draw_list, text_x, text_y, color, text)
    local arrow = '▼'
    local arrow_w, arrow_h = r.ImGui_CalcTextSize(ctx, arrow)
    r.ImGui_DrawList_AddText(draw_list,
        x + width - (frame_h * 0.70 + arrow_w) * 0.5,
        y + math.max(0, (frame_h - arrow_h) * 0.5), color, arrow)

    if #entries == 0 then return nil end
    local padding_x, padding_y = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_WindowPadding())
    local item_gap_x, item_gap_y = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
    local inner_height = #entries * frame_h + (#entries - 1) * item_gap_y
    local popup_height = inner_height + 2 * padding_y + S(4)
    local popup_width = math.max(width, S(85))
    -- Popup opens directly below the combo. Set an exact height large enough
    -- for every entry and forbid both scrollbar and mouse-wheel scrolling.
    r.ImGui_SetNextWindowSize(ctx, popup_width, popup_height, r.ImGui_Cond_Always())
    local popup_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    local chosen_index = nil
    if r.ImGui_BeginPopup(ctx, popup_id, popup_flags) then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_SelectableTextAlign(), 0.5, 0.5)
        for i, value in ipairs(entries) do
            local selected = (i == selected_index)
            if r.ImGui_Selectable(ctx, value .. '##' .. id .. '_' .. i, selected, 0, 0, frame_h) then
                chosen_index = i
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_EndPopup(ctx)
    end
    return chosen_index
end

local function DrawTrackBatchController(ctx)
    local selected_track = reaper.GetSelectedTrack(0, 0)
    local selected_count = reaper.CountSelectedTracks(0)

    local should_update = false
    if selected_track and selected_count > 0 then
        local is_window_focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
        local is_item_active = reaper.ImGui_IsAnyItemActive(ctx)
        local is_down = sel_mgr and sel_mgr.IsMouseDown() or false
        local cur_mode, cur_active = "Track", true
        if sel_mgr then
            cur_mode, cur_active = sel_mgr.GetMode()
        end

        if is_window_focused or is_item_active or (not is_down and cur_mode == "Track" and cur_active) then
            should_update = true
        end
    end

    if should_update then
        local linear_vol = reaper.GetMediaTrackInfo_Value(selected_track, "D_VOL")
        volume_db = (linear_vol > 0)
            and (20.0 * math.log(linear_vol) / math.log(10))
            or MIN_DB
        volume_db = math.max(MIN_DB, math.min(volume_db, MAX_DB))
        pan_val = reaper.GetMediaTrackInfo_Value(selected_track, "D_PAN")
        width_val = reaper.GetMediaTrackInfo_Value(selected_track, "D_WIDTH")
        track_channels = reaper.GetMediaTrackInfo_Value(selected_track, "I_NCHAN") or track_channels
    end

    local label_width = S(86)
    local round_button_width = S(48)
    local checkbox_width = S(20)
    local row_gap = S(6)
    local row_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))

    local volume_slider_width = math.max(1,
        row_width - label_width - round_button_width - checkbox_width - (row_gap * 2))
    local full_control_width = math.max(1, row_width - label_width)

    local function BeginLabeledRow(label)
        local row_x = reaper.ImGui_GetCursorPosX(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, label)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, row_x + label_width)
    end

    -- Volume
    BeginLabeledRow("Volume")
    reaper.ImGui_SetNextItemWidth(ctx, volume_slider_width)
    local vol_format = (volume_db <= MIN_DB) and "-inf dB" or string.format("%.1f dB", volume_db)
    local changed_vol, new_slider_pos = reaper.ImGui_SliderDouble(
        ctx, "##TrackVolume", db_to_slider_pos(volume_db), 0.0, 1.0, vol_format
    )
    if changed_vol then
        SliderUndoBegin()
        volume_db = slider_pos_to_db(new_slider_pos)
        Action_SetSelectedTracksVolume(math.min(10 ^ (volume_db / 20.0), 3.98))
    end
    SliderUndoEnd(ctx, "Set Selected Tracks Volume")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        volume_db = 0.0
        Action_SetSelectedTracksVolume(1.0)
        reaper.Undo_EndBlock("Reset Volume", -1)
    end
    
    -- 0.5dB 버튼
    reaper.ImGui_SameLine(ctx, 0, row_gap)
    if reaper.ImGui_Button(ctx, "0.5dB", round_button_width, S(22)) then
        Action_RoundTracksVolumeToHalfDB(apply_all_tracks)
        ReadSelectedTrackValues()
    end

    -- 0.5dB 버튼 오른쪽 프로젝트 전체 적용 체크박스
    reaper.ImGui_SameLine(ctx, 0, row_gap)
    local changed_chk, new_chk = reaper.ImGui_Checkbox(ctx, "##ApplyAllTracksChk", apply_all_tracks)
    if changed_chk then
        apply_all_tracks = new_chk
        reaper.SetExtState("JKK_TrackTool", "apply_all_tracks", apply_all_tracks and "1" or "0", true)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Check to apply 0.5dB rounding to all tracks in the project")
    end

    -- Pan
    BeginLabeledRow("Pan")
    reaper.ImGui_SetNextItemWidth(ctx, full_control_width)
    local pan_display = math.abs(pan_val * 100)
    local pan_format = "Center"
    if pan_val < 0 then
        pan_format = string.format("%.0fL", pan_display)
    elseif pan_val > 0 then
        pan_format = string.format("%.0fR", pan_display)
    end
    local changed_pan, new_pan = reaper.ImGui_SliderDouble(ctx, "##TrackPan", pan_val, -1.0, 1.0, pan_format)
    if changed_pan then
        SliderUndoBegin()
        pan_val = new_pan
        Action_SetSelectedTracksPan(pan_val)
    end
    SliderUndoEnd(ctx, "Set Selected Tracks Panning")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        pan_val = 0.0
        Action_SetSelectedTracksPan(0.0)
        reaper.Undo_EndBlock("Reset Pan", -1)
    end

    -- Width
    BeginLabeledRow("Width")
    reaper.ImGui_SetNextItemWidth(ctx, full_control_width)
    local width_display = math.abs(width_val * 100)
    local width_format = string.format("%.0f W", width_display)
    if width_val == 0 then
        width_format = "Mono"
    elseif width_val < 0 then
        width_format = string.format("%.0f W (Rev)", width_display)
    end
    local changed_width, new_width = reaper.ImGui_SliderDouble(ctx, "##TrackWidth", width_val, -1.0, 1.0, width_format)
    if changed_width then
        SliderUndoBegin()
        width_val = new_width
        Action_SetSelectedTracksWidth(width_val)
    end
    SliderUndoEnd(ctx, "Set Selected Tracks Width")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        width_val = 1.0
        Action_SetSelectedTracksWidth(1.0)
        reaper.Undo_EndBlock("Reset Width", -1)
    end

    -- Track channels and Master/Parent output share one controller row.
    BeginLabeledRow("Channels")
    local channel_options = {'2 ch', '4 ch', '6 ch', '8 ch', '10 ch', '12 ch', '16 ch'}
    local current_nchan = selected_track
        and reaper.GetMediaTrackInfo_Value(selected_track, "I_NCHAN")
        or track_channels
    local channel_map = {2, 4, 6, 8, 10, 12, 16}
    local channel_idx = nil
    for i, value in ipairs(channel_map) do
        if value == current_nchan then channel_idx = i; break end
    end

    local nav_width, nav_gap = S(21), S(3)
    local between_groups = S(9)
    local out_label_width = select(1, reaper.ImGui_CalcTextSize(ctx, 'Out'))
    -- Both channel groups occupy precisely the same width. Like the supplied
    -- desired image, put the unused horizontal room AFTER the 'Out' label,
    -- before its left arrow (not between the first combo and its arrows).
    local group_width = math.max(nav_width * 2 + nav_gap * 2 + S(30),
        math.floor(full_control_width * 0.405))
    local out_label_right_gap = math.max(S(12),
        full_control_width - group_width * 2 - between_groups - out_label_width)
    local combo_width = math.max(S(30), group_width - nav_width * 2 - nav_gap * 2)
    local track_combo_width, out_combo_width = combo_width, combo_width
    local can_change = selected_count > 0

    -- Navigation honors non-preset channel counts too (e.g. 14ch).
    local function StepTrackChannels(direction)
        local current = tonumber(current_nchan) or 2
        local next_value
        if direction > 0 then
            for _, value in ipairs(channel_map) do
                if value > current then next_value = value; break end
            end
            next_value = next_value or channel_map[1]
        else
            for i = #channel_map, 1, -1 do
                if channel_map[i] < current then next_value = channel_map[i]; break end
            end
            next_value = next_value or channel_map[#channel_map]
        end
        Action_SetTrackChannels(next_value)
        current_nchan = next_value
        track_channels = next_value
    end

    if not can_change then reaper.ImGui_BeginDisabled(ctx) end
    local previous = reaper.ImGui_Button(ctx, '◀##TrackChannelsPrev', nav_width, 0)
    if previous and can_change then StepTrackChannels(-1) end
    reaper.ImGui_SameLine(ctx, 0, nav_gap)
    local channel_preview = (channel_idx and channel_options[channel_idx])
        or ('%d ch'):format(math.floor((current_nchan or 2) + 0.5))
    local new_channel_idx = DrawCenteredChannelCombo(ctx, '##TrackChannels',
        channel_preview, channel_options, channel_idx, track_combo_width)
    if new_channel_idx and can_change then
        Action_SetTrackChannels(channel_map[new_channel_idx])
        track_channels = channel_map[new_channel_idx]
    end
    reaper.ImGui_SameLine(ctx, 0, nav_gap)
    local following = reaper.ImGui_Button(ctx, '▶##TrackChannelsNext', nav_width, 0)
    if following and can_change then StepTrackChannels(1) end
    if not can_change then reaper.ImGui_EndDisabled(ctx) end

    -- Output destination uses REAPER's actual Master/Parent send offset.
    -- Keep the send width unchanged (0 means all track channels), including
    -- multichannel sends such as 4ch / 6ch. Mono sends may use every channel;
    -- multichannel sends navigate in stereo pairs.
    local current_offset = selected_track and math.max(0,
        math.floor((reaper.GetMediaTrackInfo_Value(selected_track, "C_MAINSEND_OFFS") or 0) + 0.5)) or 0
    local send_width = selected_track and GetParentOutputWidth(selected_track) or 2
    local step = (send_width == 1) and 1 or 2
    local offsets = {}
    -- Only list routings whose LAST destination channel is <= 10.
    -- Keep the real send width intact for mono and multichannel tracks.
    local max_offset = MAX_VISIBLE_OUTPUT_CHANNEL - send_width
    if max_offset >= 0 then
        for offset = 0, max_offset, step do offsets[#offsets + 1] = offset end
    end

    local function output_caption(offset)
        local first = offset + 1
        local last = offset + send_width
        return send_width == 1 and ('%d'):format(first)
            or ('%d-%d'):format(first, last)
    end

    local output_entries = {}
    local current_out_idx = nil
    for i, offset in ipairs(offsets) do
        if offset == current_offset then current_out_idx = i end
        output_entries[#output_entries + 1] = output_caption(offset)
    end
    -- Out-of-range current routing remains unchanged and visible in preview,
    -- but is never inserted as an extra selectable item above channel 9-10.
    local output_preview = selected_track and output_caption(current_offset) or '-'
    if #offsets == 0 then
        output_preview = selected_track and 'N/A' or '-'
    end

    local function StepOutputChannels(direction)
        if #offsets == 0 then return end
        local new_offset
        if direction > 0 then
            for _, offset in ipairs(offsets) do
                if offset > current_offset then new_offset = offset; break end
            end
            new_offset = new_offset or offsets[1]
        else
            for i = #offsets, 1, -1 do
                if offsets[i] < current_offset then new_offset = offsets[i]; break end
            end
            new_offset = new_offset or offsets[#offsets]
        end
        Action_SetParentOutputOffset(new_offset)
        current_offset = new_offset
    end

    reaper.ImGui_SameLine(ctx, 0, between_groups)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, 'Out')
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, 'Master/Parent output channels (destination); preserves the number of sent channels')
    end
    reaper.ImGui_SameLine(ctx, 0, out_label_right_gap)
    local can_change_out = can_change and #offsets > 0
    if not can_change_out then reaper.ImGui_BeginDisabled(ctx) end
    local out_previous = reaper.ImGui_Button(ctx, '◀##TrackOutputPrev', nav_width, 0)
    if out_previous and can_change_out then StepOutputChannels(-1) end
    reaper.ImGui_SameLine(ctx, 0, nav_gap)
    local new_out_idx = DrawCenteredChannelCombo(ctx, '##TrackParentOutput',
        output_preview, output_entries, current_out_idx, out_combo_width)
    if new_out_idx and can_change_out then
        Action_SetParentOutputOffset(offsets[new_out_idx])
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx,
            'Master/Parent output destination: ' .. output_caption(current_offset)
            .. '. Selecting channels beyond the parent width expands the parent track.')
    end
    reaper.ImGui_SameLine(ctx, 0, nav_gap)
    local out_following = reaper.ImGui_Button(ctx, '▶##TrackOutputNext', nav_width, 0)
    if out_following and can_change_out then StepOutputChannels(1) end
    if not can_change_out then reaper.ImGui_EndDisabled(ctx) end
end

------------------------------------------------------------
-- UI: Context-specific Actions
------------------------------------------------------------

local function DrawTrackActions(ctx)
    local available_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local button_gap = S(6)
    local button_width = math.max(1, (available_width - (button_gap * 2)) / 3)
    if reaper.ImGui_Button(ctx, "Trim", button_width, S(22)) then
        Action_SetSelectedTracksAutomationMode(0)
    end
    reaper.ImGui_SameLine(ctx, 0, button_gap)
    if reaper.ImGui_Button(ctx, "Read", button_width, S(22)) then
        Action_SetSelectedTracksAutomationMode(1)
    end
    reaper.ImGui_SameLine(ctx, 0, button_gap)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x992222FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCC3333FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF4444FF)
    if reaper.ImGui_Button(ctx, "Write", button_width, S(22)) then
        Action_SetSelectedTracksAutomationMode(3)
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
end

local function DrawTimelineActions(ctx)
    local overlapping_regions = GetOverlappingRegions()
    local has_regions = overlapping_regions and #overlapping_regions > 0
    reaper.ImGui_BeginDisabled(ctx, not has_regions)
    local button_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    if reaper.ImGui_Button(ctx, "Delete Selected Regions", button_width, S(22)) then
        DeleteOverlappingRegions()
    end
    reaper.ImGui_EndDisabled(ctx)
    if not has_regions then
        reaper.ImGui_Text(ctx, "Description: Adjust a time selection over one or more regions.")
    end
end

-- Shared core for the standalone Track Manager and JKK_ReaTools.
local track_mgr_core = nil
local function GetTrackManagerCore()
    if track_mgr_core then return track_mgr_core end
    if _G.JKK_TrackManagerCore then
        track_mgr_core = _G.JKK_TrackManagerCore
        return track_mgr_core
    end
    local this_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
    local path = this_dir .. "JKK_TrackManager_Core.lua"
    if reaper.file_exists(path) then
        local ok, result = pcall(dofile, path)
        if ok then track_mgr_core = result end
    end
    return track_mgr_core
end

local function DrawActivationAndSort(ctx)
    local core = GetTrackManagerCore()
    local available_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    -- The three management buttons share exactly the same 1:1:1 geometry
    -- as Trim / Read / Write. Shorten captions only if necessary.
    local gap = S(6)
    local third = math.max(1, (available_width - gap * 2) / 3)
    local function ResponsiveCaption(full, short)
        local text_width = select(1, reaper.ImGui_CalcTextSize(ctx, full))
        return (text_width + S(12) <= third) and full or short
    end
    local sel_count = reaper.CountSelectedTracks(0)

    reaper.ImGui_BeginDisabled(ctx, sel_count == 0 or core == nil)
    local any_active = false
    if core then
        for i = 0, sel_count - 1 do
            local tr = reaper.GetSelectedTrack(0, i)
            if tr and core.IsTrackActive(tr) then any_active = true; break end
        end
    end
    local label = any_active and "Deactivate Tracks" or "Activate Tracks"
    local activation_caption = ResponsiveCaption(label, any_active and "Deactivate" or "Activate")
    if reaper.ImGui_Button(ctx, activation_caption .. "##JKK_Activation", third, S(22)) and core then
        core.ToggleSelectedTracksActive()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Toggle activation of selected tracks and folder descendants")
    end
    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_SameLine(ctx, 0, gap)
    if reaper.ImGui_Button(ctx, ResponsiveCaption("Delete Unused Tracks", "Delete Unused") .. "##JKK_DeleteUnused", third, S(22)) then
        DeleteEmptyTracksAndFolders()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Delete empty tracks and folders")
    end

    reaper.ImGui_SameLine(ctx, 0, gap)
    reaper.ImGui_BeginDisabled(ctx, sel_count == 0 or core == nil)
    if reaper.ImGui_Button(ctx, ResponsiveCaption("Sort Tracks A-Z", "Sort A-Z") .. "##JKK_SortTracks", third, S(22)) and core then
        local ok, message = core.SortSelectedTrackSiblingsAZ()
        if not ok and message and not message:find("already sorted", 1, true) then
            reaper.MB(message, "Sort Tracks", 0)
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Sort all direct siblings A-Z at the first selected track's level; folder children stay together and are not sorted")
    end
    reaper.ImGui_EndDisabled(ctx)
end

local function JKK_TrackTool_Draw(ctx, active_context)
    active_context = active_context or "track"
    if active_context == "track" then
        DrawTrackBatchController(ctx)
        reaper.ImGui_Spacing(ctx)
        -- Automation modes sit above; management actions are the fixed footer.
        DrawTrackActions(ctx)

        local footer_cursor_y = reaper.ImGui_GetCursorPosY(ctx)
        local _, footer_available_y = reaper.ImGui_GetContentRegionAvail(ctx)
        local management_height = S(22)
        reaper.ImGui_SetCursorPosY(
            ctx, footer_cursor_y + math.max(0, footer_available_y - management_height)
        )
        DrawActivationAndSort(ctx)
    elseif active_context == "timeline" then
        DrawTimelineActions(ctx)
    end
end

return {
    JKK_TrackTool_Draw = JKK_TrackTool_Draw,
    JKK_TrackTool_DrawController = DrawTrackBatchController,
    JKK_TrackTool_DrawActions = DrawTrackActions,
    JKK_TrackTool_DrawTimelineActions = DrawTimelineActions
}