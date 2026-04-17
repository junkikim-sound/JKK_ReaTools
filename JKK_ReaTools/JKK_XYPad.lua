--========================================================
-- @title JKK_XYPad
-- @author Junki Kim
-- @version 0.5.0
-- @provides
--     [nomain] Modules/JKK_Theme.lua
--========================================================

local reaper = reaper
local ctx = reaper.ImGui_CreateContext('JKK XY Pad')

local global_state = nil

--========================================================
-- 테마(Theme) 모듈 불러오기
--========================================================
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local theme_path = script_path .. "Modules/JKK_Theme.lua"

local theme_module = nil
if reaper.file_exists(theme_path) then
    theme_module = dofile(theme_path)
end

local ApplyTheme = theme_module and theme_module.ApplyTheme or function() return 0, 0 end

--========================================================
-- 유틸리티: GUID로 트랙 찾기
--========================================================
local function FindTrackByGUID(guid)
    local master = reaper.GetMasterTrack(0)
    if reaper.GetTrackGUID(master) == guid then return master end
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if reaper.GetTrackGUID(tr) == guid then return tr end
    end
    return nil
end

--========================================================
-- 직렬화 & 역직렬화 (데이터 저장)
--========================================================
local function SerializeMacroState(state)
    local function serialize_maps(maps)
        local t = {}
        for _, map in ipairs(maps) do
            table.insert(t, string.format("%s,%d,%d,%f,%f,%s", map.target_guid, map.fx_idx, map.param_idx, map.min_val, map.max_val, map.fx_guid or ""))
        end
        return table.concat(t, ";")
    end
    return string.format("%f,%f,%d,%d,%f|%s|%s", state.x_tgt, state.y_tgt, state.x_mode, state.y_mode, state.pad_ratio or 0.0, serialize_maps(state.x_maps), serialize_maps(state.y_maps))
end

local function DeserializeMacroState(str, state)
    if not str or str == "" then return end
    local parts = {}
    for part in string.gmatch(str, "([^|]+)") do table.insert(parts, part) end
    if #parts >= 1 then
        local coords = {}
        for c in string.gmatch(parts[1], "([^,]+)") do table.insert(coords, tonumber(c)) end
        if #coords >= 4 then
            state.x_cur, state.x_tgt = coords[1], coords[1]
            state.y_cur, state.y_tgt = coords[2], coords[2]
            state.x_mode = coords[3] and math.floor(coords[3]) or 0
            state.y_mode = coords[4] and math.floor(coords[4]) or 0
        end
        if #coords >= 5 and coords[5] > 0 then
            state.pad_ratio = coords[5]
        end
    end
    local function deserialize_maps(map_str, dest_table)
        if not map_str then return end
        for m in string.gmatch(map_str, "([^;]+)") do
            local vals = {}
            for v in string.gmatch(m, "([^,]+)") do table.insert(vals, v) end
            if #vals >= 5 then
                local guid = vals[1]
                local fx_idx = tonumber(vals[2])
                local p_idx = tonumber(vals[3])
                local fx_guid = vals[6] or ""
                
                local target_tr = FindTrackByGUID(guid)
                local tr_name = "Unknown"
                local fx_name = "Offline"
                local p_name = "Offline"
                
                if target_tr then
                    if target_tr == reaper.GetMasterTrack(0) then
                        tr_name = "Master"
                    else
                        _, tr_name = reaper.GetTrackName(target_tr)
                    end
                    local _, raw_fx = reaper.TrackFX_GetFXName(target_tr, fx_idx, "")
                    fx_name = raw_fx:gsub("^.-: ", ""):gsub("^.-:", "")
                    _, p_name = reaper.TrackFX_GetParamName(target_tr, fx_idx, p_idx, "")
                end

                table.insert(dest_table, {
                    target_guid = guid, target_name = tr_name,
                    fx_idx = fx_idx, param_idx = p_idx, fx_guid = fx_guid,
                    fx_name = fx_name, param_name = p_name, 
                    min_val = tonumber(vals[4]), max_val = tonumber(vals[5])
                })
            end
        end
    end
    deserialize_maps(parts[2], state.x_maps)
    deserialize_maps(parts[3], state.y_maps)
end

local function GetGlobalMacroState()
    if not global_state then
        global_state = {
            x_tgt=0.5, x_cur=0.5, y_tgt=0.5, y_cur=0.5, pad_ratio=nil, 
            x_mode=0, y_mode=0,
            x_maps={}, y_maps={}, learn_mode=0, needs_save=false,
            learn_track=-1, learn_fx=-1, learn_param=-1, learn_val=0.0
        }
        local retval, saved_str = reaper.GetProjExtState(0, "JKK_XY_PAD", "MACROS")
        if retval > 0 and saved_str ~= "" then 
            DeserializeMacroState(saved_str, global_state) 
        end
    end
    return global_state
end

--========================================================
-- 매크로 동기화 & 삭제 검증
--========================================================
local function ValidateAndSyncMacros(state)
    local changed = false
    local function sync_maps(maps)
        for i = #maps, 1, -1 do
            local m = maps[i]
            local target_tr = FindTrackByGUID(m.target_guid)
            local is_valid = false
            
            if target_tr then
                if m.fx_guid and m.fx_guid ~= "" then
                    for fx = 0, reaper.TrackFX_GetCount(target_tr) - 1 do
                        if reaper.TrackFX_GetFXGUID(target_tr, fx) == m.fx_guid then
                            if m.fx_idx ~= fx then
                                m.fx_idx = fx
                                changed = true
                            end
                            is_valid = true
                            break
                        end
                    end
                else
                    if m.fx_idx < reaper.TrackFX_GetCount(target_tr) then
                        local _, raw_fx = reaper.TrackFX_GetFXName(target_tr, m.fx_idx, "")
                        local current_fx_name = raw_fx:gsub("^.-: ", ""):gsub("^.-:", "")
                        if current_fx_name == m.fx_name then
                            is_valid = true
                            m.fx_guid = reaper.TrackFX_GetFXGUID(target_tr, m.fx_idx)
                            changed = true
                        end
                    end
                end
            end
            
            if not is_valid then
                table.remove(maps, i)
                changed = true
            end
        end
    end
    sync_maps(state.x_maps)
    sync_maps(state.y_maps)
    if changed then state.needs_save = true end
end

--========================================================
-- 매크로 로직 업데이트
--========================================================
local function UpdateAndApplyMacros(state)
    if state.learn_mode > 0 then return end
    local speed = 0.25
    state.x_cur = state.x_cur + (state.x_tgt - state.x_cur) * speed
    state.y_cur = state.y_cur + (state.y_tgt - state.y_cur) * speed
    
    local function Apply(maps, mode, axis_val)
        local shaped = axis_val
        if mode == 1 then -- Center Peak
            shaped = 1.0 - math.abs(axis_val - 0.5) * 2.0
        elseif mode == 2 then -- Radial Peak
            local dx = state.x_cur - 0.5
            local dy = state.y_cur - 0.5
            local dist = math.sqrt(dx*dx + dy*dy) * 2.0
            shaped = 1.0 - math.min(1.0, dist)
        elseif mode == 3 then -- Radial Valley
            local dx = state.x_cur - 0.5
            local dy = state.y_cur - 0.5
            local dist = math.sqrt(dx*dx + dy*dy) * 2.0
            shaped = math.min(1.0, dist)
        end
        
        for _, map in ipairs(maps) do 
            local target_tr = FindTrackByGUID(map.target_guid)
            if target_tr then
                reaper.TrackFX_SetParamNormalized(target_tr, map.fx_idx, map.param_idx, map.min_val + (map.max_val - map.min_val) * shaped)
            end
        end
    end
    
    Apply(state.x_maps, state.x_mode, state.x_cur)
    Apply(state.y_maps, state.y_mode, state.y_cur)
end

--========================================================
-- UI 렌더링
--========================================================
local function DrawMacroMapList(ctx, state, axis_name, maps, learn_id)
    reaper.ImGui_PushID(ctx, "MacroList_" .. learn_id)
    reaper.ImGui_Text(ctx, axis_name .. " Axis")
    
    local cursor_x = reaper.ImGui_GetCursorPosX(ctx)
    local avail_header_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local combo_w = 120 
    local btn_w = 80
    local total_w = combo_w + btn_w + 8
    
    if avail_header_w > total_w then
        reaper.ImGui_SameLine(ctx, cursor_x + avail_header_w - total_w)
    else
        reaper.ImGui_SameLine(ctx)
    end
    
    local mode = (learn_id == 1) and state.x_mode or state.y_mode
    reaper.ImGui_SetNextItemWidth(ctx, combo_w)
    
    local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "##mode", mode, "Normal\0Center Peak\0Radial Peak\0Radial Valley\0")
    
    if changed_mode then
        if learn_id == 1 then state.x_mode = new_mode else state.y_mode = new_mode end
        state.needs_save = true
    end
    
    reaper.ImGui_SameLine(ctx)
    
    local is_learning_visual = (state.learn_mode == learn_id)
    if is_learning_visual then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xCC3333FF) end
    
    if reaper.ImGui_Button(ctx, (is_learning_visual and "Learning..." or "Learn") .. "##learn", btn_w) then 
        if state.learn_mode == learn_id then
            state.learn_mode = 0 
        else
            state.learn_mode = learn_id 
            local ret, tr_idx, fx_idx, p_idx = reaper.GetLastTouchedFX()
            if ret then
                local t = (tr_idx == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, tr_idx-1)
                if t then
                    state.learn_val = reaper.TrackFX_GetParamNormalized(t, fx_idx, p_idx)
                    state.learn_track = tr_idx
                    state.learn_fx = fx_idx
                    state.learn_param = p_idx
                end
            else
                state.learn_track = -1
            end
        end
    end
    
    if is_learning_visual then reaper.ImGui_PopStyleColor(ctx) end
    
    if state.learn_mode == learn_id then
        local ret, tr_idx, fx_idx, p_idx = reaper.GetLastTouchedFX()
        if ret then
            local target_tr = (tr_idx == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, tr_idx-1)
            local val = 0
            if target_tr then
                val = reaper.TrackFX_GetParamNormalized(target_tr, fx_idx, p_idx)
            end
            
            local is_new_touch = false
            if tr_idx ~= state.learn_track or fx_idx ~= state.learn_fx or p_idx ~= state.learn_param then
                is_new_touch = true
            elseif math.abs(val - state.learn_val) > 0.0001 then
                is_new_touch = true
            end

            if is_new_touch and target_tr then
                local target_guid = reaper.GetTrackGUID(target_tr)
                
                for j = #state.x_maps, 1, -1 do
                    local m = state.x_maps[j]
                    if m.target_guid == target_guid and m.fx_idx == fx_idx and m.param_idx == p_idx then
                        table.remove(state.x_maps, j)
                    end
                end
                
                for j = #state.y_maps, 1, -1 do
                    local m = state.y_maps[j]
                    if m.target_guid == target_guid and m.fx_idx == fx_idx and m.param_idx == p_idx then
                        table.remove(state.y_maps, j)
                    end
                end
                
                local tr_name = "Master"
                if target_tr ~= reaper.GetMasterTrack(0) then _, tr_name = reaper.GetTrackName(target_tr) end
                local _, fx_n = reaper.TrackFX_GetFXName(target_tr, fx_idx, "")
                local _, p_n = reaper.TrackFX_GetParamName(target_tr, fx_idx, p_idx, "")
                local fx_guid = reaper.TrackFX_GetFXGUID(target_tr, fx_idx)
                
                table.insert(maps, {
                    target_guid = target_guid, target_name = tr_name,
                    fx_idx = fx_idx, param_idx = p_idx, fx_guid = fx_guid,
                    fx_name = fx_n:gsub("^.-: ", ""), param_name = p_n, 
                    min_val = 0.0, max_val = 1.0
                })
                state.needs_save = true
                
                state.learn_track = tr_idx
                state.learn_fx = fx_idx
                state.learn_param = p_idx
                state.learn_val = val
            end
        end
    end
    
    for i, map in ipairs(maps) do
        reaper.ImGui_PushID(ctx, "map"..i)
        
        if reaper.ImGui_Button(ctx, "X##del") then table.remove(maps, i); state.needs_save = true; reaper.ImGui_PopID(ctx); break end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, string.format("[%s] %s: %s", map.target_name, map.fx_name, map.param_name))
        
        reaper.ImGui_Indent(ctx, 28)
        
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local slider_w = (avail_w * 0.5) - 45 
        if slider_w < 50 then slider_w = 50 end 
        
        reaper.ImGui_SetNextItemWidth(ctx, slider_w)
        local c1, n1 = reaper.ImGui_SliderDouble(ctx, "Min##"..i, map.min_val, 0, 1)
        
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_SetNextItemWidth(ctx, slider_w)
        local c2, n2 = reaper.ImGui_SliderDouble(ctx, "Max##"..i, map.max_val, 0, 1)
        
        if c1 or c2 then map.min_val, map.max_val = n1, n2; state.needs_save = true end
        
        reaper.ImGui_Unindent(ctx, 28)
        reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_PopID(ctx)
end

function Loop()
    local style_pop_count, color_pop_count = ApplyTheme(ctx)

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 350, 300, 9999, 9999)
    local visible, open = reaper.ImGui_Begin(ctx, 'JKK XY Pad Global', true)
    
    if visible then
        local state = GetGlobalMacroState()
        
        if state then
            ValidateAndSyncMacros(state)
            
            local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
            local top_area_h
            
            if state.pad_ratio then
                top_area_h = avail_h * state.pad_ratio
            else
                local expected_list_h = 80 + (#state.x_maps + #state.y_maps) * 55 
                top_area_h = math.max(150, avail_h - expected_list_h - 10)
            end
            
            top_area_h = math.max(100, math.min(top_area_h, avail_h - 50))
            
            if reaper.ImGui_BeginChild(ctx, "PadRegion", 0, top_area_h) then
                local pad_avail_w, pad_avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
                
                local pad_w = math.max(50, pad_avail_w - 20)
                local pad_h = math.max(50, pad_avail_h - 20)
                
                reaper.ImGui_SetCursorPos(ctx, (pad_avail_w - pad_w) * 0.5, (pad_avail_h - pad_h) * 0.5)
                local p_x, p_y = reaper.ImGui_GetCursorScreenPos(ctx)
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                
                reaper.ImGui_InvisibleButton(ctx, "PadBtn", pad_w, pad_h)
                
                reaper.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x+pad_w, p_y+pad_h, 0x1E1E1EFF)
                reaper.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x+pad_w, p_y+pad_h, 0xFFFFFF33)
                reaper.ImGui_DrawList_AddLine(draw_list, p_x+pad_w/2, p_y, p_x+pad_w/2, p_y+pad_h, 0xFFFFFF22) 
                reaper.ImGui_DrawList_AddLine(draw_list, p_x, p_y+pad_h/2, p_x+pad_w, p_y+pad_h/2, 0xFFFFFF22) 

                if reaper.ImGui_IsItemActive(ctx) then
                    local mx, my = reaper.ImGui_GetMousePos(ctx)
                    state.x_tgt = math.max(0, math.min(1, (mx - p_x)/pad_w))
                    state.y_tgt = math.max(0, math.min(1, 1.0 - (my - p_y)/pad_h))
                    state.needs_save = true
                elseif reaper.ImGui_IsItemClicked(ctx, 1) then
                    state.x_tgt, state.y_tgt = 0.5, 0.5; state.needs_save = true
                end
                
                UpdateAndApplyMacros(state)
                
                local dot_radius = math.max(5, math.min(pad_w, pad_h) * 0.03)
                reaper.ImGui_DrawList_AddCircleFilled(draw_list, p_x + (state.x_cur * pad_w), p_y + ((1-state.y_cur) * pad_h), dot_radius, 0xE3DB8EFF)
                
                reaper.ImGui_EndChild(ctx)
            end

            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 0, 0)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x333333FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x555555FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x777777FF)
            
            reaper.ImGui_Button(ctx, "##splitter", -1, 5) 
            
            if reaper.ImGui_IsItemActive(ctx) then
                local _, delta_y = reaper.ImGui_GetMouseDelta(ctx)
                local new_h = top_area_h + delta_y
                state.pad_ratio = new_h / avail_h
                state.pad_ratio = math.max(0.1, math.min(state.pad_ratio, 0.9)) 
                state.needs_save = true
            end
            
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
                if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                    state.pad_ratio = nil 
                    state.needs_save = true
                end
            end
            
            reaper.ImGui_PopStyleColor(ctx, 3)
            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_Spacing(ctx)
            
            if reaper.ImGui_BeginChild(ctx, "ListRegion", 0, 0) then
                DrawMacroMapList(ctx, state, "X", state.x_maps, 1)
                reaper.ImGui_Separator(ctx)
                DrawMacroMapList(ctx, state, "Y", state.y_maps, 2)
                reaper.ImGui_EndChild(ctx)
            end

            if state.needs_save then
                reaper.SetProjExtState(0, "JKK_XY_PAD", "MACROS", SerializeMacroState(state))
                state.needs_save = false
            end
        end

        if not reaper.ImGui_IsAnyItemActive(ctx) then
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
                reaper.Main_OnCommand(40044, 0)
            end
            if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) then
                reaper.Main_OnCommand(40029, 0)
            end
            if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift()) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) then
                reaper.Main_OnCommand(40030, 0)
            end
        end

        reaper.ImGui_End(ctx)
    end
    
    if style_pop_count and style_pop_count > 0 then
        reaper.ImGui_PopStyleVar(ctx, style_pop_count)
    end
    if color_pop_count and color_pop_count > 0 then
        reaper.ImGui_PopStyleColor(ctx, color_pop_count)
    end
    
    if open then reaper.defer(Loop) end
end

reaper.defer(Loop)