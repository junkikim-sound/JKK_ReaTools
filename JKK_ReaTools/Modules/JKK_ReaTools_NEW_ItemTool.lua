--========================================================
-- @title JKK_ReaTools_NEW_ItemTool
-- @author Junki Kim
-- @noindex
--========================================================

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
        end
        function ApplyBatchPan()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local take = reaper.GetActiveTake(item)
                if take then
                    reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", adjust_pan)
                end
            end

            reaper.UpdateArrange()
        end
        function ApplyBatchPitch()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(item), "D_PITCH", adjust_pitch)
            end
            
            reaper.UpdateArrange()
        end
        function ApplyBatchRate()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

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
        end
        function ApplyGroupStretch(stretch_ratio)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt < 2 then 
              return 
            end

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
        end
    -- Properties Variables
        local item_loop_src = false
        local item_mute = false
        local item_lock = false
        function ApplyItemProperty(key, val)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemInfo_Value(item, key, val)
            end
            reaper.UpdateArrange()
        end
    -- Fader
        local drag_start_cur = 0.0
        local adj_fade_in_cur = 0.0
        local adj_fade_out_cur = 0.0
        function ApplyBatchFadeIn(cur)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemInfo_Value(item, "D_FADEINDIR", -cur)
            end
            reaper.UpdateArrange()
        end
        function ApplyBatchFadeOut(cur)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", cur)
            end
            
            reaper.UpdateArrange()
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

            -- REAPER I_PITCHMODE encoding:
            -- high 16 bits = pitch shifter algorithm (main mode)
            -- low 16 bits  = algorithm parameter (sub mode)
            local final_val = -1

            if main_mode ~= -1 then
                final_val = (math.floor(main_mode) << 16) | (math.floor(sub_mode) & 0xFFFF)
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
                            -- REAPER stores the shifter in the high word and
                            -- its parameter/sub-mode in the low word.
                            take_pitch_mode = (raw_pitch >> 16) & 0xFFFF
                            take_pitch_sub_mode = raw_pitch & 0xFFFF
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
        function DrawPitchModeCombo(ctx, width1, width2, stacked_sub, stacked_x)
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
            if width2 then
                if stacked_sub then
                    reaper.ImGui_SetCursorPosX(ctx, stacked_x or 0)
                else
                    reaper.ImGui_SameLine(ctx)
                end
            end
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
            local use_gap_mode = false -- use_edit_cursor 대체
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
            local prev_use_gap_mode = use_gap_mode
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
                use_gap_mode  ~= prev_use_gap_mode or
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
            prev_use_gap_mode   = use_gap_mode
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
            use_gap_mode = LoadFlag("JKK_ItemTool", "use_gap_mode", false)
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
            reaper.SetExtState("JKK_ItemTool", "use_gap_mode", use_gap_mode and "1" or "0", true)
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

        -- Validate the complete cached cluster membership against the CURRENT
        -- REAPER selection. Checking only the first cached pointer is unsafe:
        -- an old cluster can remain valid even after the user selects other items.
        local function IsPersistentClustersValidForSelection(selected_items)
            if #selected_items == 0 or #persistentClusters == 0 then return false end

            local selected_set = {}
            for _, data in ipairs(selected_items) do
                if not data.item or not reaper.ValidatePtr(data.item, "MediaItem*") then
                    return false
                end
                selected_set[data.item] = true
            end

            local cached_set = {}
            local cached_count = 0
            for _, cluster in ipairs(persistentClusters) do
                if type(cluster.items_data) ~= "table" then return false end
                for _, item_data in ipairs(cluster.items_data) do
                    local item = item_data.item
                    if not item
                        or not reaper.ValidatePtr(item, "MediaItem*")
                        or not selected_set[item]
                        or cached_set[item] then
                        return false
                    end
                    cached_set[item] = true
                    cached_count = cached_count + 1
                end
            end

            if cached_count ~= #selected_items then return false end
            for _, data in ipairs(selected_items) do
                if not cached_set[data.item] then return false end
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
            -- Always take a fresh snapshot before applying Width. The module is
            -- now drawn in a separate panel, so selection synchronization must
            -- not depend on the old unified controller draw order.
            local selected_items = CollectAndSortSelectedItems()
            if #selected_items == 0 then
                persistentClusters = {}
                return
            end

            local start_pos = reaper.GetCursorPosition() -- 에디트 커서 고정
            local _, grid_size = reaper.GetSetProjectGrid(0, false)
            local spacing = CalculateSpacingAmount(width)

            if not IsPersistentClustersValidForSelection(selected_items) then
                if use_clustering then
                    persistentClusters = BuildClusters(selected_items)
                else
                    persistentClusters = {}
                    for _, data in ipairs(selected_items) do
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

            reaper.PreventUIRefresh(1)

            local track_counters = {}
            local track_start_pos = {}
            local track_last_end_pos = {}

            for i, cluster in ipairs(clusters) do
                local cluster_base_pos = start_pos
                
                local track_key = "global"
                if not use_clustering then
                    track_key = reaper.GetMediaItem_Track(cluster.items_data[1].item)
                end
                
                if not track_counters[track_key] then
                    track_counters[track_key] = 1
                    track_start_pos[track_key] = start_pos
                    cluster_base_pos = start_pos
                else
                    track_counters[track_key] = track_counters[track_key] + 1
                    if use_gap_mode then
                        -- Gap 모드: 이전 아이템의 꼬리부터 간격 시작
                        cluster_base_pos = track_last_end_pos[track_key] + spacing
                    else
                        -- 기본 모드: 일정한 Start-to-Start 간격
                        cluster_base_pos = track_start_pos[track_key] + spacing * (track_counters[track_key] - 1)
                    end
                end
                
                -- Gap 모드일 때는 저장된 오프셋 무시 (랜덤 방지)
                if not use_gap_mode and stored_offsets[i] ~= nil then
                    cluster_base_pos = cluster_base_pos + stored_offsets[i]
                end
                
                local max_cluster_end = cluster_base_pos
                for _, item_data in ipairs(cluster.items_data) do
                    local item = item_data.item
                    if reaper.ValidatePtr(item, "MediaItem*") then
                        local new_pos = cluster_base_pos + item_data.rel_pos
                        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
                        
                        -- 배치 후 꼬리 길이 계산
                        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        if new_pos + len > max_cluster_end then
                            max_cluster_end = new_pos + len
                        end
                    end
                end
                -- 다음 배치를 위해 가장 긴 꼬리 위치 저장
                track_last_end_pos[track_key] = max_cluster_end
            end

            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
            current_play_slot = 0
        end
    -- Arrange Items Logic (Randomization/Arrangement)
        function arrange_items()
            local sorted_items = CollectAndSortSelectedItems()
            if #sorted_items == 0 then
                persistentClusters = {}
                return
            end

            local start_pos = reaper.GetCursorPosition() -- 에디트 커서 고정
            local spacing = CalculateSpacingAmount(width)

            reaper.PreventUIRefresh(1)

            if not IsPersistentClustersValidForSelection(sorted_items) then
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

            local track_counters = {}
            local track_start_pos = {}
            local track_last_end_pos = {}

            for i, cluster in ipairs(clusters) do
                local cluster_base_pos = start_pos
                
                local track_key = "global"
                if not use_clustering then
                    track_key = reaper.GetMediaItem_Track(cluster.items_data[1].item)
                end
                
                if not track_counters[track_key] then
                    track_counters[track_key] = 1
                    track_start_pos[track_key] = start_pos
                    cluster_base_pos = start_pos
                else
                    track_counters[track_key] = track_counters[track_key] + 1
                    if use_gap_mode then
                        cluster_base_pos = track_last_end_pos[track_key] + spacing
                    else
                        cluster_base_pos = track_start_pos[track_key] + spacing * (track_counters[track_key] - 1)
                    end
                end

                local max_cluster_end = cluster_base_pos
                for j, item_data in ipairs(cluster.items_data) do
                    local item = item_data.item
                    if reaper.ValidatePtr(item, "MediaItem*") then
                        local take = reaper.GetActiveTake(item)
                        local item_key = i .. "_" .. j 

                        local rnd_pitch_val = random_pitch and ((math.random() * pitch_range * 2) - pitch_range) or (stored_pitch[item_key] or 0)
                        local rnd_play_rate = random_play and (2 ^ (((math.random() * playback_range * 2) - playback_range) / 12)) or (stored_playrates[item_key] or 1.0)
                        
                        -- Gap 모드일 경우 겹침 방지를 위해 랜덤 위치 오프셋 무시
                        local rnd_pos_offset = 0
                        if use_gap_mode then
                            rnd_pos_offset = 0
                            stored_offsets[item_key] = 0
                        else
                            rnd_pos_offset = random_pos and ((math.random() * pos_range * 2) - pos_range) or (stored_offsets[item_key] or 0)
                        end
                        
                        local rnd_vol_val = stored_vols[item_key] or 1.0
                        if random_vol then
                            if vol_range > 0 then
                                local rnd_db = (math.random() * 2.0 - 1.0) * vol_range
                                rnd_vol_val = 10 ^ (rnd_db / 20)
                            else
                                rnd_vol_val = 1.0
                            end
                        end

                        stored_vols[item_key] = rnd_vol_val
                        stored_pitch[item_key] = rnd_pitch_val
                        stored_playrates[item_key] = rnd_play_rate
                        if not use_gap_mode then stored_offsets[item_key] = rnd_pos_offset end

                        local new_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        if take then
                            reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", rnd_pitch_val)
                            reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", rnd_vol_val)
                            
                            local current_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                            local current_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                            local source_len = current_length * current_rate
                            new_len = source_len / rnd_play_rate
                            
                            reaper.SetMediaItemLength(item, new_len, true)
                            reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rnd_play_rate)
                        end

                        local final_cluster_pos = cluster_base_pos + rnd_pos_offset
                        local scaled_rel_pos = item_data.rel_pos / rnd_play_rate
                        local new_item_pos = final_cluster_pos + scaled_rel_pos
                        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_item_pos)

                        if new_item_pos + new_len > max_cluster_end then
                            max_cluster_end = new_item_pos + new_len
                        end
                    end
                end
                track_last_end_pos[track_key] = max_cluster_end
            end

            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
            current_play_slot = 0
        end
    function shuffle_item_order()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            -- 1. 현재 배치 상태를 기준으로 클러스터 빌드 (슬롯 생성)
            local sorted_items = CollectAndSortSelectedItems()
            local clusters
            
            if use_clustering then
                clusters = BuildClusters(sorted_items)
            else
                clusters = {}
                for _, data in ipairs(sorted_items) do
                    table.insert(clusters, {
                        items = {data.item},
                        start_pos = data.pos,
                        end_pos = data.end_pos,
                        items_data = {{item = data.item, rel_pos = 0}}
                    })
                end
            end

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

            -- 5. 변경된 클러스터 구조 저장 (기존 볼륨/피치 상태 유지)
            persistentClusters = clusters

            -- arrange_items() 대신 위치(간격)만 재배열하는 함수 호출
            apply_spacing_only()
        end

----------------------------------------------------------
-- Item Splitter
----------------------------------------------------------
    -- Default Value
        local silenceThreshold = 0.01
        local minSilenceDuration = 0.2
        local showGuideBox = false
        local keep_original_state = reaper.GetExtState("PeaksAndValleys", "shouldKeepOriginal")
        local shouldKeepOriginal = (keep_original_state == "" or keep_original_state == "true")
        local grid_slice_n = 5
        local splitAndSpace = false
        local shouldAlignToMarker = false

        local lastSelectionSignature = ""
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
    -- The legacy standalone Peaks & Valleys window has been folded into the
    -- unified Item Splitter UI below. Its detached ImGui context/loop is removed.
    -- Grid Splitter
        local function GridSplitMain(n_val)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            local _, grid_sec = reaper.GetSetProjectGrid(0, false)
            if grid_sec <= 0 then return end

            -- 입력값의 2배 그리드 간격 적용
            local slice_interval = grid_sec * (n_val * 2)

            for i = cnt - 1, 0, -1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local item_end = item_start + item_len

                local split_pos = item_start + slice_interval

                while split_pos < item_end - 0.0001 do
                    local new_item = reaper.SplitMediaItem(item, split_pos)
                    if new_item then
                        item = new_item
                    end
                    split_pos = split_pos + slice_interval
                end
            end

            reaper.UpdateArrange()
        end

----------------------------------------------------------
-- UI_Module: Unified Item / Track Workspace
----------------------------------------------------------
local function GetAvailableWidth(ctx)
    local width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    return math.max(60, width or 60)
end

local function PushJKKButtonStyle(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
end

local function PopJKKButtonStyle(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
end

local function DrawItemBatchController(ctx, selected_item_count, prev_count, current_count)
    -- Keep the previous controller visible when the selection is empty. The
    -- parent panel wraps this draw call in ImGui_BeginDisabled/EndDisabled.
    -- A fixed label column keeps every slider aligned to the Play Rate row.
    local label_width = 86
    local row_width = GetAvailableWidth(ctx)
    local slider_width = math.max(70, row_width - label_width)
    local function BeginLabeledRow(label)
        local row_x = reaper.ImGui_GetCursorPosX(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, label)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, row_x + label_width)
        reaper.ImGui_SetNextItemWidth(ctx, slider_width)
    end

    -- Volume
    BeginLabeledRow("Volume")
    local changed_vol, new_vol = reaper.ImGui_SliderDouble(ctx, "##ItemVolume", adjust_vol, -30.0, 30.0, "%.2f dB")
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_vol then
        adjust_vol = new_vol
        ApplyBatchVolume()
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Batch Take Volume Applied", -1)
    end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_vol = 0.0
        ApplyBatchVolume()
        reaper.Undo_EndBlock("Reset Volume", -1)
    end

    -- Pan
    BeginLabeledRow("Pan")
    local pan_display_val = math.abs(adjust_pan * 100)
    local pan_format = "Center"
    if adjust_pan < 0 then
        pan_format = string.format("%.0fL", pan_display_val)
    elseif adjust_pan > 0 then
        pan_format = string.format("%.0fR", pan_display_val)
    end
    local changed_pan, new_pan = reaper.ImGui_SliderDouble(ctx, "##ItemPan", adjust_pan, -1.0, 1.0, pan_format)
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_pan then
        adjust_pan = new_pan
        ApplyBatchPan()
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Batch Pan Applied", -1)
    end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_pan = 0.0
        ApplyBatchPan()
        reaper.Undo_EndBlock("Reset Pan", -1)
    end

    -- Pitch
    BeginLabeledRow("Pitch")
    local changed_pitch, new_pitch = reaper.ImGui_SliderDouble(ctx, "##ItemPitch", adjust_pitch, -12.0, 12.0, "%.1f st")
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_pitch then
        adjust_pitch = new_pitch
        ApplyBatchPitch()
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Batch Pitch Applied", -1)
    end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_pitch = 0.0
        ApplyBatchPitch()
        reaper.Undo_EndBlock("Reset Pitch", -1)
    end

    -- Playback Rate
    BeginLabeledRow("Play Rate")
    local changed_rate, new_rate = reaper.ImGui_SliderDouble(
        ctx, "##ItemPlaybackRate", adjust_rate, 0.25, 4.0, "%.2f",
        reaper.ImGui_SliderFlags_Logarithmic()
    )
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_rate then
        adjust_rate = new_rate
        ApplyBatchRate()
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Batch Playback Rate Applied", -1)
    end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_rate = 1.0
        ApplyBatchRate()
        reaper.Undo_EndBlock("Reset Playback Rate", -1)
    end

    -- Group Stretch
    BeginLabeledRow("Stretch")
    local changed_group_stretch, new_group_stretch = reaper.ImGui_SliderDouble(
        ctx, "##ItemGroupStretch", group_stretch_ratio, 0.25, 4.0, "%.2f",
        reaper.ImGui_SliderFlags_Logarithmic()
    )
    local group_stretch_active = reaper.ImGui_IsItemActive(ctx)
    if current_count ~= prev_count and not group_stretch_active then
        if group_stretch_ratio ~= 1.0 or prev_group_stretch_ratio ~= 1.0 then
            group_stretch_ratio = 1.0
            prev_group_stretch_ratio = 1.0
        end
    end
    if reaper.ImGui_IsItemActivated(ctx) then reaper.Undo_BeginBlock() end
    if changed_group_stretch then
        group_stretch_ratio = new_group_stretch
        if group_stretch_ratio ~= prev_group_stretch_ratio then
            ApplyGroupStretch(group_stretch_ratio)
            prev_group_stretch_ratio = group_stretch_ratio
            update_prev()
        end
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Group Time Stretch Applied", -1)
    end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        group_stretch_ratio = 1.0
        ApplyGroupStretch(group_stretch_ratio)
        prev_group_stretch_ratio = 1.0
        update_prev()
        reaper.Undo_EndBlock("Reset Group Stretch", -1)
    end

    -- Compute the primary action width once. Normalize uses the same width and
    -- right edge as Render Take so the controller rows form a clean boundary.
    local available_width = GetAvailableWidth(ctx)
    local action_gap = 6
    local nav_button_width = math.max(28,
        math.min(48, (available_width - (2 * 84) - (action_gap * 4)) / 3))
    local primary_button_width = math.max(68,
        math.min(116, (available_width - (nav_button_width * 3) - (action_gap * 4)) / 2))

    -- Properties and Normalize share one line directly below the sliders.
    -- Set vertical ItemSpacing to zero for this row so it touches the final
    -- slider; the horizontal spacing remains unchanged.
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 0)
    local checkbox_row_x = reaper.ImGui_GetCursorPosX(ctx)
    local changed_loop, new_loop = reaper.ImGui_Checkbox(ctx, "Loop", item_loop_src)
    if changed_loop then
        item_loop_src = new_loop
        ApplyItemProperty("B_LOOPSRC", item_loop_src and 1.0 or 0.0)
    end
    reaper.ImGui_SameLine(ctx)
    local changed_mute, new_mute = reaper.ImGui_Checkbox(ctx, "Mute", item_mute)
    if changed_mute then
        item_mute = new_mute
        ApplyItemProperty("B_MUTE", item_mute and 1.0 or 0.0)
    end
    reaper.ImGui_SameLine(ctx)
    local changed_lock, new_lock = reaper.ImGui_Checkbox(ctx, "Lock", item_lock)
    if changed_lock then
        item_lock = new_lock
        ApplyItemProperty("C_LOCK", item_lock and 1.0 or 0.0)
    end
    reaper.ImGui_SameLine(ctx, 0, action_gap)
    reaper.ImGui_SetCursorPosX(ctx, checkbox_row_x + math.max(0, available_width - primary_button_width))
    if reaper.ImGui_Button(ctx, "Normalize", primary_button_width, 22) then
        reaper.Main_OnCommand(42460, 0)
    end
    reaper.ImGui_PopStyleVar(ctx, 1)

    -- Pin the Reverse / take-navigation / FX / Render Take row to the bottom
    -- of the controller panel. The panel table is full-height in the main UI.
    local footer_cursor_y = reaper.ImGui_GetCursorPosY(ctx)
    local _, footer_available_y = reaper.ImGui_GetContentRegionAvail(ctx)
    local take_action_height = 22
    reaper.ImGui_SetCursorPosY(
        ctx, footer_cursor_y + math.max(0, footer_available_y - take_action_height)
    )

    local selected_item = reaper.GetSelectedMediaItem(0, 0)
    local has_multiple_takes = selected_item and reaper.CountTakes(selected_item) > 1 or false
    local selected_take = selected_item and reaper.GetActiveTake(selected_item) or nil
    local has_take_fx = selected_take and reaper.TakeFX_GetCount(selected_take) > 0 or false

    PushJKKButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Reverse", primary_button_width, 22) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(41051, 0)
        reaper.Undo_EndBlock("Take Reverse", -1)
    end
    PopJKKButtonStyle(ctx)

    reaper.ImGui_SameLine(ctx, 0, action_gap)
    reaper.ImGui_BeginDisabled(ctx, not has_multiple_takes)
    -- Previous/next take navigation buttons intentionally keep the default theme color.
    if reaper.ImGui_Button(ctx, "<", nav_button_width, 22) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(42350, 0)
        reaper.Undo_EndBlock("Prev Take", -1)
    end
    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_SameLine(ctx, 0, action_gap)
    PushJKKButtonStyle(ctx)
    if has_take_fx then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF) end
    if reaper.ImGui_Button(ctx, "FX", nav_button_width, 22) then
        reaper.Main_OnCommand(40638, 0)
    end
    if has_take_fx then reaper.ImGui_PopStyleColor(ctx) end
    PopJKKButtonStyle(ctx)

    reaper.ImGui_SameLine(ctx, 0, action_gap)
    reaper.ImGui_BeginDisabled(ctx, not has_multiple_takes)
    if reaper.ImGui_Button(ctx, ">", nav_button_width, 22) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(42349, 0)
        reaper.Undo_EndBlock("Next Take", -1)
    end
    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_SameLine(ctx, 0, action_gap)
    PushJKKButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Render Take", primary_button_width, 22) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(41999, 0)
        reaper.Undo_EndBlock("Render to New Take", -1)
    end
    PopJKKButtonStyle(ctx)
end

local function DrawItemTakeMetadata(ctx)
    -- Reduce the horizontal padding on both sides of the Take Controls / Item
    -- Info divider without changing the fixed 2:1 column ratio.
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_CellPadding(), 8, 0)
    local properties_width = 0
    local metadata_flags = reaper.ImGui_TableFlags_SizingStretchProp()
        | reaper.ImGui_TableFlags_BordersInnerV()
    if reaper.ImGui_BeginTable(ctx, "TakeSettingsLayout", 2, metadata_flags) then
        reaper.ImGui_TableSetupColumn(ctx, "Take Controls", reaper.ImGui_TableColumnFlags_WidthStretch(), 2.0)
        reaper.ImGui_TableSetupColumn(ctx, "Item Info", reaper.ImGui_TableColumnFlags_WidthStretch(), 1.0)

        -- Left: Take Channel + Pitch Mode. Both right-side combo edges align.
        reaper.ImGui_TableNextColumn(ctx)
        local controls_width = GetAvailableWidth(ctx)
        local label_width = 86
        local combo_width = math.max(60, controls_width - label_width - 8)

        local row_x = reaper.ImGui_GetCursorPosX(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, "Take Channel")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, row_x + label_width)
        DrawChannelModeCombo(ctx, combo_width)

        row_x = reaper.ImGui_GetCursorPosX(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, "Pitch Mode")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, row_x + label_width)
        -- The lower sub-mode combo starts at the same X and has the same width
        -- as the main combo, instead of extending past the controls column.
        DrawPitchModeCombo(ctx, combo_width, combo_width, true, row_x + label_width)

        -- Right: compact metadata and Properties button; no extra vertical spacer.
        reaper.ImGui_TableNextColumn(ctx)
        if item_info_str1 ~= "" then reaper.ImGui_Text(ctx, item_info_str1) end
        if item_info_str2 ~= "" then reaper.ImGui_Text(ctx, item_info_str2) end
        if item_info_str3 ~= "" then reaper.ImGui_Text(ctx, item_info_str3) end

        properties_width = GetAvailableWidth(ctx)
        if reaper.ImGui_Button(ctx, "Properties...", properties_width, 22) then
            reaper.Main_OnCommand(40011, 0)
        end
        reaper.ImGui_EndTable(ctx)
    end
    -- This spacer must be outside the nested table. A Dummy inside the final
    -- table cell can be absorbed by that cell's row sizing and not create a
    -- visible margin beneath the complete metadata block.
    reaper.ImGui_Dummy(ctx, 10, 6)
    reaper.ImGui_PopStyleVar(ctx, 1)
    return properties_width
end

local function GetUtilityRowLayout(ctx)
    local available_width = GetAvailableWidth(ctx)
    local label_width = 104
    local button_width = 100
    local item_spacing = 8

    -- Width slider now uses the same width as the other utility sliders.
    local slider_width = math.max(48,
        available_width - label_width - button_width - item_spacing)

    return {
        label_width = label_width,
        slider_width = slider_width,
        width_slider_width = slider_width,
        button_width = button_width,
        shuffle_width = button_width,
        item_spacing = item_spacing
    }
end

local function DrawIntervalWidthTools(ctx, layout)
    layout = layout or GetUtilityRowLayout(ctx)

    local row_x = reaper.ImGui_GetCursorPosX(ctx)
    local row_y = reaper.ImGui_GetCursorPosY(ctx)

    local frame_height = reaper.ImGui_GetFrameHeight(ctx)
    local inner_spacing = 4

    if reaper.ImGui_GetStyleVar and reaper.ImGui_StyleVar_ItemInnerSpacing then
        local ok, value = pcall(
            reaper.ImGui_GetStyleVar,
            ctx,
            reaper.ImGui_StyleVar_ItemInnerSpacing()
        )
        if ok and type(value) == "number" then
            inner_spacing = value
        end
    end

    local button_height = 22

    -- Width label
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, "Arrange Width")

    -- Width slider
    reaper.ImGui_SetCursorPos(
        ctx,
        row_x + layout.label_width,
        row_y
    )

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

    reaper.ImGui_SetNextItemWidth(ctx, layout.slider_width)

    local changed_width, new_width = reaper.ImGui_SliderDouble(
        ctx,
        "##IntervalWidth",
        width,
        cur_min,
        cur_max,
        format_str
    )

    if reaper.ImGui_IsItemActivated(ctx) then
        reaper.Undo_BeginBlock()
    end

    if changed_width then
        width = (spacing_mode == 0)
            and math.floor(new_width + 0.5)
            or new_width

        apply_spacing_only()
    end

    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.Undo_EndBlock("Update Interval Width", -1)
    end

    if reaper.ImGui_IsItemClicked(ctx, 1) then
        spacing_mode = (spacing_mode + 1) % 3

        if spacing_mode == 0 then
            width = 2.0
        elseif spacing_mode == 1 then
            width = 1.5
        else
            width = 120.0
        end
    end

    if reaper.ImGui_IsItemHovered(ctx) then
        local mode_names = {"Grid", "Seconds", "RPM"}
        reaper.ImGui_SetTooltip(
            ctx,
            "Current: " .. mode_names[spacing_mode + 1]
            .. "\nRight-click to toggle (Grid -> Sec -> RPM)"
        )
    end

    -- Shuffle Order: first row, right side
    local shuffle_x = row_x
        + layout.label_width
        + layout.slider_width
        + layout.item_spacing

    reaper.ImGui_SetCursorPos(ctx, shuffle_x, row_y)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x24866FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1F735FFF)

    if reaper.ImGui_Button(
        ctx,
        "Shuffle Order",
        layout.button_width,
        button_height
    ) then
        shuffle_item_order()
    end

    reaper.ImGui_PopStyleColor(ctx, 3)

    -- Gap / Grp: second row, directly below the slider
    local checkbox_y = row_y + frame_height + inner_spacing

    reaper.ImGui_SetCursorPos(
        ctx,
        row_x + layout.label_width,
        checkbox_y
    )

    local changed_gap, new_gap = reaper.ImGui_Checkbox(
        ctx,
        "Gap",
        use_gap_mode
    )

    if changed_gap then
        use_gap_mode = new_gap
    end

    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(
            ctx,
            "Checked: End-to-Start\nUnchecked: Start-to-Start"
        )
    end

    reaper.ImGui_SameLine(ctx, 0, layout.item_spacing)

    local changed_group, new_group = reaper.ImGui_Checkbox(
        ctx,
        "Group",
        use_clustering
    )

    if changed_group then
        use_clustering = new_group
        persistentClusters = {}
    end

    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(
            ctx,
            "Checked: Move overlapping items as one group\nUnchecked: Move items individually"
        )
    end

    -- Loopmaker button: second row, right side
    reaper.ImGui_SetCursorPos(ctx, shuffle_x, checkbox_y)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)

    if reaper.ImGui_Button(
        ctx,
        "Loopmaker",
        layout.button_width,
        button_height
    ) then
        reaper.Undo_BeginBlock()
        local cmd_id = reaper.NamedCommandLookup("_RScca2c247e3eef55035a013459ae01e9beab07629")
        if cmd_id ~= 0 then
            reaper.Main_OnCommand(cmd_id, 0)
        end
        reaper.Undo_EndBlock("Run Loopmaker Action", -1)
    end

    reaper.ImGui_PopStyleColor(ctx, 3)

    -- Move cursor below the complete two-row layout.
    reaper.ImGui_SetCursorPosY(
        ctx,
        row_y + frame_height * 2 + inner_spacing
    )
end

local function DrawDynamicItemSplitter(ctx, selected_item_count, is_active_context, layout)
    layout = layout or GetUtilityRowLayout(ctx)

    -- Threshold + Split. All utility sliders and buttons use the shared C-panel dimensions.
    local row_label_width = layout.label_width
    local splitter_button_width = layout.button_width
    local row_x = reaper.ImGui_GetCursorPosX(ctx)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, "Threshold")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, row_x + row_label_width)
    local slider_width = layout.slider_width
    reaper.ImGui_SetNextItemWidth(ctx, slider_width)
    local thres_changed, new_thres = reaper.ImGui_SliderDouble(ctx, "##Threshold", silenceThreshold, 0.001, 0.3, "%.3f")
    if thres_changed then silenceThreshold = new_thres end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        silenceThreshold = 0.01
        thres_changed = true
    end
    reaper.ImGui_SameLine(ctx, 0, layout.item_spacing)
    PushJKKButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Split Dyn", splitter_button_width, 22) then
        cleanup()
        reaper.Undo_BeginBlock()
        local items = storeSelectedMediaItems()
        if safeToExecute(items) then
            items = storeSelectedMediaItems()
            for _, item in ipairs(items) do
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
    PopJKKButtonStyle(ctx)

    -- Minimum silence length + Split & Takes
    row_x = reaper.ImGui_GetCursorPosX(ctx)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, "Min Length")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, row_x + row_label_width)
    slider_width = layout.slider_width
    reaper.ImGui_SetNextItemWidth(ctx, slider_width)
    local dur_changed, new_dur = reaper.ImGui_SliderDouble(ctx, "##MinDuration", minSilenceDuration, 0.001, 2.0, "%.3f")
    if dur_changed then minSilenceDuration = new_dur end
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        minSilenceDuration = 0.2
        dur_changed = true
    end
    reaper.ImGui_SameLine(ctx, 0, layout.item_spacing)
    PushJKKButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Split & Takes", splitter_button_width, 22) then
        cleanup()
        reaper.Undo_BeginBlock()
        local items = storeSelectedMediaItems()
        if safeToExecute(items) then
            if shouldAlignToMarker then
                promptUserForNumber("Align with marker", "Please enter the Marker ID")
            end
            items = storeSelectedMediaItems()
            for _, item in ipairs(items) do
                selectOnlyThisItem(item)
                local take = reaper.GetActiveTake(item)
                local align_on_start = true
                local silences_in_loop = getSilenceTime(item, take)
                implodeMain(item, take, false, align_on_start, silences_in_loop)
            end
            reaper.UpdateArrange()
        end
        reaper.Undo_EndBlock("Split & Takes", -1)
    end
    PopJKKButtonStyle(ctx)

    -- Live guide generation: remove the leading spacer and keep breathing room below.
    local changed_keep, new_keep = reaper.ImGui_Checkbox(ctx, "Keep Origin When Rendering", shouldKeepOriginal)
    if changed_keep then
        shouldKeepOriginal = new_keep
        reaper.SetExtState("PeaksAndValleys", "shouldKeepOriginal", tostring(shouldKeepOriginal), true)
    end
    reaper.ImGui_SameLine(ctx)
    local guide_changed, new_guide = reaper.ImGui_Checkbox(ctx, "Guide", showGuideBox)
    if guide_changed then
        showGuideBox = new_guide
        if not showGuideBox then clearTemporaryItems() end
    end
    reaper.ImGui_Spacing(ctx)

    local current_signature = GetSelectionHash()
    if is_active_context and showGuideBox
        and (thres_changed or dur_changed or guide_changed or current_signature ~= lastSelectionSignature) then
        cleanup()
        local items = storeSelectedMediaItems()
        for _, item in ipairs(items) do
            local take = reaper.GetActiveTake(item)
            local track = reaper.GetMediaItem_Track(item)
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local silences = getSilenceTime(item, take)
            if silences then
                createTemporaryItems(track, silences, item_pos)
            end
        end
        lastSelectionSignature = current_signature
    end
end

local function DrawGridSplitter(ctx, layout)
    layout = layout or GetUtilityRowLayout(ctx)

    local row_x = reaper.ImGui_GetCursorPosX(ctx)

    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, "Slice Interval")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, row_x + layout.label_width)
    reaper.ImGui_SetNextItemWidth(ctx, layout.slider_width)
    local changed_slice, new_slice = reaper.ImGui_SliderInt(ctx, "##GridSliceCount", grid_slice_n, 1, 10, "%d grid")
    if changed_slice then grid_slice_n = new_slice end
    if reaper.ImGui_IsItemClicked(ctx, 1) then grid_slice_n = 5 end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Grid slice interval (1~10)\nRight-click to reset (5)")
    end

    reaper.ImGui_SameLine(ctx, 0, layout.item_spacing)
    PushJKKButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Split Grid", layout.button_width, 22) then
        reaper.Undo_BeginBlock()
        GridSplitMain(grid_slice_n)
        reaper.Undo_EndBlock("Grid Split Items", -1)
    end
    PopJKKButtonStyle(ctx)
end

function JKK_ItemTool_Draw(ctx, prev_count, current_count, active_context, track_module)
    local selected_item_count = reaper.CountSelectedMediaItems(0)
    active_context = active_context or (selected_item_count > 0 and "item" or "none")

    if active_context == "item" then
        -- When the selection becomes empty, keep the last read values visible
        -- underneath the parent panel's disabled state instead of resetting them.
        if selected_item_count > 0 then
            SyncSelectionData(ctx)
        end
        DrawItemBatchController(
            ctx,
            selected_item_count,
            prev_count or 0,
            current_count or reaper.GetProjectStateChangeCount(0)
        )
    elseif active_context == "track" then
        if track_module and track_module.JKK_TrackTool_Draw then
            track_module.JKK_TrackTool_Draw(ctx, "track")
        else
            reaper.ImGui_Text(ctx, "Track tools module is unavailable.")
        end
    elseif active_context == "timeline" then
        if track_module and track_module.JKK_TrackTool_DrawTimelineActions then
            track_module.JKK_TrackTool_DrawTimelineActions(ctx)
        else
            reaper.ImGui_Text(ctx, "Timeline tools module is unavailable.")
        end
    else
        reaper.ImGui_Text(ctx, "Select an item, track, or timeline area to show its tools.")
    end

    if active_context == "item" then
        local general_state_changed = has_changed()
        if general_state_changed then
            update_prev()
            SaveSettings()
        end
    end
end

function JKK_ItemTool_DrawEditingUtilities(ctx, is_active_context)
    local layout = GetUtilityRowLayout(ctx)

    -- Capture available panel area.
    local start_y = reaper.ImGui_GetCursorPosY(ctx)
    local _, available_height = reaper.ImGui_GetContentRegionAvail(ctx)

    local frame_height = reaper.ImGui_GetFrameHeight(ctx)
    local spacing_y = 8

    -- Draw Width at the top.
    DrawIntervalWidthTools(ctx, layout)

    -- Estimate the height of the bottom-anchored controls:
    -- Slice Interval
    -- Threshold
    -- Min Length
    -- Keep Origin / Guide
    local bottom_block_height =
        frame_height * 4
        + spacing_y * 3

    local current_y = reaper.ImGui_GetCursorPosY(ctx)

    -- Anchor the remaining controls to the bottom.
    local bottom_y = start_y
        + available_height
        - bottom_block_height - 13

    -- Avoid overlapping Width when the panel is too short.
    bottom_y = math.max(
        bottom_y,
        current_y + spacing_y
    )

    reaper.ImGui_SetCursorPosY(ctx, bottom_y)
    reaper.ImGui_Separator(ctx)
    -- Spacing below separator
    reaper.ImGui_Spacing(ctx)

    DrawGridSplitter(ctx, layout)

    reaper.ImGui_Spacing(ctx)

    DrawDynamicItemSplitter(
        ctx,
        reaper.CountSelectedMediaItems(0),
        is_active_context == true,
        layout
    )
end

function JKK_ItemTool_DrawMetadata(ctx)
    -- Take Channel / Pitch Mode and Item Info are now grouped below Renamer
    -- in Panel C. Return the actual Properties button width so Renamer Lite
    -- can use precisely the same width on the next frame.
    return DrawItemTakeMetadata(ctx)
end

-- Backward-compatible combined entry point for older callers.
function JKK_ItemTool_DrawUtilities(ctx)
    JKK_ItemTool_DrawEditingUtilities(ctx, true)
    reaper.ImGui_Spacing(ctx)
    JKK_ItemTool_DrawMetadata(ctx)
end

return {
    JKK_ItemTool_Draw = JKK_ItemTool_Draw,
    JKK_ItemTool_DrawUtilities = JKK_ItemTool_DrawUtilities,
    JKK_ItemTool_DrawEditingUtilities = JKK_ItemTool_DrawEditingUtilities,
    JKK_ItemTool_DrawMetadata = JKK_ItemTool_DrawMetadata,
}