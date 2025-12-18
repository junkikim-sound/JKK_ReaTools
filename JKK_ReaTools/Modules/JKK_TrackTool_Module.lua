--========================================================
-- @title JKK_Track Manager_Module
-- @author Junki Kim
-- @version 0.6.1
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

-- Color Palette Data (24 Colors)
local track_colors = {
  {10,70,57}, {14,96,78},  {21,139,114}, {23,156,128},  {69,171,148},  {162,202,189}, {121,18,19}, {156,23,24},  {168,58,59},  {179,93,93},  {202,162,162}, {221,195,195},
  {10,43,70}, {15,64,104}, {23,96,156},  {102,143,182}, {171,186,207}, {225,230,237}, {88,114,47}, {125,162,67}, {159,206,85}, {184,239,99}, {205,244,152}, {226,248,200},
}

-- Icon Set
local icon_path      = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Icons/"
local icon_crtts     = nil
local icon_crtregion = nil
local icon_flwgrp    = nil
local icon_delunsd   = nil

------------------------------------------------------------
-- Function: Set Selected Tracks Volume
------------------------------------------------------------
local function Action_SetSelectedTracksVolume(vol_val)
    reaper.Undo_BeginBlock()
    local selcnt = reaper.CountSelectedTracks(0)
    for i = 0, selcnt - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        reaper.SetMediaTrackInfo_Value(tr, "D_VOL", vol_val) 
    end
    reaper.Undo_EndBlock("JKK: Set Selected Tracks Volume", -1)
end

------------------------------------------------------------
-- Function: Set Selected Tracks Pan
------------------------------------------------------------
local function Action_SetSelectedTracksPan(pan_val)
    reaper.Undo_BeginBlock()
    local selcnt = reaper.CountSelectedTracks(0)
    for i = 0, selcnt - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan_val)
    end
    reaper.Undo_EndBlock("JKK: Set Selected Tracks Panning", -1)
end

------------------------------------------------------------
-- Function: Select Track by Level
------------------------------------------------------------
local function GetTrackCount() return reaper.CountTracks(0) end

local function CalcTrackLevelByIndex(idx)
    local level = 0
    for i = 0, idx do
        local tr = reaper.GetTrack(0, i)
        if not tr then break end
        local d = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        level = level + d
    end
    return math.max(0, level)
end

local function Action_SelectTracksByLevel(target_level)
    reaper.Undo_BeginBlock()

    local trackCount = GetTrackCount()
    
    local effective_level = target_level
    if effective_level > 0 then
        effective_level = effective_level - 1 
    end

    for idx = 0, trackCount - 1 do
        local tr = reaper.GetTrack(0, idx)
        if tr then
            local current_level = CalcTrackLevelByIndex(idx)
            
            local select_it = false
            
            if target_level == 0 then
                select_it = true
            elseif current_level == effective_level then
                select_it = true
            end
            
            reaper.SetTrackSelected(tr, select_it)
        end
    end
    
    reaper.Undo_EndBlock("JKK: Select Tracks by Level", -1)
end

local function GetSortedSelectedTracksWithLevel()
    local out = {}
    local selcnt = reaper.CountSelectedTracks(0)
    for i = 0, selcnt - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        local idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
        local level = CalcTrackLevelByIndex(idx) 
        table.insert(out, {track = tr, idx = idx, level = level})
    end
    table.sort(out, function(a,b) return a.idx < b.idx end)
    return out
end

local function GetFullFolderRangeIndicesByIndex(start_idx)
    local tr = reaper.GetTrack(0, start_idx)
    if not tr then return {start_idx} end

    local folderDepth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    
    if folderDepth <= 0 then
        return {start_idx}
    end
    
    local depth_count = 1
    local out = {start_idx}

    local trackCount = GetTrackCount()
    for i = start_idx + 1, trackCount - 1 do
        local t = reaper.GetTrack(0, i)
        if not t then break end
        local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
        
        depth_count = depth_count + d
        table.insert(out, i)
        
        if depth_count <= 0 then
            break
        end
    end

    return out
end

local function GetItemRangeFromTrackIndices(indices)
    local min_pos = math.huge
    local max_end = -math.huge
    for _, idx in ipairs(indices) do
        local tr = reaper.GetTrack(0, idx)
        if tr then
            local cnt = reaper.CountTrackMediaItems(tr)
            for j = 0, cnt - 1 do
                local item = reaper.GetTrackMediaItem(tr, j)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                if pos < min_pos then min_pos = pos end
                if pos + len > max_end then max_end = pos + len end
            end
        end
    end
    if min_pos == math.huge then return nil, nil end
    return min_pos, max_end
end

local function GetTopLevelSelectedTracks()
    local sel = GetSortedSelectedTracksWithLevel()
    if #sel == 0 then return {} end
    
    return sel 
end

------------------------------------------------------------
-- Function: Create Time Selection
------------------------------------------------------------
local function Action_TimeSelection()
    reaper.Undo_BeginBlock()
    local topSel = GetTopLevelSelectedTracks() 
    if #topSel == 0 then 
        reaper.Undo_EndBlock("JKK: TimeSelection (none)", -1) 
        return 
    end
    
    local idxSet = {}
    for _, e in ipairs(topSel) do
        local indices = GetFullFolderRangeIndicesByIndex(e.idx)
        for _, ii in ipairs(indices) do idxSet[ii] = true end
    end

    local indicesList = {}
    for k,_ in pairs(idxSet) do table.insert(indicesList, k) end
    table.sort(indicesList)

    local min_pos, max_end = GetItemRangeFromTrackIndices(indicesList)
    if min_pos then
        reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
    end

    reaper.Undo_EndBlock("JKK: TimeSelection (merged all selected tracks)", -1)
end

------------------------------------------------------------
-- Function: Create Regions
------------------------------------------------------------
local function CreateRegion(start_pos, end_pos, name)
    if start_pos and end_pos and end_pos > start_pos then
        reaper.AddProjectMarker2(0, true, start_pos, end_pos, name or "", -1, 0)
    end
end

local function Action_CreateRegions()
    reaper.Undo_BeginBlock()
    local topSel = GetTopLevelSelectedTracks()
    if #topSel == 0 then reaper.Undo_EndBlock("JKK: CreateRegions (none)", -1) return end

    for _, e in ipairs(topSel) do
        local indices = GetFullFolderRangeIndicesByIndex(e.idx)
        local min_pos, max_end = GetItemRangeFromTrackIndices(indices)
        if min_pos then
            local _, name = reaper.GetSetMediaTrackInfo_String(e.track, "P_NAME", "", false)
            CreateRegion(min_pos, max_end, (name ~= "") and name or ("Region_"..(e.idx+1)))
        end
    end

    reaper.Undo_EndBlock("JKK: CreateRegions (per selected track)", -1)
end

------------------------------------------------------------
-- Function: Remove Unused Tracks
------------------------------------------------------------

local function Safe_GetTrack(proj, idx)
    return reaper.GetTrack(proj, idx)
end

local function TrackHasItems(track)
    if not track then return false end
    return reaper.CountTrackMediaItems(track) > 0
end

local function IsFolderStart(track)
    if not track then return false end
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
end

local function FolderIsEmpty(proj, start_index, track_count)
    local depth = 1
    local has_items = TrackHasItems(Safe_GetTrack(proj, start_index))
    if has_items then return false end

    for i = start_index + 1, track_count - 1 do
        local tr = Safe_GetTrack(proj, i)
        if not tr then break end
        local d = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        depth = depth + d
        if depth <= 0 then
            if i == start_index + 1 then
                return true
            else
                return false
            end
        end
    end

    return true
end

local function DeleteEmptyTracksAndFolders()
    local proj = 0
    local track_count = reaper.CountTracks(proj)
    if track_count == 0 then return end

    reaper.Undo_BeginBlock()

    local i = track_count - 1
    while i >= 0 do
        local tr = Safe_GetTrack(proj, i)
        if tr then
            local folder_start = IsFolderStart(tr)
            local has_items = TrackHasItems(tr)

            if folder_start then
                if FolderIsEmpty(proj, i, track_count) then
                    reaper.DeleteTrack(tr)
                end
            else
                if not has_items then
                    reaper.DeleteTrack(tr)
                end
            end
        end
        i = i - 1
        track_count = reaper.CountTracks(proj)
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Delete empty tracks and folders", -1)
end

------------------------------------------------------------
-- Function: Floow Group Track's Name
------------------------------------------------------------
local function Safe_GetTrack(idx)
    return reaper.GetSelectedTrack(0, idx)
end

local function GetSelectedTrackCount()
    return reaper.CountSelectedTracks(0)
end

local function GetParentFolderTrack(track)
    if not track then return nil end
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1

    for i = idx - 1, 0, -1 do
        local tr = reaper.GetTrack(0, i)
        if tr then
            local d = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
            if d == 1 then
                return tr
            end
        end
    end
    return nil
end

local function FollowFolderName()
    local count = GetSelectedTrackCount()
    if count == 0 then return end

    reaper.Undo_BeginBlock()

    for i = 0, count - 1 do
        local track = Safe_GetTrack(i)
        if track then
            local depth_val = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if depth_val == 1 then 
                goto continue_loop 
            end
            local parent = GetParentFolderTrack(track)
            if parent then
                local retval, parent_name = reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
                if retval then
                    local new_name = string.format("%s_%02d", parent_name, i+1)
                    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
                end
            end
        end
        ::continue_loop::
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Batch Rename Tracks by Parent Folder", -1)
end

------------------------------------------------------------
-- Function: Batch Track Rename
------------------------------------------------------------
function RenameTracks()
    local sel_cnt = reaper.CountSelectedTracks(0)
    if sel_cnt == 0 then return end

    reaper.Undo_BeginBlock()
    for i = 0, sel_cnt - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        local new_name = string.format("%s_%02d", base_name, i+1)
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", new_name, true)
    end
    reaper.Undo_EndBlock('Rename Selected Tracks', -1)
end

----------------------------------------------------------
-- Function: Color Palette 
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
function JKK_TrackTool_Draw(ctx, shared_info)
    if not icon_crtts or not reaper.ImGui_ValidatePtr(icon_crtts, 'ImGui_Image*') then 
        icon_crtts = reaper.ImGui_CreateImage(icon_path .. "TRACK_Create Time Selection @streamline.png")
    end
    local draw_crtts = reaper.ImGui_ValidatePtr(icon_crtts, 'ImGui_Image*')
    if not icon_crtregion or not reaper.ImGui_ValidatePtr(icon_crtregion, 'ImGui_Image*') then 
        icon_crtregion = reaper.ImGui_CreateImage(icon_path .. "TRACK_Create Region @streamline.png")
    end
    local draw_crtregion = reaper.ImGui_ValidatePtr(icon_crtregion, 'ImGui_Image*')
    if not icon_flwgrp or not reaper.ImGui_ValidatePtr(icon_flwgrp, 'ImGui_Image*') then 
        icon_flwgrp = reaper.ImGui_CreateImage(icon_path .. "TRACK_Follow Group Name @streamline.png")
    end
    local draw_flwgrp = reaper.ImGui_ValidatePtr(icon_flwgrp, 'ImGui_Image*')
    if not icon_delunsd or not reaper.ImGui_ValidatePtr(icon_delunsd, 'ImGui_Image*') then 
        icon_delunsd = reaper.ImGui_CreateImage(icon_path .. "TRACK_Delete Unused Tracks @streamline.png")
    end
    local draw_delunsd = reaper.ImGui_ValidatePtr(icon_delunsd, 'ImGui_Image*')
    
    reaper.ImGui_Text(ctx, 'Select TRACKS before using this feature.')
    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Tracks Batch Controller')
    
    local sel_tr = reaper.GetSelectedTrack(0, 0)
    
    if sel_tr and not reaper.ImGui_IsItemActive(ctx) then 
        local linear_vol = reaper.GetMediaTrackInfo_Value(sel_tr, "D_VOL")
        
        if linear_vol > 0 then
            local current_db = 20.0 * math.log(linear_vol) / math.log(10)
            volume_db = math.min(current_db, 12.0)
        else
            volume_db = -100.0
        end
    end

    local min_db = -100.0
    local max_db = 12.0
    
    local function db_to_slider_pos(db)
        if db <= 0 then
            return ((db + 100.0) * 0.75) / 100.0
        
        else
            return 0.75 + (db / max_db) * 0.25
        end
    end

    local function slider_pos_to_db(pos)
        if pos <= 0.75 then
            local attenuation_factor = 100.0
            return (pos / 0.75) * attenuation_factor + min_db 
        
        else
            return ((pos - 0.75) / 0.25) * max_db
        end
    end
    
    local current_slider_pos = db_to_slider_pos(volume_db)
    
    local changed_vol, new_slider_pos = reaper.ImGui_SliderDouble(ctx, 'Volume', current_slider_pos, 0.0, 1.0, nil)
    local reset_vol = reaper.ImGui_IsItemClicked(ctx, 1)
    local display_db = volume_db
    if volume_db < 0 then
         display_db = volume_db
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_ADJ_VOL"
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, string.format('%.1f dB', display_db))
    
    if reset_vol then
        volume_db = 0.0
        Action_SetSelectedTracksVolume(1.0)
    elseif changed_vol then
        volume_db = slider_pos_to_db(new_slider_pos)
        local linear_vol = 10 ^ (volume_db / 20.0) 
        linear_vol = math.min(linear_vol, 3.98107) 
        Action_SetSelectedTracksVolume(linear_vol) 
    end

    local sel_tr_for_pan = reaper.GetSelectedTrack(0, 0)
    if sel_tr_for_pan and not reaper.ImGui_IsItemActive(ctx) then
        local current_pan = reaper.GetMediaTrackInfo_Value(sel_tr_for_pan, "D_PAN")
        pan_val = current_pan
    end

    local changed_pan, new_pan = reaper.ImGui_SliderDouble(ctx, 'Pan', pan_val, -1.0, 1.0, '%.2f')
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_ADJ_PAN"
    end
    local reset_pan = reaper.ImGui_IsItemClicked(ctx, 1)
    
    if reset_pan then
        pan_val = 0.0
        Action_SetSelectedTracksPan(pan_val)
    elseif changed_pan then
        pan_val = new_pan
        Action_SetSelectedTracksPan(pan_val) 
    end
    reaper.ImGui_Spacing(ctx)
    
    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Tracks Selector by Folder Level')

    local changed, new_level = reaper.ImGui_SliderInt(ctx, '##SelectLevel', select_level, 0, 8, '%d')
    if changed then
        select_level = new_level
        Action_SelectTracksByLevel(select_level) 
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_LV_SEL"
    end
    reaper.ImGui_Spacing(ctx)
    
    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Actions')
    
    if reaper.ImGui_ImageButton(ctx, "##btn_crtts", icon_crtts, 22, 22) then
        Action_TimeSelection()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_CRT_TS"
    end
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_ImageButton(ctx, "##btn_crtregion", icon_crtregion, 22, 22) then
        Action_CreateRegions()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_CRT_REGION"
    end
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_ImageButton(ctx, "##btn_flwgrp", icon_flwgrp, 22, 22) then
        FollowFolderName()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_FLWNAME"
    end
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_ImageButton(ctx, "##btn_delunsd", icon_delunsd, 22, 22) then
        DeleteEmptyTracksAndFolders()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_DEL_UNSD"
    end
    reaper.ImGui_SameLine(ctx)

    local changed_base_name, new_base_name = reaper.ImGui_InputTextMultiline(ctx, '##RenameNewBaseName', base_name, 191, 27)
    if changed_base_name then base_name = new_base_name end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_RENAME"
    end
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, 'Rename Tracks', 116, 27) then
        if base_name ~= "" then
            RenameTracks()
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        shared_info.hovered_id = "TRACK_RENAME"
    end
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_SetCursorPos(ctx, 0, 500)

    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Track Color Palette')

    local palette_columns = 12
    for i, col in ipairs(track_colors) do
        local r, g, b = col[1], col[2], col[3]
          
        local packed_col = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, 1.0)
          
        reaper.ImGui_PushID(ctx, "col"..i)
          
        if reaper.ImGui_ColorButton(ctx, "##Color", packed_col, 0, 30, 30) then
            SetTrackColors(r, g, b)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            shared_info.hovered_id = "TRACK_CHNG_COL"
        end
      
        reaper.ImGui_PopID(ctx)
      
        if i % palette_columns ~= 0 then
            reaper.ImGui_SameLine(ctx)
        end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushID(ctx, "col_default")
    local packed_default_col = reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1.0)
    if reaper.ImGui_ColorButton(ctx, "##DefaultColor", packed_default_col, 0, 45, 30) then
        SetTrackColors(0, 0, 0)
    end
    reaper.ImGui_PopID(ctx)
end
return {
    JKK_TrackTool_Draw = JKK_TrackTool_Draw,
}