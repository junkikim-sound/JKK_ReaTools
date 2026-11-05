--========================================================
-- @title JKK_Loopmaker
-- @author Junki Kim
-- @version 1.0.1
--========================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'
local RPR = reaper

-- ==========================================
-- 1. 테마(JKK_Theme.lua) 동적 로드
-- ==========================================
local script_path = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or ""
local theme_paths = {
    script_path .. "Modules/JKK_Theme.lua",
    script_path .. "../Modules/JKK_Theme.lua",
    RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Theme.lua"
}

local ApplyTheme = function(ctx) return 0, 0 end
for _, tpath in ipairs(theme_paths) do
    if RPR.file_exists(tpath) then
        local status, result = pcall(dofile, tpath)
        if status and type(result) == "table" and result.ApplyTheme then
            ApplyTheme = result.ApplyTheme
            break
        end
    end
end

-- ==========================================
-- 2. 전역 상태 및 페이드 커브 데이터
-- ==========================================
local ctx = ImGui.CreateContext('JKK_Loopmaker')
local font = ImGui.CreateFont('sans-serif', 14)
local font_btn = ImGui.CreateFont('sans-serif', 18)
ImGui.Attach(ctx, font)
ImGui.Attach(ctx, font_btn)

-- 저장된 설정값 불러오기 (기본값 설정)
local cfg = {
    loop_len = tonumber(reaper.GetExtState("JKK_Loopmaker", "loop_len")) or 5.0,
    fade_len = tonumber(reaper.GetExtState("JKK_Loopmaker", "fade_len")) or 1.0,
    src_mode = tonumber(reaper.GetExtState("JKK_Loopmaker", "src_mode")) or 1,
    glue_res = reaper.GetExtState("JKK_Loopmaker", "glue_res") ~= "false",
    shape_idx = tonumber(reaper.GetExtState("JKK_Loopmaker", "shape_idx")) or 5
}

local fade_shape_names = {
    "Linear",
    "Inverted quadratic",
    "Quadratic",
    "Inverted quartic",
    "Quartic",
    "Cosine S-curve",
    "Quartic S-curve"
}

local is_session_active = false
local is_valid = false
local err_msg = ""
local target_items = {}
local original_solos = {}
local original_env = {}
local preview_tracks = {}

-- ==========================================
-- 3. 페이드 커브 UI 드로잉 엔진
-- ==========================================

local function EvaluateFadePoint(shape, t)
    t = math.max(0, math.min(1, t))
    if shape == 0 then return t
    elseif shape == 1 then return 1 - (1 - t) ^ 2
    elseif shape == 2 then return t ^ 2
    elseif shape == 3 then return 1 - (1 - t) ^ 4
    elseif shape == 4 then return t ^ 4
    elseif shape == 5 then return (1 - math.cos(math.pi * t)) * 0.5
    elseif shape == 6 then return (t * (2 - t)) ^ 2
    end
    return t
end

local function DrawFadeCurveButton(ctx, str_id, shape_idx, is_fade_out)
    local btn_h = ImGui.GetFrameHeight(ctx)
    local btn_w = 38
    local clicked = ImGui.Button(ctx, "##" .. str_id, btn_w, btn_h)
    local right_clicked = ImGui.IsItemClicked(ctx, 1)
    
    local p_min_x, p_min_y = ImGui.GetItemRectMin(ctx)
    local p_max_x, p_max_y = ImGui.GetItemRectMax(ctx)
    local dl = ImGui.GetWindowDrawList(ctx)
    
    local pad_x, pad_y = 6, 5
    local x0, x1 = p_min_x + pad_x, p_max_x - pad_x
    local y_top, y_bot = p_min_y + pad_y, p_max_y - pad_y
    local w, h = x1 - x0, y_bot - y_top
    
    local color = 0x068FC3FF
    local steps = 16
    
    for i = 0, steps - 1 do
        local t1 = i / steps
        local t2 = (i + 1) / steps
        local val1 = EvaluateFadePoint(shape_idx, is_fade_out and (1 - t1) or t1)
        local val2 = EvaluateFadePoint(shape_idx, is_fade_out and (1 - t2) or t2)
        ImGui.DrawList_AddLine(dl, x0 + t1 * w, y_bot - val1 * h, x0 + t2 * w, y_bot - val2 * h, color, 2.0)
    end
    return clicked, right_clicked
end

local function DrawFadeCurveSelectorPopup(ctx, popup_id, current_shape, is_fade_out)
    local selected_shape = nil
    if ImGui.BeginPopup(ctx, popup_id) then
        ImGui.TextColored(ctx, 0x808080FF, "Select Curve Shape:")
        ImGui.Spacing(ctx)
        local cols = 3
        for idx = 0, 6 do
            ImGui.PushID(ctx, idx)
            local is_active = (current_shape == idx)
            if is_active then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x068FC388)
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x068FC3FF)
            end
            
            local btn_w, btn_h = 44, 32
            local clicked = ImGui.Button(ctx, "##curve_btn", btn_w, btn_h)
            local p_min_x, p_min_y = ImGui.GetItemRectMin(ctx)
            local p_max_x, p_max_y = ImGui.GetItemRectMax(ctx)
            local dl = ImGui.GetWindowDrawList(ctx)
            local pad_x, pad_y = 6, 5
            local x0, x1 = p_min_x + pad_x, p_max_x - pad_x
            local y_top, y_bot = p_min_y + pad_y, p_max_y - pad_y
            local w, h = x1 - x0, y_bot - y_top
            local line_col = is_active and 0xFFFFFFFF or 0xEDEDEDFF
            
            local steps = 16
            for s = 0, steps - 1 do
                local t1 = s / steps
                local t2 = (s + 1) / steps
                local val1 = EvaluateFadePoint(idx, is_fade_out and (1 - t1) or t1)
                local val2 = EvaluateFadePoint(idx, is_fade_out and (1 - t2) or t2)
                ImGui.DrawList_AddLine(dl, x0 + t1 * w, y_bot - val1 * h, x0 + t2 * w, y_bot - val2 * h, line_col, 2.0)
            end
            
            if is_active then ImGui.PopStyleColor(ctx, 2) end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, fade_shape_names[idx + 1]) end
            if clicked then selected_shape = idx; ImGui.CloseCurrentPopup(ctx) end
            
            ImGui.PopID(ctx)
            if (idx + 1) % cols ~= 0 then ImGui.SameLine(ctx) end
        end
        ImGui.EndPopup(ctx)
    end
    return selected_shape
end

-- ==========================================
-- 4. 유틸리티 및 오디오 엔진
-- ==========================================

-- 설정값 즉시 영구 저장 함수
function SaveSettings()
    reaper.SetExtState("JKK_Loopmaker", "loop_len", tostring(cfg.loop_len), true)
    reaper.SetExtState("JKK_Loopmaker", "fade_len", tostring(cfg.fade_len), true)
    reaper.SetExtState("JKK_Loopmaker", "src_mode", tostring(cfg.src_mode), true)
    reaper.SetExtState("JKK_Loopmaker", "glue_res", tostring(cfg.glue_res), true)
    reaper.SetExtState("JKK_Loopmaker", "shape_idx", tostring(cfg.shape_idx), true)
end

function GetSelectedOriginalItems()
    local preview_track_set = {}
    for _, tr in ipairs(preview_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            preview_track_set[tr] = true
        end
    end

    local items = {}
    local item_count = reaper.CountSelectedMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        if not preview_track_set[track] then
            table.insert(items, item)
        end
    end
    return items
end

function InitialValidate()
    local orig_items = GetSelectedOriginalItems()
    if #orig_items == 0 then return false, "No audio items selected.", {} end

    local track_map = {}
    local valid_items = {}
    for _, item in ipairs(orig_items) do
        local take = reaper.GetActiveTake(item)
        if not take or reaper.TakeIsMIDI(take) then
            return false, "MIDI items are not supported. Please select audio items.", {}
        end

        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if len < 3.0 then
            return false, string.format("Includes item(s) under 3 seconds (min 3s, current: %.2fs).", len), {}
        end

        local track = reaper.GetMediaItem_Track(item)
        if track_map[track] then
            return false, "Select only one item per track, or glue them first.", {}
        end
        track_map[track] = true
        table.insert(valid_items, item)
    end
    return true, "", valid_items
end

function FindZeroCrossing(item, approx_pos)
    local take = reaper.GetActiveTake(item)
    if not take then return approx_pos end
    local accessor = reaper.CreateTakeAudioAccessor(take)
    local srate = 44100
    local window = 0.04
    local start_time = approx_pos - (window / 2)
    local sample_count = math.floor(window * srate)
    local buffer = reaper.new_array(sample_count)
    
    reaper.GetAudioAccessorSamples(accessor, srate, 1, start_time, sample_count, buffer)
    reaper.DestroyAudioAccessor(accessor)
    
    local tbl = buffer.table()
    local closest_to_zero = approx_pos
    local min_val = 9999
    
    for i = 1, #tbl - 1 do
        if (tbl[i] <= 0 and tbl[i+1] >= 0) or (tbl[i] >= 0 and tbl[i+1] <= 0) then
            local abs_val = math.abs(tbl[i])
            if abs_val < min_val then
                min_val = abs_val
                closest_to_zero = start_time + (i / srate)
            end
        end
    end
    return closest_to_zero
end

function CheckAndSyncSelection()
    local cur_valid, cur_err, cur_items = InitialValidate()
    
    if not is_session_active then
        if cur_valid then
            InitSession(cur_items)
        else
            is_valid = false
            err_msg = cur_err
        end
        return
    end

    if is_session_active and not cur_valid then
        CancelAndRevert()
        is_session_active = false
        is_valid = false
        err_msg = cur_err
        return
    end

    if is_session_active and cur_valid then
        local selection_changed = false
        if #cur_items ~= #target_items then
            selection_changed = true
        else
            for i, it in ipairs(cur_items) do
                if it ~= target_items[i] then
                    selection_changed = true
                    break
                end
            end
        end

        if selection_changed then
            CancelAndRevert()
            InitSession(cur_items)
        end
    end
end

function InitSession(items)
    is_valid = true
    err_msg = ""
    target_items = items
    original_solos = {}
    preview_tracks = {}

    original_env.cursor = reaper.GetCursorPosition()
    original_env.ts_start, original_env.ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    original_env.loop = reaper.GetToggleCommandState(1068) == 1

    reaper.PreventUIRefresh(1)
    
    for i, orig_item in ipairs(target_items) do
        local orig_track = reaper.GetMediaItem_Track(orig_item)
        original_solos[orig_track] = reaper.GetMediaTrackInfo_Value(orig_track, "I_SOLO")
        
        local track_idx = reaper.CSurf_TrackToID(orig_track, false)
        reaper.InsertTrackAtIndex(track_idx, false)
        local prev_track = reaper.GetTrack(0, track_idx)
        table.insert(preview_tracks, prev_track)
        
        reaper.SetMediaTrackInfo_Value(prev_track, "I_SOLO", 2)
    end

    reaper.PreventUIRefresh(-1)
    is_session_active = true
    UpdatePreview("end")
end

function UpdatePreview(cursor_mode)
    cursor_mode = cursor_mode or "end"
    if not is_valid or not is_session_active then return end

    reaper.PreventUIRefresh(1)
    
    local first_start = 0
    local first_end = 0
    local first_xfade = 0

    for i, orig_item in ipairs(target_items) do
        local prev_track = preview_tracks[i]
        
        while reaper.CountTrackMediaItems(prev_track) > 0 do
            local item_to_del = reaper.GetTrackMediaItem(prev_track, 0)
            reaper.DeleteTrackMediaItem(prev_track, item_to_del)
        end
        
        local _, chunk = reaper.GetItemStateChunk(orig_item, "", false)
        local work_item = reaper.AddMediaItemToTrack(prev_track)
        reaper.SetItemStateChunk(work_item, chunk, false)
        
        local start_p, end_p, xfade_p = ProcessItemPreview(work_item)
        
        if first_start == 0 then
            first_start = start_p
            first_end = end_p
            first_xfade = xfade_p
        end
    end

    if first_end > 0 then
        reaper.GetSet_LoopTimeRange(true, false, first_start, first_end, false)
        
        local start_cursor = math.max(first_start, first_end - 1.0)
        if cursor_mode == "xfade" then
            start_cursor = math.max(first_start, first_xfade - 1.0)
        end
        
        reaper.SetEditCurPos(start_cursor, false, false)
        if reaper.GetToggleCommandState(1068) == 0 then 
            reaper.Main_OnCommand(1068, 0)
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

function ProcessItemPreview(item)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    
    local target_raw_len = math.min(item_len, cfg.loop_len + cfg.fade_len)
    
    if item_len > target_raw_len then
        local right_tail = reaper.SplitMediaItem(item, item_pos + target_raw_len)
        if right_tail then 
            reaper.SetMediaItemSelected(right_tail, false)
            reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), right_tail) 
        end
    end

    target_raw_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local mid_pos = item_pos + (target_raw_len / 2)
    mid_pos = FindZeroCrossing(item, mid_pos)
    
    if mid_pos <= item_pos + 0.1 or mid_pos >= item_pos + target_raw_len - 0.1 then
        mid_pos = item_pos + (target_raw_len / 2)
    end
    
    local item_b = reaper.SplitMediaItem(item, mid_pos) -- Tail
    local item_a = item -- Head

    if item_b then reaper.SetMediaItemSelected(item_b, false) end
    if item_a then reaper.SetMediaItemSelected(item_a, false) end

    local len_a = mid_pos - item_pos
    local len_b = target_raw_len - len_a
    local actual_fade = math.min(cfg.fade_len, len_a * 0.8, len_b * 0.8)

    reaper.SetMediaItemInfo_Value(item_b, "D_POSITION", item_pos)
    local new_a_pos = item_pos + len_b - actual_fade
    reaper.SetMediaItemInfo_Value(item_a, "D_POSITION", new_a_pos)

    reaper.SetMediaItemInfo_Value(item_b, "D_FADEINLEN_AUTO", 0)
    reaper.SetMediaItemInfo_Value(item_b, "D_FADEOUTLEN_AUTO", 0)
    reaper.SetMediaItemInfo_Value(item_a, "D_FADEINLEN_AUTO", 0)
    reaper.SetMediaItemInfo_Value(item_a, "D_FADEOUTLEN_AUTO", 0)

    reaper.SetMediaItemInfo_Value(item_b, "C_BEHAVIOR", 1)
    reaper.SetMediaItemInfo_Value(item_a, "C_BEHAVIOR", 1)

    reaper.SetMediaItemInfo_Value(item_b, "D_FADEINLEN", 0)
    reaper.SetMediaItemInfo_Value(item_b, "D_FADEOUTLEN", actual_fade)
    reaper.SetMediaItemInfo_Value(item_a, "D_FADEINLEN", actual_fade)
    reaper.SetMediaItemInfo_Value(item_a, "D_FADEOUTLEN", 0)

    reaper.SetMediaItemInfo_Value(item_b, "C_FADEOUTSHAPE", cfg.shape_idx)
    reaper.SetMediaItemInfo_Value(item_a, "C_FADEINSHAPE", cfg.shape_idx)
    reaper.SetMediaItemInfo_Value(item_b, "C_FADEOUTDIR", 0)
    reaper.SetMediaItemInfo_Value(item_a, "C_FADEINDIR", 0)

    reaper.UpdateItemInProject(item_b)
    reaper.UpdateItemInProject(item_a)

    return item_pos, new_a_pos + len_a, new_a_pos
end

function ApplyAndClose()
    if not is_valid or not is_session_active then return end
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    for i, orig_item in ipairs(target_items) do
        local prev_track = preview_tracks[i]
        local orig_track = reaper.GetMediaItem_Track(orig_item)
        
        if cfg.glue_res then
            reaper.Main_OnCommand(40289, 0)
            local item_cnt = reaper.CountTrackMediaItems(prev_track)
            for k = 0, item_cnt - 1 do
                reaper.SetMediaItemSelected(reaper.GetTrackMediaItem(prev_track, k), true)
            end
            reaper.Main_OnCommand(41588, 0) -- Glue
            local glued = reaper.GetSelectedMediaItem(0, 0)
            if glued then
                reaper.SetMediaItemInfo_Value(glued, "B_LOOPSRC", 1)
            end
        end

        if cfg.src_mode == 0 then -- Replace
            local item_cnt = reaper.CountTrackMediaItems(prev_track)
            for k = item_cnt - 1, 0, -1 do
                local it = reaper.GetTrackMediaItem(prev_track, k)
                reaper.MoveMediaItemToTrack(it, orig_track)
            end
            reaper.DeleteTrackMediaItem(orig_track, orig_item)
            reaper.DeleteTrack(prev_track)
        elseif cfg.src_mode == 1 then -- New Track & Mute Original
            reaper.SetMediaItemInfo_Value(orig_item, "B_MUTE", 1)
        end
    end
    
    for tr, solo in pairs(original_solos) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", solo)
        end
    end
    for _, tr in ipairs(preview_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
        end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Create Seamless Loop", -1)
    SaveSettings()
    is_session_active = false
end

function CancelAndRevert()
    reaper.PreventUIRefresh(1)
    reaper.Main_OnCommand(1016, 0)
    
    for _, tr in ipairs(preview_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            reaper.DeleteTrack(tr)
        end
    end
    preview_tracks = {}
    
    for tr, solo in pairs(original_solos) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", solo) end
    end
    if original_env.ts_start then
        reaper.GetSet_LoopTimeRange(true, false, original_env.ts_start, original_env.ts_end, false)
        reaper.SetEditCurPos(original_env.cursor, false, false)
        if not original_env.loop and reaper.GetToggleCommandState(1068) == 1 then
            reaper.Main_OnCommand(1068, 0)
        end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    is_session_active = false
end

-- ==========================================
-- 5. ReaImGui 메인 렌더링 루프
-- ==========================================

function Loop()
    CheckAndSyncSelection()

    local style_pop_count, color_pop_count = ApplyTheme(ctx)

    ImGui.PushFont(ctx, font)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 10, 10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 14)

    -- 창 크기 제약 조건 및 최초 창 크기 변경
    ImGui.SetNextWindowSizeConstraints(ctx, 500, 300, 9999, 9999)
    ImGui.SetNextWindowSize(ctx, 550, 350, ImGui.Cond_FirstUseEver)
    
    local window_flags = ImGui.WindowFlags_NoCollapse
    local visible, open = ImGui.Begin(ctx, 'JKK_Loopmaker', true, window_flags)
    
    if visible then
        local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then open = false end
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Space) then reaper.Main_OnCommand(40044, 0) end
        if is_valid and enter_pressed then 
            ApplyAndClose() 
            open = false 
        end

        local label_w = 90
        
        -- 1. Loop Length 
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.Text(ctx, "Loop Length")
        ImGui.SameLine(ctx, label_w)
        local avail_w = ImGui.GetContentRegionAvail(ctx)
        ImGui.SetNextItemWidth(ctx, avail_w)
        local changed_len, new_len = ImGui.SliderDouble(ctx, "##loop_len", cfg.loop_len, 3.0, 30.0, "%.1f s")
        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then new_len = 5.0; changed_len = true end
        if changed_len then 
            cfg.loop_len = new_len 
            SaveSettings()
        end
        if ImGui.IsItemDeactivatedAfterEdit(ctx) or (changed_len and ImGui.IsMouseClicked(ctx, 1)) then UpdatePreview("end") end
        
        -- 2. Crossfade 
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.Text(ctx, "Crossfade")
        ImGui.SameLine(ctx, label_w)
        
        local btn_w = 38
        local spacing = 10
        local fade_slider_w = avail_w - btn_w - spacing
        
        ImGui.SetNextItemWidth(ctx, fade_slider_w)
        local changed_fade, new_fade = ImGui.SliderDouble(ctx, "##fade_len", cfg.fade_len, 0.2, 5.0, "%.2f s")
        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then new_fade = 1.0; changed_fade = true end
        if changed_fade then 
            cfg.fade_len = new_fade 
            SaveSettings()
        end
        if ImGui.IsItemDeactivatedAfterEdit(ctx) or (changed_fade and ImGui.IsMouseClicked(ctx, 1)) then UpdatePreview("xfade") end
        
        ImGui.SameLine(ctx)
        local btn_clicked, btn_rclicked = DrawFadeCurveButton(ctx, "xfade_shape_btn", cfg.shape_idx, false)
        if btn_clicked then
            cfg.shape_idx = (cfg.shape_idx + 1) % 7
            SaveSettings()
            UpdatePreview("xfade")
        end
        if btn_rclicked then
            ImGui.OpenPopup(ctx, "xfade_shape_popup")
        end
        
        local new_shape = DrawFadeCurveSelectorPopup(ctx, "xfade_shape_popup", cfg.shape_idx, false)
        if new_shape then
            cfg.shape_idx = new_shape
            SaveSettings()
            UpdatePreview("xfade")
        end
        
        -- 3. Options UI
        local modes = {"Replace in place", "Create new track & Mute original", "Create new track & Keep original"}
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.Text(ctx, "Handling")
        ImGui.SameLine(ctx, label_w)
        ImGui.SetNextItemWidth(ctx, avail_w)
        if ImGui.BeginCombo(ctx, "##src_handling", modes[cfg.src_mode + 1]) then
            for i, mode in ipairs(modes) do
                if ImGui.Selectable(ctx, mode, cfg.src_mode == (i-1)) then 
                    cfg.src_mode = i - 1 
                    SaveSettings()
                end
            end
            ImGui.EndCombo(ctx)
        end

        ImGui.SetCursorPosX(ctx, label_w)
        local changed_glue, new_glue = ImGui.Checkbox(ctx, "Glue final result into single item", cfg.glue_res)
        if changed_glue then 
            cfg.glue_res = new_glue 
            SaveSettings()
        end
        
        -- ==========================================
        -- 4. 하단 고정 영역 (경고문 + Make Loop 버튼)
        -- ==========================================
        local btn_height = 45
        local bottom_h = btn_height
        if not is_valid then
            bottom_h = bottom_h + ImGui.GetTextLineHeight(ctx) + spacing
        end
        
        local _, c_avail_h = ImGui.GetContentRegionAvail(ctx)
        if c_avail_h > bottom_h then
            ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + c_avail_h - bottom_h)
        end
        
        if not is_valid then
            ImGui.TextColored(ctx, 0xFFFF00FF, "[!] " .. err_msg)
            ImGui.BeginDisabled(ctx, true)
        end
        
        ImGui.PushFont(ctx, font_btn)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x24866FFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x2A9A80FF)
        
        if ImGui.Button(ctx, " Make Loop ", -1, btn_height) then
            ApplyAndClose()
            open = false
        end
        
        ImGui.PopStyleColor(ctx, 2)
        ImGui.PopFont(ctx)
        
        if not is_valid then ImGui.EndDisabled(ctx) end

        ImGui.End(ctx)
    end

    ImGui.PopStyleVar(ctx, 3)
    ImGui.PopFont(ctx)

    if color_pop_count > 0 then ImGui.PopStyleColor(ctx, color_pop_count) end
    if style_pop_count > 0 then ImGui.PopStyleVar(ctx, style_pop_count) end

    if open then
        reaper.defer(Loop)
    else
        SaveSettings()
        if is_session_active and not enter_pressed then 
            CancelAndRevert() 
        end
    end
end

reaper.defer(Loop)