--========================================================
-- @title JKK_ItemTools
-- @author Junki Kim
-- @noindex
--========================================================

local open = true

local theme_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/Modules/JKK_Theme.lua"
local theme_module = nil
if reaper.file_exists(theme_path) then
    theme_module = dofile(theme_path)
end

local ApplyTheme = theme_module and theme_module.ApplyTheme or function(ctx) return 0, 0 end
local style_pop_count, color_pop_count

-- Regions Renamer
local reaper = reaper

math.randomseed(os.time())

----------------------------------------------------------
-- Items Batch Controller
----------------------------------------------------------
    -- Controller
        local adjust_vol = 0.0
        local adjust_pan = 0.0
        local adjust_pitch = 0
        local adjust_rate = 1.0
        local group_stretch_ratio = 1.0
        local prev_group_stretch_ratio = 1.0
        function ApplyBatchVolume()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            reaper.Undo_BeginBlock()

            -- dB를 Linear 값으로 변환
            local linear_vol = 10^(adjust_vol / 20)
            
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local take = reaper.GetActiveTake(item)
                
                if take then
                    reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", linear_vol)
                end
            end
            
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Batch Take Volume Applied", -1)
        end
        function ApplyBatchPan()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            
            reaper.Undo_BeginBlock()

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local take = reaper.GetActiveTake(item)
                if take then
                    reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", adjust_pan)
                end
            end

            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Batch Pan Applied", -1)
        end
        function ApplyBatchPitch()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            reaper.Undo_BeginBlock()

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(item), "D_PITCH", adjust_pitch)
            end
            
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Batch Pitch Applied", -1)
        end
        function ApplyBatchRate()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            reaper.Undo_BeginBlock()

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local take = reaper.GetActiveTake(item)
                if take then
                    reaper.SetMediaItemInfo_Value(item, "B_PPITCH", 0)
                    
                    local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local current_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                    
                    local source = reaper.GetMediaItemTake_Source(take)
                    if source then
                        local origin_length = current_length * current_rate
                        local adjust_length = origin_length / adjust_rate
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", adjust_rate)
                        reaper.SetMediaItemLength(item, adjust_length, true)
                    end
                end
            end
            
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Batch Playback Rate Applied", -1)
        end
        function ApplyGroupStretch(stretch_ratio)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt < 2 then 
              return 
            end

            reaper.Undo_BeginBlock()

            local min_pos = math.huge
            local items_data = {}

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                if pos < min_pos then min_pos = pos end
                table.insert(items_data, {item=item, pos=pos})
            end

            local stretch_factor = stretch_ratio / prev_group_stretch_ratio

            for _, data in ipairs(items_data) do
                local item = data.item
                local take = reaper.GetActiveTake(item)
                
                local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local cur_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local cur_rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0

                local pos_offset = cur_pos - min_pos
                local new_pos = min_pos + (pos_offset * stretch_factor)
                local new_len = cur_len * stretch_factor
                local new_rate = cur_rate / stretch_factor
                
                reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
                reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
                if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate) end
            end
            
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Group Time Stretch Applied", -1)
        end
    -- Properties Variables
        local item_loop_src = false
        local item_mute = false
        local item_lock = false
        function ApplyItemProperty(key, val)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            reaper.Undo_BeginBlock()
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemInfo_Value(item, key, val)
            end
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Change Item Property: " .. key, -1)
        end
    -- Fader
        local drag_start_cur = 0.0
        local adj_fade_in_cur = 0.0
        local adj_fade_out_cur = 0.0
        function ApplyBatchFadeIn(cur)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            
            reaper.Undo_BeginBlock()
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemInfo_Value(item, "D_FADEINDIR", -cur)
            end
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Batch Fade In Curve", -1)
        end
        function ApplyBatchFadeOut(cur)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            
            reaper.Undo_BeginBlock()
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", cur)
            end
            
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Batch Fade Out Curve", -1)
        end
        function ApplyFadeShape(shape_idx, is_fade_in)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            
            reaper.Undo_BeginBlock()
            reaper.PreventUIRefresh(1)
            
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                if item then
                    local field = is_fade_in and "C_FADEINSHAPE" or "C_FADEOUTSHAPE"
                    reaper.SetMediaItemInfo_Value(item, field, shape_idx)
                    reaper.UpdateItemInProject(item)
                end
            end
            
            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Set Fade Shape", -1)
        end
        local function GetFadeCurveY(t, shape_idx)
            if shape_idx == 0 then return t -- Linear
            elseif shape_idx == 1 then return t * t -- Slow Start
            elseif shape_idx == 2 then return 1 - (1 - t) * (1 - t) -- Fast Start
            elseif shape_idx == 3 then return t * t * (3 - 2 * t) -- S-Curve
            elseif shape_idx == 4 then return 1 - ((1 - t) ^ 4) -- Logarithmic
            elseif shape_idx == 5 then return t ^ 4 -- Exponential
            elseif shape_idx == 6 then -- S-Curve (Steep)
                if t < 0.5 then return 8 * (t ^ 4) else return 1 - 8 * ((1 - t) ^ 4) end
            end
            return t
        end
        local function DrawPopupShapePreview(draw_list, p_min_x, p_min_y, p_max_x, p_max_y, shape_idx, is_fade_in, color)
            local segments = 16
            local width = p_max_x - p_min_x
            local height = p_max_y - p_min_y
            local points = {}
            
            for i = 0, segments do
                local t = i / segments
                local curve_val = GetFadeCurveY(t, shape_idx)
                
                local x, y
                if is_fade_in then
                    x = p_min_x + (t * width)
                    y = p_max_y - (curve_val * height)
                else
                    x = p_min_x + ((1 - t) * width)
                    y = p_max_y - (curve_val * height)
                end
                table.insert(points, x)
                table.insert(points, y)
            end
            
            for i = 1, #points - 2, 2 do
                reaper.ImGui_DrawList_AddLine(draw_list, points[i], points[i+1], points[i+2], points[i+3], color, 2.0)
            end
        end
        function DrawFadeWidget(ctx, label, cur, width, height, is_fade_in)
            local cursor_x, cursor_y = reaper.ImGui_GetCursorScreenPos(ctx)
            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            
            -- 1. 배경 그리기
            reaper.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + width, cursor_y + height, 0x222222FF)
            reaper.ImGui_DrawList_AddRect(draw_list, cursor_x, cursor_y, cursor_x + width, cursor_y + height, 0x555555FF)
            local mid_y = cursor_y + (height / 2)
            reaper.ImGui_DrawList_AddLine(draw_list, cursor_x, mid_y, cursor_x + width, mid_y, 0x444444FF, 1)

            -- 2. 버튼 생성 (이벤트 감지용)
            reaper.ImGui_InvisibleButton(ctx, "##" .. label, width, height)
            
            local changed = false

            -- 3. Ctrl + 좌클릭 초기화 (Tension Reset)
            if reaper.ImGui_IsItemClicked(ctx, 0) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) then
                cur = 0.0
                changed = true
            end

            -- 4. 드래그 로직 (Tension Control)
            if reaper.ImGui_IsItemActivated(ctx) then
                drag_start_cur = cur 
            end

            if reaper.ImGui_IsItemActive(ctx) then
                local _, dy = reaper.ImGui_GetMouseDragDelta(ctx)
                -- 감도 조절 (0.4)
                local delta_cur = -dy / (height / 2) * 0.4
                cur = math.max(-1, math.min(1, drag_start_cur + delta_cur))
                changed = true
                reaper.ImGui_SetTooltip(ctx, string.format("Curve Tension: %.2f", cur))
            end

            -- 5. 우클릭 시 셰이프 선택 팝업 열기
            local popup_id = "FadeShapePopup_" .. label
            if reaper.ImGui_IsItemClicked(ctx, 1) then
                reaper.ImGui_OpenPopup(ctx, popup_id)
            end

            reaper.ImGui_SetNextWindowSize(ctx, 122, 385)
            if reaper.ImGui_BeginPopup(ctx, popup_id) then
                reaper.ImGui_Text(ctx, is_fade_in and "Fade In Type" or "Fade Out Type")
                reaper.ImGui_Separator(ctx)
                
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                local btn_w, btn_h = 100, 40 

                local draw_order = {0, 2, 1, 4, 5, 3, 6}

                for k, visual_idx in ipairs(draw_order) do
                    local apply_idx = k - 1 
                    
                    local sx, sy = reaper.ImGui_GetCursorScreenPos(ctx)
                    local btn_id = "##btn_shape_" .. label .. "_" .. apply_idx
                    
                    if reaper.ImGui_InvisibleButton(ctx, btn_id, btn_w, btn_h) then
                        ApplyFadeShape(apply_idx, is_fade_in)
                        reaper.ImGui_CloseCurrentPopup(ctx)
                    end
                    
                    -- 스타일링
                    local is_hover = reaper.ImGui_IsItemHovered(ctx)
                    local bg_col = is_hover and 0x444444FF or 0x222222FF
                    local line_col = is_hover and 0xFFFF00FF or 0xAAAAAAFF
                    
                    reaper.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + btn_w, sy + btn_h, bg_col)
                    DrawPopupShapePreview(dl, sx + 5, sy + 5, sx + btn_w - 5, sy + btn_h - 5, visual_idx, is_fade_in, line_col)
                    reaper.ImGui_DrawList_AddRect(dl, sx, sy, sx + btn_w, sy + btn_h, 0x555555FF)
                    reaper.ImGui_Spacing(ctx)
                end
                reaper.ImGui_EndPopup(ctx)
            end

            -- 6. 메인 위젯 시각화
            local col_line = reaper.ImGui_IsItemHovered(ctx) and 0x49B6CCFF or 0x068FC3FF
            
            local start_x, start_y, end_x, end_y
            local convex_cp_x, convex_cp_y, concave_cp_x, concave_cp_y

            if is_fade_in then
                start_x, start_y = cursor_x, cursor_y + height
                end_x, end_y = cursor_x + width, cursor_y
                convex_cp_x, convex_cp_y = start_x, end_y 
                concave_cp_x, concave_cp_y = end_x, start_y 
            else
                start_x, start_y = cursor_x + width, cursor_y + height
                end_x, end_y = cursor_x, cursor_y
                convex_cp_x, convex_cp_y = start_x, end_y 
                concave_cp_x, concave_cp_y = end_x, start_y
            end
            
            local t = (cur + 1) / 2
            local ctrl_x = concave_cp_x + (convex_cp_x - concave_cp_x) * t
            local ctrl_y = concave_cp_y + (convex_cp_y - concave_cp_y) * t

            reaper.ImGui_DrawList_AddBezierQuadratic(draw_list, start_x, start_y, ctrl_x, ctrl_y, end_x, end_y, col_line, 2)
            
            return changed, cur
        end
        local last_project_change_count = reaper.GetProjectStateChangeCount(0)
    -- Take Name & Region Name
        local base_name = ""
        local is_sequential_name = true
        function RenameSelectedTakes()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            reaper.Undo_BeginBlock()

            local items_to_rename = {}
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                table.insert(items_to_rename, {ptr = item, pos = pos})
            end

            -- 2. 시간순 정렬
            table.sort(items_to_rename, function(a, b) return a.pos < b.pos end)

            -- 3. 이름 변경 적용
            for i, data in ipairs(items_to_rename) do
                local take = reaper.GetActiveTake(data.ptr)

                if take then
                    local new_name = base_name
                    if is_sequential_name then
                        new_name = string.format("%s_%02d", base_name, i)
                    end
                    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
                end
            end

            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Batch Rename Takes", -1)
        end
        local function CreateRegionsFromSelectedItems()
            local project = reaper.EnumProjects(-1, 0)
            if not project then return end

            local sel_items = {}
            local item_count = reaper.CountSelectedMediaItems(project)

            if item_count == 0 then return end

            -- 1. 아이템 수집 (Collect item start/end)
            for i = 0, item_count - 1 do
                local item = reaper.GetSelectedMediaItem(project, i)
                local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local end_time = start_time + length
                table.insert(sel_items, {start=start_time, end_=end_time})
            end

            -- 2. 시간순 정렬 (Sort by start time)
            table.sort(sel_items, function(a, b) return a.start < b.start end)

            -- 3. 겹치는 구간 병합 (Merge overlapping items)
            local regions_to_create = {}
            local current_start, current_end = -1, -1

            for _, item_data in ipairs(sel_items) do
                local s = item_data.start
                local e = item_data.end_
                
                if current_start == -1 then
                    current_start = s
                    current_end = e
                elseif s <= current_end then
                    current_end = math.max(current_end, e)
                else
                    table.insert(regions_to_create, {start=current_start, end_=current_end})
                    current_start = s
                    current_end = e
                end
            end

            if current_start ~= -1 then
                table.insert(regions_to_create, {start=current_start, end_=current_end})
            end

            reaper.Undo_BeginBlock()
            
            for i, region_data in ipairs(regions_to_create) do
                local start = region_data.start
                local end_ = region_data.end_
                local n = base_name
                
                if is_sequential_name then
                    n = string.format("%s_%02d", base_name, i)
                end
                reaper.AddProjectMarker(project, 1, start, end_, n, -1)
            end

            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Create Regions from Items", -1)
        end
    -- Take Channel Mode & Pitch Mode
        function ApplyTakeChannelMode(mode)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            reaper.Undo_BeginBlock()
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local take = reaper.GetActiveTake(item)
                if take then
                    reaper.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", mode)
                end
            end
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Set Take Channel Mode", -1)
        end
        -- Pitch Mode Values
            local take_pitch_mode = -1 
            local take_pitch_sub_mode = 0
            local pitch_mode_list = {}

            -- 1. Project Default 추가
            table.insert(pitch_mode_list, { id = -1, name = "Project Default" })

            -- 2. REAPER 알고리즘 목록 불러오기
            local i = 0
            while true do
                local retval, mode_name = reaper.EnumPitchShiftModes(i)
                if not retval then break end
                if mode_name and mode_name ~= "" then
                    table.insert(pitch_mode_list, { id = i, name = mode_name })
                end
                
                i = i + 1
            end
        function ApplyTakePitchMode(main_mode, sub_mode)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            sub_mode = sub_mode or 0

            -- 값 합치기
            local final_val = -1
            
            if main_mode ~= -1 then
                final_val = (math.floor(sub_mode) << 16) | math.floor(main_mode)
            end

            reaper.Undo_BeginBlock()
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local take = reaper.GetActiveTake(item)
                if take then
                    reaper.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", final_val)
                end
            end
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Set Take Pitch Mode", -1)
        end
    -- Item Sync
        local take_chan_mode = 0
        local function GetSelectedItemsGUIDString()
            local guids = {}
            local cnt = reaper.CountSelectedMediaItems(0)
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
                table.insert(guids, guid)
            end
            return table.concat(guids, ",")
        end
        item_info_str1 = "  SR: "
        item_info_str2 = "  Ch:   |  Len: "
        item_info_str3 = "  Take: "
        function SyncSelectionData(ctx)
            if reaper.ImGui_IsAnyItemActive(ctx) then
                last_project_change_count = reaper.GetProjectStateChangeCount(0)
                return 
            end

            -- 2. 변경 감지
            local cur_change_count = reaper.GetProjectStateChangeCount(0)
            local cur_guids = GetSelectedItemsGUIDString()

            if cur_change_count ~= last_project_change_count or cur_guids ~= last_selected_guids then
                last_project_change_count = cur_change_count
                last_selected_guids = cur_guids

                -- Stretch/Batch 관련 변수 초기화
                anchor_min_pos = nil
                persistentClusters = {} 
                slot_group_base = {} 
                slot_stretch_ratio = 1.0 
                prev_slot_stretch_ratio = 1.0

                local cnt = reaper.CountSelectedMediaItems(0)
                
                -- Read Take ==================================
                if cnt > 0 then
                    local item = reaper.GetSelectedMediaItem(0, 0)
                        -- Fade Curve
                        adj_fade_in_cur = -reaper.GetMediaItemInfo_Value(item, "D_FADEINDIR")
                        adj_fade_out_cur = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTDIR")
                        
                        -- Loop & Mute
                        item_loop_src = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC") >= 1.0
                        item_mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE") >= 1.0
                        
                        -- Lock
                        local val_lock = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
                        item_lock = (val_lock ~= 0.0)
                    local take = reaper.GetActiveTake(item)
                    if take then
                        base_name = reaper.GetTakeName(take)
                        -- Volume (dB 변환)
                        local val_vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                        if val_vol > 0.00000001 then
                            adjust_vol = 20 * (math.log(val_vol) / math.log(10))
                        else
                            adjust_vol = -150.0
                        end
                        -- Volume Clamp
                        if adjust_vol < -30 then adjust_vol = -30 end
                        if adjust_vol > 30 then adjust_vol = 30 end
                        
                        -- Pan, Pitch, Rate
                        adjust_pan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN")
                        adjust_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                        adjust_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

                        -- Take Channel
                        take_chan_mode = math.floor(reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"))
                        local raw_pitch = math.floor(reaper.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE"))
                        if raw_pitch == -1 then
                            take_pitch_mode = -1
                            take_pitch_sub_mode = 0
                        else
                            take_pitch_mode = raw_pitch & 0xFFFF 
                            take_pitch_sub_mode = raw_pitch >> 16
                        end
                    end
                    if take then
                        -- 1. Source 가져오기
                        local source = reaper.GetMediaItemTake_Source(take)
                        
                        -- 2. Sample Rate & Channel
                        local s_rate = reaper.GetMediaSourceSampleRate(source)
                        local n_chan = reaper.GetMediaSourceNumChannels(source)
                        
                        -- 3. File Length (전체 파일 길이)
                        local src_len, is_qn = reaper.GetMediaSourceLength(source)
                        if is_qn then src_len = reaper.TimeMap2_QNToTime(0, src_len) end
                        
                        -- 시간 포맷팅 (mm:ss.ms)
                        local min = math.floor(src_len / 60)
                        local sec = src_len % 60
                        local len_str = string.format("%d:%05.2f", min, sec)

                        -- 4. Take Info (Current / Total)
                        local take_idx = reaper.GetMediaItemTakeInfo_Value(take, "IP_TAKENUMBER") + 1
                        local take_cnt = reaper.CountTakes(item)
                        
                        item_info_str1 = string.format("  SR: %dHz", s_rate)
                        item_info_str2 = string.format("  Ch: %d  |  Len: %s", n_chan, len_str)
                        item_info_str3 = string.format("  Take: %d/%d", take_idx, take_cnt)
                    end
                else
                -- Default Values =============================
                    adjust_vol = 0.0
                    adjust_pan = 0.0
                    adjust_pitch = 0.0
                    adjust_rate = 1.0
                    item_loop_src = 0.0
                    item_mute = 0.0
                    item_lock = 0.0
                    adj_fade_in_cur = 0.0
                    adj_fade_out_cur = 0.0
                    base_name = ""
                    item_info_str1 = "  SR: "
                    item_info_str2 = "  Ch:   |  Len: "
                    item_info_str3 = "  Take: "
                end
            end
        end
    -- Channel Mode & Pitch Mode Combo Draw
        function DrawChannelModeCombo(ctx, width)
            reaper.ImGui_SetNextItemWidth(ctx, width or 128)
            -- [1] Preview Text
            local preview_text = ""

            if reaper.CountSelectedMediaItems(0) > 0 then
                if take_chan_mode == 0 then preview_text = "  Normal"
                elseif take_chan_mode == 1 then preview_text = "  Reverse Stereo"
                elseif take_chan_mode == 2 then preview_text = "  Mono (Mix L+R)"
                elseif take_chan_mode == 3 then preview_text = "  Mono (Left)"
                elseif take_chan_mode == 4 then preview_text = "  Mono (Right)"
                elseif take_chan_mode >= 67 then
                    local st_ch = take_chan_mode - 66
                    preview_text = string.format("  Stereo %d/%d", st_ch, st_ch + 1)
                elseif take_chan_mode >= 5 then
                    local mono_ch = take_chan_mode - 2
                    preview_text = string.format("  Mono %d", mono_ch)
                else
                    preview_text = "  Custom / Other"
                end
            end

            -- [2] 드롭다운 시작
            if reaper.ImGui_BeginCombo(ctx, "##ChannelMode", preview_text, reaper.ImGui_ComboFlags_HeightLarge()) then
                
                -- A. 기본 모드들 (0 ~ 4)
                local base_modes = { "Normal", "Reverse Stereo", "Mono (Mix L+R)", "Mono (Left)", "Mono (Right)" }
                for i, name in ipairs(base_modes) do
                    local real_val = i - 1
                    if reaper.ImGui_Selectable(ctx, name, take_chan_mode == real_val) then
                        take_chan_mode = real_val
                        ApplyTakeChannelMode(take_chan_mode)
                    end
                end

                reaper.ImGui_Separator(ctx)

                -- B. Mono (3 ~ 12)
                if reaper.ImGui_BeginMenu(ctx, "Mono (3-12)") then
                    for i = 3, 12 do
                        local real_val = i + 2
                        
                        if reaper.ImGui_MenuItem(ctx, "Mono " .. i, nil, take_chan_mode == real_val) then
                            take_chan_mode = real_val
                            ApplyTakeChannelMode(take_chan_mode) 
                        end
                    end
                    reaper.ImGui_EndMenu(ctx)
                end

                -- C. Stereo (1 ~ 12)
                if reaper.ImGui_BeginMenu(ctx, "Stereo (1-12)") then
                    for i = 1, 12 do
                        local real_val = i + 66
                        local label = string.format("Stereo %d/%d", i, i+1)
                        
                        if reaper.ImGui_MenuItem(ctx, label, nil, take_chan_mode == real_val) then
                            take_chan_mode = real_val
                            ApplyTakeChannelMode(take_chan_mode)
                        end
                    end
                    reaper.ImGui_EndMenu(ctx)
                end

                reaper.ImGui_Separator(ctx)

                -- Action
                if reaper.ImGui_Selectable(ctx, "Open Channel Mapper...") then
                    reaper.Main_OnCommand(42429, 0)
                end

                reaper.ImGui_EndCombo(ctx)
            end
        end
        function DrawPitchModeCombo(ctx, width1, width2)
            local item_cnt = reaper.CountSelectedMediaItems(0)
            
            -- 1. Main Mode Combo (Algorithm)
            reaper.ImGui_SetNextItemWidth(ctx, width1 or 128)
            
            local main_preview = ""
            if item_cnt > 0 then
                main_preview = "  Project Default"
                for _, mode in ipairs(pitch_mode_list) do
                    if mode.id == take_pitch_mode then
                        main_preview = "  " .. mode.name
                        break
                    end
                end
            end

            if reaper.ImGui_BeginCombo(ctx, "##PitchModeMain", main_preview, reaper.ImGui_ComboFlags_HeightLarge()) then
                for _, mode in ipairs(pitch_mode_list) do
                    local is_selected = (take_pitch_mode == mode.id)
                    local label = mode.name .. "##pm_" .. mode.id
                    
                    if reaper.ImGui_Selectable(ctx, label, is_selected) then
                        take_pitch_mode = mode.id
                        take_pitch_sub_mode = 0
                        ApplyTakePitchMode(take_pitch_mode, take_pitch_sub_mode)
                    end

                    if is_selected then reaper.ImGui_SetItemDefaultFocus(ctx) end
                end
                reaper.ImGui_EndCombo(ctx)
            end

            -- 2. Sub Mode Combo (Parameter)
            reaper.ImGui_SetNextItemWidth(ctx, width2 or 128)
            local is_sub_active = (item_cnt > 0) and (take_pitch_mode ~= -1)
            local sub_preview = ""

            if is_sub_active then
                local current_sub_name = reaper.EnumPitchShiftSubModes(take_pitch_mode, take_pitch_sub_mode)
                if current_sub_name then 
                    sub_preview = "  " .. current_sub_name 
                else
                    sub_preview = "  Normal"
                end
            end

            if reaper.ImGui_BeginCombo(ctx, "##PitchModeSub", sub_preview) then
                if is_sub_active then
                    local j = 0
                    while true do
                        local sub_name = reaper.EnumPitchShiftSubModes(take_pitch_mode, j)
                        if not sub_name then break end

                        local is_selected = (take_pitch_sub_mode == j)
                        if reaper.ImGui_Selectable(ctx, sub_name .. "##sub_" .. j, is_selected) then
                            take_pitch_sub_mode = j
                            ApplyTakePitchMode(take_pitch_mode, take_pitch_sub_mode)
                        end
                        
                        if is_selected then reaper.ImGui_SetItemDefaultFocus(ctx) end
                        j = j + 1
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
        end

----------------------------------------------------------
-- Items Arranger & Randomizer
----------------------------------------------------------
    -- Live Update Check & Settings Load/Save
        -- Default Value
            local slot_stretch_ratio = 1.0
            local prev_slot_stretch_ratio = 1.0
            local slot_group_base = {}
            local last_selected_guids = ""

            local width        = 5
            local spacing_mode = 0
            local use_clustering = true
            local use_edit_cursor = false
            local pos_range    = 0
            local pitch_range      = 0
            local playback_range   = 0
            local vol_range        = 0
            local current_play_slot = 0
        -- Checkbox Default Value
            local checkbox_x     = 455
            local checkbox_y     = 338
            local checkbox_h     = 25
            local random_pos     = true
            local random_pitch   = true
            local random_play    = true
            local random_vol     = true
            local random_order   = false
            local live_update    = true
        -- State tracking for selection change and initialization
            local prev_project_state_count = reaper.GetProjectStateChangeCount(0) 
        -- Save
            local prev_width, prev_pos_range = width, pos_range
            local prev_pitch_range, prev_playback_range, prev_vol_range = pitch_range, playback_range, vol_range
            local prev_random_pos, prev_random_pitch, prev_random_play, prev_random_vol, prev_random_order =
                random_pos, random_pitch, random_play, random_vol, random_order
        -- freeze (Cluster IDs based)
            local stored_offsets    = {}
            local stored_pitch      = {}
            local stored_playrates  = {}
            local stored_vols       = {}
        -- Slot Persistent (Now stores CLUSTERS, not just items)
            local persistentClusters = {} 
            local anchor_min_pos = nil
        function has_changed()
            return (
                width        ~= prev_width or
                use_clustering ~= prev_use_clustering or
                spacing_mode  ~= prev_spacing_mode or
                pos_range    ~= prev_pos_range or
                pitch_range  ~= prev_pitch_range or
                playback_range ~= prev_playback_range or
                vol_range    ~= prev_vol_range or
                random_pos   ~= prev_random_pos or
                random_pitch ~= prev_random_pitch or
                random_play  ~= prev_random_play or
                random_vol   ~= prev_random_vol
            )
        end
        function has_range_value_changed()
            return (
                pos_range    ~= prev_pos_range or
                pitch_range  ~= prev_pitch_range or
                playback_range ~= prev_playback_range or
                vol_range    ~= prev_vol_range
            )
        end
        function update_prev()
            prev_width        = width
            prev_use_clustering = use_clustering
            prev_spacing_mode   = spacing_mode
            prev_pos_range    = pos_range
            prev_pitch_range  = pitch_range
            prev_playback_range = playback_range
            prev_vol_range    = vol_range
            prev_random_pos   = random_pos
            prev_random_pitch = random_pitch
            prev_random_play  = random_play
            prev_random_vol   = random_vol
        end
        local function LoadSettings()
            local function LoadFlag(namespace, key, default)
                local v = reaper.GetExtState(namespace, key)
                if v == "1" then return true end
                if v == "0" then return false end
                return default
            end

            width = tonumber(reaper.GetExtState("JKK_ItemTool", "width")) or 5.0
            use_clustering = (tonumber(reaper.GetExtState("JKK_ItemTool", "use_clustering")) or 1) == 1
            spacing_mode = tonumber(reaper.GetExtState("JKK_ItemTool", "spacing_mode")) or 0
            use_edit_cursor = LoadFlag("JKK_ItemTool", "use_edit_cursor", false)
            pos_range = tonumber(reaper.GetExtState("JKK_ItemTool", "pos_range")) or 0.0
            pitch_range = tonumber(reaper.GetExtState("JKK_ItemTool", "pitch_range")) or 0.0
            playback_range = tonumber(reaper.GetExtState("JKK_ItemTool", "playback_range")) or 0.0
            vol_range = tonumber(reaper.GetExtState("JKK_ItemTool", "vol_range")) or 0.0

            random_pos   = LoadFlag("JKK_ItemTool", "random_pos", true)
            random_pitch = LoadFlag("JKK_ItemTool", "random_pitch", true)
            random_play  = LoadFlag("JKK_ItemTool", "random_play", true)
            random_vol   = LoadFlag("JKK_ItemTool", "random_vol", true)
            random_order = LoadFlag("JKK_ItemTool", "random_order", false)
            live_update  = LoadFlag("JKK_ItemTool", "live_update", true)

            update_prev() 
        end
        local function SaveSettings()
            reaper.SetExtState("JKK_ItemTool", "width", tostring(width), true)
            reaper.SetExtState("JKK_ItemTool", "use_clustering", use_clustering and "1" or "0", true)
            reaper.SetExtState("JKK_ItemTool", "spacing_mode", tostring(spacing_mode), true)
            reaper.SetExtState("JKK_ItemTool", "use_edit_cursor", use_edit_cursor and "1" or "0", true)
            reaper.SetExtState("JKK_ItemTool", "pos_range", tostring(pos_range), true)
            reaper.SetExtState("JKK_ItemTool", "pitch_range", tostring(pitch_range), true)
            reaper.SetExtState("JKK_ItemTool", "playback_range", tostring(playback_range), true)
            reaper.SetExtState("JKK_ItemTool", "vol_range", tostring(vol_range), true)
            
            reaper.SetExtState("JKK_ItemTool", "random_pos", random_pos and "1" or "0", true)
            reaper.SetExtState("JKK_ItemTool", "random_pitch", random_pitch and "1" or "0", true)
            reaper.SetExtState("JKK_ItemTool", "random_play", random_play and "1" or "0", true)
            reaper.SetExtState("JKK_ItemTool", "random_vol", random_vol and "1" or "0", true)
            reaper.SetExtState("JKK_ItemTool", "random_order", random_order and "1" or "0", true)
            reaper.SetExtState("JKK_ItemTool", "live_update", live_update and "1" or "0", true)
        end
        LoadSettings()
    -- Clustering Logic
        local function CollectAndSortSelectedItems()
            local cnt = reaper.CountSelectedMediaItems(0)
            local items = {}
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                table.insert(items, {
                    item = item,
                    pos = pos,
                    end_pos = pos + len,
                    len = len
                })
            end
            table.sort(items, function(a, b) return a.pos < b.pos end)
            return items
        end

        local function BuildClusters(sorted_items)
            local clusters = {}
            if #sorted_items == 0 then return clusters end

            local epsilon = 0.001 
            local current_cluster = nil

            for i, data in ipairs(sorted_items) do
                if current_cluster == nil then
                    current_cluster = {
                        items = {data.item},
                        start_pos = data.pos,
                        end_pos = data.end_pos,
                        items_data = {{item = data.item, rel_pos = 0}}
                    }
                else
                    if data.pos < current_cluster.end_pos - epsilon then
                        table.insert(current_cluster.items, data.item)
                        table.insert(current_cluster.items_data, {
                            item = data.item,
                            rel_pos = data.pos - current_cluster.start_pos
                        })
                        
                        if data.end_pos > current_cluster.end_pos then
                            current_cluster.end_pos = data.end_pos
                        end
                    else
                        table.insert(clusters, current_cluster)
                        current_cluster = {
                            items = {data.item},
                            start_pos = data.pos,
                            end_pos = data.end_pos,
                            items_data = {{item = data.item, rel_pos = 0}}
                        }
                    end
                end
            end

            if current_cluster then
                table.insert(clusters, current_cluster)
            end

            return clusters
        end

        local last_selection_hash = ""
        local function GetSelectionHash()
            local cnt = reaper.CountSelectedMediaItems(0)
            local hash = ""
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                hash = hash .. tostring(item)
            end
            return hash
        end

        local function IsPersistentClustersValid()
            if #persistentClusters == 0 then return false end
            if persistentClusters[1] and persistentClusters[1].items[1] then
                if not reaper.ValidatePtr(persistentClusters[1].items[1], "MediaItem*") then
                    return false
                end
            else
                return false
            end
            return true
        end

        local function ShuffleClusters(clusters)
            local shuffled = {}
            for i, v in ipairs(clusters) do shuffled[i] = v end
            for i = #shuffled, 2, -1 do
                local j = math.random(i)
                shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
            end
            return shuffled
        end

        local p = 1.737
        local slider_pos, display_str
        local max_grid, max_sec = 10.0, 5.0
        local min_rpm, max_rpm = 40.0, 2000.0
        local function CalculateSpacingAmount(val)
            local spacing = 0.0
            
            if spacing_mode == 0 then -- Grid
                local _, grid_size = reaper.GetSetProjectGrid(0, false)
                spacing = grid_size * val * 2
                
            elseif spacing_mode == 1 then -- Seconds
                local p = 1.737
                spacing = ((val / 5.0) ^ p) * 5.0
                
            elseif spacing_mode == 2 then -- RPM
                if val < 1 then val = 1 end
                spacing = 60 / val
            end
            
            return spacing
        end
    -- Apply Spacing
        function apply_spacing_only()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            local base_anchor
            if use_edit_cursor then
                base_anchor = reaper.GetCursorPosition()
            else
                if anchor_min_pos == nil then
                    local sorted = CollectAndSortSelectedItems()
                    if sorted[1] then anchor_min_pos = sorted[1].pos end
                end
                base_anchor = anchor_min_pos
            end

            local _, grid_size = reaper.GetSetProjectGrid(0, false)
            local spacing = CalculateSpacingAmount(width)
            local start_pos = base_anchor

            if not IsPersistentClustersValid() then
                local sorted_items = CollectAndSortSelectedItems()
                
                if use_clustering then
                    persistentClusters = BuildClusters(sorted_items)
                else
                    persistentClusters = {}
                    for _, data in ipairs(sorted_items) do
                        table.insert(persistentClusters, {
                            items = {data.item},
                            start_pos = data.pos,
                            end_pos = data.end_pos,
                            items_data = {{item = data.item, rel_pos = 0}}
                        })
                    end
                end
            end
            local clusters = persistentClusters

            reaper.Undo_BeginBlock()
            reaper.PreventUIRefresh(1)

            for i, cluster in ipairs(clusters) do
                local cluster_base_pos = start_pos + spacing * (i - 1)
                
                if stored_offsets[i] ~= nil then
                    cluster_base_pos = cluster_base_pos + stored_offsets[i]
                end
                
                for _, item_data in ipairs(cluster.items_data) do
                    local item = item_data.item
                    if reaper.ValidatePtr(item, "MediaItem*") then
                        local new_pos = cluster_base_pos + item_data.rel_pos
                        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
                    end
                end
            end

            reaper.PreventUIRefresh(-1)
            reaper.Undo_EndBlock("Cluster Spacing Updated", -1)
            reaper.UpdateArrange()
            current_play_slot = 0
        end
    -- Arrange Items Logic (Randomization/Arrangement)
        function arrange_items()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            -- 1. 아이템 수집 및 기준 위치(Anchor) 설정
            local sorted_items = CollectAndSortSelectedItems()
            
            if anchor_min_pos == nil then
                if sorted_items[1] then anchor_min_pos = sorted_items[1].pos end
            end

            local start_pos = base_anchor or anchor_min_pos
            if use_edit_cursor then start_pos = reaper.GetCursorPosition() end
            
            -- 2. 간격 계산
            local spacing = CalculateSpacingAmount(width)

            reaper.Undo_BeginBlock()
            reaper.PreventUIRefresh(1)

            -- 3. 클러스터 관리
            if not IsPersistentClustersValid() then
                persistentClusters = BuildClusters(sorted_items)
            end
            local clusters = persistentClusters

            -- 4. 랜덤 및 배치 로직 루프
            for i, cluster in ipairs(clusters) do
                local cluster_base_pos = start_pos + spacing * (i - 1)

                for j, item_data in ipairs(cluster.items_data) do
                    local item = item_data.item
                    if reaper.ValidatePtr(item, "MediaItem*") then
                        local take = reaper.GetActiveTake(item)
                        local item_key = i .. "_" .. j 

                        local rnd_pitch_val = random_pitch and ((math.random() * pitch_range * 2) - pitch_range) or (stored_pitch[item_key] or 0)
                        local rnd_play_rate = random_play and (2 ^ (((math.random() * playback_range * 2) - playback_range) / 12)) or (stored_playrates[item_key] or 1.0)
                        local rnd_pos_offset = random_pos and ((math.random() * pos_range * 2) - pos_range) or (stored_offsets[item_key] or 0)
                        
                        local rnd_vol_val = stored_vols[item_key] or 1.0
                        if random_vol then
                            if vol_range > 0 then
                                local rnd_db = (math.random() * 2.0 - 1.0) * vol_range
                                rnd_vol_val = 10 ^ (rnd_db / 20)
                            else
                                rnd_vol_val = 1.0
                            end
                        end

                        -- 데이터 캐싱
                        stored_vols[item_key] = rnd_vol_val
                        stored_pitch[item_key] = rnd_pitch_val
                        stored_playrates[item_key] = rnd_play_rate
                        stored_offsets[item_key] = rnd_pos_offset

                        -- 테이크 속성 적용
                        if take then
                            reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", rnd_pitch_val)
                            reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", rnd_vol_val)
                            
                            local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                            local current_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                            local source_len = current_length * current_rate
                            local new_len = source_len / rnd_play_rate
                            
                            reaper.SetMediaItemLength(item, new_len, true)
                            reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rnd_play_rate)
                        end

                        local final_cluster_pos = cluster_base_pos + rnd_pos_offset
                        local scaled_rel_pos = item_data.rel_pos / rnd_play_rate
                        reaper.SetMediaItemInfo_Value(item, "D_POSITION", final_cluster_pos + scaled_rel_pos)
                    end
                end
            end

            reaper.PreventUIRefresh(-1)
            reaper.Undo_EndBlock("Variator (Cluster) Updated", -1)
            reaper.UpdateArrange()
            current_play_slot = 0
        end
        function shuffle_item_order()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            -- 1. 현재 배치 상태를 기준으로 클러스터 빌드 (슬롯 생성)
            local sorted_items = CollectAndSortSelectedItems()
            local clusters = BuildClusters(sorted_items)

            -- 2. 트랙별로 아이템 모으기
            local track_map = {}
            local track_list = {}

            for i, cluster in ipairs(clusters) do
                for j, item_data in ipairs(cluster.items_data) do
                    local track = reaper.GetMediaItem_Track(item_data.item)
                    if not track_map[track] then
                        track_map[track] = {}
                        table.insert(track_list, track)
                    end
                    table.insert(track_map[track], item_data.item)
                end
            end

            -- 3. 각 트랙 내에서 아이템 순서만 무작위로 섞기
            for _, track in ipairs(track_list) do
                local items = track_map[track]
                for i = #items, 2, -1 do
                    local j = math.random(i)
                    items[i], items[j] = items[j], items[i]
                end
            end

            -- 4. 섞인 아이템들을 원래 클러스터 구조(슬롯)에 다시 끼워넣기
            local track_counters = {}
            for _, track in ipairs(track_list) do track_counters[track] = 1 end

            for i, cluster in ipairs(clusters) do
                for j, item_data in ipairs(cluster.items_data) do
                    local track = reaper.GetMediaItem_Track(item_data.item)
                    local idx = track_counters[track]
                    
                    item_data.item = track_map[track][idx]
                    track_counters[track] = idx + 1
                end
            end

            -- 5. 변경된 클러스터 구조 저장 및 캐시 초기화
            persistentClusters = clusters
            stored_offsets = {}
            stored_pitch = {}
            stored_playrates = {}
            stored_vols = {}

            arrange_items()
        end

----------------------------------------------------------
-- Item Spliter
----------------------------------------------------------
    -- Default Value
        local silenceThreshold = 0.01
        local minSilenceDuration = 0.2
        local showGuideBox = false
        local shouldKeepOriginal = true

        local lastSelectionSignature = ""
        local silenceItems = {}
    -- Logic & Function
        local function tableToString(tbl, depth)
            if depth == nil then depth = 1 end
            if depth > 5 then return "..." end

            local str = "{"
            for k, v in pairs(tbl) do
                local key = tostring(k)
                local value = type(v) == "table" and tableToString(v, depth + 1) or tostring(v)
                str = str .. "[" .. key .. "] = " .. value .. ", "
            end
            str = str:sub(1, -3)
            str = str .. "}"
            return str
        end

        local function print(string)
            reaper.ShowConsoleMsg(string .. "\n")
        end

        local function showMessage(string, title, errType)
            local userChoice = reaper.MB(string, title, errType)
            return userChoice
        end

        if not reaper.APIExists("CF_GetSWSVersion") then
            local userChoice = showMessage("This script requires the SWS Extension to run. Would you like to download it ?", "Error", 4)
            if userChoice == 6 then
                openURL("https://www.sws-extension.org/")
            else
                return
            end
        end

        if not reaper.APIExists("ImGui_GetVersion") then
            showMessage("This script requires ReaImGui to run. Please install it with ReaPack.", "Error", 0)
            return
        end


        local selectedItems = {}
        local silenceItems = {}
        local lastTrack = nil
        ---------------------------------------
        -- FIRST RUN CHECK
        ---------------------------------------
            local extStateKey = "PeaksAndValleysByKusa"
            local extStateFlag = "HasRunBefore"

            local hasRunBefore = reaper.GetExtState(extStateKey, extStateFlag)

            if hasRunBefore == "" then
                local userChoice = showMessage("If you have just installed this script, please close and reopen REAPER to prevent potential crashes.\n Would you like to quit REAPER now ?", "Thank you for downloading Peaks & Valleys.", 4)
                if userChoice == 6 then
                    reaper.SetExtState(extStateKey, extStateFlag, "true", true)
                    reaper.Main_OnCommand(40004, 0) -- File: Quit REAPER
                else
                reaper.SetExtState(extStateKey, extStateFlag, "true", true)
                end
            end

        ---------------------------------------
        -- GENERAL FUNCTIONS
        ---------------------------------------
            local function getChannelsOfSelectedItem(take)
                local source = reaper.GetMediaItemTake_Source(take)
                if not source then return nil end

                local channels = reaper.GetMediaSourceNumChannels(source)
                return channels
            end

            local function selectNextTrack(currentTrack)
                local currentTrackIndex = reaper.GetMediaTrackInfo_Value(currentTrack, "IP_TRACKNUMBER") - 1
                local totalTracks = reaper.CountTracks(0)
                local nextTrackIndex = currentTrackIndex + 1
                if nextTrackIndex < totalTracks then
                    local nextTrack = reaper.GetTrack(0, nextTrackIndex)
                    reaper.SetOnlyTrackSelected(nextTrack)
                else
                    showMessage("No next track available.", "Error", 0)
                end
            end

            local function setAllFXStateOnTrack(track, state)
                local fxCount = reaper.TrackFX_GetCount(track)
                for fxIndex = 0, fxCount - 1 do
                    reaper.TrackFX_SetEnabled(track, fxIndex, state)
                end
            end

            local function muteOriginalItem(item, originalTrack)
                reaper.SetMediaTrackInfo_Value(originalTrack, "B_MUTE", 0)
                local itemCount = reaper.GetTrackNumMediaItems(originalTrack)
                local trackItemPosition = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                reaper.SetMediaItemInfo_Value(item, "B_MUTE_ACTUAL", 1)
                return trackItemPosition
            end

            local function getMediaItemAtPosition(track, position)
                local itemCount = reaper.CountTrackMediaItems(track)
                for i = 0, itemCount - 1 do
                    local item = reaper.GetTrackMediaItem(track, i)
                    if item then
                        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        if itemStart == position then
                            return item
                        end
                    end
                end
                return nil
            end

            local function findChildTrackByName(parentTrack, trackName)
                local parentTrackIdx = reaper.GetMediaTrackInfo_Value(parentTrack, "IP_TRACKNUMBER") - 1
                local trackCount = reaper.CountTracks(0)
                for i = parentTrackIdx + 1, trackCount - 1 do
                    local track = reaper.GetTrack(0, i)
                    local isChild = reaper.GetParentTrack(track) == parentTrack
                    retval, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
                    if isChild and name == trackName then
                        return track
                    elseif reaper.GetTrackDepth(track) <= reaper.GetTrackDepth(parentTrack) then
                        break
                    end
                end
                return nil
            end

            local function getUnusedGroupNumber()
                local groupNumber = 1
                while true do
                    local found = false
                    for i = 0, reaper.CountMediaItems(0) - 1 do
                        local item = reaper.GetMediaItem(0, i)
                        if item and reaper.GetMediaItemInfo_Value(item, "I_GROUPID") == groupNumber then
                            found = true
                            break
                        end
                    end
                    if not found then return groupNumber end
                    groupNumber = groupNumber + 1
                end
            end

            local function createChildTrack(parentTrack, childTrack, item, trackItemPosition)
                local trackName = "Original item"
                local parentTrackIndex = reaper.CSurf_TrackToID(parentTrack, false)
                reaper.ReorderSelectedTracks(parentTrackIndex, 1)
                local newItem = getMediaItemAtPosition(childTrack, trackItemPosition)
                reaper.MoveMediaItemToTrack(newItem, parentTrack)
                local originalItemTrack = findChildTrackByName(parentTrack, trackName)
                if originalItemTrack then
                    reaper.MoveMediaItemToTrack(item, originalItemTrack)
                    reaper.DeleteTrack(childTrack)
                else
                    reaper.MoveMediaItemToTrack(item, childTrack)
                    reaper.GetSetMediaTrackInfo_String(childTrack, "P_NAME", trackName, true)
                end
                reaper.SetMediaItemSelected(item, false)
                reaper.SetMediaItemSelected(newItem, true)
                reaper.UpdateArrange()
                return newItem
            end

            local function removeOldItemFromTable(item, selectedItems)
                for i = #selectedItems, 1, -1 do
                    if selectedItems[i] == item then
                        table.remove(selectedItems, i)
                        break
                    end
                end  
            end

            local function storeSelectedMediaItems()
                local itemCount = reaper.CountSelectedMediaItems(0)
                local selectedItems = {}
                for i = 0, itemCount - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    local take = reaper.GetActiveTake(item)
                    if item and take then
                        table.insert(selectedItems, item)
                    end
                end
                return selectedItems
            end

            local function cleanupAfterRender(item, originalTrack, shouldKeepOriginal, selectedItems)
                setAllFXStateOnTrack(originalTrack, true)
                local trackItemPosition = muteOriginalItem(item, originalTrack)
                reaper.Main_OnCommand(40635, 0) -- Time selection: Remove (unselect) time selection
                local track = reaper.GetMediaItem_Track(item)
                local childTrack = reaper.GetSelectedTrack(0, 0)
                local newItem
                if shouldKeepOriginal then
                    newItem = createChildTrack(originalTrack, childTrack, item, trackItemPosition)

                else
                    newItem = getMediaItemAtPosition(childTrack, trackItemPosition)
                    reaper.MoveMediaItemToTrack(newItem, originalTrack)
                    reaper.DeleteTrackMediaItem(originalTrack, item)
                    reaper.DeleteTrack(childTrack)
                    reaper.SetMediaItemSelected(newItem, true)
                end
                reaper.UpdateArrange()
            end

            local function addFades()
                local numItems = reaper.CountSelectedMediaItems(0)
                for i = 0, numItems - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0.0001)
                    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0.1)
                end
            end

            local function spaceSelectedItems(amount)
                local itemCount = reaper.CountSelectedMediaItems(0)
                if itemCount < 2 then return end
                local prevItem = reaper.GetSelectedMediaItem(0, 0)
                local prevItemEnd = reaper.GetMediaItemInfo_Value(prevItem, "D_LENGTH") + reaper.GetMediaItemInfo_Value(prevItem, "D_POSITION")
                for i = 1, itemCount - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    local newPosition = prevItemEnd + amount
                    reaper.SetMediaItemPosition(item, newPosition, false)
                    prevItemEnd = newPosition + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                end
            end

            local function getSelectedItemPlayrate(take)
                local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                return playrate
            end

            local function bounceInPlace(item, track, shouldKeepOriginal, selectedItems)
                local take = reaper.GetActiveTake(item)
                reaper.SetOnlyTrackSelected(track)
                local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local itemEnd = itemStart + itemLength
                reaper.GetSet_LoopTimeRange(true, false, itemStart, itemEnd, false)
                local numChannels = getChannelsOfSelectedItem(take)
                setAllFXStateOnTrack(track, false)
                if numChannels == 1 then
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_AWRENDERMONOSMART"), 0)
                else
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_AWRENDERSTEREOSMART"), 0)
                end
                cleanupAfterRender(item, track, shouldKeepOriginal, selectedItems)
            end

            local function audioIsWav(take)
                if take then
                    local source = reaper.GetMediaItemTake_Source(take)
                    local sourceType = reaper.GetMediaSourceType(source, "")
                    return sourceType == "WAVE"
                end
                return false
            end

            local function hasBeenStretchedFunction(take, item, track)
                local retval = reaper.GetTakeNumStretchMarkers(take)
                local playrate = getSelectedItemPlayrate(take)
                local epsilon = 0.1

                if retval > 0 then
                    return true, "The item has stretch markers."
                elseif math.abs(playrate - 1) > epsilon then
                    return true, "The item's playrate has been altered."
                else
                    return false, ""
                end
            end

        ---------------------------------------
        -- BUFFER 
        ---------------------------------------
            local function calculateDownsamplingFactor(totalSamples, numChannels)
                --local maxBufferSize = 4159674
                local maxBufferSize = 3000000
                local maxSamplesPerChannel = maxBufferSize / numChannels
                return math.max(1, math.ceil(totalSamples / maxSamplesPerChannel))
            end

            local function prepareItemAnalysis(item, take)
                if not take then return end
                local accessor = reaper.CreateTakeAudioAccessor(take)
                local retval, currentSampleRate = reaper.GetAudioDeviceInfo("SRATE")
                local sampleRate = tonumber(currentSampleRate)
                if not sampleRate then
                    showMessage("Sample Rate could not be found. Is the Audio Device set ?", "Whoops", 0)
                    return
                end
                local numChannels = getChannelsOfSelectedItem(take)
                local startTime = reaper.GetAudioAccessorStartTime(accessor)
                local endTime = reaper.GetAudioAccessorEndTime(accessor)
                return accessor, sampleRate, numChannels, startTime, endTime
            end

            local function calculateTotalSamples(startTime, endTime, sampleRate)
                return math.floor((endTime - startTime) * sampleRate)
            end

            local function populateBufferWithDownsampling(accessor, sampleRate, numChannels, startTime, totalSamples, isSilence)
                local downsamplingFactor = calculateDownsamplingFactor(totalSamples, numChannels)
                if isSilence then
                    downsamplingFactor = downsamplingFactor * 80
                end
                local totalBlocks = math.ceil(totalSamples / downsamplingFactor)
                local buffer = reaper.new_array(totalBlocks * numChannels)
                buffer.clear()
                for i = 0, totalBlocks - 1 do
                    local blockStartTime = startTime + (i * downsamplingFactor / sampleRate)
                    local blockBuffer = reaper.new_array(numChannels)
                    blockBuffer.clear()
                    reaper.GetAudioAccessorSamples(accessor, sampleRate, numChannels, blockStartTime, 1, blockBuffer)
                    for ch = 1, numChannels do
                        buffer[i * numChannels + ch] = blockBuffer[ch]
                    end
                end
                return buffer, downsamplingFactor, totalBlocks
            end


            local function getBufferReady(item, isSilence, take)
                local accessor, sampleRate, numChannels, startTime, endTime = prepareItemAnalysis(item, take)
                if not sampleRate then return end
                local totalSamples = calculateTotalSamples(startTime, endTime, sampleRate)
                local buffer, downsamplingFactor, numSamplesInBuffer = populateBufferWithDownsampling(accessor, sampleRate, numChannels, startTime, totalSamples, isSilence)
                return buffer, numSamplesInBuffer, numChannels, downsamplingFactor, accessor, sampleRate, startTime
            end

        ---------------------------------------
        -- PEAK 
        ---------------------------------------
            local function findPeakInBuffer(buffer, numSamplesInBuffer, numChannels, downsamplingFactor)
                local peakValue = 0
                local peakIndex = 0
                for i = 1, numSamplesInBuffer do
                    local bufferIndex = (i - 1) * numChannels + 1
                    if bufferIndex <= #buffer then
                        for channel = 1, numChannels do
                            local sampleIndex = bufferIndex + (channel - 1)
                            if sampleIndex <= #buffer then
                                local sample = buffer[sampleIndex]
                                if sample > peakValue then
                                    peakValue = sample
                                    peakIndex = i
                                end
                            end
                        end
                    end
                end
                peakIndex = peakIndex * downsamplingFactor
                return peakValue, peakIndex
            end

            local function calculatePeakTime(take, item, peakIndex, sampleRate)
                local takeStartOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                local peakTimeRelativeToSource = takeStartOffset + (peakIndex / sampleRate)
                local itemPosition = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local peakTimeRelativeToProject = itemPosition + peakTimeRelativeToSource
                local itemStartPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local peakTime = itemStartPos + (peakIndex / sampleRate)

                if peakTimeRelativeToSource < 0 then peakTimeRelativeToSource = 0 end
                return peakTime
            end

            local function getPeakTime(item, take)
                local isSilence = false
                local peakBuffer, numSamplesInBuffer, numChannels, downsamplingFactor, peakAccessor, sampleRate, startTime = getBufferReady(item, isSilence, take)
                if not sampleRate then return end
                local peakValue, peakIndex = findPeakInBuffer(peakBuffer, numSamplesInBuffer, numChannels, downsamplingFactor)
                local peakTime = calculatePeakTime(take, item, peakIndex, sampleRate)
                reaper.DestroyAudioAccessor(peakAccessor)
                return peakTime
            end

        ---------------------------------------
        -- SILENCES 
        ---------------------------------------
            local function detectSilences(buffer, silenceThreshold, minSilenceDuration, sampleRate, downsamplingFactor, numChannels)
                local silences = {}
                local silenceStartIndex = nil
                local currentSilenceDuration = 0
                local minSilenceSamples = minSilenceDuration * sampleRate / downsamplingFactor * numChannels

                for i = 1, #buffer do
                    local sample = math.abs(buffer[i])
                    local isSilent = sample <= silenceThreshold

                    if isSilent then
                        if silenceStartIndex == nil then
                            silenceStartIndex = i
                        end
                        currentSilenceDuration = currentSilenceDuration + 1
                    else
                        if silenceStartIndex and currentSilenceDuration >= minSilenceSamples then
                            local silenceEndTimeIndex = silenceStartIndex + currentSilenceDuration - 1
                            table.insert(silences, { start = silenceStartIndex, ["end"] = silenceEndTimeIndex })
                        end
                        silenceStartIndex = nil
                        currentSilenceDuration = 0
                    end
                end

                if silenceStartIndex and currentSilenceDuration >= minSilenceSamples then
                    local silenceEndTimeIndex = silenceStartIndex + currentSilenceDuration - 1
                    table.insert(silences, { start = silenceStartIndex, ["end"] = silenceEndTimeIndex })
                end
                return silences
            end

            local function convertSilencesToTime(silences, startTime, sampleRate, downsamplingFactor, numChannels)
                local silencesInTime = {}
                for _, silence in ipairs(silences) do
                    local startInTime = startTime + ((silence.start / numChannels) * downsamplingFactor - downsamplingFactor) / sampleRate
                    local endInTime = startTime + ((silence["end"] / numChannels) * downsamplingFactor - downsamplingFactor) / sampleRate
                    if startInTime < 0 then
                        startInTime = 0
                    end

                    table.insert(silencesInTime, { start = startInTime, ["end"] = endInTime })
                end
                return silencesInTime
            end

            local function deleteSilencesFromItem(item, silences)
                if not item or #silences == 0 then
                    return
                end
                reaper.PreventUIRefresh(1)
                local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                for i = #silences, 1, -1 do
                    local silence = silences[i]
                    local silenceStart = itemStart + silence.start
                    local silenceEnd = itemStart + silence["end"]
                    if silenceEnd < silenceStart then
                        silenceEnd = silenceStart
                    end
                    if silenceStart == itemStart then
                        local splitItemEnd = reaper.SplitMediaItem(item, silenceEnd)
                        if splitItemEnd then
                            reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
                        end
                    else
                        local splitItemEnd = reaper.SplitMediaItem(item, silenceEnd)
                        local splitItemStart = reaper.SplitMediaItem(item, silenceStart)
                        if splitItemStart then
                            reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(splitItemStart), splitItemStart)
                        end
                    end
                end
                reaper.PreventUIRefresh(-1)

                reaper.UpdateArrange()
            end



            local function deleteShortItems(coeff)
                local selectedItemsCount = reaper.CountSelectedMediaItems(0)
                if selectedItemsCount == 0 then return end

                local totalLength = 0
                for i = 0, selectedItemsCount - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    totalLength = totalLength + length
                end

                local averageLength = totalLength / selectedItemsCount
                local minLength = averageLength / coeff

                for i = selectedItemsCount - 1, 0, -1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    
                    if length < minLength then
                        local track = reaper.GetMediaItem_Track(item)
                        reaper.DeleteTrackMediaItem(track, item)
                    end
                end
            end

            local function createTemporaryItems(track, silences, itemPosition)
                lastTrack = track
                local redColor = reaper.ColorToNative(255, 0, 0) | 0x1000000
                for _, silence in ipairs(silences) do
                    local silenceStart = itemPosition + silence.start
                    local silenceEnd = itemPosition + silence["end"]
                    local silenceLength = silenceEnd - silenceStart

                    local newItem = reaper.AddMediaItemToTrack(track)
                    reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", silenceStart)
                    reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", silenceLength)
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", 0)
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", 0)

                    reaper.SetMediaItemInfo_Value(newItem, "I_CUSTOMCOLOR", redColor)
                    table.insert(silenceItems, newItem)
                end
            end

            local function clearTemporaryItems()
                for _, item in ipairs(silenceItems) do
                    if reaper.ValidatePtr(item, "MediaItem*") then
                        local track = reaper.GetMediaItem_Track(item)
                        reaper.DeleteTrackMediaItem(track, item)
                    end
                end
                silenceItems = {}
            end

            local function cleanup()
                    clearTemporaryItems()
                    reaper.UpdateArrange()
            end

            local function getSilenceTime(item, take)
                local isSilence = true
                local silenceBuffer, numSamplesInBuffer, numChannels, downsamplingFactor, silenceAccessor, sampleRate, startTime = getBufferReady(item, isSilence, take)
                if not sampleRate then return end
                local silences = detectSilences(silenceBuffer, silenceThreshold, minSilenceDuration, sampleRate, downsamplingFactor, numChannels)
                local silencesInTime = convertSilencesToTime(silences, startTime, sampleRate, downsamplingFactor, numChannels)
                reaper.DestroyAudioAccessor(silenceAccessor)
                return silencesInTime
            end

        ---------------------------------------
        -- MAIN FUNCTIONS 
        ---------------------------------------
            local function getSelectedItemsBounds(selectedItemsCount)
                local minPos, maxEnd = math.huge, -math.huge

                for i = 0, selectedItemsCount - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local itemEnd = itemPos + itemLength

                    minPos = math.min(minPos, itemPos)
                    maxEnd = math.max(maxEnd, itemEnd)
                end

                return minPos, maxEnd
            end

            local function implodeToTakesKeepPosition()
                local selectedItemsCount = reaper.CountSelectedMediaItems(0)
                if selectedItemsCount < 1 then return end

                local minPos, maxEnd = getSelectedItemsBounds(selectedItemsCount)

                for i = 0, selectedItemsCount - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                    reaper.BR_SetItemEdges(item, minPos, maxEnd)
                end

                reaper.Main_OnCommand(40543, 0) -- Command ID for "Take: Implode items on same track into takes"
            end

            local function alignItemsByPeakTime()
                local numItems = reaper.CountSelectedMediaItems(0)
                if numItems < 2 then return end

                local firstItem = reaper.GetSelectedMediaItem(0, 0)
                local takeFirstItem = reaper.GetActiveTake(firstItem)
                local firstPeakTime = getPeakTime(firstItem, takeFirstItem)
                if not firstPeakTime then return end

                for i = 1, numItems - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    local take = reaper.GetActiveTake(item)
                    local peakTime = getPeakTime(item, take)
                    if not peakTime then return end
                    if peakTime then
                        local offset = firstPeakTime - peakTime
                        local itemPosition = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        local newPosition = itemPosition + offset
                        reaper.SetMediaItemInfo_Value(item, "D_POSITION", newPosition)
                    end
                end
                return firstPeakTime
            end

            local function alignItemsByStartPosition()
                local numItems = reaper.CountSelectedMediaItems(0)
                if numItems < 2 then return end

                local earliestStart = math.huge
                for i = 0, numItems - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    local itemPosition = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    if itemPosition < earliestStart then
                        earliestStart = itemPosition
                    end
                end

                for i = 0, numItems - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    reaper.SetMediaItemInfo_Value(item, "D_POSITION", earliestStart)
                end
                return earliestStart
            end

            local function splitMain(item, take, splitAndSpace)
                local silencesInLoop = getSilenceTime(item, take)
                reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                deleteSilencesFromItem(item, silencesInLoop)
                deleteShortItems(3)
                if splitAndSpace then
                    spaceSelectedItems(1)
                    addFades()
                end
            end

            local function implodeMain(item, take, onPeak, alignOnStart, silencesInLoop, shouldAlignToMarker, userMarkerChoice)
                local firstPeakTime
                local splitAndSpace = false
                splitMain(item, take, splitAndSpace)
                addFades()
                if onPeak then
                    firstPeakTime = alignItemsByPeakTime()
                    if not firstPeakTime then return end
                else
                    alignItemsByStartPosition()
                end
                implodeToTakesKeepPosition()
            end

            function tableIsEmpty(table)
                for _ in pairs(table) do
                    return false
                end
                return true
            end

            local function itemsAreValid(selectedItems)
                if not tableIsEmpty(selectedItems) then
                    local itemsToConvert = {}
                    local errorMessages = {}
                    for _, item in ipairs(selectedItems) do
                        local take = reaper.GetActiveTake(item)
                        local track = reaper.GetMediaItem_Track(item)
                        local isWav = audioIsWav(take)
                        local hasBeenStretched, stretchErrorMessage = hasBeenStretchedFunction(take, item, track)
                        if not isWav then
                            table.insert(itemsToConvert, item)
                            table.insert(errorMessages, "The item is not in WAV format.")
                        elseif hasBeenStretched then
                            table.insert(itemsToConvert, item)
                            table.insert(errorMessages, stretchErrorMessage)
                        end
                    end
                    if tableIsEmpty(itemsToConvert) then
                        return nil
                    else
                        return itemsToConvert, errorMessages
                    end
                end
                return nil
            end

            local function itemsAreSelected(table)
                for _ in pairs(table) do
                    return true
                end
                return false
            end

            local function unselectEveryItem()
                local itemCount = reaper.CountMediaItems(0)
                for i = 0, itemCount - 1 do
                    local currentItem = reaper.GetMediaItem(0, i)
                    reaper.SetMediaItemSelected(currentItem, false)
                end
            end

            local function askForBounce(shouldKeepOriginal, itemsToConvert, errorMessages)
                local message = table.concat(errorMessages, "\n") .. "\nAnalysing it might freeze REAPER. \nWould you like to create a usable copy?"
                local userChoice = showMessage(message, "Warning", 4)
                if userChoice == 6 then
                    for i, item in ipairs(itemsToConvert) do
                        local track = reaper.GetMediaItem_Track(item)
                        bounceInPlace(item, track, shouldKeepOriginal, itemsToConvert)
                    end
                    return true
                else
                    unselectEveryItem()
                    return false
                end
            end

            local function selectOnlyThisItem(item)
                unselectEveryItem()
                if item then
                    reaper.SetMediaItemSelected(item, true)
                end
            end

            local function safeToExecute(selectedItems)
                cleanup()
                local itemsToConvert, errorMessages = itemsAreValid(selectedItems)
                if itemsToConvert then
                    reaper.Undo_BeginBlock()
                    local goodToGo = askForBounce(shouldKeepOriginal, itemsToConvert, errorMessages)
                    reaper.Undo_EndBlock("Bounce in place.", -1)
                    return goodToGo
                else
                    return true
                end
            end

            local function safeToPreview(selectedItems)
                cleanup()
                local itemsToConvert, errorMessages = itemsAreValid(selectedItems)
                if itemsToConvert then
                    return false 
                else
                    return true
                end
            end
    -- Loop Module
        local ctx = reaper.ImGui_CreateContext('Peaks and Valleys by Kusa')

        silenceThreshold = 0.01
        minSilenceDuration = 0.2

        local activeMode
        local activeModeChanged
        local activeRetValString = reaper.GetExtState("PeaksAndValleys", "activeMode")
        if activeRetValString ~= "" then
            activeMode = (activeRetValString == "true")
        else
            activeMode = false
        end

        local shouldKeepOriginal
        local shouldKeepOriginalChanged
        local shouldKeepOriginalRetValString = reaper.GetExtState("PeaksAndValleys", "shouldKeepOriginal")
        if shouldKeepOriginalRetValString ~= "" then
            shouldKeepOriginal = (shouldKeepOriginalRetValString == "true")
        else
            shouldKeepOriginal = true
        end

        local alignToMarkerChanged = false
        local isWav = true
        local hasBeenStretched = false
        local splitAndSpace = false


        local lastSelectionSignature = ""

        local function loop()
            local visible, open = reaper.ImGui_Begin(ctx, "Peaks and Valleys by Kusa", true)
            
            if visible then
                -------- Item selection
                selectedItems = storeSelectedMediaItems()
                if not itemsAreSelected(selectedItems) then
                    cleanup()
                end

                -------- Check for Selection Change
                local currentSelectionSignature = ""
                for i, item in ipairs(selectedItems) do
                    currentSelectionSignature = currentSelectionSignature .. tostring(item) .. tostring(reaper.GetMediaItemInfo_Value(item, "D_POSITION"))
                end
                local selectionChanged = (currentSelectionSignature ~= lastSelectionSignature)
                lastSelectionSignature = currentSelectionSignature

                -------- Sliders change
                local thresholdChanged
                local minDurChanged
                thresholdChanged, silenceThreshold = reaper.ImGui_SliderDouble(ctx, 'Threshold', silenceThreshold, 0.001, 0.3, "%.3f")       
                minDurChanged, minSilenceDuration = reaper.ImGui_SliderDouble(ctx, 'Min Duration', minSilenceDuration, 0.001, 2.0, "%.3f")

                if activeMode and (thresholdChanged or minDurChanged or activeModeChanged or selectionChanged) then
                    if safeToPreview(selectedItems) then
                        selectedItems = storeSelectedMediaItems()
                        for i, item in ipairs(selectedItems) do
                            local take = reaper.GetActiveTake(item)
                            local track = reaper.GetMediaItem_Track(item)
                            local itemPosition = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                            local silencesInLoop = getSilenceTime(item, take)
                            if silencesInLoop then
                                createTemporaryItems(track, silencesInLoop, itemPosition)
                            end
                        end
                    end
                elseif not activeMode and activeModeChanged then
                     cleanup()
                end

                -------- Align with marker
                activeModeChanged, activeMode = reaper.ImGui_Checkbox(ctx, "Show Red Guide Box", activeMode)
                if activeModeChanged then
                    reaper.SetExtState("PeaksAndValleys", "activeMode", tostring(activeMode), true)
                end

                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, 'Split and Make Takes') then
                    cleanup()
                    reaper.Undo_BeginBlock()
                    if safeToExecute(selectedItems) then
                        local userMarkerChoice = nil
                        if shouldAlignToMarker then
                            userMarkerChoice = promptUserForNumber("Align with marker", "Please enter the Marker ID")
                        end
                        local selectedItems = storeSelectedMediaItems()
                        for i, item in ipairs(selectedItems) do
                            selectOnlyThisItem(item)
                            local take = reaper.GetActiveTake(item)
                            local track = reaper.GetMediaItem_Track(item)
                            local onPeak = false
                            local alignOnStart = true
                            local silencesInLoop = getSilenceTime(item, take) 
                            implodeMain(item, take, onPeak, alignOnStart, silencesInLoop)
                        end
                        reaper.UpdateArrange()
                    end
                    reaper.Undo_EndBlock("Implode to takes (start).", -1)
                end

                reaper.ImGui_SameLine(ctx)

                if reaper.ImGui_Button(ctx, 'Split and space items') then
                    cleanup()
                    reaper.Undo_BeginBlock()
                    if safeToExecute(selectedItems) then
                        local selectedItems = storeSelectedMediaItems()
                        for i, item in ipairs(selectedItems) do
                            local take = reaper.GetActiveTake(item)
                            selectOnlyThisItem(item)
                            splitAndSpace = true
                            splitMain(item, take, splitAndSpace)
                            addFades()
                        end
                        reaper.UpdateArrange()
                    end
                    reaper.Undo_EndBlock("Delete silences and space items.", -1)
                end

                reaper.ImGui_SameLine(ctx)

                if reaper.ImGui_Button(ctx, 'Split') then
                    cleanup()
                    reaper.Undo_BeginBlock()
                    if safeToExecute(selectedItems) then
                        local selectedItems = storeSelectedMediaItems()
                        for i, item in ipairs(selectedItems) do
                            local take = reaper.GetActiveTake(item)
                            selectOnlyThisItem(item)
                            cleanup()
                            splitAndSpace = false
                            splitMain(item, take, splitAndSpace)
                            addFades() 
                        end
                        reaper.UpdateArrange()
                    end
                    reaper.Undo_EndBlock("Delete silences.", -1)
                end

                reaper.ImGui_SameLine(ctx)
                
                shouldKeepOriginalChanged, shouldKeepOriginal = reaper.ImGui_Checkbox(ctx, "Keep original item(s) when rendering", shouldKeepOriginal)
                if shouldKeepOriginalChanged then
                    reaper.SetExtState("PeaksAndValleys", "shouldKeepOriginal", tostring(shouldKeepOriginal), true)
                end

                reaper.ImGui_End(ctx)
            end

            if open then
                reaper.defer(loop)
            end
        end

----------------------------------------------------------
-- Function: Color Palette 
----------------------------------------------------------
    -- Color Palette Data
        local item_colors = {
          {10,70,57}, {14,96,78},  {21,139,114}, {23,156,128},  {69,171,148},  {162,202,189}, {121,18,19}, {156,23,24},  {168,58,59},  {179,93,93},  {202,162,162}, {221,195,195},
          {10,43,70}, {15,64,104}, {23,96,156},  {102,143,182}, {171,186,207}, {225,230,237}, {88,114,47}, {125,162,67}, {159,206,85}, {184,239,99}, {205,244,152}, {226,248,200},
        }

    local function SetItemColors(r, g, b)
      local count = reaper.CountSelectedMediaItems(0)
      if count == 0 then return end

      reaper.Undo_BeginBlock()

      local native_color
      if r == 0 and g == 0 and b == 0 then
        native_color = 0 
      else
        native_color = reaper.ColorToNative(r, g, b) | 0x1000000
      end
      
      for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color)
      end
      
      reaper.UpdateArrange()
      reaper.Undo_EndBlock("Set Item Color", -1)
    end

----------------------------------------------------------
-- UI_Module 
----------------------------------------------------------
    function JKK_ItemTool_Draw(ctx, prev_count, current_count)
        -- 현재 선택된 아이템 개수 파악
            local selected_item_count = reaper.CountSelectedMediaItems(0)
            local disable_all = (selected_item_count == 0)
            local current_hash = GetSelectionHash()
            if current_hash ~= last_selection_hash then
                persistentClusters = {}
                last_selection_hash = current_hash
            end
        SyncSelectionData(ctx)
        if disable_all then
            reaper.ImGui_BeginDisabled(ctx, true)
        end
        local table_full      = reaper.ImGui_TableFlags_SizingFixedFit() | 
                                reaper.ImGui_TableFlags_BordersInnerV()
        if reaper.ImGui_BeginTable(ctx, "table_full", 3, table_full) then
            reaper.ImGui_TableSetupColumn(ctx, 'table_01', reaper.ImGui_TableColumnFlags_WidthFixed(), 805)
            reaper.ImGui_TableSetupColumn(ctx, 'table_02', reaper.ImGui_TableColumnFlags_WidthFixed(), 425)
            reaper.ImGui_TableSetupColumn(ctx, 'table_03', reaper.ImGui_TableColumnFlags_WidthFixed(), 460)
            reaper.ImGui_TableNextColumn(ctx)
            -- 1st Table: Items Batch Controller ===============================
                local table_01      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_01", 3, table_01) then
                    reaper.ImGui_TableSetupColumn(ctx, 'Items Batch Controller', reaper.ImGui_TableColumnFlags_WidthFixed(), 280)
                    reaper.ImGui_TableSetupColumn(ctx, 'Fade', reaper.ImGui_TableColumnFlags_WidthFixed(), 115)
                    reaper.ImGui_TableSetupColumn(ctx, 'Renamer', reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
                    reaper.ImGui_TableNextColumn(ctx)
                    -- Items Batch Controller ================================
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF)
                        reaper.ImGui_SeparatorText(ctx, 'Items Batch Controller')
                        reaper.ImGui_PopStyleColor(ctx)
                        -- Volume Slider
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Volume")
                            reaper.ImGui_SameLine(ctx)

                            reaper.ImGui_PushItemWidth(ctx, 200)
                            reaper.ImGui_SetCursorPosX(ctx, 494)
                            changed_vol, adjust_vol = reaper.ImGui_SliderDouble(ctx, "##Volume", adjust_vol, -30.00, 30.00, "%.2f")
                            if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_vol = 0.0; ApplyBatchVolume() end
                        -- Pan Slider
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Pan")
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_SetCursorPosX(ctx, 494)

                            local pan_display_val = math.abs(adjust_pan * 100)
                            local pan_format = "Center"
                            if adjust_pan < 0 then
                                pan_format = string.format("%.0fL", pan_display_val)
                            elseif adjust_pan > 0 then
                                pan_format = string.format("%.0fR", pan_display_val)
                            end
                            changed_pan, adjust_pan = reaper.ImGui_SliderDouble(ctx, "##Pan", adjust_pan, -1.00, 1.00, pan_format)
                            if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_pan = 0.0; ApplyBatchPan() end
                        -- Pitch Slider
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Pitch")
                            reaper.ImGui_SameLine(ctx)

                            reaper.ImGui_SetCursorPosX(ctx, 494)
                            changed_pitch, adjust_pitch = reaper.ImGui_SliderDouble(ctx, "##Pitch", adjust_pitch, -12, 12, "%.1f")
                            if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_pitch = 0.0; ApplyBatchPitch() end
                        -- Rate Slider
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Play Rate")
                            reaper.ImGui_SameLine(ctx)

                            reaper.ImGui_SetCursorPosX(ctx, 494)
                            changed_rate, adjust_rate = reaper.ImGui_SliderDouble(ctx, "##Playback Rate", adjust_rate, 0.25, 4.0, "%.2f", reaper.ImGui_SliderFlags_Logarithmic())
                            if reaper.ImGui_IsItemClicked(ctx, 1) then adjust_rate = 1.0; ApplyBatchRate() end
                        -- Group Stretch Ratio Slider
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Stretch")
                            reaper.ImGui_SameLine(ctx)

                            reaper.ImGui_SetCursorPosX(ctx, 494)
                            changed_group_stretch, adjust_ratio = reaper.ImGui_SliderDouble(ctx, "##Group Stretch", group_stretch_ratio, 0.25, 4.0, "%.2f", reaper.ImGui_SliderFlags_Logarithmic())
                            local is_group_stretch_slider_active = reaper.ImGui_IsItemActive(ctx)
                            if current_project_state_count ~= prev_count and not is_group_stretch_slider_active then
                                if group_stretch_ratio ~= 1.0 or prev_group_stretch_ratio ~= 1.0 then
                                    group_stretch_ratio = 1.0
                                    prev_group_stretch_ratio = 1.0
                                end
                            end
                            if reaper.ImGui_IsItemClicked(ctx, 1) then 
                                adjust_ratio = 1.0
                                group_stretch_ratio = 1.0
                                ApplyGroupStretch(group_stretch_ratio)
                                prev_group_stretch_ratio = 1.0
                                update_prev()
                            end
                        -- Call only the function corresponding to the changed slider
                            if changed_vol then ApplyBatchVolume() end
                            if changed_pan then ApplyBatchPan() end
                            if changed_pitch then ApplyBatchPitch() end
                            if changed_rate then ApplyBatchRate() end
                            if changed_group_stretch then
                                group_stretch_ratio = adjust_ratio
                                if group_stretch_ratio ~= prev_group_stretch_ratio then
                                    ApplyGroupStretch(group_stretch_ratio)
                                    prev_group_stretch_ratio = group_stretch_ratio
                                    update_prev()
                                end
                            end
                            reaper.ImGui_Spacing(ctx)
                        -- Properties Checkbox
                            reaper.ImGui_Text(ctx, "")
                            reaper.ImGui_SameLine(ctx)

                            -- Loop Checkbox
                            local changed_loop, new_loop = reaper.ImGui_Checkbox(ctx, "Loop", item_loop_src)
                            if changed_loop then
                                item_loop_src = new_loop
                                ApplyItemProperty("B_LOOPSRC", item_loop_src and 1.0 or 0.0)
                            end
                            reaper.ImGui_SameLine(ctx)

                            -- Mute Checkbox
                            local changed_mute, new_mute = reaper.ImGui_Checkbox(ctx, "Mute", item_mute)
                            if changed_mute then
                                item_mute = new_mute
                                ApplyItemProperty("B_MUTE", item_mute and 1.0 or 0.0)
                            end
                            reaper.ImGui_SameLine(ctx)

                            -- Lock Checkbox
                            local changed_lock, new_lock = reaper.ImGui_Checkbox(ctx, "Lock", item_lock)
                            if changed_lock then
                                item_lock = new_lock
                                ApplyItemProperty("C_LOCK", item_lock and 1.0 or 0.0)
                            end
                            reaper.ImGui_SameLine(ctx)

                            -- Normalize
                            if reaper.ImGui_Button(ctx, 'Normalize', 80, 22) then
                                if base_name ~= "" then
                                    reaper.Main_OnCommand(42460, 0)
                                end
                            end
                        reaper.ImGui_PopItemWidth(ctx)
                        reaper.ImGui_TableNextColumn(ctx)
                    -- Items Batch Crossfader & Take Button ==================
                        reaper.ImGui_SeparatorText(ctx, '')
                        -- Fade In
                            local changed_in, new_in_cur = DrawFadeWidget(ctx, "InArea", adj_fade_in_cur, 90, 31, true)
                            if changed_in then
                                adj_fade_in_cur = new_in_cur
                                ApplyBatchFadeIn(adj_fade_in_cur)
                            end
                        -- Fade Out
                            local changed_out, new_out_cur = DrawFadeWidget(ctx, "OutArea", adj_fade_out_cur, 90, 31, false)
                            if changed_out then
                                adj_fade_out_cur = new_out_cur
                                ApplyBatchFadeOut(adj_fade_out_cur)
                            end
                            reaper.ImGui_Spacing(ctx)
                        -- Reverse
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
                            if reaper.ImGui_Button(ctx, 'Reverse', 90, 22) then
                                if base_name ~= "" then
                                    reaper.Undo_BeginBlock()
                                    reaper.Main_OnCommand(41051, 0)
                                    reaper.Undo_EndBlock("Take Reverse", -1)
                                end
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                            reaper.ImGui_Spacing(ctx)
                        -- Take FX
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
                            if reaper.ImGui_Button(ctx, "Take FX", 90, 22) then
                                if reaper.CountSelectedMediaItems(0) > 0 then
                                    reaper.Main_OnCommand(40638, 0)
                                end
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                        -- Render Take
                            if reaper.ImGui_Button(ctx, "Render Take", 90, 22) then
                                if reaper.CountSelectedMediaItems(0) > 0 then
                                    reaper.Undo_BeginBlock()
                                    reaper.Main_OnCommand(41999, 0)
                                    reaper.Undo_EndBlock("Render to New Take", -1)
                                end
                            end
                        reaper.ImGui_TableNextColumn(ctx)
                    -- Items Batch Renamer ===================================
                        reaper.ImGui_SeparatorText(ctx, '')
                        local table_rename    = reaper.ImGui_TableFlags_SizingFixedFit()
                        if reaper.ImGui_BeginTable(ctx, "table rename", 3, table_rename) then
                            reaper.ImGui_TableSetupColumn(ctx, 'prev take', reaper.ImGui_TableColumnFlags_WidthFixed(), 25)
                            reaper.ImGui_TableSetupColumn(ctx, 'rename', reaper.ImGui_TableColumnFlags_WidthFixed(), 350)
                            reaper.ImGui_TableSetupColumn(ctx, 'next take', reaper.ImGui_TableColumnFlags_WidthFixed(), 25)
                            reaper.ImGui_TableNextColumn(ctx)
                            -- Items Take Renamer =================================
                                if reaper.ImGui_Button(ctx, '<', 20, 49) then
                                    reaper.Undo_BeginBlock()
                                    reaper.Main_OnCommand(42350, 0)
                                    reaper.Undo_EndBlock("Prev Take", -1)
                                end
                                reaper.ImGui_TableNextColumn(ctx)
                                changed, base_name = reaper.ImGui_InputTextMultiline(ctx, '##BaseName', base_name, 282, 22)
                                reaper.ImGui_SameLine(ctx)
                                if reaper.ImGui_Button(ctx, "Clear##ClearBaseName", 55, 22) then
                                    base_name = ""
                                end
                                if reaper.ImGui_Button(ctx, 'Edit Take Name', 137, 22) then
                                    if base_name ~= "" then
                                        RenameSelectedTakes()
                                    end
                                end
                                reaper.ImGui_SameLine(ctx)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
                                if reaper.ImGui_Button(ctx, 'Create Regions', 137, 22) then
                                    if base_name ~= "" then
                                        CreateRegionsFromSelectedItems()
                                    end
                                end
                                reaper.ImGui_PopStyleColor(ctx, 3)
                                reaper.ImGui_SameLine(ctx)
                                local chk_changed, chk_val = reaper.ImGui_Checkbox(ctx, "_nn", is_sequential_name)
                                if chk_changed then
                                    is_sequential_name = chk_val
                                end
                                reaper.ImGui_TableNextColumn(ctx)
                                if reaper.ImGui_Button(ctx, '>', 20, 49) then
                                    reaper.Undo_BeginBlock()
                                    reaper.Main_OnCommand(42349, 0)
                                    reaper.Undo_EndBlock("Next Take", -1)
                                end
                            reaper.ImGui_EndTable(ctx)
                        end
                        reaper.ImGui_Spacing(ctx)
                        reaper.ImGui_Spacing(ctx)
                        reaper.ImGui_Separator(ctx)
                        reaper.ImGui_Spacing(ctx)
                        reaper.ImGui_Spacing(ctx)
                    -- Item Chennel & Pitch Mode & Properties ================
                        local table_cp    = reaper.ImGui_TableFlags_SizingFixedFit()
                        if reaper.ImGui_BeginTable(ctx, "channel & properties", 2, table_full) then
                            reaper.ImGui_TableSetupColumn(ctx, 'Channel', reaper.ImGui_TableColumnFlags_WidthFixed(), 250)
                            reaper.ImGui_TableSetupColumn(ctx, 'Properties', reaper.ImGui_TableColumnFlags_WidthFixed(), 200)
                            reaper.ImGui_TableNextColumn(ctx)
                            -- Items Channel & Pitch =================================
                                reaper.ImGui_AlignTextToFramePadding(ctx)
                                reaper.ImGui_Text(ctx, "Channel")
                                reaper.ImGui_SameLine(ctx)
                                reaper.ImGui_SetCursorPosX(ctx, 477 + 413)
                                DrawChannelModeCombo(ctx, 165)

                                reaper.ImGui_AlignTextToFramePadding(ctx)
                                reaper.ImGui_Text(ctx, "Pitch Mode")
                                reaper.ImGui_SameLine(ctx)
                                DrawPitchModeCombo(ctx, 165, 240)
                            reaper.ImGui_TableNextColumn(ctx)
                            -- Items Info ============================================
                                if item_info_str1 ~= "" then
                                    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) - 7)
                                    reaper.ImGui_Text(ctx, item_info_str1)
                                end
                                if item_info_str2 ~= "" then
                                    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) - 3)
                                    reaper.ImGui_Text(ctx, item_info_str2)
                                end
                                if item_info_str3 ~= "" then
                                    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) - 3)
                                    reaper.ImGui_Text(ctx, item_info_str3)
                                end
                                reaper.ImGui_Text(ctx, "    ")
                                reaper.ImGui_SameLine(ctx)
                                if reaper.ImGui_Button(ctx, 'Properties..', 108, 22) then
                                    if base_name ~= "" then
                                        reaper.Main_OnCommand(40011, 0)
                                    end
                                end
                                reaper.ImGui_Dummy(ctx, 0, 0)
                            reaper.ImGui_EndTable(ctx)
                        end
                    reaper.ImGui_Dummy(ctx, 0, 0)
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_TableNextColumn(ctx)
            -- 2nd Table: Items Arranger & Randomizer ==========================
                reaper.ImGui_Text(ctx, " ")
                reaper.ImGui_SameLine(ctx)
                local table_02      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_02", 1, table_01) then
                    reaper.ImGui_TableSetupColumn(ctx, 'Items Arranger & Randomizer', reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
                    reaper.ImGui_TableNextColumn(ctx)
                    -- Items Arranger & Randomizer ============================
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF)
                        reaper.ImGui_SeparatorText(ctx, 'Items Arranger & Randomizer')
                        reaper.ImGui_PopStyleColor(ctx)
                        local changed
                        -- Width
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Interval Width")
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_SetNextItemWidth(ctx, 126)
                            reaper.ImGui_SetCursorPosX(ctx, 930 + 413)

                            -- 현재 모드에 따른 포맷과 값 범위 설정
                            local format_str, cur_max, cur_min = "", 0, 0

                            if spacing_mode == 0 then
                                format_str = string.format("%.0f grid", width)
                                cur_min, cur_max = 0.0, max_grid
                            elseif spacing_mode == 1 then
                                format_str = string.format("%.2fs", width)
                                cur_min, cur_max = 0.0, max_sec
                            elseif spacing_mode == 2 then
                                format_str = string.format("%.1f RPM", width)
                                cur_min, cur_max = min_rpm, max_rpm
                            end

                            -- 슬라이더 그리기
                            local changed, new_val = reaper.ImGui_SliderDouble(ctx, "##Width", width, cur_min, cur_max, format_str)

                            if changed then 
                                if spacing_mode == 0 then
                                    width = math.floor(new_val + 0.5)
                                else
                                    width = new_val
                                end
                                apply_spacing_only()
                            end

                            -- 우클릭 시 3가지 모드 순환 (0 -> 1 -> 2 -> 0)
                            if reaper.ImGui_IsItemClicked(ctx, 1) then
                                spacing_mode = (spacing_mode + 1) % 3
                                if spacing_mode == 0 then width = 2.0
                                elseif spacing_mode == 1 then width = 1.5
                                elseif spacing_mode == 2 then width = 120.0
                                end
                            end

                            -- 툴팁 업데이트
                            if reaper.ImGui_IsItemHovered(ctx) then
                                local mode_names = {"Grid", "Seconds", "RPM"}
                                reaper.ImGui_SetTooltip(ctx, "Current: " .. mode_names[spacing_mode + 1] .. "\nRight-click to toggle (Grid -> Sec -> RPM)")
                            end

                            reaper.ImGui_SameLine(ctx)
                            _, use_edit_cursor = reaper.ImGui_Checkbox(ctx, 'Cursor', use_edit_cursor)
                            reaper.ImGui_SameLine(ctx)
                            local changed_chk, new_chk = reaper.ImGui_Checkbox(ctx, "Group", use_clustering)
                            if changed_chk then
                                use_clustering = new_chk
                                persistentClusters = {} 
                            end
                            if reaper.ImGui_IsItemHovered(ctx) then
                                reaper.ImGui_SetTooltip(ctx, "Checked: Move overlapping items as one group\nUnchecked: Move every item individually")
                            end
                            reaper.ImGui_Spacing(ctx)
                        -- Position Range
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Pos Range")
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_PushItemWidth(ctx, 200)
                            reaper.ImGui_SetCursorPosX(ctx, 930 + 413)
                            changed, pos_range = reaper.ImGui_SliderDouble(ctx, '##Pos Range', pos_range, 0, 1.0, '%.3f')
                            if reaper.ImGui_IsItemClicked(ctx, 1) then pos_range = 0.0 end
                            reaper.ImGui_SameLine(ctx)
                            changed, random_pos = reaper.ImGui_Checkbox(ctx, 'Rand##pos', random_pos)
                        -- Pitch Range
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Pitch Range")
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_PushItemWidth(ctx, 200)
                            reaper.ImGui_SetCursorPosX(ctx, 930 + 413)
                            changed, pitch_range = reaper.ImGui_SliderDouble(ctx, '##Pitch Range', pitch_range, 0, 24, '%.3f')
                            if reaper.ImGui_IsItemClicked(ctx, 1) then pitch_range = 0.0 end
                            reaper.ImGui_SameLine(ctx)
                            changed, random_pitch = reaper.ImGui_Checkbox(ctx, 'Rand##pitch', random_pitch)
                        -- Playback Rate Range
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Playrate Range")
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_PushItemWidth(ctx, 200)
                            reaper.ImGui_SetCursorPosX(ctx, 930 + 413)
                            changed, playback_range = reaper.ImGui_SliderDouble(ctx, '##Playrate Range', playback_range, 0, 24, '%.3f')
                            if reaper.ImGui_IsItemClicked(ctx, 1) then playback_range = 0.0 end
                            reaper.ImGui_SameLine(ctx)
                            changed, random_play = reaper.ImGui_Checkbox(ctx, 'Rand##playback', random_play)
                        -- Volume Range
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            reaper.ImGui_Text(ctx, "  Vol Range")
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_PushItemWidth(ctx, 200)
                            reaper.ImGui_SetCursorPosX(ctx, 930 + 413)
                            changed, vol_range = reaper.ImGui_SliderDouble(ctx, '##Vol Range', vol_range, 0, 10, '%.02f')
                            if reaper.ImGui_IsItemClicked(ctx, 1) then vol_range = 0.0 end
                            reaper.ImGui_SameLine(ctx)
                            changed, random_vol = reaper.ImGui_Checkbox(ctx, 'Rand##vol', random_vol)
                            reaper.ImGui_Spacing(ctx)                         
                        -- Btn Apply
                            reaper.ImGui_Text(ctx, "")
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
                            if reaper.ImGui_Button(ctx, "Apply", 100, 22) then
                                arrange_items()
                                update_prev()
                                SaveSettings()
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                            reaper.ImGui_SameLine(ctx)
                        -- Random Order
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
                            if reaper.ImGui_Button(ctx, "Shuffle Order", 100, 22) then
                                shuffle_item_order()
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                            reaper.ImGui_SameLine(ctx)
                        -- Live Update
                            changed, live_update = reaper.ImGui_Checkbox(ctx, 'Live Update', live_update)
                        reaper.ImGui_TableNextColumn(ctx)
                    reaper.ImGui_Dummy(ctx, 0, 0)
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_TableNextColumn(ctx)
            -- 3rd Table: Items Spliter & Color ================================
                reaper.ImGui_Text(ctx, " ")
                reaper.ImGui_SameLine(ctx)
                local table_03      = reaper.ImGui_TableFlags_SizingFixedFit()
                if reaper.ImGui_BeginTable(ctx, "table_03", 1, table_01) then
                    reaper.ImGui_TableSetupColumn(ctx, 'Items Spliter & Color', reaper.ImGui_TableColumnFlags_WidthFixed(), 430)
                    reaper.ImGui_TableNextColumn(ctx)
                -- Items Spliter ================================================
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF)
                    reaper.ImGui_SeparatorText(ctx, 'Item Spliter')
                    reaper.ImGui_PopStyleColor(ctx)
                    -- Threshold 
                        reaper.ImGui_AlignTextToFramePadding(ctx)
                        reaper.ImGui_Text(ctx, "  Threshold")
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        reaper.ImGui_SetCursorPosX(ctx, 1330 + 413)
                        local thres_changed, new_thres = reaper.ImGui_SliderDouble(ctx, '##Threshold', silenceThreshold, 0.001, 0.3, "%.3f")
                        if thres_changed then silenceThreshold = new_thres end
                        if reaper.ImGui_IsItemClicked(ctx, 1) then 
                            silenceThreshold = 0.01
                            thres_changed = true 
                        end
                        reaper.ImGui_SameLine(ctx)
                    -- Split
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
                        if reaper.ImGui_Button(ctx, 'Split', 100, 22) then
                            cleanup()
                            reaper.Undo_BeginBlock()
                            if safeToExecute(selectedItems) then
                                local selectedItems = storeSelectedMediaItems()
                                for i, item in ipairs(selectedItems) do
                                    local take = reaper.GetActiveTake(item)
                                    selectOnlyThisItem(item)
                                    cleanup()
                                    splitAndSpace = false
                                    splitMain(item, take, splitAndSpace)
                                    addFades() 
                                end
                                reaper.UpdateArrange()
                            end
                            reaper.Undo_EndBlock("Split", -1)
                        end
                        reaper.ImGui_PopStyleColor(ctx, 3)
                    -- Min Duration
                        reaper.ImGui_AlignTextToFramePadding(ctx)
                        reaper.ImGui_Text(ctx, "  Min Length")
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 200)
                        reaper.ImGui_SetCursorPosX(ctx, 1330 + 413)
                        local dur_changed, new_dur = reaper.ImGui_SliderDouble(ctx, '##Min Duration', minSilenceDuration, 0.001, 2.0, "%.3f")
                        if dur_changed then minSilenceDuration = new_dur end
                        if reaper.ImGui_IsItemClicked(ctx, 1) then 
                            minSilenceDuration = 0.2
                            dur_changed = true
                        end                         
                        reaper.ImGui_SameLine(ctx)
                    -- Split & Takes
                        if reaper.ImGui_Button(ctx, 'Split & Takes', 100, 22) then
                            cleanup()
                            reaper.Undo_BeginBlock()
                            if safeToExecute(selectedItems) then
                                local userMarkerChoice = nil
                                if shouldAlignToMarker then
                                    userMarkerChoice = promptUserForNumber("Align with marker", "Please enter the Marker ID")
                                end
                                local selectedItems = storeSelectedMediaItems()
                                for i, item in ipairs(selectedItems) do
                                    selectOnlyThisItem(item)
                                    local take = reaper.GetActiveTake(item)
                                    local track = reaper.GetMediaItem_Track(item)
                                    local onPeak = false
                                    local alignOnStart = true
                                    local silencesInLoop = getSilenceTime(item, take) 
                                    implodeMain(item, take, onPeak, alignOnStart, silencesInLoop)
                                end
                                reaper.UpdateArrange()
                            end
                            reaper.Undo_EndBlock("Split & Takes", -1)
                        end
                    -- 실시간 분석 및 가이드 박스 업데이트 로직
                        local currentSignature = GetSelectionHash()
                        if showGuideBox and (thres_changed or dur_changed or guide_changed or currentSignature ~= lastSelectionSignature) then
                            cleanup()
                            local items = storeSelectedMediaItems()
                            for _, item in ipairs(items) do
                                local take = reaper.GetActiveTake(item)
                                local track = reaper.GetMediaItem_Track(item)
                                local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                                local silences = getSilenceTime(item, take)
                                if silences then
                                    createTemporaryItems(track, silences, itemPos)
                                end
                            end
                            lastSelectionSignature = currentSignature
                        end
                    -- Keep Original
                        reaper.ImGui_Text(ctx, "")
                        reaper.ImGui_SameLine(ctx)
                        shouldKeepOriginalChanged, shouldKeepOriginal = reaper.ImGui_Checkbox(ctx, "Keep Origin When Rendering", shouldKeepOriginal)
                        if shouldKeepOriginalChanged then
                            reaper.SetExtState("PeaksAndValleys", "shouldKeepOriginal", tostring(shouldKeepOriginal), true)
                        end
                        reaper.ImGui_SameLine(ctx)
                    -- Guide
                        local guide_changed, new_guide = reaper.ImGui_Checkbox(ctx, "Guide", showGuideBox)
                        if guide_changed then 
                            showGuideBox = new_guide 
                            if not showGuideBox then clearTemporaryItems() end
                        end
                -- Item Color Palette =====================================
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF)
                    reaper.ImGui_SeparatorText(ctx, 'Item Color Palette')
                    reaper.ImGui_PopStyleColor(ctx)
                    local table_03      = reaper.ImGui_TableFlags_SizingFixedFit()
                    if reaper.ImGui_BeginTable(ctx, "table_color", 2, table_01) then
                        reaper.ImGui_TableSetupColumn(ctx, 'colors', reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
                        reaper.ImGui_TableSetupColumn(ctx, 'default', reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
                        reaper.ImGui_TableNextColumn(ctx)
                            local palette_columns = 12                        
                            for i, col in ipairs(item_colors) do
                                local r, g, b = col[1], col[2], col[3]                          
                                local packed_col = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, 1.0)
                              
                                reaper.ImGui_PushID(ctx, "col"..i)                          
                                if reaper.ImGui_ColorButton(ctx, "##Color", packed_col, 0, 25, 25) then
                                  SetItemColors(r, g, b)
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
                                SetItemColors(0, 0, 0)
                            end
                            reaper.ImGui_PopID(ctx)
                        reaper.ImGui_TableNextColumn(ctx)
                        reaper.ImGui_EndTable(ctx)
                    end 
                    reaper.ImGui_Dummy(ctx, 0, 0)
                    reaper.ImGui_EndTable(ctx)
                end
            reaper.ImGui_EndTable(ctx)
        end
        if disable_all then
            reaper.ImGui_EndDisabled(ctx)
        end

        local general_state_changed = has_changed()
        
        if general_state_changed then
            if has_range_value_changed() and live_update then
                arrange_items()
            end
            update_prev()
            SaveSettings()
        end
    end

return {
    JKK_ItemTool_Draw = JKK_ItemTool_Draw,
}
