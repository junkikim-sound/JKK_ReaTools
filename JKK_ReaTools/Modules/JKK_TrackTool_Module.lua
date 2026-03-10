--========================================================
-- @title JKK_Track Manager_Module
-- @author Junki Kim
-- @noindex
--========================================================

local open = true

local theme_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_Theme/JKK_Theme.lua"
local theme_module = nil
if reaper.file_exists(theme_path) then
    theme_module = dofile(theme_path)
end

local ApplyTheme = theme_module and theme_module.ApplyTheme or function(ctx) return 0, 0 end
local style_pop_count, color_pop_count

local select_level = 0
local volume_db = 0.0
local pan_val = 0.0

local first_sel_tr = reaper.GetSelectedTrack(0, 0)
if first_sel_tr then
    local linear_vol = reaper.GetMediaTrackInfo_Value(first_sel_tr, "D_VOL")
    
    if linear_vol > 0 then
        volume_db = 20.0 * math.log(linear_vol) / math.log(10) 
    else
        volume_db = -100.0
    end
    volume_db = math.min(volume_db, 12.0)
    pan_val = reaper.GetMediaTrackInfo_Value(first_sel_tr, "D_PAN")
end

-- Track Renamer
local reaper = reaper
local base_name = ""
local last_sel_tr_guid = nil

-- Color Palette Data (24 Colors)
local track_colors = {
  {10,70,57}, {14,96,78},  {21,139,114}, {23,156,128},  {69,171,148},  {162,202,189}, {121,18,19}, {156,23,24},  {168,58,59},  {179,93,93},  {202,162,162}, {221,195,195},
  {10,43,70}, {15,64,104}, {23,96,156},  {102,143,182}, {171,186,207}, {225,230,237}, {88,114,47}, {125,162,67}, {159,206,85}, {184,239,99}, {205,244,152}, {226,248,200},
}

------------------------------------------------------------
-- Tracks Batch Controller
------------------------------------------------------------
    -- Batch Track Rename
        function RenameTracks()
            local sel_cnt = reaper.CountSelectedTracks(0)
            if sel_cnt == 0 then return end

            reaper.Undo_BeginBlock()
            for i = 0, sel_cnt - 1 do
                local tr = reaper.GetSelectedTrack(0, i)
                local new_name
                
                if is_sequential_name then
                    new_name = string.format("%s_%02d", base_name, i + 1)
                else
                    new_name = base_name
                end
                
                reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", new_name, true)
            end
            reaper.Undo_EndBlock('Rename Selected Tracks', -1)
        end
    -- Follow Group Track's Name
        local function GetParentFolderTrack(track)
            if not track then return nil end
            local target_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
            
            for i = target_idx - 1, 0, -1 do
                local tr = reaper.GetTrack(0, i)
                if tr then
                    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
                    if depth == 1 then
                        local check_depth = 1
                        local is_parent = false
                        for j = i + 1, target_idx do
                            local sub_tr = reaper.GetTrack(0, j)
                            if j == target_idx then
                                if check_depth >= 1 then is_parent = true end
                                break
                            end
                            check_depth = check_depth + reaper.GetMediaTrackInfo_Value(sub_tr, "I_FOLDERDEPTH")
                            if check_depth <= 0 then break end
                        end
                        if is_parent then return tr end
                    end
                end
            end
            return nil
        end

        local function FollowFolderName()
            local count = reaper.CountSelectedTracks(0)
            if count == 0 then return end

            reaper.Undo_BeginBlock()

            local parent_counters = {}

            for i = 0, count - 1 do
                local track = reaper.GetSelectedTrack(0, i)
                if track then
                    local parent = GetParentFolderTrack(track)
                    
                    if parent then
                        local parent_guid = reaper.GetTrackGUID(parent)
                        
                        if not parent_counters[parent_guid] then
                            parent_counters[parent_guid] = 1
                        else
                            parent_counters[parent_guid] = parent_counters[parent_guid] + 1
                        end

                        local current_idx = parent_counters[parent_guid]
                        local retval, parent_name = reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
                        
                        if retval and parent_name ~= "" then
                            local new_name = string.format("%s_%02d", parent_name, current_idx)
                            reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
                        end
                    end
                end
            end

            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Rename Selected Tracks by Parent (Smart Numbering)", -1)
        end
    -- Set Selected Tracks Volume
        local function Action_SetSelectedTracksVolume(vol_val)
            reaper.Undo_BeginBlock()
            local selcnt = reaper.CountSelectedTracks(0)
            for i = 0, selcnt - 1 do
                local tr = reaper.GetSelectedTrack(0, i)
                reaper.SetMediaTrackInfo_Value(tr, "D_VOL", vol_val) 
            end
            reaper.Undo_EndBlock("Set Selected Tracks Volume", -1)
        end
    -- Set Selected Tracks Pan
        local function Action_SetSelectedTracksPan(pan_val)
            reaper.Undo_BeginBlock()
            local selcnt = reaper.CountSelectedTracks(0)
            for i = 0, selcnt - 1 do
                local tr = reaper.GetSelectedTrack(0, i)
                reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan_val)
            end
            reaper.Undo_EndBlock("Set Selected Tracks Panning", -1)
        end
    -- Set Selected Tracks Width
        local width_val = 1.0
        local function Action_SetSelectedTracksWidth(width_val)
            reaper.Undo_BeginBlock()
            local selcnt = reaper.CountSelectedTracks(0)
            for i = 0, selcnt - 1 do
                local tr = reaper.GetSelectedTrack(0, i)
                -- D_WIDTH: -1.0 (reverse stereo) to 1.0 (normal stereo)
                reaper.SetMediaTrackInfo_Value(tr, "D_WIDTH", width_val)
            end
            reaper.Undo_EndBlock("Set Selected Tracks Width", -1)
        end
    -- Constants & Static Functions
        local MAX_DB = 12.0
        local MIN_DB = -100.0

        -- 볼륨 dB -> 슬라이더 위치 (0~1)
        local function db_to_slider_pos(db)
            if db <= 0 then
                return ((db + 100.0) * 0.75) / 100.0
            else
                return 0.75 + (db / MAX_DB) * 0.25
            end
        end

        -- 슬라이더 위치 (0~1) -> 볼륨 dB
        local function slider_pos_to_db(pos)
            if pos <= 0.75 then
                return (pos / 0.75) * 100.0 + MIN_DB
            else
                return ((pos - 0.75) / 0.25) * MAX_DB
            end
        end

        -- [State Variables]
        local volume_db = 0.0
        local pan_val = 0.0
    -- Draw Slider
        function DrawTrackBatchController(ctx)
            local sel_tr = reaper.GetSelectedTrack(0, 0)
            -- 1. 트랙 상태 동기화 (사용자가 마우스로 슬라이더를 잡고 있지 않을 때만)
            if sel_tr and not reaper.ImGui_IsAnyItemActive(ctx) then 
                -- Volume Sync
                local linear_vol = reaper.GetMediaTrackInfo_Value(sel_tr, "D_VOL")
                volume_db = (linear_vol > 0) and (20.0 * math.log(linear_vol, 10)) or MIN_DB
                volume_db = math.max(MIN_DB, math.min(volume_db, MAX_DB))
                
                -- Pan Sync
                pan_val = reaper.GetMediaTrackInfo_Value(sel_tr, "D_PAN")

                -- Width Sync
                if sel_tr and not reaper.ImGui_IsAnyItemActive(ctx) then
                    width_val = reaper.GetMediaTrackInfo_Value(sel_tr, "D_WIDTH")
                end
            end

            -- 2. Volume Slider
                local vol_format = (volume_db <= MIN_DB) and "-inf dB" or string.format("%.1f dB", volume_db)
                -- 2. Volume Slider (슬라이더 내부 텍스트 포맷팅 적용)
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, "   Volume")
                reaper.ImGui_SameLine(ctx)

                local current_slider_pos = db_to_slider_pos(volume_db)
                reaper.ImGui_SetNextItemWidth(ctx, 272)
                reaper.ImGui_SetCursorPosX(ctx, 494)

                -- ★ 마지막 인자에 "" 대신 미리 만든 vol_format을 넣습니다.
                local changed_vol, new_slider_pos = reaper.ImGui_SliderDouble(ctx, '##VolumeSlider', current_slider_pos, 0.0, 1.0, vol_format)
                local reset_vol = reaper.ImGui_IsItemClicked(ctx, 1)

                -- 3. Volume Logic
                if reset_vol then
                    volume_db = 0.0
                    Action_SetSelectedTracksVolume(1.0)
                elseif changed_vol then
                    volume_db = slider_pos_to_db(new_slider_pos)
                    local linear_vol = 10 ^ (volume_db / 20.0)
                    Action_SetSelectedTracksVolume(math.min(linear_vol, 3.98)) -- Max +12dB
                end
            -- 3. Pan Slider
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, "   Pan")
                reaper.ImGui_SameLine(ctx)

                local pan_display_val = math.abs(pan_val * 100)
                local pan_format = "Center"
                
                if pan_val < 0 then
                    pan_format = string.format("%.0fL", pan_display_val)
                elseif pan_val > 0 then
                    pan_format = string.format("%.0fR", pan_display_val)
                end
                reaper.ImGui_SetNextItemWidth(ctx, 272)
                reaper.ImGui_SetCursorPosX(ctx, 494)
                local changed_pan, new_pan = reaper.ImGui_SliderDouble(ctx, '##Pan', pan_val, -1.0, 1.0, pan_format)
    
                -- 우클릭 초기화 (0.0으로 리셋)
                if reaper.ImGui_IsItemClicked(ctx, 1) then
                    pan_val = 0.0
                    Action_SetSelectedTracksPan(0.0)
                elseif changed_pan then
                    pan_val = new_pan
                    Action_SetSelectedTracksPan(pan_val)
                end
            -- 4. Width Slider
                local width_display = math.abs(width_val * 100)
                local width_format = string.format("%.0f W", width_display)

                if width_val == 0 then 
                    width_format = "Mono"
                elseif width_val < 0 then
                    width_format = string.format("%.0f W (Rev)", width_display)
                end

                -- 3. Width Slider 그리기
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, "   Width")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 272)
                reaper.ImGui_SetCursorPosX(ctx, 494)

                local changed_width, new_width = reaper.ImGui_SliderDouble(ctx, '##WidthSlider', width_val, -1.0, 1.0, width_format)

                -- 우클릭 시 기본 스테레오(1.0, 100%)로 초기화
                if reaper.ImGui_IsItemClicked(ctx, 1) then
                    width_val = 1.0
                    Action_SetSelectedTracksWidth(1.0)
                elseif changed_width then
                    width_val = new_width
                    Action_SetSelectedTracksWidth(width_val)
                end
        end

------------------------------------------------------------
-- Actions
------------------------------------------------------------
    -- Remove Unused Tracks
        local function DeleteEmptyTracksAndFolders()
            local function IsTrackUnused(track)
                if reaper.CountTrackMediaItems(track) > 0 then return false end
                if reaper.GetTrackNumSends(track, -1) > 0 then return false end
                if reaper.GetTrackNumSends(track, 0) > 0 then return false end
                if reaper.GetTrackNumSends(track, 1) > 0 then return false end
                if reaper.GetMediaTrackInfo_Value(track, 'I_RECARM') == 1 then return false end
                if reaper.CountTrackEnvelopes(track) > 0 then return false end
                return true
            end

            reaper.Undo_BeginBlock()
            reaper.PreventUIRefresh(1)

            local saved_tracks = {}
            for i = 0, reaper.CountSelectedTracks(0) - 1 do
                table.insert(saved_tracks, reaper.GetSelectedTrack(0, i))
            end

            reaper.Main_OnCommand(40297, 0)

            local trackCount = reaper.CountTracks(0)
            for i = trackCount - 1, 0, -1 do
                local track = reaper.GetTrack(0, i)
                local folder_depth = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
                
                if folder_depth == 1 then
                    local childUsed = false
                    local depth = reaper.GetTrackDepth(track)
                    local trackidx = i + 1
                    
                    while trackidx < trackCount do
                        local child = reaper.GetTrack(0, trackidx)
                        local childDepth = reaper.GetTrackDepth(child)
                        if childDepth <= depth then break end
                        
                        if not reaper.IsTrackSelected(child) then
                            childUsed = true
                            break
                        end
                        trackidx = trackidx + 1
                    end
                    
                    if not childUsed then
                        reaper.SetTrackSelected(track, IsTrackUnused(track))
                    end
                else
                    reaper.SetTrackSelected(track, IsTrackUnused(track))
                end
            end

            reaper.Main_OnCommand(40005, 0) 
            for _, tr in ipairs(saved_tracks) do
                if reaper.ValidatePtr(tr, 'MediaTrack*') then
                    reaper.SetTrackSelected(tr, true)
                end
            end

            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("JKK: Delete Unused Tracks", -1)
        end
    -- Track Automation Mode (Trim/Read, Read, Write)
    -- Track Channel Set (7.1 까지)

----------------------------------------------------------
-- Color Palette 
----------------------------------------------------------
    local function SetTrackColors(r, g, b)
      local count = reaper.CountSelectedTracks(0)
      if count == 0 then return end

      reaper.Undo_BeginBlock()

      local native_color
      if r == 0 and g == 0 and b == 0 then
        native_color = 0 -- Remove custom color
      else
        native_color = reaper.ColorToNative(r, g, b) | 0x1000000
      end

      for i = 0, count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", native_color)
      end

      reaper.UpdateArrange()
      reaper.Undo_EndBlock("Set Track Color", -1)
    end

------------------------------------------------------------
-- UI_Mudule
------------------------------------------------------------
    function JKK_TrackTool_Draw(ctx)        
        local sel_tr = reaper.GetSelectedTrack(0, 0)
        local current_guid = sel_tr and reaper.GetTrackGUID(sel_tr) or nil
        if current_guid ~= last_sel_tr_guid then
            if sel_tr then
                local retval, name = reaper.GetSetMediaTrackInfo_String(sel_tr, "P_NAME", "", false)
                if retval then 
                    base_name = name 
                end
            else
                base_name = "" 
            end
            last_sel_tr_guid = current_guid
        end
        local table_full      = reaper.ImGui_TableFlags_SizingFixedFit() | 
                                reaper.ImGui_TableFlags_BordersInnerV()
        if reaper.ImGui_BeginTable(ctx, "table_full", 3, table_full) then
            reaper.ImGui_TableSetupColumn(ctx, 'table_01', reaper.ImGui_TableColumnFlags_WidthFixed(), 405)
            reaper.ImGui_TableSetupColumn(ctx, 'table_02', reaper.ImGui_TableColumnFlags_WidthFixed(), 425)
            reaper.ImGui_TableSetupColumn(ctx, 'table_03', reaper.ImGui_TableColumnFlags_WidthFixed(), 460)
            reaper.ImGui_TableNextColumn(ctx)
            -- Tracks Batch Controller ====================================
                reaper.ImGui_SeparatorText(ctx, 'Tracks Batch Controller')
                    reaper.ImGui_Text(ctx, " ")
                    reaper.ImGui_SameLine(ctx)
                    local changed_base_name, new_base_name = reaper.ImGui_InputTextMultiline(ctx, '##RenameNewBaseName', base_name, 272, 22)
                    if changed_base_name then base_name = new_base_name end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "Clear##ClearBaseName", 55, 22) then
                        base_name = ""
                    end

                    reaper.ImGui_Text(ctx, " ")
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, 'Edit Tracks Name', 132, 22) then
                        if base_name ~= "" then
                            RenameTracks()
                        end
                    end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, 'Follow Folder Name', 132, 22) then
                        if base_name ~= "" then
                            FollowFolderName()
                        end
                    end
                    reaper.ImGui_SameLine(ctx)
                    local chk_changed, chk_val = reaper.ImGui_Checkbox(ctx, "_nn", is_sequential_name)
                    if chk_changed then
                        is_sequential_name = chk_val -- 값 업데이트
                    end
                    reaper.ImGui_Spacing(ctx)
                    DrawTrackBatchController(ctx)
            -- Actions ====================================================
                reaper.ImGui_SeparatorText(ctx, 'Actions')
                
                if reaper.ImGui_Button(ctx, 'Delete Empty Tracks', 90, 22) then
                    if base_name ~= "" then
                        DeleteEmptyTracksAndFolders()
                    end
                end

                reaper.ImGui_Spacing(ctx)
            -- Track Color Palette ========================================
                reaper.ImGui_SeparatorText(ctx, 'Track Color Palette')
                local table_03      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_color", 2, table_01) then
                    reaper.ImGui_TableSetupColumn(ctx, 'colors', reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
                    reaper.ImGui_TableSetupColumn(ctx, 'default', reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
                    reaper.ImGui_TableNextColumn(ctx)
                        local palette_columns = 12
                        for i, col in ipairs(track_colors) do
                            local r, g, b = col[1], col[2], col[3]                          
                            local packed_col = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, 1.0)    

                            reaper.ImGui_PushID(ctx, "col"..i)                          
                            if reaper.ImGui_ColorButton(ctx, "##Color", packed_col, 0, 25, 25) then
                                SetTrackColors(r, g, b)
                            end
                            reaper.ImGui_PopID(ctx)
                            if i % palette_columns ~= 0 then
                                reaper.ImGui_SameLine(ctx)
                            end
                        end
                        reaper.ImGui_TableNextColumn(ctx)
                        reaper.ImGui_PushID(ctx, "col_default")
                        local packed_default_col = reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1.0)
                        if reaper.ImGui_ColorButton(ctx, "##DefaultColor", packed_default_col, 0, 30, 55) then
                            SetTrackColors(0, 0, 0)
                        end
                        reaper.ImGui_PopID(ctx)
                    reaper.ImGui_TableNextColumn(ctx)
                    reaper.ImGui_EndTable(ctx)
                end 
            reaper.ImGui_TableNextColumn(ctx)
            reaper.ImGui_TableNextColumn(ctx)
            reaper.ImGui_EndTable(ctx)
        end
    end
return {
    JKK_TrackTool_Draw = JKK_TrackTool_Draw
}