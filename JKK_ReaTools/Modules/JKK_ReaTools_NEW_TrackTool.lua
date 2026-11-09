--========================================================
-- @title JKK_ReaTools_NEW_TrackTool
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper

------------------------------------------------------------
-- Track Controller State
------------------------------------------------------------
local MAX_DB = 12.0
local MIN_DB = -100.0

local volume_db = 0.0
local pan_val = 0.0
local width_val = 1.0
local track_channels = 2

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

local function Action_RoundSelectedTracksVolumeToHalfDB()
    local count = reaper.CountSelectedTracks(0)
    if count == 0 then return end

    reaper.Undo_BeginBlock()
    for i = 0, count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
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
    reaper.Undo_EndBlock("Round Volume to 0.5dB", -1)
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

local function DrawTrackBatchController(ctx)
    local selected_track = reaper.GetSelectedTrack(0, 0)
    local selected_count = reaper.CountSelectedTracks(0)

    -- Refresh cached values only when a track exists. With no selection, keep
    -- the last values on screen; the parent panel disables all interactions.
    if selected_track and selected_count > 0 and not reaper.ImGui_IsAnyItemActive(ctx) then
        local linear_vol = reaper.GetMediaTrackInfo_Value(selected_track, "D_VOL")
        volume_db = (linear_vol > 0)
            and (20.0 * math.log(linear_vol) / math.log(10))
            or MIN_DB
        volume_db = math.max(MIN_DB, math.min(volume_db, MAX_DB))
        pan_val = reaper.GetMediaTrackInfo_Value(selected_track, "D_PAN")
        width_val = reaper.GetMediaTrackInfo_Value(selected_track, "D_WIDTH")
        track_channels = reaper.GetMediaTrackInfo_Value(selected_track, "I_NCHAN") or track_channels
    end

    local label_width = 86
    local round_button_width = 48
    local row_gap = 6
    local row_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))

    -- Volume reserves the exact space required by the 0.5 dB button. The
    -- lower controls use the full combined width, so their right edges align
    -- with the right edge of that button.
    local volume_slider_width = math.max(1,
        row_width - label_width - round_button_width - row_gap)
    local full_control_width = math.max(1, row_width - label_width)

    local function BeginLabeledRow(label)
        local row_x = reaper.ImGui_GetCursorPosX(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, label)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, row_x + label_width)
    end

    -- Volume: leave a reserved 0.5 dB button slot so every track slider has the same width.
    BeginLabeledRow("Volume")
    reaper.ImGui_SetNextItemWidth(ctx, volume_slider_width)
    local vol_format = (volume_db <= MIN_DB) and "-inf dB" or string.format("%.1f dB", volume_db)
    local changed_vol, new_slider_pos = reaper.ImGui_SliderDouble(
        ctx, "##TrackVolume", db_to_slider_pos(volume_db), 0.0, 1.0, vol_format
    )
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_vol then
        volume_db = slider_pos_to_db(new_slider_pos)
        Action_SetSelectedTracksVolume(math.min(10 ^ (volume_db / 20.0), 3.98))
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Set Selected Tracks Volume", -1)
    end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        volume_db = 0.0
        Action_SetSelectedTracksVolume(1.0)
        reaper.Undo_EndBlock("Reset Volume", -1)
    end
    reaper.ImGui_SameLine(ctx, 0, row_gap)
    if reaper.ImGui_Button(ctx, "0.5dB", round_button_width, 22) then
        Action_RoundSelectedTracksVolumeToHalfDB()
        ReadSelectedTrackValues()
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
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_pan then
        pan_val = new_pan
        Action_SetSelectedTracksPan(pan_val)
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Set Selected Tracks Panning", -1)
    end
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
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_width then
        width_val = new_width
        Action_SetSelectedTracksWidth(width_val)
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Set Selected Tracks Width", -1)
    end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        width_val = 1.0
        Action_SetSelectedTracksWidth(1.0)
        reaper.Undo_EndBlock("Reset Width", -1)
    end

    -- Channels: align its control with the slider start, matching the rows above.
    BeginLabeledRow("Channels")
    local channel_options = " 2 ch\0 4 ch\0 6 ch\0 8 ch\0 10 ch\0 12 ch\0 16 ch\0"
    local current_nchan = selected_track
        and reaper.GetMediaTrackInfo_Value(selected_track, "I_NCHAN")
        or track_channels
    local channel_map = {2, 4, 6, 8, 10, 12, 16}
    local channel_idx = 0
    for i, value in ipairs(channel_map) do
        if value == current_nchan then
            channel_idx = i - 1
            break
        end
    end
    reaper.ImGui_SetNextItemWidth(ctx, full_control_width)
    local changed_channels, new_channel_idx = reaper.ImGui_Combo(ctx, "##TrackChannels", channel_idx, channel_options)
    if changed_channels then
        Action_SetTrackChannels(channel_map[new_channel_idx + 1])
    end
end

------------------------------------------------------------
-- UI: Context-specific Actions
------------------------------------------------------------
local function DrawTrackActions(ctx)
    local available_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    if reaper.ImGui_Button(ctx, "Delete Unused Tracks", available_width, 22) then
        DeleteEmptyTracksAndFolders()
    end

    local button_gap = 6
    local button_width = math.max(1, (available_width - (button_gap * 2)) / 3)
    if reaper.ImGui_Button(ctx, "Trim", button_width, 22) then
        Action_SetSelectedTracksAutomationMode(0)
    end
    reaper.ImGui_SameLine(ctx, 0, button_gap)
    if reaper.ImGui_Button(ctx, "Read", button_width, 22) then
        Action_SetSelectedTracksAutomationMode(1)
    end
    reaper.ImGui_SameLine(ctx, 0, button_gap)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x992222FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCC3333FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF4444FF)
    if reaper.ImGui_Button(ctx, "Write", button_width, 22) then
        Action_SetSelectedTracksAutomationMode(3)
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
end

local function DrawTimelineActions(ctx)
    local overlapping_regions = GetOverlappingRegions()
    local has_regions = overlapping_regions and #overlapping_regions > 0
    reaper.ImGui_BeginDisabled(ctx, not has_regions)
    local button_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    if reaper.ImGui_Button(ctx, "Delete Selected Regions", button_width, 22) then
        DeleteOverlappingRegions()
    end
    reaper.ImGui_EndDisabled(ctx)
    if not has_regions then
        reaper.ImGui_Text(ctx, "Adjust a time selection over one or more regions.")
    end
end

local function JKK_TrackTool_Draw(ctx, active_context)
    active_context = active_context or "track"
    if active_context == "track" then
        DrawTrackBatchController(ctx)

        -- Keep Delete Unused Tracks and the Trim / Read / Write row at the
        -- bottom of the full-height controller panel.
        local footer_cursor_y = reaper.ImGui_GetCursorPosY(ctx)
        local _, footer_available_y = reaper.ImGui_GetContentRegionAvail(ctx)
        local track_actions_height = 22 * 2 + 6 -- two rows plus one row gap
        reaper.ImGui_SetCursorPosY(
            ctx, footer_cursor_y + math.max(0, footer_available_y - track_actions_height)
        )
        DrawTrackActions(ctx)
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
