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

----------------------------------------------------------
-- Icon
----------------------------------------------------------
    local TRACK_ICONS = {}

    local function LoadTrackIcons()
        if TRACK_ICONS.loaded then return end
        
        local path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Images/"
        
        TRACK_ICONS.crtts     = reaper.ImGui_CreateImage(path .. "TRACK_Create Time Selection @streamline.png")
        TRACK_ICONS.crtregion = reaper.ImGui_CreateImage(path .. "TRACK_Create Region @streamline.png")
        TRACK_ICONS.crtprlgrp = reaper.ImGui_CreateImage(path .. "TRACK_Create Parallel FX Group @streamline.png")
        TRACK_ICONS.flwgrp    = reaper.ImGui_CreateImage(path .. "TRACK_Follow Group Name @streamline.png")
        TRACK_ICONS.delunsd   = reaper.ImGui_CreateImage(path .. "TRACK_Delete Unused Tracks @streamline.png")

        
        TRACK_ICONS.loaded = true
    end

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
-- Function: Smart Track Level Selector (Contextual)
------------------------------------------------------------
    local function BuildTrackLevelMap()
        local level_map = {}
        local cnt = reaper.CountTracks(0)
        
        for i = 0, cnt - 1 do
            local tr = reaper.GetTrack(0, i)
            level_map[tr] = reaper.GetTrackDepth(tr)
        end
        return level_map
    end

    -- 특정 트랙의 부모 트랙 찾기
    local function GetParentTrack(track)
        local tr_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        local current_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        
        -- 역방향 탐색으로 부모 찾기
        -- 부모를 찾으려면 내 위쪽 트랙들을 훑으면서 레벨이 나보다 1 낮은 트랙을 찾아야 함
        -- 하지만 리퍼 구조상 위에서부터 레벨을 계산해오는게 정확함.
        
        -- 간단한 방법: 내 인덱스 위로 올라가면서, 나보다 레벨이 작은 첫번째 트랙 찾기? (X 폴더 구조상 아닐수 있음)
        -- 정석: 위에서부터 내려오며 레벨 추적.
        
        -- 여기서는 Action 실행 시 전체 맵을 만들기 때문에 그것을 활용하는 게 빠름.
        return nil -- 이 함수는 Action 내부 로직으로 대체합니다.
    end

    local function Action_SelectTracksByLevel(target_level_ui)
        -- [추가됨] 0이면 아무것도 선택하지 않음 (All Unselect)
        if target_level_ui == 0 then
            reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
            return
        end

        -- UI 값(1~)을 실제 Depth(0~)로 변환
        local target_level = target_level_ui - 1

        local sel_cnt = reaper.CountSelectedTracks(0)
        
        -- A. 아무것도 선택되지 않았을 때 -> Global Selection (0-based depth 기준)
        if sel_cnt == 0 then
            reaper.Undo_BeginBlock()
            local level_map = BuildTrackLevelMap()
            for i = 0, reaper.CountTracks(0) - 1 do
                local tr = reaper.GetTrack(0, i)
                if level_map[tr] == target_level then
                    reaper.SetTrackSelected(tr, true)
                end
            end
            reaper.Undo_EndBlock("JKK: Select Level (Global)", -1)
            return
        end

        reaper.Undo_BeginBlock()
        
        -- B. Contextual Selection (이하 로직은 Depth 기준으로 동일하게 작동)
        local level_map = BuildTrackLevelMap()
        local source_tracks = {}
        for i = 0, sel_cnt - 1 do
            table.insert(source_tracks, reaper.GetSelectedTrack(0, i))
        end

        -- 기준 레벨 확인
        local current_level = level_map[source_tracks[1]]
        
        -- ... (이하 로직은 기존과 동일하지만 target_level 변수를 그대로 사용) ...

        if target_level == current_level then
            -- 1. SIBLINGS (형제)
            local parent_ranges = {} 
            for _, src_tr in ipairs(source_tracks) do
                local parent = reaper.GetParentTrack(src_tr)
                if parent then
                    table.insert(parent_ranges, parent) 
                else
                    table.insert(parent_ranges, "ROOT")
                end
            end
            
            reaper.Main_OnCommand(40297, 0) -- Unselect all

            for i = 0, reaper.CountTracks(0) - 1 do
                local tr = reaper.GetTrack(0, i)
                local tr_parent = reaper.GetParentTrack(tr)
                local tr_level = level_map[tr]

                if tr_level == target_level then
                    for _, p_ref in ipairs(parent_ranges) do
                        if p_ref == "ROOT" then
                            if tr_parent == nil then
                                reaper.SetTrackSelected(tr, true)
                                break
                            end
                        else
                            if tr_parent == p_ref then
                                reaper.SetTrackSelected(tr, true)
                                break
                            end
                        end
                    end
                end
            end

        elseif target_level < current_level then
            -- 2. ANCESTORS (부모)
            reaper.Main_OnCommand(40297, 0) 
            
            for _, src_tr in ipairs(source_tracks) do
                local parent = reaper.GetParentTrack(src_tr)
                while parent do
                    if level_map[parent] == target_level then
                        reaper.SetTrackSelected(parent, true)
                        break 
                    end
                    if level_map[parent] < target_level then break end 
                    parent = reaper.GetParentTrack(parent)
                end
            end

        else -- target_level > current_level
            -- 3. DESCENDANTS (자식)
            reaper.Main_OnCommand(40297, 0)

            for _, src_tr in ipairs(source_tracks) do
                local src_idx = reaper.GetMediaTrackInfo_Value(src_tr, "IP_TRACKNUMBER") - 1
                local src_lvl = level_map[src_tr]
                local tr_cnt = reaper.CountTracks(0)
                
                for i = src_idx + 1, tr_cnt - 1 do
                    local child = reaper.GetTrack(0, i)
                    local child_lvl = level_map[child]
                    
                    if child_lvl <= src_lvl then break end -- 폴더 범위 끝
                    
                    if child_lvl == target_level then
                        reaper.SetTrackSelected(child, true)
                    end
                end
            end
        end

        reaper.Undo_EndBlock("JKK: Select Level (Contextual)", -1)
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
    local function DeleteEmptyTracksAndFolders()
    local proj = 0
    local track_count = reaper.CountTracks(proj)
    if track_count == 0 then return end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1) -- UI 깜빡임 방지 및 성능 향상

    -- 뒤에서부터 검사하여 삭제 시 인덱스 꼬임 방지
    for i = track_count - 1, 0, -1 do
        local tr = reaper.GetTrack(proj, i)
        if tr then
            local item_count = reaper.CountTrackMediaItems(tr)
            local fx_count = reaper.TrackFX_GetCount(tr)
            local folder_depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")

            -- [조건] 아이템 없고, FX 없고, 하위 트랙도 없는 경우 (depth가 1이면 자식이 있다는 뜻이므로 제외)
            if item_count == 0 and fx_count == 0 and folder_depth <= 0 then
                
                -- 만약 이 트랙이 폴더를 닫는 역할(< 0)을 하고 있다면, 그 값을 위쪽 트랙으로 전달
                if folder_depth < 0 then
                    if i > 0 then
                        local prev_tr = reaper.GetTrack(proj, i - 1)
                        local prev_depth = reaper.GetMediaTrackInfo_Value(prev_tr, "I_FOLDERDEPTH")
                        -- 이전 트랙의 depth에 현재 삭제될 트랙의 depth 값을 더함
                        reaper.SetMediaTrackInfo_Value(prev_tr, "I_FOLDERDEPTH", prev_depth + folder_depth)
                    end
                end
                
                -- 트랙 삭제
                reaper.DeleteTrack(tr)
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Delete unused tracks (Structure Preserved)", -1)
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

----------------------------------------------------------
-- Function: Auto Parallel FX Routing
----------------------------------------------------------
    local function CreateParallelRouting()
        local parent_track = reaper.GetSelectedTrack(0, 0)
        if not parent_track then 
            return 
        end
        local folder_depth = reaper.GetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH")
        
        if folder_depth == 1 then
            return
        end

        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)

        local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER")
        local _, parent_name = reaper.GetSetMediaTrackInfo_String(parent_track, "P_NAME", "", false)
        if parent_name == "" then parent_name = "Track" end

        local suffixes = {"_Dry", "_Wet_01", "_Wet_02", "_Wet_03"}
        local new_tracks = {}

        for i, suffix in ipairs(suffixes) do
            local insert_idx = parent_idx + (i - 1)
            reaper.InsertTrackAtIndex(insert_idx, true)
            
            local new_tr = reaper.GetTrack(0, insert_idx)
            reaper.GetSetMediaTrackInfo_String(new_tr, "P_NAME", parent_name .. suffix, true)
            table.insert(new_tracks, new_tr)
        end

        local dry_track = new_tracks[1]
        local last_wet_track = new_tracks[4]

        reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
        reaper.SetMediaTrackInfo_Value(last_wet_track, "I_FOLDERDEPTH", -1)

        local item_count = reaper.CountTrackMediaItems(parent_track)
        for i = item_count - 1, 0, -1 do
            local item = reaper.GetTrackMediaItem(parent_track, i)
            reaper.MoveMediaItemToTrack(item, dry_track)
        end

        for i = 2, 4 do 
            local wet_tr = new_tracks[i]
            local send_idx = reaper.CreateTrackSend(dry_track, wet_tr)
            reaper.SetTrackSendInfo_Value(dry_track, 0, send_idx, "I_SENDMODE", 1)
        end

        reaper.PreventUIRefresh(-1)
        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Create Parallel FX Routing", -1)
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
        if shared_info.needs_reload then
            TRACK_ICONS.loaded = false
            shared_info.needs_reload = false
        end
        LoadTrackIcons()
        
        reaper.ImGui_Text(ctx, 'Select TRACKS before using this feature.')
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
            local sel_tr_level = reaper.GetSelectedTrack(0, 0)
            if sel_tr_level and not reaper.ImGui_IsAnyItemActive(ctx) then
                select_level = reaper.GetTrackDepth(sel_tr_level) + 1
            end

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
            
            if reaper.ImGui_ImageButton(ctx, "##btn_crtts", TRACK_ICONS.crtts, 22, 22) then
                Action_TimeSelection()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "TRACK_CRT_TS"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_crtregion", TRACK_ICONS.crtregion, 22, 22) then
                Action_CreateRegions()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "TRACK_CRT_REGION"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_crtprlgrp", TRACK_ICONS.crtprlgrp, 22, 22) then
                CreateParallelRouting()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "TRACK_CRT_PRLGRP"
            end
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_ImageButton(ctx, "##btn_flwgrp", TRACK_ICONS.flwgrp, 22, 22) then
                FollowFolderName()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "TRACK_FLWNAME"
            end
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_ImageButton(ctx, "##btn_delunsd", TRACK_ICONS.delunsd, 22, 22) then
                DeleteEmptyTracksAndFolders()
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "TRACK_DEL_UNSD"
            end
            reaper.ImGui_Spacing(ctx)

            local changed_base_name, new_base_name = reaper.ImGui_InputTextMultiline(ctx, '##RenameNewBaseName', base_name, 345, 27)
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
            reaper.ImGui_SetCursorPos(ctx, 0, 550)

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
            if reaper.ImGui_IsItemHovered(ctx) then
                shared_info.hovered_id = "TRACK_CHNG_COL"
            end
            reaper.ImGui_PopID(ctx)
        -- ========================================================
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
            reaper.Main_OnCommand(40044, 0)
        end
    end
return {
    JKK_TrackTool_Draw = JKK_TrackTool_Draw,
}