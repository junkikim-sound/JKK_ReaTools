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
            -- 1. 트랙 상태 동기화
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
                -- 2. Volume Slider
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, "  Volume")
                reaper.ImGui_SameLine(ctx)

                local current_slider_pos = db_to_slider_pos(volume_db)
                reaper.ImGui_SetNextItemWidth(ctx, 272)
                reaper.ImGui_SetCursorPosX(ctx, 494)

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
                reaper.ImGui_Text(ctx, "  Pan")
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
                reaper.ImGui_Text(ctx, "  Width")
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
-- FX List
------------------------------------------------------------
    local function DrawTrackFXList(ctx, track)
        reaper.ImGui_SeparatorText(ctx, 'Track FX List')
        
        if not track or reaper.TrackFX_GetCount(track) == 0 then
            reaper.ImGui_Text(ctx, "  No FX on this track")
            return
        end

        local fx_count = reaper.TrackFX_GetCount(track)

        for i = 0, fx_count - 1 do
            local _, fx_name = reaper.TrackFX_GetFXName(track, i, "")
            local is_enabled = reaper.TrackFX_GetEnabled(track, i)
            
            reaper.ImGui_PushID(ctx, "fx_item_" .. i)
            
            -- 1. Bypass
            local changed, new_enabled = reaper.ImGui_Checkbox(ctx, "##enabled", is_enabled)
            if changed then
                reaper.Undo_BeginBlock()
                reaper.TrackFX_SetEnabled(track, i, new_enabled)
                reaper.Undo_EndBlock("Toggle FX Bypass via Checkbox", -1)
            end
            
            reaper.ImGui_SameLine(ctx)
            
            -- 2. FX Name
            if reaper.ImGui_Selectable(ctx, fx_name, false) then
                local alt_pressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt()) or 
                                    reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightAlt())
                
                local shift_pressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or 
                                      reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())

                if alt_pressed then
                    -- Alt + Click
                    reaper.Undo_BeginBlock()
                    reaper.TrackFX_Delete(track, i)
                    reaper.Undo_EndBlock("Delete FX via UI (Alt-Click)", -1)
                    
                elseif shift_pressed then
                    -- Shift + Click
                    reaper.Undo_BeginBlock()
                    reaper.TrackFX_SetEnabled(track, i, not is_enabled)
                    reaper.Undo_EndBlock("Toggle FX Bypass via UI (Shift-Click)", -1)
                    
                else
                    -- Click
                    local is_open = reaper.TrackFX_GetOpen(track, i)
                    if is_open then
                        reaper.TrackFX_Show(track, i, 2)
                    else
                        reaper.TrackFX_Show(track, i, 3)
                    end
                end
            end

            -- 3. Right Click
            if reaper.ImGui_BeginPopupContextItem(ctx) then
                if reaper.ImGui_MenuItem(ctx, "Delete FX") then
                    reaper.Undo_BeginBlock()
                    reaper.TrackFX_Delete(track, i)
                    reaper.Undo_EndBlock("Delete FX via Context Menu", -1)
                end
                reaper.ImGui_EndPopup(ctx)
            end

            -- 4. Drag and Drop Source
            if reaper.ImGui_BeginDragDropSource(ctx) then
                reaper.ImGui_SetDragDropPayload(ctx, 'FX_DRAG_DROP', tostring(i))
                reaper.ImGui_Text(ctx, "Move: " .. fx_name)
                reaper.ImGui_EndDragDropSource(ctx)
            end

            -- 5. Drag and Drop Target
            if reaper.ImGui_BeginDragDropTarget(ctx) then
                local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, 'FX_DRAG_DROP')
                if rv then
                    local src_idx = tonumber(payload)
                    local dest_idx = i
                    if src_idx ~= dest_idx then
                        reaper.TrackFX_CopyToTrack(track, src_idx, track, dest_idx, true)
                    end
                end
                reaper.ImGui_EndDragDropTarget(ctx)
            end
            
            reaper.ImGui_PopID(ctx)
        end
    end

------------------------------------------------------------
-- XY Pad & Macro Manager
------------------------------------------------------------
    local track_macros = {}

    local function SerializeMacroState(state)
        local function serialize_maps(maps)
            local t = {}
            for _, map in ipairs(maps) do
                table.insert(t, string.format("%d,%d,%f,%f", map.fx_idx, map.param_idx, map.min_val, map.max_val))
            end
            return table.concat(t, ";")
        end
        local x_str = serialize_maps(state.x_maps)
        local y_str = serialize_maps(state.y_maps)
        return string.format("%f,%f,%d,%d|%s|%s", state.x_tgt, state.y_tgt, state.x_peak and 1 or 0, state.y_peak and 1 or 0, x_str, y_str)
    end

    local function DeserializeMacroState(track, str, state)
        if not str or str == "" then return end
        
        local parts = {}
        local start_idx = 1
        while true do
            local delim = string.find(str, "|", start_idx, true)
            if delim then
                table.insert(parts, string.sub(str, start_idx, delim - 1))
                start_idx = delim + 1
            else
                table.insert(parts, string.sub(str, start_idx))
                break
            end
        end

        if #parts >= 3 then
            local coords = {}
            for c in string.gmatch(parts[1], "([^,]+)") do table.insert(coords, tonumber(c)) end
            if #coords >= 2 then
                state.x_cur = coords[1]; state.x_tgt = coords[1]
                state.y_cur = coords[2]; state.y_tgt = coords[2]
                if #coords >= 4 then
                    state.x_peak = (coords[3] == 1)
                    state.y_peak = (coords[4] == 1)
                end
            end

            local function deserialize_maps(map_str, dest_table)
                for m in string.gmatch(map_str, "([^;]+)") do
                    local vals = {}
                    for v in string.gmatch(m, "([^,]+)") do table.insert(vals, tonumber(v)) end
                    if #vals >= 4 then
                        local fx, p, min_v, max_v = vals[1], vals[2], vals[3], vals[4]
                        
                        if fx < reaper.TrackFX_GetCount(track) then
                            local _, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
                            local _, param_name = reaper.TrackFX_GetParamName(track, fx, p, "")
                            table.insert(dest_table, {
                                fx_idx = fx, param_idx = p,
                                fx_name = fx_name, param_name = param_name,
                                min_val = min_v, max_val = max_v
                            })
                        end
                    end
                end
            end

            deserialize_maps(parts[2], state.x_maps)
            deserialize_maps(parts[3], state.y_maps)
        end
    end

    local function GetTrackMacroState(track)
        local guid = reaper.GetTrackGUID(track)
        if not track_macros[guid] then
            track_macros[guid] = {
                x_tgt = 0.5, x_cur = 0.5,
                y_tgt = 0.5, y_cur = 0.5,
                glide = 0.1, 
                x_maps = {}, y_maps = {},
                learn_mode = 0,
                learn_track = -1, learn_fx = -1, learn_param = -1, learn_val = 0.0,
                needs_save = false,
                x_peak = false,
                y_peak = false
            }
            
            local retval, saved_str = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:JKK_MACRO", "", false)
            if retval and saved_str ~= "" then
                DeserializeMacroState(track, saved_str, track_macros[guid])
            end
        end
        return track_macros[guid]
    end

    -- Glide(스무딩) 처리 및 파라미터 실제 적용 함수
    local function UpdateAndApplyMacros(track, state)
        if state.learn_mode > 0 then return end

        local fixed_glide = 0.75
        local speed = 1.0 - fixed_glide
        if speed < 0.01 then speed = 0.01 end
        
        local x_changed = false
        local y_changed = false

        if math.abs(state.x_tgt - state.x_cur) > 0.0001 then
            state.x_cur = state.x_cur + (state.x_tgt - state.x_cur) * speed
            x_changed = true
        elseif state.x_cur ~= state.x_tgt then
            state.x_cur = state.x_tgt
            x_changed = true
        end
        
        if math.abs(state.y_tgt - state.y_cur) > 0.0001 then
            state.y_cur = state.y_cur + (state.y_tgt - state.y_cur) * speed
            y_changed = true
        elseif state.y_cur ~= state.y_tgt then
            state.y_cur = state.y_tgt
            y_changed = true
        end

        local function ApplyToFX(maps, macro_val, is_peak)
            local shaped_val = macro_val
            if is_peak then
                shaped_val = 1.0 - math.abs(macro_val - 0.5) * 2.0
            end
            
            for _, map in ipairs(maps) do
                local final_val = map.min_val + (map.max_val - map.min_val) * shaped_val
                reaper.TrackFX_SetParamNormalized(track, map.fx_idx, map.param_idx, final_val)
            end
        end

        if x_changed then ApplyToFX(state.x_maps, state.x_cur, state.x_peak) end
        if y_changed then ApplyToFX(state.y_maps, state.y_cur, state.y_peak) end
    end

    -- 리스트에 표시할 매크로 맵핑 UI
    local function DrawMacroMapList(ctx, track, state, axis_name, maps, learn_id)
        reaper.ImGui_PushID(ctx, "MacroList_" .. learn_id)

        reaper.ImGui_AlignTextToFramePadding(ctx) 
        reaper.ImGui_Text(ctx, axis_name .. " Axis Parameters")
        
        reaper.ImGui_SameLine(ctx, 150)
        
        local is_peak = false
        if learn_id == 1 then
            is_peak = state.x_peak
        else
            is_peak = state.y_peak
        end
        
        if is_peak then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00AAFFAA)
        end
        
        if reaper.ImGui_Button(ctx, is_peak and "Peak: C" or "Peak: R", 72) then
            if learn_id == 1 then 
                state.x_peak = not state.x_peak 
            else 
                state.y_peak = not state.y_peak 
            end
            state.needs_save = true
        end
        
        if is_peak then reaper.ImGui_PopStyleColor(ctx) end
        
        reaper.ImGui_SameLine(ctx)
        
        -- Learn 버튼
        local is_learning = (state.learn_mode == learn_id)
        if is_learning then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00FF00AA)
        end
        if reaper.ImGui_Button(ctx, is_learning and "Learning..." or "Learn", 72) then
            if is_learning then
                state.learn_mode = 0
            else
                state.learn_mode = learn_id
                local ret, tr, fx, p = reaper.GetLastTouchedFX()
                if ret then
                    local t = (tr == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, tr - 1)
                    if t then
                        state.learn_val = reaper.TrackFX_GetParamNormalized(t, fx, p)
                        state.learn_track = tr
                        state.learn_fx = fx
                        state.learn_param = p
                    end
                else
                    state.learn_track = -1
                end
            end
        end
        
        if is_learning then
            reaper.ImGui_PopStyleColor(ctx)
            
            local ret, tr, fx, p = reaper.GetLastTouchedFX()
            if ret then
                local t = (tr == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, tr - 1)
                
                if t == track then 
                    local val = reaper.TrackFX_GetParamNormalized(t, fx, p)
                    
                    local is_new_touch = false
                    if tr ~= state.learn_track or fx ~= state.learn_fx or p ~= state.learn_param then
                        is_new_touch = true
                    elseif math.abs(val - state.learn_val) > 0.0001 then
                        is_new_touch = true
                    end
                    
                    if is_new_touch then
                        local is_duplicate = false
                        for _, map in ipairs(maps) do
                            if map.fx_idx == fx and map.param_idx == p then
                                is_duplicate = true
                                break
                            end
                        end
                        
                        if not is_duplicate then
                            local _, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
                            local _, param_name = reaper.TrackFX_GetParamName(track, fx, p, "")
                            table.insert(maps, {
                                fx_idx = fx, param_idx = p,
                                fx_name = fx_name, param_name = param_name,
                                min_val = 0.0, max_val = 1.0
                            })
                            state.needs_save = true
                            
                            state.learn_track = tr
                            state.learn_fx = fx
                            state.learn_param = p
                            state.learn_val = val
                        else
                            state.learn_track = tr
                            state.learn_fx = fx
                            state.learn_param = p
                            state.learn_val = val
                        end
                    end
                end
            end
        end

        for i, map in ipairs(maps) do
            reaper.ImGui_Text(ctx, " ")
            reaper.ImGui_SameLine(ctx)
            
            reaper.ImGui_PushID(ctx, axis_name .. "_map_" .. i)
            
            if reaper.ImGui_Button(ctx, "X", 20, 46) then
                table.remove(maps, i)
                state.needs_save = true
                reaper.ImGui_PopID(ctx)
                break
            end
            
            reaper.ImGui_SameLine(ctx)
            
            reaper.ImGui_BeginGroup(ctx)
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, string.format("[%s] %s", map.fx_name, map.param_name))
                
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, " Min")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 80)
                local changed_min, new_min = reaper.ImGui_SliderDouble(ctx, "##MinSlider", map.min_val, 0.0, 1.0, "%.2f")
                if changed_min then 
                    map.min_val = new_min 
                    state.needs_save = true
                end
                
                reaper.ImGui_SameLine(ctx)
                
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, "  Max")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 80)
                local changed_max, new_max = reaper.ImGui_SliderDouble(ctx, "##MaxSlider", map.max_val, 0.0, 1.0, "%.2f")
                if changed_max then 
                    map.max_val = new_max 
                    state.needs_save = true
                end
            reaper.ImGui_EndGroup(ctx)
            reaper.ImGui_PopID(ctx)
            reaper.ImGui_Spacing(ctx)
        end
        
        reaper.ImGui_PopID(ctx)
    end

    -- 메인 UI 렌더링 함수
    local function DrawTrackMacroController(ctx, track)
        local is_disabled = (track == nil)
        local state
        
        if is_disabled then
            state = {
                x_tgt = 0.5, x_cur = 0.5, y_tgt = 0.5, y_cur = 0.5,
                x_maps = {}, y_maps = {}, learn_mode = 0,
                x_peak = false, y_peak = false, needs_save = false
            }
        else
            state = GetTrackMacroState(track)
        end

        reaper.ImGui_SeparatorText(ctx, 'XY Pad & Macros')

        if is_disabled then
            reaper.ImGui_BeginDisabled(ctx)
        end

        local table_flags = reaper.ImGui_TableFlags_BordersInnerV() | reaper.ImGui_TableFlags_SizingFixedFit()
        if reaper.ImGui_BeginTable(ctx, "XY_Macro_Layout", 2, table_flags) then
            
            reaper.ImGui_TableSetupColumn(ctx, "PadCol", reaper.ImGui_TableColumnFlags_WidthFixed(), 170)
            reaper.ImGui_TableSetupColumn(ctx, "ListCol", reaper.ImGui_TableColumnFlags_WidthFixed(), 420)
            
            reaper.ImGui_TableNextRow(ctx)
            
            -- [Column 1] XY 패드
                reaper.ImGui_TableNextColumn(ctx)
                
                reaper.ImGui_Text(ctx, "")
                reaper.ImGui_SameLine(ctx)
                local pad_size = 150
                local p_x, p_y = reaper.ImGui_GetCursorScreenPos(ctx)
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

                reaper.ImGui_InvisibleButton(ctx, "XYPad", pad_size, pad_size)
                local is_active = reaper.ImGui_IsItemActive(ctx)
                local is_right_clicked = reaper.ImGui_IsItemClicked(ctx, 1)

                local bg_col = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1.0)
                local border_col = reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 1.0)
                reaper.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + pad_size, p_y + pad_size, bg_col, 5.0)
                reaper.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + pad_size, p_y + pad_size, border_col, 5.0)
                reaper.ImGui_DrawList_AddLine(draw_list, p_x + pad_size/2, p_y, p_x + pad_size/2, p_y + pad_size, border_col)
                reaper.ImGui_DrawList_AddLine(draw_list, p_x, p_y + pad_size/2, p_x + pad_size, p_y + pad_size/2, border_col)

                if is_active then
                    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
                    local rel_x = (mouse_x - p_x) / pad_size
                    local rel_y = 1.0 - ((mouse_y - p_y) / pad_size)
                    
                    state.x_tgt = math.max(0.0, math.min(1.0, rel_x))
                    state.y_tgt = math.max(0.0, math.min(1.0, rel_y))
                    state.needs_save = true
                elseif is_right_clicked then
                    state.x_tgt = 0.5
                    state.y_tgt = 0.5
                    state.needs_save = true
                end

                if not is_disabled then
                    UpdateAndApplyMacros(track, state)
                end

                local dot_x = p_x + (state.x_cur * pad_size)
                local dot_y = p_y + ((1.0 - state.y_cur) * pad_size)
                local dot_col = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.8, 0.5, 1.0)
                reaper.ImGui_DrawList_AddCircleFilled(draw_list, dot_x, dot_y, 8.0, dot_col)
                
            -- [Column 2] X 축 & Y 축 맵핑 리스트
                reaper.ImGui_TableNextColumn(ctx)
                
                DrawMacroMapList(ctx, track, state, "    X", state.x_maps, 1)
                reaper.ImGui_Separator(ctx)
                DrawMacroMapList(ctx, track, state, "    Y", state.y_maps, 2)

                reaper.ImGui_EndTable(ctx)
        end

        if not is_disabled and state.needs_save then
            local serialized = SerializeMacroState(state)
            reaper.GetSetMediaTrackInfo_String(track, "P_EXT:JKK_MACRO", serialized, true)
            state.needs_save = false
        end

        if is_disabled then
            reaper.ImGui_EndDisabled(ctx)
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
        local function Action_SetSelectedTracksAutomationMode(mode_idx)
            reaper.Undo_BeginBlock()
            local sel_cnt = reaper.CountSelectedTracks(0)
            for i = 0, sel_cnt - 1 do
                local tr = reaper.GetSelectedTrack(0, i)
                reaper.SetMediaTrackInfo_Value(tr, "I_AUTOMODE", mode_idx)
            end
            reaper.Undo_EndBlock("Set Selected Tracks Automation Mode", -1)
        end
    -- Track Channel Set
        local function Action_SetTrackChannels(num_channels)
            reaper.Undo_BeginBlock()
            local sel_cnt = reaper.CountSelectedTracks(0)
            for i = 0, sel_cnt - 1 do
                local tr = reaper.GetSelectedTrack(0, i)
                reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", num_channels)
            end
            reaper.Undo_EndBlock("Set Track Channels", -1)
        end

----------------------------------------------------------
-- Color Palette 
----------------------------------------------------------
    local function SetTrackColors(r, g, b)
      local count = reaper.CountSelectedTracks(0)
      if count == 0 then return end

      reaper.Undo_BeginBlock()

      local native_color
      if r == 0 and g == 0 and b == 0 then
        native_color = 0
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
        local sel_track_count = reaper.CountSelectedTracks(0)
        local is_disabled = (sel_track_count == 0)
        reaper.ImGui_BeginDisabled(ctx, is_disabled)

        local table_full      = reaper.ImGui_TableFlags_SizingFixedFit() | 
                                reaper.ImGui_TableFlags_BordersInnerV()
        if reaper.ImGui_BeginTable(ctx, "table_full", 5, table_full) then
            reaper.ImGui_TableSetupColumn(ctx, 'table_batch_control', reaper.ImGui_TableColumnFlags_WidthFixed(), 370)
            reaper.ImGui_TableSetupColumn(ctx, 'table_fx', reaper.ImGui_TableColumnFlags_WidthFixed(), 320)
            reaper.ImGui_TableSetupColumn(ctx, 'table_xypad', reaper.ImGui_TableColumnFlags_WidthFixed(), 490)
            reaper.ImGui_TableSetupColumn(ctx, 'table_action', reaper.ImGui_TableColumnFlags_WidthFixed(), 470)
            reaper.ImGui_TableSetupColumn(ctx, 'table_color', reaper.ImGui_TableColumnFlags_WidthFixed(), 460)
            reaper.ImGui_TableNextColumn(ctx)
            -- Tracks Batch Controller ====================================
                local table_batch_control      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_batch_control", 1, table_batch_control) then
                    reaper.ImGui_TableSetupColumn(ctx, 'Tracks Batch Controller', reaper.ImGui_TableColumnFlags_WidthFixed(), 360)
                    reaper.ImGui_TableNextColumn(ctx)
                    reaper.ImGui_SeparatorText(ctx, 'Tracks Batch Controller')
                        reaper.ImGui_Text(ctx, "")
                        reaper.ImGui_SameLine(ctx)
                        local changed_base_name, new_base_name = reaper.ImGui_InputTextMultiline(ctx, '##RenameNewBaseName', base_name, 272, 22)
                        if changed_base_name then base_name = new_base_name end
                        reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_Button(ctx, "Clear##ClearBaseName", 55, 22) then
                            base_name = ""
                        end

                        reaper.ImGui_Text(ctx, "")
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
                            is_sequential_name = chk_val
                        end
                        reaper.ImGui_Spacing(ctx)
                        DrawTrackBatchController(ctx)
                    -- asdfasdf
                        reaper.ImGui_AlignTextToFramePadding(ctx)
                        reaper.ImGui_Text(ctx, "  Channels")
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetCursorPosX(ctx, 494)
                        local channel_options = " 2 ch\0 4 ch\0 6 ch\0 8 ch\0 10 ch\0 12 ch\0 16 ch\0"
                        local current_nchan = sel_tr and reaper.GetMediaTrackInfo_Value(sel_tr, "I_NCHAN") or 2
                        
                        local channel_idx = 0
                        local nchan_map = { 2, 4, 6, 8, 10, 12, 16}
                        for i, v in ipairs(nchan_map) do if v == current_nchan then channel_idx = i - 1 break end end

                        reaper.ImGui_SetNextItemWidth(ctx, 120)
                        local ch_changed, new_ch_idx = reaper.ImGui_Combo(ctx, "##Channels", channel_idx, channel_options)
                        if ch_changed then
                            Action_SetTrackChannels(nchan_map[new_ch_idx + 1])
                        end
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_TableNextColumn(ctx)
            -- Track FX List ====================================
                reaper.ImGui_Text(ctx, " ")
                reaper.ImGui_SameLine(ctx)
                local table_fx      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_fx", 1, table_fx) then
                    reaper.ImGui_TableSetupColumn(ctx, 'table_fx', reaper.ImGui_TableColumnFlags_WidthFixed(), 300)
                    reaper.ImGui_TableNextColumn(ctx)
                        DrawTrackFXList(ctx, sel_tr)
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_TableNextColumn(ctx)
            -- Track FX List ====================================
                reaper.ImGui_Text(ctx, " ")
                reaper.ImGui_SameLine(ctx)
                local table_xypad      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_xypad", 1, table_xypad) then
                    reaper.ImGui_TableSetupColumn(ctx, 'table_xypad', reaper.ImGui_TableColumnFlags_WidthFixed(), 470)
                    reaper.ImGui_TableNextColumn(ctx)
                        DrawTrackMacroController(ctx, sel_tr)
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_TableNextColumn(ctx)
            -- Actions ====================================================
                reaper.ImGui_Text(ctx, "")
                reaper.ImGui_SameLine(ctx)
                local table_action      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_action", 1, table_action) then
                    reaper.ImGui_TableSetupColumn(ctx, 'table_action', reaper.ImGui_TableColumnFlags_WidthFixed(), 450)
                    reaper.ImGui_TableNextColumn(ctx)
                -- Actions ================================================
                    reaper.ImGui_SeparatorText(ctx, 'Actions')
                        reaper.ImGui_Text(ctx, " ")
                        reaper.ImGui_SameLine(ctx)
                    -- Del Unused Tracks
                        if reaper.ImGui_Button(ctx, 'Delete Unused Tracks', 160, 22) then
                            if base_name ~= "" then
                                DeleteEmptyTracksAndFolders()
                            end
                        end
                        reaper.ImGui_SameLine(ctx)
                    
                    -- Trim/Read
                        if reaper.ImGui_Button(ctx, 'Trim', 70) then
                            Action_SetSelectedTracksAutomationMode(0)
                        end
                        reaper.ImGui_SameLine(ctx)

                    -- Read
                        if reaper.ImGui_Button(ctx, 'Read', 70) then
                            Action_SetSelectedTracksAutomationMode(1)
                        end
                        reaper.ImGui_SameLine(ctx)

                    -- Write
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x882222FF)
                        if reaper.ImGui_Button(ctx, 'Write', 70) then
                            Action_SetSelectedTracksAutomationMode(3)
                        end
                        reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_Spacing(ctx)
                -- Track Color Palette ========================================
                    reaper.ImGui_SeparatorText(ctx, 'Track Color Palette')
                    reaper.ImGui_Text(ctx, " ")
                    reaper.ImGui_SameLine(ctx)
                    local table_color      = reaper.ImGui_TableFlags_SizingFixedFit()
                    if reaper.ImGui_BeginTable(ctx, "table_color", 2, table_color) then
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
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_TableNextColumn(ctx)
            reaper.ImGui_TableNextColumn(ctx)
            reaper.ImGui_EndTable(ctx)
        end
        reaper.ImGui_EndDisabled(ctx)
    end
return {
    JKK_TrackTool_Draw = JKK_TrackTool_Draw
}
