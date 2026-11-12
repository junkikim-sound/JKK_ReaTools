--========================================================
-- @title JKK_ReaTools_NEW_ItemTool
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper

-- JKK_ReaTools가 먼저 로드한 SelectionManager 참조 (단독 로드 시 폴백 포함)
local script_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local sel_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_SelectionManager.lua"
if not reaper.file_exists(sel_path) then
    sel_path = script_dir .. "JKK_SelectionManager.lua"
end
local sel_mgr = _G.JKK_SelectionManager or (reaper.file_exists(sel_path) and dofile(sel_path))

-- UI zoom factor published by JKK_ReaTools (1.0 = original design size).
-- Kept global on purpose: this chunk is already close to Lua's local-variable limit.
function JKK_Scale(v) return v * (JKK_UI_SCALE or 1) end

-- FIX: slider undo blocks. The block used to open when a slider was clicked and
-- close only after an actual edit, so a click without a change left it open.
-- It now opens on the first change and closes whenever the slider is released.
JKK_ItemSliderUndoOpen = false
function JKK_ItemSliderUndoBegin()
    if not JKK_ItemSliderUndoOpen then
        reaper.Undo_BeginBlock()
        JKK_ItemSliderUndoOpen = true
    end
end
function JKK_ItemSliderUndoEnd(ctx, description)
    if JKK_ItemSliderUndoOpen and reaper.ImGui_IsItemDeactivated(ctx) then
        reaper.Undo_EndBlock(description, -1)
        JKK_ItemSliderUndoOpen = false
    end
end

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
        function JKK_IT_ApplyBatchVolume()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            -- dB를 Linear 값으로 변환
            local linear_vol = 10^(adjust_vol / 20)
            
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local take = reaper.GetActiveTake(item)
                
                if take then
                    -- FIX: a negative take volume means "polarity flipped". Keep the
                    -- sign so changing the volume no longer resets the polarity.
                    local current = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                    reaper.SetMediaItemTakeInfo_Value(take, "D_VOL",
                        (current < 0) and -linear_vol or linear_vol)
                end
            end
            
            reaper.UpdateArrange()
        end
        function JKK_IT_ApplyBatchPan()
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
        function JKK_IT_ApplyBatchPitch()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                -- FIX: empty items have no take; passing nil raised an argument error.
                local take = reaper.GetActiveTake(item)
                if take then
                    reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", adjust_pitch)
                end
            end
            
            reaper.UpdateArrange()
        end
        function JKK_IT_ApplyBatchRate()
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
        function JKK_IT_ApplyGroupStretch(stretch_ratio)
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
        function JKK_IT_ApplyItemProperty(key, val)
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            -- FIX: these toggles were not recorded in the undo history.
            reaper.Undo_BeginBlock()
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemInfo_Value(item, key, val)
            end
            reaper.UpdateArrange()
            local names = { B_LOOPSRC = "Loop Source", B_MUTE = "Mute", C_LOCK = "Lock" }
            reaper.Undo_EndBlock("Set Item " .. (names[key] or key), -1)
        end
    -- Fader
        local drag_start_cur = 0.0
        local adj_fade_in_cur = 0.0
        local adj_fade_out_cur = 0.0
        local last_project_change_count = reaper.GetProjectStateChangeCount(0)
    -- Take Channel Mode & Pitch Mode
        function JKK_IT_ApplyTakeChannelMode(mode)
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
        function JKK_IT_ApplyTakePitchMode(main_mode, sub_mode)
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
        JKK_IT_item_info_str1 = "  SR: "
        JKK_IT_item_info_str2 = "  Ch:   |  Len: "
        JKK_IT_item_info_str3 = "  Take: "
        local function JKK_IT_SyncSelectionData(prev_state, curr_state, force)
            -- Skip updates during active mouse dragging or UI slider adjustment
            if sel_mgr and sel_mgr.IsMouseDown() then
                return
            end

            if reaper.JS_Mouse_GetState and (reaper.JS_Mouse_GetState(1) & 1) == 1 then
                return
            end
            -- 2. 변경 감지
            local cur_change_count = reaper.GetProjectStateChangeCount(0)
            local cur_guids = GetSelectedItemsGUIDString()

            if cur_change_count ~= last_project_change_count or cur_guids ~= JKK_IT_sync_last_guids then
                last_project_change_count = cur_change_count
                JKK_IT_sync_last_guids = cur_guids

                -- FIX: removed resets of anchor_min_pos / persistentClusters / slot_*.
                -- They ran before those locals were declared, so they only wrote unused
                -- globals; behaviour is unchanged.

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
                        -- FIX: read the magnitude; a flipped polarity is a negative value.
                        local val_vol = math.abs(reaper.GetMediaItemTakeInfo_Value(take, "D_VOL"))
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
                        
                        JKK_IT_item_info_str1 = string.format("  SR: %dHz", s_rate)
                        JKK_IT_item_info_str2 = string.format("  Ch: %d  |  Len: %s", n_chan, len_str)
                        JKK_IT_item_info_str3 = string.format("  Take: %d/%d", take_idx, take_cnt)
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
                    JKK_IT_item_info_str1 = "  SR: "
                    JKK_IT_item_info_str2 = "  Ch:   |  Len: "
                    JKK_IT_item_info_str3 = "  Take: "
                end
            end
        end
    -- Channel Mode & Pitch Mode Combo Draw
        function JKK_IT_DrawChannelModeCombo(ctx, width)
            reaper.ImGui_SetNextItemWidth(ctx, width or JKK_Scale(128))
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
                        JKK_IT_ApplyTakeChannelMode(take_chan_mode)
                    end
                end

                reaper.ImGui_Separator(ctx)

                -- B. Mono (3 ~ 12)
                if reaper.ImGui_BeginMenu(ctx, "Mono (3-12)") then
                    for i = 3, 12 do
                        local real_val = i + 2
                        
                        if reaper.ImGui_MenuItem(ctx, "Mono " .. i, nil, take_chan_mode == real_val) then
                            take_chan_mode = real_val
                            JKK_IT_ApplyTakeChannelMode(take_chan_mode) 
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
                            JKK_IT_ApplyTakeChannelMode(take_chan_mode)
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
        function JKK_IT_DrawPitchModeCombo(ctx, width1, width2, stacked_sub, stacked_x)
            local item_cnt = reaper.CountSelectedMediaItems(0)
            
            -- 1. Main Mode Combo (Algorithm)
            reaper.ImGui_SetNextItemWidth(ctx, width1 or JKK_Scale(128))
            
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
                        JKK_IT_ApplyTakePitchMode(take_pitch_mode, take_pitch_sub_mode)
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
            reaper.ImGui_SetNextItemWidth(ctx, width2 or JKK_Scale(128))
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
                            JKK_IT_ApplyTakePitchMode(take_pitch_mode, take_pitch_sub_mode)
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
        function JKK_IT_has_changed()
            return (
                width        ~= prev_width or
                use_clustering ~= JKK_IT_prev_use_clustering or
                spacing_mode  ~= JKK_IT_prev_spacing_mode or
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
        function JKK_IT_update_prev()
            prev_width        = width
            JKK_IT_prev_use_clustering = use_clustering
            prev_use_gap_mode   = use_gap_mode
            JKK_IT_prev_spacing_mode   = spacing_mode
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

            JKK_IT_update_prev() 
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
        function JKK_IT_apply_spacing_only()
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
    function JKK_IT_shuffle_item_order()
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
            JKK_IT_apply_spacing_only()
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
        local grid_live = {
            enabled = false,
            mode = 0,          -- 0: Grid, 1: Seconds
            sec = 0.5,         -- Seconds 모드 기본값 (0.01 ~ 5.0초)
            snapshot = nil,    -- 원본 아이템 상태 스냅샷
            output_guids = nil,
            undo_label = "Live Grid Split Items",
        }
        local splitAndSpace = false
        local shouldAlignToMarker = false

        local lastSelectionSignature = ""
        local guide_guard = {
            max_items = 30,          -- 동시 분석 허용 최대 아이템 수
            max_total_sec = 300.0,   -- 동시 분석 허용 최대 총 길이 (초, 5분)
            max_guide_items = 200,   -- 생성할 붉은 가이드 아이템 최대 개수 상한
            debounce_delay = 0.08,   -- 슬라이더 드래그 시 갱신 지연 시간 (초)
            pending_update = false,
            last_change_time = 0.0,
            warning_msg = nil,
            buffer_cache = {},
        }
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
            -- FIX: openURL did not exist (load error on "Yes"), and "No" made the
            -- whole Item Tools module fail to load. Only the Split functions need SWS.
            if userChoice == 6 then
                os.execute('start "" "https://www.sws-extension.org/"')
            end
        end

        if not reaper.APIExists("ImGui_GetVersion") then
            showMessage("This script requires ReaImGui to run. Please install it with ReaPack.", "Error", 0)
        end


        local selectedItems = {}
        local silenceItems = {}
        local lastTrack = nil
        -- FIX: removed the first-run "quit REAPER now?" prompt inherited from the
        -- standalone Peaks & Valleys script; it does not apply inside ReaTools.

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
                    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
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
                -- FIX: silences is nil when the analysis could not run (e.g. no audio device).
                if not item or not silences or #silences == 0 then
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

            local function createTemporaryItems(track, silences, itemPosition, max_remaining)
                lastTrack = track
                local redColor = reaper.ColorToNative(255, 0, 0) | 0x1000000
                local created = 0
                local capped = false
                for _, silence in ipairs(silences) do
                    if max_remaining and created >= max_remaining then
                        capped = true
                        break
                    end
                    local silenceStart = itemPosition + silence.start
                    local silenceEnd = itemPosition + silence["end"]
                    local silenceLength = silenceEnd - silenceStart

                    if silenceLength > 0.0001 then
                        local newItem = reaper.AddMediaItemToTrack(track)
                        reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", silenceStart)
                        reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", silenceLength)
                        reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", 0)
                        reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", 0)

                        reaper.SetMediaItemInfo_Value(newItem, "I_CUSTOMCOLOR", redColor)
                        table.insert(silenceItems, newItem)
                        created = created + 1
                    end
                end
                return created, capped
            end

            local function clearTemporaryItems(skip_refresh)
                if #silenceItems > 0 then
                    if not skip_refresh then reaper.PreventUIRefresh(1) end
                    for _, item in ipairs(silenceItems) do
                        if reaper.ValidatePtr(item, "MediaItem*") then
                            local track = reaper.GetMediaItem_Track(item)
                            reaper.DeleteTrackMediaItem(track, item)
                        end
                    end
                    silenceItems = {}
                    if not skip_refresh then
                        reaper.PreventUIRefresh(-1)
                        reaper.UpdateArrange()
                    end
                else
                    silenceItems = {}
                end
            end

            local function cleanup()
                clearTemporaryItems(false)
            end

            local function GetItemBufferCacheKey(item, take)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                return string.format("%s|%s|%.4f|%.4f|%.4f|%.4f",
                    tostring(item), tostring(take), pos, len, offs, rate)
            end

            local function GetCachedSilenceBuffer(item, take)
                if not item or not take then return nil end
                local cache_key = GetItemBufferCacheKey(item, take)
                local cached = guide_guard.buffer_cache[cache_key]
                if cached then
                    return cached.buffer, cached.num_blocks, cached.num_channels,
                           cached.downsampling_factor, cached.sample_rate, cached.start_time
                end

                local accessor, sampleRate, numChannels, startTime, endTime = prepareItemAnalysis(item, take)
                if not accessor then return nil end
                if not sampleRate or not numChannels or numChannels <= 0 or endTime <= startTime then
                    reaper.DestroyAudioAccessor(accessor)
                    return nil
                end

                local totalSamples = calculateTotalSamples(startTime, endTime, sampleRate)
                if totalSamples <= 0 then
                    reaper.DestroyAudioAccessor(accessor)
                    return nil
                end

                local downsamplingFactor = calculateDownsamplingFactor(totalSamples, numChannels) * 80
                local effectiveRate = math.max(200, math.floor(sampleRate / downsamplingFactor))
                local eff_factor = sampleRate / effectiveRate
                local totalBlocks = math.max(1, math.ceil((endTime - startTime) * effectiveRate))

                -- 배열 메모리 상한 보호 (최대 250,000 요소)
                if totalBlocks * numChannels > 250000 then
                    totalBlocks = math.floor(250000 / numChannels)
                    effectiveRate = math.max(50, math.floor(totalBlocks / math.max(0.001, endTime - startTime)))
                    eff_factor = sampleRate / effectiveRate
                end

                -- 1샘플 루프 대신 C++ API 한 번으로 전체 블록 일괄 추출
                local buffer = reaper.new_array(totalBlocks * numChannels)
                buffer.clear()
                reaper.GetAudioAccessorSamples(accessor, effectiveRate, numChannels, startTime, totalBlocks, buffer)
                reaper.DestroyAudioAccessor(accessor)

                guide_guard.buffer_cache[cache_key] = {
                    buffer = buffer,
                    num_blocks = totalBlocks,
                    num_channels = numChannels,
                    downsampling_factor = eff_factor,
                    sample_rate = sampleRate,
                    start_time = startTime
                }
                return buffer, totalBlocks, numChannels, eff_factor, sampleRate, startTime
            end

            local function getSilenceTime(item, take, use_cache)
                if use_cache then
                    local silenceBuffer, _, numChannels, downsamplingFactor, sampleRate, startTime = GetCachedSilenceBuffer(item, take)
                    if not silenceBuffer then return nil end
                    local silences = detectSilences(silenceBuffer, silenceThreshold, minSilenceDuration, sampleRate, downsamplingFactor, numChannels)
                    return convertSilencesToTime(silences, startTime, sampleRate, downsamplingFactor, numChannels)
                end

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

            function JKK_IT_tableIsEmpty(table)
                for _ in pairs(table) do
                    return false
                end
                return true
            end

            local function itemsAreValid(selectedItems)
                if not JKK_IT_tableIsEmpty(selectedItems) then
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
                    if JKK_IT_tableIsEmpty(itemsToConvert) then
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
        local function GetSelectedItemGUIDList()
            local list = {}
            local cnt = reaper.CountSelectedMediaItems(0)
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
                list[#list + 1] = guid
            end
            return list
        end

        local function AreGUIDListsEqual(a, b)
            if not a or not b or #a ~= #b then return false end
            for i = 1, #a do
                if a[i] ~= b[i] then return false end
            end
            return true
        end

        local function ResetLiveGridSession()
            grid_live.snapshot = nil
            grid_live.output_guids = nil
        end

        local function CaptureLiveGridSnapshot()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return nil end

            local entries = {}
            for i = 0, cnt - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                local track = reaper.GetMediaItem_Track(item)
                local take = reaper.GetActiveTake(item)
                entries[#entries + 1] = {
                    item = item,
                    track = track,
                    pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
                    len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
                    fadein = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
                    fadeout = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
                    startoffs = take and reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or nil,
                }
            end
            return entries
        end

        local function RestoreLiveGridSnapshot()
            if not grid_live.snapshot then return false end

            -- 1. 현재 선택된 분할 조각들 중 원본 포인터가 아닌 조각들 삭제
            local original_set = {}
            for _, entry in ipairs(grid_live.snapshot) do
                if not entry.item or not reaper.ValidatePtr(entry.item, "MediaItem*") then
                    ResetLiveGridSession()
                    return false
                end
                original_set[entry.item] = true
            end

            for i = reaper.CountSelectedMediaItems(0) - 1, 0, -1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                if not original_set[item] then
                    local tr = reaper.GetMediaItem_Track(item)
                    if tr then reaper.DeleteTrackMediaItem(tr, item) end
                end
            end

            -- 2. 원본 아이템의 길이·위치·페이드·오프셋 복구
            for _, entry in ipairs(grid_live.snapshot) do
                reaper.SetMediaItemInfo_Value(entry.item, "D_POSITION", entry.pos)
                reaper.SetMediaItemInfo_Value(entry.item, "D_LENGTH", entry.len)
                reaper.SetMediaItemInfo_Value(entry.item, "D_FADEINLEN", entry.fadein)
                reaper.SetMediaItemInfo_Value(entry.item, "D_FADEOUTLEN", entry.fadeout)
                if entry.startoffs then
                    local take = reaper.GetActiveTake(entry.item)
                    if take then
                        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", entry.startoffs)
                    end
                end
                reaper.SetMediaItemSelected(entry.item, true)
            end
            return true
        end

        local function GridSplitMain()
            local cnt = reaper.CountSelectedMediaItems(0)
            if cnt == 0 then return end

            local slice_interval = 0.0
            if grid_live.mode == 0 then
                local _, grid_sec = reaper.GetSetProjectGrid(0, false)
                if grid_sec <= 0 then return end
                slice_interval = grid_sec * (grid_slice_n * 2)
            else
                slice_interval = grid_live.sec
            end

            if not slice_interval or slice_interval <= 0.001 then return end

            reaper.PreventUIRefresh(1)
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
            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
        end

        local function ExecuteLiveGridSplit()
            if reaper.CountSelectedMediaItems(0) == 0 then
                ResetLiveGridSession()
                return
            end

            local cur_guids = GetSelectedItemGUIDList()
            local is_continuing = grid_live.snapshot
                and grid_live.output_guids
                and AreGUIDListsEqual(cur_guids, grid_live.output_guids)

            reaper.PreventUIRefresh(1)
            reaper.Undo_BeginBlock()

            if is_continuing then
                if not RestoreLiveGridSnapshot() then
                    grid_live.snapshot = CaptureLiveGridSnapshot()
                end
            else
                grid_live.snapshot = CaptureLiveGridSnapshot()
            end

            GridSplitMain()

            reaper.Undo_EndBlock(grid_live.undo_label, -1)
            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()

            grid_live.output_guids = GetSelectedItemGUIDList()
        end

----------------------------------------------------------
-- UI_Module: Unified Item / Track Workspace
----------------------------------------------------------
local function GetAvailableWidth(ctx)
    local width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    return math.max(JKK_Scale(60), width or JKK_Scale(60))
end

local function PushJKKButtonStyle(ctx)
    if JKK_Theme then
        JKK_Theme.PushButton(ctx, "primary")
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
    end
end

local function PopJKKButtonStyle(ctx)
    if JKK_Theme then
        JKK_Theme.PopButton(ctx)
    else
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
end

local function PushJKKConfirmButtonStyle(ctx)
    if JKK_Theme then
        JKK_Theme.PushButton(ctx, "confirm")
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x24866FFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1F735FFF)
    end
end

local function PopJKKConfirmButtonStyle(ctx)
    if JKK_Theme then
        JKK_Theme.PopButton(ctx)
    else
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
end

local function DrawItemBatchController(ctx, selected_item_count, prev_count, current_count)
    -- Keep the previous controller visible when the selection is empty. The
    -- parent panel wraps this draw call in ImGui_BeginDisabled/EndDisabled.
    -- A fixed label column keeps every slider aligned to the Play Rate row.
    local label_width = JKK_Scale(86)
    local row_width = GetAvailableWidth(ctx)
    local slider_width = math.max(JKK_Scale(70), row_width - label_width)
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
    if changed_vol then
        JKK_ItemSliderUndoBegin()
        adjust_vol = new_vol
        JKK_IT_ApplyBatchVolume()
    end
    JKK_ItemSliderUndoEnd(ctx, "Batch Take Volume Applied")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_vol = 0.0
        JKK_IT_ApplyBatchVolume()
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
    if changed_pan then
        JKK_ItemSliderUndoBegin()
        adjust_pan = new_pan
        JKK_IT_ApplyBatchPan()
    end
    JKK_ItemSliderUndoEnd(ctx, "Batch Pan Applied")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_pan = 0.0
        JKK_IT_ApplyBatchPan()
        reaper.Undo_EndBlock("Reset Pan", -1)
    end

    -- Pitch
    BeginLabeledRow("Pitch")
    local changed_pitch, new_pitch = reaper.ImGui_SliderDouble(ctx, "##ItemPitch", adjust_pitch, -12.0, 12.0, "%.1f st")
    if changed_pitch then
        JKK_ItemSliderUndoBegin()
        adjust_pitch = new_pitch
        JKK_IT_ApplyBatchPitch()
    end
    JKK_ItemSliderUndoEnd(ctx, "Batch Pitch Applied")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_pitch = 0.0
        JKK_IT_ApplyBatchPitch()
        reaper.Undo_EndBlock("Reset Pitch", -1)
    end

    -- Playback Rate
    BeginLabeledRow("Play Rate")
    local changed_rate, new_rate = reaper.ImGui_SliderDouble(
        ctx, "##ItemPlaybackRate", adjust_rate, 0.25, 4.0, "%.2f",
        reaper.ImGui_SliderFlags_Logarithmic()
    )
    if changed_rate then
        JKK_ItemSliderUndoBegin()
        adjust_rate = new_rate
        JKK_IT_ApplyBatchRate()
    end
    JKK_ItemSliderUndoEnd(ctx, "Batch Playback Rate Applied")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        adjust_rate = 1.0
        JKK_IT_ApplyBatchRate()
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
    if changed_group_stretch then
        JKK_ItemSliderUndoBegin()
        group_stretch_ratio = new_group_stretch
        if group_stretch_ratio ~= prev_group_stretch_ratio then
            JKK_IT_ApplyGroupStretch(group_stretch_ratio)
            prev_group_stretch_ratio = group_stretch_ratio
            JKK_IT_update_prev()
        end
    end
    JKK_ItemSliderUndoEnd(ctx, "Group Time Stretch Applied")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.Undo_BeginBlock()
        group_stretch_ratio = 1.0
        JKK_IT_ApplyGroupStretch(group_stretch_ratio)
        prev_group_stretch_ratio = 1.0
        JKK_IT_update_prev()
        reaper.Undo_EndBlock("Reset Group Stretch", -1)
    end

    -- 버튼 적정 최대 크기 및 기본 간격 정의
    local available_width = GetAvailableWidth(ctx)
    local max_primary_w = JKK_Scale(130)
    local max_nav_w = JKK_Scale(50)
    local nav_gap = JKK_Scale(6)
    local min_outer_gap = JKK_Scale(6)

    -- 최대 크기 기준 필요 너비 (양쪽 최소 여백 및 내부 간격 포함)
    local max_buttons_w = (max_primary_w * 2) + (max_nav_w * 3)
    local base_gaps_w = (min_outer_gap * 2) + (nav_gap * 2)
    local threshold_w = max_buttons_w + base_gaps_w

    local primary_button_width = max_primary_w
    local nav_button_width = max_nav_w

    -- 기준 너비보다 좁을 때는 공간에 맞춰 비례 축소 (긴 텍스트 버튼에 여유 비중 배분)
    if available_width < threshold_w then
        local usable_for_buttons = math.max(JKK_Scale(120), available_width - base_gaps_w)
        local ratio = usable_for_buttons / max_buttons_w
        primary_button_width = math.max(JKK_Scale(64), max_primary_w * math.min(1.0, ratio * 1.06))
        nav_button_width = math.max(JKK_Scale(26), (usable_for_buttons - (primary_button_width * 2)) / 3)
        if usable_for_buttons < JKK_Scale(220) then
            nav_gap = math.max(JKK_Scale(2), nav_gap * ratio)
        end
    end

    -- Properties and Normalize share one line directly below the sliders.
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), JKK_Scale(8), 0)
    local checkbox_row_x = reaper.ImGui_GetCursorPosX(ctx)
    local changed_loop, new_loop = reaper.ImGui_Checkbox(ctx, "Loop", item_loop_src)
    if changed_loop then
        item_loop_src = new_loop
        JKK_IT_ApplyItemProperty("B_LOOPSRC", item_loop_src and 1.0 or 0.0)
    end
    reaper.ImGui_SameLine(ctx)
    local changed_mute, new_mute = reaper.ImGui_Checkbox(ctx, "Mute", item_mute)
    if changed_mute then
        item_mute = new_mute
        JKK_IT_ApplyItemProperty("B_MUTE", item_mute and 1.0 or 0.0)
    end
    reaper.ImGui_SameLine(ctx)
    local changed_lock, new_lock = reaper.ImGui_Checkbox(ctx, "Lock", item_lock)
    if changed_lock then
        item_lock = new_lock
        JKK_IT_ApplyItemProperty("C_LOCK", item_lock and 1.0 or 0.0)
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, checkbox_row_x + math.max(0, available_width - primary_button_width))
    if reaper.ImGui_Button(ctx, "Normalize", primary_button_width, JKK_Scale(22)) then
        reaper.Main_OnCommand(42460, 0)
    end
    reaper.ImGui_PopStyleVar(ctx, 1)

    -- Pin the Reverse / take-navigation / FX / Render Take row to the bottom
    local footer_cursor_y = reaper.ImGui_GetCursorPosY(ctx)
    local _, footer_available_y = reaper.ImGui_GetContentRegionAvail(ctx)
    local take_action_height = JKK_Scale(22)
    reaper.ImGui_SetCursorPosY(
        ctx, footer_cursor_y + math.max(0, footer_available_y - take_action_height)
    )

    local selected_item = reaper.GetSelectedMediaItem(0, 0)
    local has_multiple_takes = selected_item and reaper.CountTakes(selected_item) > 1 or false
    local selected_take = selected_item and reaper.GetActiveTake(selected_item) or nil
    local has_take_fx = selected_take and reaper.TakeFX_GetCount(selected_take) > 0 or false

    local footer_row_x = reaper.ImGui_GetCursorPosX(ctx)
    local center_group_w = (nav_button_width * 3) + (nav_gap * 2)
    local center_group_x = footer_row_x + math.max(0, (available_width - center_group_w) * 0.5)

    -- 1. 왼쪽 끝: Reverse
    PushJKKButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Reverse", primary_button_width, JKK_Scale(22)) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(41051, 0)
        reaper.Undo_EndBlock("Take Reverse", -1)
    end
    PopJKKButtonStyle(ctx)

    -- 2. 가운데 정렬: <, FX, >
    reaper.ImGui_SameLine(ctx, 0, 0)
    reaper.ImGui_SetCursorPosX(ctx, center_group_x)
    reaper.ImGui_BeginDisabled(ctx, not has_multiple_takes)
    if reaper.ImGui_Button(ctx, "<", nav_button_width, JKK_Scale(22)) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(42350, 0)
        reaper.Undo_EndBlock("Prev Take", -1)
    end
    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_SameLine(ctx, 0, nav_gap)
    PushJKKButtonStyle(ctx)
    if has_take_fx then
        if JKK_Theme then JKK_Theme.PushText(ctx, "accent") else reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF) end
    end
    if reaper.ImGui_Button(ctx, "FX", nav_button_width, JKK_Scale(22)) then
        reaper.Main_OnCommand(40638, 0)
    end
    if has_take_fx then
        if JKK_Theme then JKK_Theme.PopText(ctx) else reaper.ImGui_PopStyleColor(ctx) end
    end
    PopJKKButtonStyle(ctx)

    reaper.ImGui_SameLine(ctx, 0, nav_gap)
    reaper.ImGui_BeginDisabled(ctx, not has_multiple_takes)
    if reaper.ImGui_Button(ctx, ">", nav_button_width, JKK_Scale(22)) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(42349, 0)
        reaper.Undo_EndBlock("Next Take", -1)
    end
    reaper.ImGui_EndDisabled(ctx)

    -- 3. 오른쪽 끝(Normalize 우측 끝과 일치): Render Take
    reaper.ImGui_SameLine(ctx, 0, 0)
    reaper.ImGui_SetCursorPosX(ctx, footer_row_x + math.max(0, available_width - primary_button_width))
    PushJKKButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Render Take", primary_button_width, JKK_Scale(22)) then
        reaper.Undo_BeginBlock()
        reaper.Main_OnCommand(41999, 0)
        reaper.Undo_EndBlock("Render to New Take", -1)
    end
    PopJKKButtonStyle(ctx)
end

local function DrawItemTakeMetadata(ctx)
    -- Reduce the horizontal padding on both sides of the Take Controls / Item
    -- Info divider without changing the fixed 2:1 column ratio.
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_CellPadding(), JKK_Scale(8), 0)
    local properties_width = 0
    local metadata_flags = reaper.ImGui_TableFlags_SizingStretchProp()
        | reaper.ImGui_TableFlags_BordersInnerV()
    if reaper.ImGui_BeginTable(ctx, "TakeSettingsLayout", 2, metadata_flags) then
        reaper.ImGui_TableSetupColumn(ctx, "Take Controls", reaper.ImGui_TableColumnFlags_WidthStretch(), 2.0)
        reaper.ImGui_TableSetupColumn(ctx, "Item Info", reaper.ImGui_TableColumnFlags_WidthStretch(), 1.0)

        -- Left: Take Channel + Pitch Mode. Both right-side combo edges align.
        reaper.ImGui_TableNextColumn(ctx)
        local controls_width = GetAvailableWidth(ctx)
        local label_width = JKK_Scale(104)
        local combo_width = math.max(JKK_Scale(60), controls_width - label_width - JKK_Scale(8))

        local row_x = reaper.ImGui_GetCursorPosX(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, "Take Channel")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, row_x + label_width)
        JKK_IT_DrawChannelModeCombo(ctx, combo_width)

        row_x = reaper.ImGui_GetCursorPosX(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, "Pitch Mode")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, row_x + label_width)
        -- The lower sub-mode combo starts at the same X and has the same width
        -- as the main combo, instead of extending past the controls column.
        JKK_IT_DrawPitchModeCombo(ctx, combo_width, combo_width, true, row_x + label_width)

        -- Right: compact metadata and Properties button; no extra vertical spacer.
        reaper.ImGui_TableNextColumn(ctx)
        if JKK_IT_item_info_str1 ~= "" then reaper.ImGui_Text(ctx, JKK_IT_item_info_str1) end
        if JKK_IT_item_info_str2 ~= "" then reaper.ImGui_Text(ctx, JKK_IT_item_info_str2) end
        if JKK_IT_item_info_str3 ~= "" then reaper.ImGui_Text(ctx, JKK_IT_item_info_str3) end

        properties_width = GetAvailableWidth(ctx)
        if reaper.ImGui_Button(ctx, "Properties...", properties_width, JKK_Scale(22)) then
            reaper.Main_OnCommand(40011, 0)
        end
        reaper.ImGui_EndTable(ctx)
    end
    -- No trailing spacer: the main script measures this block and aligns its
    -- bottom with the other panels.
    reaper.ImGui_PopStyleVar(ctx, 1)
    return properties_width
end

local function GetUtilityRowLayout(ctx)
    local available_width = GetAvailableWidth(ctx)
    local label_width = JKK_Scale(104)
    local button_width = JKK_Scale(100)
    local item_spacing = JKK_Scale(8)

    -- Width slider now uses the same width as the other utility sliders.
    local slider_width = math.max(JKK_Scale(48),
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
    -- Row gap: the regular vertical ItemSpacing used by every panel, so these
    -- rows line up with the Controller rows next to them. (The old code read
    -- the X value of ItemInnerSpacing.)
    local _, inner_spacing = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    inner_spacing = inner_spacing or JKK_Scale(6)

    local button_height = JKK_Scale(22)

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

    if changed_width then
        JKK_ItemSliderUndoBegin()
        width = (spacing_mode == 0)
            and math.floor(new_width + 0.5)
            or new_width

        JKK_IT_apply_spacing_only()
    end

    JKK_ItemSliderUndoEnd(ctx, "Update Interval Width")

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

    PushJKKConfirmButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Shuffle Order", layout.button_width, button_height) then
        reaper.Undo_BeginBlock()
        JKK_IT_shuffle_item_order()
        reaper.Undo_EndBlock("Shuffle Item Order", -1)
    end
    PopJKKConfirmButtonStyle(ctx)

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

    PushJKKButtonStyle(ctx)
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

    PopJKKButtonStyle(ctx)

    -- Move cursor below the complete two-row layout.
    reaper.ImGui_SetCursorPosY(
        ctx,
        row_y + frame_height * 2 + inner_spacing * 2
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
    PushJKKConfirmButtonStyle(ctx)
    if reaper.ImGui_Button(ctx, "Split Dyn", splitter_button_width, JKK_Scale(22)) then
        showGuideBox = false
        guide_guard.pending_update = false
        guide_guard.warning_msg = nil
        guide_guard.buffer_cache = {}
        lastSelectionSignature = ""
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
    PopJKKConfirmButtonStyle(ctx)

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
    if reaper.ImGui_Button(ctx, "Split & Takes", splitter_button_width, JKK_Scale(22)) then
        showGuideBox = false
        guide_guard.pending_update = false
        guide_guard.warning_msg = nil
        guide_guard.buffer_cache = {}
        lastSelectionSignature = ""
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

    -- Live guide generation
    local changed_keep, new_keep = reaper.ImGui_Checkbox(ctx, "Keep Origin When Rendering", shouldKeepOriginal)
    if changed_keep then
        shouldKeepOriginal = new_keep
        reaper.SetExtState("PeaksAndValleys", "shouldKeepOriginal", tostring(shouldKeepOriginal), true)
    end
    reaper.ImGui_SameLine(ctx)
    local guide_changed, new_guide = reaper.ImGui_Checkbox(ctx, "Guide", showGuideBox)
    if guide_changed then
        showGuideBox = new_guide
        guide_guard.warning_msg = nil
        if not showGuideBox then
            guide_guard.pending_update = false
            guide_guard.buffer_cache = {}
            lastSelectionSignature = ""
            cleanup()
        end
    end
    if guide_guard.warning_msg then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0xFF8844FF, guide_guard.warning_msg)
    end

    -- 아이템 선택이 모두 해제되면 잔여 가이드 아이템 정리
    if showGuideBox and reaper.CountSelectedMediaItems(0) == 0 and #silenceItems > 0 then
        guide_guard.buffer_cache = {}
        lastSelectionSignature = ""
        cleanup()
    end

    if is_active_context and showGuideBox then
        local items = storeSelectedMediaItems()
        local sig_parts = {}
        local total_len = 0.0
        for _, item in ipairs(items) do
            local take = reaper.GetActiveTake(item)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            total_len = total_len + len
            sig_parts[#sig_parts + 1] = string.format("%s:%s:%.3f:%.3f", tostring(item), tostring(take), pos, len)
        end
        local current_signature = table.concat(sig_parts, "|")
        local selection_changed = (current_signature ~= lastSelectionSignature)

        if selection_changed then
            guide_guard.buffer_cache = {}
            lastSelectionSignature = current_signature
        end

        if guide_changed or selection_changed or thres_changed or dur_changed then
            guide_guard.pending_update = true
            if guide_changed or selection_changed then
                guide_guard.last_change_time = 0
            else
                guide_guard.last_change_time = reaper.time_precise()
            end
        end

        if guide_guard.pending_update
            and (reaper.time_precise() - guide_guard.last_change_time) >= guide_guard.debounce_delay then
            guide_guard.pending_update = false

            -- 방지 로직 1: 아이템 개수 또는 총 길이가 너무 길면 연산 차단 후 자동 해제
            if #items > guide_guard.max_items or total_len > guide_guard.max_total_sec then
                cleanup()
                showGuideBox = false
                guide_guard.buffer_cache = {}
                lastSelectionSignature = ""
                guide_guard.warning_msg = string.format(
                    "(Auto-off: >%d items or >%.0fs)",
                    guide_guard.max_items,
                    guide_guard.max_total_sec
                )
            else
                reaper.PreventUIRefresh(1)
                clearTemporaryItems(true)

                local total_created = 0
                local was_capped = false
                for _, item in ipairs(items) do
                    local remaining = guide_guard.max_guide_items - total_created
                    if remaining <= 0 then
                        was_capped = true
                        break
                    end
                    local take = reaper.GetActiveTake(item)
                    local track = reaper.GetMediaItem_Track(item)
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local silences = getSilenceTime(item, take, true)
                    if silences then
                        local created, capped = createTemporaryItems(track, silences, item_pos, remaining)
                        total_created = total_created + created
                        if capped then
                            was_capped = true
                            break
                        end
                    end
                end

                reaper.PreventUIRefresh(-1)
                reaper.UpdateArrange()

                -- 방지 로직 2: 가이드 아이템이 최대 생성 개수에 도달하면 안내 표시
                if was_capped then
                    guide_guard.warning_msg = string.format("(Max %d guides)", guide_guard.max_guide_items)
                else
                    guide_guard.warning_msg = nil
                end
            end
        end
    end
end

local function DrawGridSplitter(ctx, layout)
    layout = layout or GetUtilityRowLayout(ctx)

    -- 선택이 해제되거나 다른 아이템으로 변경되면 이전 Live 세션 초기화
    if grid_live.output_guids then
        local cur_guids = GetSelectedItemGUIDList()
        if not AreGUIDListsEqual(cur_guids, grid_live.output_guids) then
            ResetLiveGridSession()
        end
    end

    local row_x = reaper.ImGui_GetCursorPosX(ctx)
    local frame_h = reaper.ImGui_GetFrameHeight(ctx)
    local inner_x = select(1, reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemInnerSpacing())) or JKK_Scale(4)
    local live_text_w = select(1, reaper.ImGui_CalcTextSize(ctx, "Live")) or JKK_Scale(24)
    local live_chk_w = frame_h + inner_x + live_text_w
    local slice_slider_w = math.max(JKK_Scale(36), layout.slider_width - live_chk_w - layout.item_spacing)

    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, "Slice Interval")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, row_x + layout.label_width)
    reaper.ImGui_SetNextItemWidth(ctx, slice_slider_w)

    local slider_changed = false
    if grid_live.mode == 0 then
        local changed_slice, new_slice = reaper.ImGui_SliderInt(ctx, "##GridSliceCount", grid_slice_n, 1, 10, "%d grid")
        if changed_slice then
            grid_slice_n = new_slice
            slider_changed = true
        end
    else
        local changed_sec, new_sec = reaper.ImGui_SliderDouble(ctx, "##GridSliceSec", grid_live.sec, 0.01, max_sec, "%.2fs")
        if changed_sec then
            grid_live.sec = new_sec
            slider_changed = true
        end
    end

    -- 우클릭 시 Grid <-> Seconds 단위 전환
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        grid_live.mode = (grid_live.mode == 0) and 1 or 0
        if grid_live.enabled then
            slider_changed = true
        end
    end

    if slider_changed and grid_live.enabled then
        ExecuteLiveGridSplit()
    end

    if reaper.ImGui_IsItemHovered(ctx) then
        local mode_name = (grid_live.mode == 0) and "Grid" or "Seconds"
        reaper.ImGui_SetTooltip(
            ctx,
            "Current: " .. mode_name .. "\nRight-click to toggle (Grid <-> Sec)"
        )
    end

    -- 슬라이더와 Split Grid 버튼 사이 Live 체크박스
    reaper.ImGui_SameLine(ctx, 0, layout.item_spacing)
    local changed_live, new_live = reaper.ImGui_Checkbox(ctx, "Live", grid_live.enabled)
    if changed_live then
        grid_live.enabled = new_live
        ResetLiveGridSession()
        if grid_live.enabled then
            ExecuteLiveGridSplit()
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Slice dynamically while adjusting the slider")
    end

    reaper.ImGui_SameLine(ctx, 0, layout.item_spacing)
    if grid_live.enabled then
        local can_undo_live = (grid_live.snapshot ~= nil)
        reaper.ImGui_BeginDisabled(ctx, not can_undo_live)
        PushJKKButtonStyle(ctx)
        if reaper.ImGui_Button(ctx, "Undo", layout.button_width, JKK_Scale(22)) then
            reaper.PreventUIRefresh(1)
            reaper.Undo_BeginBlock()
            RestoreLiveGridSnapshot()
            reaper.Undo_EndBlock("Undo Live Grid Split", -1)
            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
            ResetLiveGridSession()
        end
        PopJKKButtonStyle(ctx)
        reaper.ImGui_EndDisabled(ctx)
        if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then
            reaper.ImGui_SetTooltip(ctx, "Restore items to their state before Live Grid Split")
        end
    else
        PushJKKConfirmButtonStyle(ctx)
        if reaper.ImGui_Button(ctx, "Split Grid", layout.button_width, JKK_Scale(22)) then
            ResetLiveGridSession()
            reaper.Undo_BeginBlock()
            GridSplitMain()
            reaper.Undo_EndBlock("Grid Split Items", -1)
        end
        PopJKKConfirmButtonStyle(ctx)
    end
end

function JKK_ItemTool_Draw(ctx, prev_count, current_count, active_context, track_module)
    local selected_item_count = reaper.CountSelectedMediaItems(0)
    active_context = active_context or (selected_item_count > 0 and "item" or "none")

    if active_context == "item" then
        -- When the selection becomes empty, keep the last read values visible
        -- underneath the parent panel's disabled state instead of resetting them.
        if selected_item_count > 0 then
            JKK_IT_SyncSelectionData(ctx)
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
        local general_state_changed = JKK_IT_has_changed()
        if general_state_changed then
            JKK_IT_update_prev()
            SaveSettings()
        end
    end
end

function JKK_ItemTool_DrawEditingUtilities(ctx, is_active_context)
    local layout = GetUtilityRowLayout(ctx)

    -- Upper block (top-aligned): Arrange Width.
    DrawIntervalWidthTools(ctx, layout)

    -- Lower block (bottom-aligned): all splitting tools (Slice Interval,
    -- Threshold, Min Length). The separator sits between Arrange Width and
    -- Slice Interval; the main script lines it up with the other panels.
    local function DrawLower()
        DrawGridSplitter(ctx, layout)
        reaper.ImGui_Spacing(ctx)
        DrawDynamicItemSplitter(
            ctx,
            reaper.CountSelectedMediaItems(0),
            is_active_context == true,
            layout
        )
    end
    if JKK_DrawLowerBlock then
        JKK_DrawLowerBlock(ctx, "D", DrawLower)
    else
        reaper.ImGui_Separator(ctx)
        DrawLower()
    end
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

-- FIX: lets the main script remove the red Guide preview items when it closes;
-- previously they stayed in the project.
local function JKK_ItemTool_Cleanup()
    clearTemporaryItems()
    reaper.UpdateArrange()
end

return {
    JKK_ItemTool_Cleanup = JKK_ItemTool_Cleanup,
    JKK_ItemTool_Draw = JKK_ItemTool_Draw,
    JKK_ItemTool_DrawUtilities = JKK_ItemTool_DrawUtilities,
    JKK_ItemTool_DrawEditingUtilities = JKK_ItemTool_DrawEditingUtilities,
    JKK_ItemTool_DrawMetadata = JKK_ItemTool_DrawMetadata,
}