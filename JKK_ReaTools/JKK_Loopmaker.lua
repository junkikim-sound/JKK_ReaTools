--========================================================
-- @title JKK_Loopmaker
-- @author Junki Kim
-- @version 1.2.7
--========================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'
local RPR = reaper

-- ==========================================
-- 1. 테마(JKK_Theme.lua) 동적 로드
-- ==========================================
local script_path = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or ""
local theme_paths = {
    script_path .. "Modules/JKK_Theme_Core.lua",
    script_path .. "../Modules/JKK_Theme_Core.lua",
    RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Theme_Core.lua"
}
local sel_paths = {
    script_path .. "Modules/JKK_SelectionManager.lua",
    script_path .. "../Modules/JKK_SelectionManager.lua",
    RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_SelectionManager.lua"
}
local sel_mgr = _G.JKK_SelectionManager
for _, spath in ipairs(sel_paths) do
    if RPR.file_exists(spath) then
        local status, result = pcall(dofile, spath)
        if status and type(result) == "table" then
            sel_mgr = result
            break
        end
    end
end

local theme = _G.JKK_Theme or {}
for _, tpath in ipairs(theme_paths) do
    if RPR.file_exists(tpath) then
        local status, result = pcall(dofile, tpath)
        if status and type(result) == "table" and result.ApplyTheme then
            theme = result
            break
        end
    end
end

local ApplyTheme = theme.ApplyTheme or function(ctx) return 0, 0 end
local PushButton = theme.PushButton or function(ctx, kind)
    if kind == "confirm" then
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x24866FFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x2A9A80FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x1B6B58FF)
    elseif kind == "highlight" then
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xFFEA70FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xEFE060FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xDFD050FF)
    else
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x233C4FFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x435665FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x042239FF)
    end
end
local PopButton = theme.PopButton or function(ctx)
    ImGui.PopStyleColor(ctx, 3)
end
local GetColor = theme.GetColor or function(role)
    if role == "accent" or role == "text_accent" then return 0xE3DB8EFF end
    if role == "slider" or role == "accent_main" then return 0x068FC3FF end
    if role == "btn_primary" then return 0x233C4FFF end
    return 0xEDEDEDFF
end

-- ==========================================
-- 2. 전역 상태 및 파라미터 (Persistence)
-- ==========================================
local ctx = ImGui.CreateContext('JKK_Loopmaker')
local font = ImGui.CreateFont('sans-serif', 14)
local font_btn = ImGui.CreateFont('sans-serif', 18)
ImGui.Attach(ctx, font)
ImGui.Attach(ctx, font_btn)

local cfg = {
    active_tab = tonumber(reaper.GetExtState("JKK_Loopmaker", "active_tab")) or 0,
    preview_vol = tonumber(reaper.GetExtState("JKK_Loopmaker", "preview_vol")) or 0.0,
    src_mode = tonumber(reaper.GetExtState("JKK_Loopmaker", "src_mode")) or 1,
    
    -- Tab 1: Loopmaker
    loop_len = tonumber(reaper.GetExtState("JKK_Loopmaker", "loop_len")) or 5.0,
    fade_len = tonumber(reaper.GetExtState("JKK_Loopmaker", "fade_len")) or 1.0,
    glue_res = reaper.GetExtState("JKK_Loopmaker", "glue_res") ~= "false",
    shape_idx = 1,
    
    -- Tab 2: Sequencer
    seq_len = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_len")) or 5.0,
    seq_int_mode = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_int_mode")) or 0,
    seq_int_sec = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_int_sec")) or 0.25,
    seq_int_grid = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_int_grid")) or 4,
    seq_int_rpm = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_int_rpm")) or 300,
    seq_poly = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_poly")) or 1,
    seq_rel = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_rel")) or 0.0,
    seq_pitch = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_pitch")) or 0.0,
    seq_seed = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_seed")) or 1,
    seq_rand_mode = tonumber(reaper.GetExtState("JKK_Loopmaker", "seq_rand_mode")) or 0,
    seq_no_consec = reaper.GetExtState("JKK_Loopmaker", "seq_no_consec") == "true"
}

local fade_shape_names = {
    "Linear", "Inverted quadratic", "Quadratic", 
    "Inverted quartic", "Quartic", "Cosine S-curve (Equal Power)", "Quartic S-curve"
}
local seq_int_formats = {"%.2f s", "%d Grid", "%d RPM"}
local rand_modes = {"Repeat Cycle", "True Random"}

local is_session_active = false
local is_valid = false
local err_msg = ""
local target_items = {}
local target_meta = {} 
local original_solos = {}
local original_env = {}
local preview_folder_track = nil
local preview_tracks = {}

-- ==========================================
-- 3. 커브 드로잉 유틸리티
-- ==========================================
local function EvaluateFadePoint(shape, t)
    t = math.max(0, math.min(1, t))
    if shape == 0 then return t
    elseif shape == 1 then return 1 - (1 - t) ^ 2
    elseif shape == 2 then return t ^ 2
    elseif shape == 3 then return 1 - (1 - t) ^ 4
    elseif shape == 4 then return t ^ 4
    elseif shape == 5 then return (1 - math.cos(math.pi * t)) * 0.5
    elseif shape == 6 then return (t * (2 - t)) ^ 2 end
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
    local pad_x, pad_y = 6, 4
    local x0, x1 = p_min_x + pad_x, p_max_x - pad_x
    local y_top, y_bot = p_min_y + pad_y, p_max_y - pad_y
    local w, h = x1 - x0, y_bot - y_top
    local color = GetColor("slider")
    local steps = 16
    for i = 0, steps - 1 do
        local t1, t2 = i / steps, (i + 1) / steps
        local val1 = EvaluateFadePoint(shape_idx, is_fade_out and (1 - t1) or t1)
        local val2 = EvaluateFadePoint(shape_idx, is_fade_out and (1 - t2) or t2)
        ImGui.DrawList_AddLine(dl, x0 + t1 * w, y_bot - val1 * h, x0 + t2 * w, y_bot - val2 * h, color, 2.0)
    end
    return clicked, right_clicked
end

local function DrawFadeCurveSelectorPopup(ctx, popup_id, current_shape, is_fade_out)
    local selected_shape = nil
    if ImGui.BeginPopup(ctx, popup_id) then
        ImGui.TextDisabled(ctx, "Select Curve Shape:")
        ImGui.Spacing(ctx)
        local slider_col = GetColor("slider")
        local slider_bg_col = (slider_col & 0xFFFFFF00) | 0x88
        for idx = 0, 6 do
            ImGui.PushID(ctx, idx)
            local is_active = (current_shape == idx)
            if is_active then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, slider_bg_col)
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, slider_col)
            end
            local clicked = ImGui.Button(ctx, "##curve_btn", 44, 32)
            local p_min_x, p_min_y = ImGui.GetItemRectMin(ctx)
            local p_max_x, p_max_y = ImGui.GetItemRectMax(ctx)
            local dl = ImGui.GetWindowDrawList(ctx)
            local x0, x1 = p_min_x + 6, p_max_x - 6
            local y_top, y_bot = p_min_y + 5, p_max_y - 5
            local w, h = x1 - x0, y_bot - y_top
            local line_col = GetColor("text_main")
            for s = 0, 15 do
                local t1, t2 = s / 16, (s + 1) / 16
                local val1 = EvaluateFadePoint(idx, is_fade_out and (1 - t1) or t1)
                local val2 = EvaluateFadePoint(idx, is_fade_out and (1 - t2) or t2)
                ImGui.DrawList_AddLine(dl, x0 + t1 * w, y_bot - val1 * h, x0 + t2 * w, y_bot - val2 * h, line_col, 2.0)
            end
            if is_active then ImGui.PopStyleColor(ctx, 2) end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, fade_shape_names[idx + 1]) end
            if clicked then selected_shape = idx; ImGui.CloseCurrentPopup(ctx) end
            ImGui.PopID(ctx)
            if (idx + 1) % 3 ~= 0 then ImGui.SameLine(ctx) end
        end
        ImGui.EndPopup(ctx)
    end
    return selected_shape
end

-- ==========================================
-- 4. 시스템 엔진 유틸리티
-- ==========================================
function SaveSettings()
    reaper.SetExtState("JKK_Loopmaker", "active_tab", tostring(cfg.active_tab), true)
    reaper.SetExtState("JKK_Loopmaker", "preview_vol", tostring(cfg.preview_vol), true)
    reaper.SetExtState("JKK_Loopmaker", "src_mode", tostring(cfg.src_mode), true)
    reaper.SetExtState("JKK_Loopmaker", "loop_len", tostring(cfg.loop_len), true)
    reaper.SetExtState("JKK_Loopmaker", "fade_len", tostring(cfg.fade_len), true)
    reaper.SetExtState("JKK_Loopmaker", "glue_res", tostring(cfg.glue_res), true)
    
    reaper.SetExtState("JKK_Loopmaker", "seq_len", tostring(cfg.seq_len), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_int_mode", tostring(cfg.seq_int_mode), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_int_sec", tostring(cfg.seq_int_sec), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_int_grid", tostring(cfg.seq_int_grid), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_int_rpm", tostring(cfg.seq_int_rpm), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_poly", tostring(cfg.seq_poly), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_rel", tostring(cfg.seq_rel), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_pitch", tostring(cfg.seq_pitch), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_seed", tostring(cfg.seq_seed), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_rand_mode", tostring(cfg.seq_rand_mode), true)
    reaper.SetExtState("JKK_Loopmaker", "seq_no_consec", tostring(cfg.seq_no_consec), true)
end

function GetSelectedOriginalItems()
    local preview_set = {}
    if preview_folder_track and reaper.ValidatePtr(preview_folder_track, "MediaTrack*") then
        preview_set[preview_folder_track] = true
    end
    for _, tr in ipairs(preview_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then preview_set[tr] = true end
    end
    
    local items = {}
    local raw_items = sel_mgr and sel_mgr.GetSelectedItems() or {}
    for _, item in ipairs(raw_items) do
        local track = reaper.GetMediaItem_Track(item)
        if not preview_set[track] then table.insert(items, item) end
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
            return false, "MIDI items are not supported.", {}
        end
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if cfg.active_tab == 0 and len < 1.0 then
            return false, string.format("Items under 1s are not allowed for Loopmaker (current: %.2fs).", len), {}
        end
        local track = reaper.GetMediaItem_Track(item)
        if cfg.active_tab == 0 and track_map[track] then
            return false, "Select only one item per track for Loop, or glue them.", {}
        end
        track_map[track] = true
        table.insert(valid_items, item)
    end
    return true, "", valid_items
end

function CaptureMeta(items)
    local meta = {}
    for i, item in ipairs(items) do
        local take = reaper.GetActiveTake(item)
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local fo = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
        meta[i] = {
            len = len,
            playrate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0,
            fo_ratio = (len > 0) and (fo / len) or 0
        }
    end
    return meta
end

-- ==========================================
-- 5. 프리뷰 코어 로직
-- ==========================================
local last_mouse_down_state = false
local pending_items_signature = nil

function CheckAndSyncSelection(is_focused)
    if sel_mgr then sel_mgr.Update(is_focused) end
    local is_mouse_down = sel_mgr and sel_mgr.IsMouseDown() or false
    local mouse_released = last_mouse_down_state and not is_mouse_down
    last_mouse_down_state = is_mouse_down

    local cur_valid, cur_err, cur_items = InitialValidate()

    -- 1. 세션이 아예 활성화되지 않은 초기 상태 (아무 대상도 없을 때)
    if not is_session_active then
        if not cur_valid then
            is_valid = false
            err_msg = cur_err
            pending_items_signature = nil
            return
        end

        -- 현재 선택된 아이템들의 고유 식별자(포인터 주소) 문자열 생성
        local sig = ""
        for _, it in ipairs(cur_items) do sig = sig .. tostring(it) .. "," end

        -- 마우스를 누르고 있는 동안에는 대기(Pending)
        if is_mouse_down then
            pending_items_signature = sig
            return
        end

        -- 마우스를 뗄 때(released) 혹은 클릭 없이 선택된 상태일 때 비로소 세션 초기화 실행
        if mouse_released or pending_items_signature == sig then
            InitSession(cur_items)
            pending_items_signature = nil
        end
        return
    end

    -- 2. 이미 세션이 활성화된 상태 (대상 변경 처리)
    if is_session_active and not cur_valid then
        CancelAndRevert()
        is_session_active = false
        is_valid = false
        err_msg = cur_err
        return
    end

    if is_session_active and cur_valid then
        if is_mouse_down then return end -- 드래그/클릭 유지 중에는 대기

        local changed = (#cur_items ~= #target_items)
        if not changed then
            for i, it in ipairs(cur_items) do
                if it ~= target_items[i] then changed = true; break end
            end
        end

        if changed then 
            CancelAndRevert()
            InitSession(cur_items) 
        end
    end
end

function InitSession(items)
    is_valid = true; err_msg = ""
    target_items = items
    target_meta = CaptureMeta(items)
    original_solos = {}; preview_tracks = {}
    
    original_env.cursor = reaper.GetCursorPosition()
    original_env.ts_start, original_env.ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    original_env.loop = reaper.GetToggleCommandState(1068) == 1

    reaper.PreventUIRefresh(1)
    
    local base_track = reaper.GetMediaItem_Track(target_items[1])
    local base_idx = reaper.CSurf_TrackToID(base_track, false)
    
    reaper.InsertTrackAtIndex(base_idx - 1, false)
    preview_folder_track = reaper.GetTrack(0, base_idx - 1)
    reaper.GetSetMediaTrackInfo_String(preview_folder_track, "P_NAME", "JKK_Preview_Folder", true)
    reaper.SetMediaTrackInfo_Value(preview_folder_track, "I_FOLDERDEPTH", 1)
    reaper.SetMediaTrackInfo_Value(preview_folder_track, "I_SOLO", 2)
    local linear_vol = 10 ^ (cfg.preview_vol / 20.0)
    reaper.SetMediaTrackInfo_Value(preview_folder_track, "D_VOL", linear_vol)
    
    local pool_size = math.max(12, #target_items)
    for i = 1, pool_size do
        reaper.InsertTrackAtIndex(base_idx + i - 1, false)
        local prev_track = reaper.GetTrack(0, base_idx + i - 1)
        table.insert(preview_tracks, prev_track)
        
        reaper.SetMediaTrackInfo_Value(prev_track, "B_SHOWINTCP", 0)
        reaper.SetMediaTrackInfo_Value(prev_track, "B_SHOWINMIXER", 0)
        reaper.SetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH", 0)
    end
    
    for _, orig_item in ipairs(target_items) do
        local orig_track = reaper.GetMediaItem_Track(orig_item)
        original_solos[orig_track] = reaper.GetMediaTrackInfo_Value(orig_track, "I_SOLO")
    end

    reaper.PreventUIRefresh(-1)
    is_session_active = true
    UpdatePreview("end")
end

local function BeginLoopmakerNoAutoFades()
    if not reaper.get_config_var_string or not reaper.set_config_var_string then
        return nil
    end

    local ok, retval, old_value = pcall(reaper.get_config_var_string, "splitautoxfade")
    if not ok or not retval or old_value == nil then return nil end

    local flags = tonumber(old_value)
    if not flags then return nil end

    local disabled_flags = math.floor(flags) | 1 | 8
    if disabled_flags ~= math.floor(flags) then
        pcall(reaper.set_config_var_string, "splitautoxfade", tostring(disabled_flags), 0)
    end

    return old_value
end

local function EndLoopmakerNoAutoFades(old_value)
    if old_value ~= nil and reaper.set_config_var_string then
        pcall(reaper.set_config_var_string, "splitautoxfade", old_value, 0)
    end
end

local function ClearItemAutoFades(item)
    if not item then return end
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", 0)
end

local function SetLoopItemFades(item, fade_in, fade_out)
    if not item then return end
    ClearItemAutoFades(item)
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", math.max(0, fade_in or 0))
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.max(0, fade_out or 0))
end

function UpdatePreviewLoop(cursor_mode)
    local first_start, first_end, first_xfade = 0, 0, 0
    local first_result_set = false
    local start_base = original_env.cursor
    local eps = 0.000001

    local old_splitautoxfade = BeginLoopmakerNoAutoFades()

    for i, orig_item in ipairs(target_items) do
        local prev_track = preview_tracks[i]
        local orig_len = target_meta[i].len
        local loop_len = math.max(0.01, cfg.loop_len)

        local requested_fade = math.max(0, math.min(
            cfg.fade_len,
            orig_len * 0.45,
            loop_len * 0.45
        ))

        local tile_count = 1
        local step_len = loop_len
        local actual_fade = 0

        if orig_len > loop_len + eps then
            tile_count = 1
            step_len = loop_len
            actual_fade = math.min(requested_fade, orig_len - loop_len)
        elseif requested_fade <= eps then
            tile_count = math.max(1, math.ceil(loop_len / math.max(orig_len, 0.01)))
            step_len = loop_len / tile_count
            actual_fade = 0
        else
            local max_count = math.max(2,
                math.ceil(loop_len / math.max(0.01, requested_fade / 0.9)) + 4)
            max_count = math.min(max_count, 10000)

            local best_count, best_step, best_fade = nil, nil, -1

            for count = 2, max_count do
                local candidate_step = loop_len / count
                local candidate_fade = math.min(
                    requested_fade,
                    candidate_step * 0.9,
                    orig_len - candidate_step
                )

                if candidate_fade > eps and candidate_fade > best_fade + eps then
                    best_count = count
                    best_step = candidate_step
                    best_fade = candidate_fade
                end
            end

            if best_count then
                tile_count = best_count
                step_len = best_step
                actual_fade = best_fade
            else
                tile_count = math.max(1, math.ceil(loop_len / math.max(orig_len, 0.01)))
                step_len = loop_len / tile_count
                actual_fade = 0
            end
        end

        local tile_len = step_len + actual_fade
        if tile_len > orig_len then
            actual_fade = math.max(0, orig_len - step_len)
            tile_len = step_len + actual_fade
        end
        tile_len = math.max(0.01, tile_len)

        local seam_offset = (step_len + actual_fade) * 0.5
        local gen_start = start_base - seam_offset
        local _, chunk = reaper.GetItemStateChunk(orig_item, "", false)
        local placed_tiles = {}

        for tile_idx = 0, tile_count - 1 do
            local tile_item = reaper.AddMediaItemToTrack(prev_track)
            reaper.SetItemStateChunk(tile_item, chunk, false)

            reaper.SetMediaItemInfo_Value(tile_item, "B_LOOPSRC", 0)
            reaper.SetMediaItemInfo_Value(tile_item, "C_BEHAVIOR", 1)
            reaper.SetMediaItemSelected(tile_item, false)
            reaper.SetMediaItemInfo_Value(tile_item, "D_POSITION", gen_start + tile_idx * step_len)
            reaper.SetMediaItemInfo_Value(tile_item, "D_LENGTH", tile_len)

            SetLoopItemFades(tile_item, actual_fade, actual_fade)
            reaper.SetMediaItemInfo_Value(tile_item, "C_FADEINSHAPE", cfg.shape_idx)
            reaper.SetMediaItemInfo_Value(tile_item, "C_FADEOUTSHAPE", cfg.shape_idx)

            placed_tiles[#placed_tiles + 1] = tile_item
        end

        local seam_tile = placed_tiles[1]
        if seam_tile then
            local seam_item_pos = reaper.GetMediaItemInfo_Value(seam_tile, "D_POSITION")
            local seam_item_len = reaper.GetMediaItemInfo_Value(seam_tile, "D_LENGTH")
            local seam_item_end = seam_item_pos + seam_item_len

            if start_base > seam_item_pos + eps and start_base < seam_item_end - eps then
                local right_item = reaper.SplitMediaItem(seam_tile, start_base)

                if right_item then
                    local left_len = start_base - seam_item_pos
                    local right_len = seam_item_end - start_base

                    reaper.SetMediaItemInfo_Value(seam_tile, "D_POSITION", seam_item_pos)
                    reaper.SetMediaItemInfo_Value(seam_tile, "D_LENGTH", left_len)
                    SetLoopItemFades(seam_tile, actual_fade, 0)
                    reaper.SetMediaItemInfo_Value(seam_tile, "C_FADEINSHAPE", cfg.shape_idx)
                    reaper.SetMediaItemInfo_Value(seam_tile, "C_FADEOUTSHAPE", cfg.shape_idx)

                    reaper.SetMediaItemInfo_Value(right_item, "D_POSITION", start_base)
                    reaper.SetMediaItemInfo_Value(right_item, "D_LENGTH", right_len)
                    SetLoopItemFades(right_item, 0, actual_fade)
                    reaper.SetMediaItemInfo_Value(right_item, "C_FADEINSHAPE", cfg.shape_idx)
                    reaper.SetMediaItemInfo_Value(right_item, "C_FADEOUTSHAPE", cfg.shape_idx)

                    reaper.SetMediaItemInfo_Value(seam_tile, "D_POSITION", seam_item_pos + loop_len)
                end
            end
        end

        for _, tile_item in ipairs(placed_tiles) do
            if reaper.ValidatePtr(tile_item, "MediaItem*") then
                ClearItemAutoFades(tile_item)
            end
        end

        if not first_result_set then
            first_start = start_base
            first_end = start_base + loop_len
            first_xfade = start_base + (step_len * 0.5)
            first_result_set = true
        end
    end

    EndLoopmakerNoAutoFades(old_splitautoxfade)

    if first_end > 0 then
        reaper.GetSet_LoopTimeRange(true, false, first_start, first_end, false)
        local start_cursor = math.max(first_start,
            (cursor_mode == "xfade" and first_xfade or first_end) - 1.0)
        reaper.SetEditCurPos(start_cursor, false, false)
        if reaper.GetToggleCommandState(1068) == 0 then reaper.Main_OnCommand(1068, 0) end
    end
end

local function GenerateSequence(N, required_items)
    math.randomseed(cfg.seq_seed)
    
    local function generate_bag()
        local bag = {}
        for i = 1, N do table.insert(bag, i) end
        for i = N, 2, -1 do
            local j = math.random(i)
            bag[i], bag[j] = bag[j], bag[i]
        end
        return bag
    end
    
    local sequence = {}
    local cycle_bag = generate_bag()
    
    while #sequence < required_items do
        if cfg.seq_rand_mode == 0 then
            if cfg.seq_no_consec and N > 1 and cycle_bag[N] == cycle_bag[1] then
                cycle_bag[1], cycle_bag[2] = cycle_bag[2], cycle_bag[1]
            end
            for _, item_idx in ipairs(cycle_bag) do
                table.insert(sequence, item_idx)
            end
        else
            local new_bag = generate_bag()
            if cfg.seq_no_consec and N > 1 and #sequence > 0 and new_bag[1] == sequence[#sequence] then
                local swap_idx = math.random(2, N)
                new_bag[1], new_bag[swap_idx] = new_bag[swap_idx], new_bag[1]
            end
            for _, item_idx in ipairs(new_bag) do
                table.insert(sequence, item_idx)
            end
        end
    end
    return sequence
end

function UpdatePreviewSeq()
    local interval_sec = cfg.seq_int_sec
    if cfg.seq_int_mode == 1 then
        local bpm = reaper.TimeMap_GetDividedBpmAtTime(0)
        interval_sec = (60 / bpm) * (4 / cfg.seq_int_grid)
    elseif cfg.seq_int_mode == 2 then
        interval_sec = 60 / cfg.seq_int_rpm
    end
    if interval_sec < 0.01 then interval_sec = 0.01 end

    local required_items = math.ceil(cfg.seq_len / interval_sec) + 10
    local sequence = GenerateSequence(#target_items, required_items)

    local start_base = original_env.cursor
    local rel_time = 0.0
    local item_idx = 1
    local track_busy_until = {}
    for i = 1, #preview_tracks do track_busy_until[i] = 0.0 end
    
    local placed_items = {}
    
    while rel_time < cfg.seq_len do
        local abs_time = start_base + rel_time
        local target_track_idx = 1
        local found_free = false
        local max_spill_tracks = math.min(cfg.seq_poly + 4, #preview_tracks)
        
        for i = 1, cfg.seq_poly do
            if track_busy_until[i] <= abs_time then
                target_track_idx = i; found_free = true; break
            end
        end
        if not found_free and cfg.seq_rel > 0.0 then
            for i = cfg.seq_poly + 1, max_spill_tracks do
                if track_busy_until[i] <= abs_time then
                    target_track_idx = i; found_free = true; break
                end
            end
        end
        if not found_free then
            local min_busy = 999999
            for i = 1, cfg.seq_poly do
                if track_busy_until[i] < min_busy then
                    min_busy = track_busy_until[i]
                    target_track_idx = i
                end
            end
        end
        
        local orig_i = sequence[item_idx]
        local orig_item = target_items[orig_i]
        local meta = target_meta[orig_i]
        
        for i = #placed_items, 1, -1 do
            local p_item = placed_items[i]
            if p_item.track_idx == target_track_idx and p_item.end_time > abs_time then
                local trunc_len = math.max(0.001, abs_time - p_item.start_time)
                reaper.SetMediaItemInfo_Value(p_item.item, "D_LENGTH", trunc_len)
                reaper.SetMediaItemInfo_Value(p_item.item, "D_FADEOUTLEN", trunc_len * p_item.fo_ratio)
                p_item.end_time = abs_time
                break
            end
        end

        local _, chunk = reaper.GetItemStateChunk(orig_item, "", false)
        local new_item = reaper.AddMediaItemToTrack(preview_tracks[target_track_idx])
        reaper.SetItemStateChunk(new_item, chunk, false)
        reaper.SetMediaItemSelected(new_item, false)
        
        local var_val = (math.random() * 2 - 1) * cfg.seq_pitch
        local new_rate = meta.playrate * (2 ^ (var_val / 12))
        local take = reaper.GetActiveTake(new_item)
        if take then reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate) end
        
        local new_len = meta.len * (meta.playrate / new_rate)
        
        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", new_len)
        reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", abs_time)
        
        table.insert(placed_items, {item = new_item, track_idx = target_track_idx, start_time = abs_time, end_time = abs_time + new_len, fo_ratio = meta.fo_ratio})
        track_busy_until[target_track_idx] = abs_time + new_len + cfg.seq_rel
        
        rel_time = rel_time + interval_sec
        item_idx = item_idx + 1
    end
    
    reaper.GetSet_LoopTimeRange(true, false, start_base, start_base + cfg.seq_len, false)
    reaper.SetEditCurPos(start_base, false, false)
    if reaper.GetToggleCommandState(1068) == 0 then reaper.Main_OnCommand(1068, 0) end
end

function UpdatePreview(cursor_mode)
    if not is_valid or not is_session_active then return end
    
    reaper.PreventUIRefresh(1)
    
    for _, tr in ipairs(preview_tracks) do
        while reaper.CountTrackMediaItems(tr) > 0 do
            reaper.DeleteTrackMediaItem(tr, reaper.GetTrackMediaItem(tr, 0))
        end
    end
    
    if cfg.active_tab == 0 then UpdatePreviewLoop(cursor_mode)
    else UpdatePreviewSeq() end
    
    local max_used = 0
    for i, tr in ipairs(preview_tracks) do
        if reaper.CountTrackMediaItems(tr) > 0 then max_used = i end
    end
    
    for i, tr in ipairs(preview_tracks) do
        if i <= max_used then
            reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
            reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1)
            reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", (i == max_used) and -1 or 0)
        else
            reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0)
            reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
            reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
        end
    end
    
    if preview_folder_track then
        reaper.SetMediaTrackInfo_Value(preview_folder_track, "I_FOLDERDEPTH", max_used > 0 and 1 or 0)
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

-- ==========================================
-- Apply & Revert
-- ==========================================
function ApplyAndClose()
    if not is_valid or not is_session_active then return end
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    if cfg.active_tab == 0 and cfg.glue_res then
        local old_splitautoxfade = BeginLoopmakerNoAutoFades()

        reaper.Main_OnCommand(40289, 0)
        local item_cnt = reaper.CountTrackMediaItems(preview_tracks[1])
        for k = 0, item_cnt - 1 do
            reaper.SetMediaItemSelected(reaper.GetTrackMediaItem(preview_tracks[1], k), true)
        end
        reaper.Main_OnCommand(41588, 0)

        local glued = reaper.GetSelectedMediaItem(0, 0)
        if glued then
            reaper.SetMediaItemInfo_Value(glued, "B_LOOPSRC", 1)
            SetLoopItemFades(glued, 0, 0)
        end

        EndLoopmakerNoAutoFades(old_splitautoxfade)
    end

    if cfg.src_mode == 0 then
        for _, orig_item in ipairs(target_items) do
            local orig_track = reaper.GetMediaItem_Track(orig_item)
            reaper.DeleteTrackMediaItem(orig_track, orig_item)
        end
    elseif cfg.src_mode == 1 then
        for _, orig_item in ipairs(target_items) do
            reaper.SetMediaItemInfo_Value(orig_item, "B_MUTE", 1)
        end
    end
    
    local max_used = 0
    for i, tr in ipairs(preview_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") and reaper.CountTrackMediaItems(tr) > 0 then max_used = i end
    end
    
    for i, tr in ipairs(preview_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then 
            if i <= max_used then
                reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
                reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1)
                reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", (i == max_used) and -1 or 0)
            else
                reaper.DeleteTrack(tr)
            end
        end
    end
    
    if preview_folder_track and reaper.ValidatePtr(preview_folder_track, "MediaTrack*") then
        reaper.SetMediaTrackInfo_Value(preview_folder_track, "I_FOLDERDEPTH", max_used > 0 and 1 or 0)
        reaper.SetMediaTrackInfo_Value(preview_folder_track, "I_SOLO", 0)
    end
    
    for tr, solo in pairs(original_solos) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", solo) end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock(cfg.active_tab == 0 and "Create Loopmaker" or "Create Sequencer Arrangement", -1)
    SaveSettings()
    is_session_active = false
end

function CancelAndRevert()
    reaper.PreventUIRefresh(1)
    reaper.Main_OnCommand(1016, 0)
    for _, tr in ipairs(preview_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then reaper.DeleteTrack(tr) end
    end
    if preview_folder_track and reaper.ValidatePtr(preview_folder_track, "MediaTrack*") then
        reaper.DeleteTrack(preview_folder_track)
    end
    preview_tracks = {}; preview_folder_track = nil
    
    for tr, solo in pairs(original_solos) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", solo) end
    end
    if original_env.ts_start then
        reaper.GetSet_LoopTimeRange(true, false, original_env.ts_start, original_env.ts_end, false)
        reaper.SetEditCurPos(original_env.cursor, false, false)
        if not original_env.loop and reaper.GetToggleCommandState(1068) == 1 then reaper.Main_OnCommand(1068, 0) end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    is_session_active = false
end

-- ==========================================
-- 6. 메인 UI 루프
-- ==========================================
function Loop()
    CheckAndSyncSelection()
    local style_pop, color_pop = ApplyTheme(ctx)

    ImGui.PushFont(ctx, font)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 3)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 10, 5)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 14)

    ImGui.SetNextWindowSizeConstraints(ctx, 500, 500, 9999, 9999)
    ImGui.SetNextWindowSize(ctx, 540, 540, ImGui.Cond_FirstUseEver)
    
    local visible, open = ImGui.Begin(ctx, 'JKK_Loopmaker', true, ImGui.WindowFlags_NoCollapse)
    
    if visible then
        local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then open = false end
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Space) then reaper.Main_OnCommand(40044, 0) end
        if is_valid and enter_pressed then ApplyAndClose(); open = false end

        local avail_w = ImGui.GetContentRegionAvail(ctx)
        
        ImGui.TextColored(ctx, GetColor("accent"), string.format("Selected %d items", #target_items))
        ImGui.Spacing(ctx)
        
        if ImGui.BeginTabBar(ctx, "MainTabs") then
            -- ================= TAB 1 : Loopmaker =================
            if ImGui.BeginTabItem(ctx, "Loopmaker") then
                if cfg.active_tab ~= 0 then 
                    cfg.active_tab = 0; SaveSettings()
                    if is_session_active then CancelAndRevert() end 
                end
                
                ImGui.Spacing(ctx)
                local label_w = 90
                
                -- Length 슬라이더: 오직 드래그가 끝난(DeactivatedAfterEdit) 시점이나 우클릭 리셋 시에만 갱신
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Length")
                ImGui.SameLine(ctx, label_w)
                ImGui.SetNextItemWidth(ctx, avail_w - label_w)
                local changed_len, new_len = ImGui.SliderDouble(ctx, "##loop_len", cfg.loop_len, 1.0, 30.0, "%.1f s")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then new_len = 5.0; changed_len = true end
                if changed_len then cfg.loop_len = new_len; SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (changed_len and ImGui.IsMouseClicked(ctx, 1)) then 
                    UpdatePreview("end") 
                end
                
                -- Crossfade 슬라이더: 오직 드래그가 끝난 시점이나 우클릭 리셋 시에만 갱신
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Crossfade")
                ImGui.SameLine(ctx, label_w)
                local btn_w, spacing = 38, 10
                ImGui.SetNextItemWidth(ctx, avail_w - label_w - btn_w - spacing)
                local changed_fade, new_fade = ImGui.SliderDouble(ctx, "##fade_len", cfg.fade_len, 0.1, 5.0, "%.2f s")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then new_fade = 1.0; changed_fade = true end
                if changed_fade then cfg.fade_len = new_fade; SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (changed_fade and ImGui.IsMouseClicked(ctx, 1)) then 
                    UpdatePreview("xfade") 
                end
                
                ImGui.SameLine(ctx)
                local b_clk, b_rclk = DrawFadeCurveButton(ctx, "xfade_shape_btn", cfg.shape_idx, false)
                if b_clk then cfg.shape_idx = (cfg.shape_idx + 1) % 7; SaveSettings(); UpdatePreview("xfade") end
                if b_rclk then ImGui.OpenPopup(ctx, "xfade_shape_popup") end
                local new_shape = DrawFadeCurveSelectorPopup(ctx, "xfade_shape_popup", cfg.shape_idx, false)
                if new_shape then cfg.shape_idx = new_shape; SaveSettings(); UpdatePreview("xfade") end
                
                ImGui.EndTabItem(ctx)
            end
            
            -- ================= TAB 2 : Sequencer =================
            if ImGui.BeginTabItem(ctx, "Sequencer") then
                if cfg.active_tab ~= 1 then 
                    cfg.active_tab = 1; SaveSettings()
                    if is_session_active then CancelAndRevert() end 
                end
                
                ImGui.Spacing(ctx)
                
                local label_w = 90
                local content_w = avail_w - label_w
                
                -- 1. Length
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Length")
                ImGui.SameLine(ctx, label_w)
                ImGui.SetNextItemWidth(ctx, content_w)
                local c_len, n_len = ImGui.SliderDouble(ctx, "##seq_len", cfg.seq_len, 1.0, 10.0, "%.1f s")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then n_len = 5.0; c_len = true end
                if c_len then cfg.seq_len = n_len; SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (c_len and ImGui.IsMouseClicked(ctx, 1)) then 
                    UpdatePreview() 
                end
                
                -- 2. Interval
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Interval")
                ImGui.SameLine(ctx, label_w)
                ImGui.SetNextItemWidth(ctx, content_w)
                
                local c_val = false
                if cfg.seq_int_mode == 0 then
                    local chg, val = ImGui.SliderDouble(ctx, "##seq_int", cfg.seq_int_sec, 0.05, 2.0, seq_int_formats[1])
                    if chg then cfg.seq_int_sec = val; c_val = true end
                elseif cfg.seq_int_mode == 1 then
                    local chg, val = ImGui.SliderInt(ctx, "##seq_int", cfg.seq_int_grid, 1, 10, seq_int_formats[2])
                    if chg then cfg.seq_int_grid = val; c_val = true end
                elseif cfg.seq_int_mode == 2 then
                    local chg, val = ImGui.SliderInt(ctx, "##seq_int", cfg.seq_int_rpm, 60, 1200, seq_int_formats[3])
                    if chg then cfg.seq_int_rpm = val; c_val = true end
                end
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then
                    cfg.seq_int_mode = (cfg.seq_int_mode + 1) % 3
                    c_val = true
                end

                if c_val then SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (c_val and ImGui.IsMouseClicked(ctx, 1)) then 
                    UpdatePreview() 
                end
                
                -- 3. Polyphony
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Polyphony")
                ImGui.SameLine(ctx, label_w)
                ImGui.SetNextItemWidth(ctx, content_w)
                local c_poly, n_poly = ImGui.SliderInt(ctx, "##seq_poly", cfg.seq_poly, 1, 8, "%d Voices")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then n_poly = 1; c_poly = true end
                if c_poly then cfg.seq_poly = n_poly; SaveSettings(); UpdatePreview() end
                
                -- 4. Release
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Release")
                ImGui.SameLine(ctx, label_w)
                ImGui.SetNextItemWidth(ctx, content_w)
                local c_rel, n_rel = ImGui.SliderDouble(ctx, "##seq_rel", cfg.seq_rel, 0.0, 3.0, "%.2f s")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then n_rel = 0.0; c_rel = true end
                if c_rel then cfg.seq_rel = n_rel; SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (c_rel and ImGui.IsMouseClicked(ctx, 1)) then UpdatePreview() end
                
                ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
                
                -- 5. Pitch Var
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Pitch Var.")
                ImGui.SameLine(ctx, label_w)
                ImGui.SetNextItemWidth(ctx, content_w)
                local c_ptc, n_ptc = ImGui.SliderDouble(ctx, "##seq_pitch", cfg.seq_pitch, 0.0, 3.0, "%.2f st")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then n_ptc = 0.0; c_ptc = true end
                if c_ptc then cfg.seq_pitch = n_ptc; SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (c_ptc and ImGui.IsMouseClicked(ctx, 1)) then UpdatePreview() end

                -- 6. Rand mode, Checkbox, Shuffle
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Rand mode")
                ImGui.SameLine(ctx, label_w)
                
                local combo_w = 135
                ImGui.SetNextItemWidth(ctx, combo_w)
                if ImGui.BeginCombo(ctx, "##rand_mode", rand_modes[cfg.seq_rand_mode + 1]) then
                    for i, mode in ipairs(rand_modes) do
                        if ImGui.Selectable(ctx, mode, cfg.seq_rand_mode == (i-1)) then
                            cfg.seq_rand_mode = i - 1; SaveSettings(); UpdatePreview()
                        end
                    end
                    ImGui.EndCombo(ctx)
                end
                
                ImGui.SameLine(ctx)
                local chg_c, val_c = ImGui.Checkbox(ctx, "No Same Consec.", cfg.seq_no_consec)
                if chg_c then cfg.seq_no_consec = val_c; SaveSettings(); UpdatePreview() end
                
                ImGui.SameLine(ctx)
                local shuffle_w = 80
                local slider_right_x = label_w + content_w
                ImGui.SetCursorPosX(ctx, slider_right_x - shuffle_w)
                
                PushButton(ctx, "primary")
                if ImGui.Button(ctx, "Shuffle", shuffle_w, ImGui.GetFrameHeight(ctx)) then
                    cfg.seq_seed = cfg.seq_seed + 1
                    SaveSettings(); UpdatePreview()
                end
                PopButton(ctx)

                ImGui.EndTabItem(ctx)
            end
            ImGui.EndTabBar(ctx)
        end
        
        local fh = ImGui.GetFrameHeight(ctx)
        local sp_y = 5
        local btn_height = 45
        local label_w = 90

        local bottom_h = btn_height + (fh + sp_y) * 3 + 15
        local warning_h = ImGui.GetTextLineHeight(ctx) + sp_y
        bottom_h = bottom_h + warning_h

        local _, c_avail_h = ImGui.GetContentRegionAvail(ctx)
        if c_avail_h > bottom_h then 
            ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + c_avail_h - bottom_h) 
        end
        
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)
        
        -- Preview Vol 슬라이더: 드래그 중 실시간 볼륨 적용 및 마우스 뗄 때 저장
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.Text(ctx, "Preview Vol")
        ImGui.SameLine(ctx, label_w)
        ImGui.SetNextItemWidth(ctx, avail_w - label_w)
        local changed_vol, new_vol = ImGui.SliderDouble(ctx, "##preview_vol", cfg.preview_vol, -60.0, 12.0, "%.1f dB")
        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then new_vol = 0.0; changed_vol = true end
        if changed_vol then 
            cfg.preview_vol = new_vol; SaveSettings()
            if preview_folder_track and reaper.ValidatePtr(preview_folder_track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(preview_folder_track, "D_VOL", 10 ^ (new_vol / 20.0))
            end
        end
        
        -- Handling 콤보박스
        local modes = {"Replace in place", "Create new track & Mute original", "Create new track & Keep original"}
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.Text(ctx, "Handling")
        ImGui.SameLine(ctx, label_w)
        ImGui.SetNextItemWidth(ctx, avail_w - label_w)
        if ImGui.BeginCombo(ctx, "##src_handling", modes[cfg.src_mode + 1]) then
            for i, mode in ipairs(modes) do
                if ImGui.Selectable(ctx, mode, cfg.src_mode == (i-1)) then cfg.src_mode = i - 1; SaveSettings() end
            end
            ImGui.EndCombo(ctx)
        end
        
        if cfg.active_tab == 0 then
            ImGui.SetCursorPosX(ctx, label_w)
            local changed_glue, new_glue = ImGui.Checkbox(ctx, "Glue final result into single item", cfg.glue_res)
            if changed_glue then cfg.glue_res = new_glue; SaveSettings() end
        else
            ImGui.Dummy(ctx, 0, fh)
        end
        
        if not is_valid then
            ImGui.TextColored(ctx, GetColor("accent"), "[!] " .. err_msg)
            ImGui.BeginDisabled(ctx, true)
        else
            ImGui.Dummy(ctx, 0, ImGui.GetTextLineHeight(ctx))
        end
        
        ImGui.PushFont(ctx, font_btn)
        PushButton(ctx, "confirm")

        local btn_text = (cfg.active_tab == 0) and " Make Loop " or " Arrange Items "
        if ImGui.Button(ctx, btn_text, -1, btn_height) then
            ApplyAndClose(); open = false
        end

        PopButton(ctx); ImGui.PopFont(ctx)
        if not is_valid then ImGui.EndDisabled(ctx) end

        ImGui.End(ctx)
    end

    ImGui.PopStyleVar(ctx, 3)
    ImGui.PopFont(ctx)
    if color_pop > 0 then ImGui.PopStyleColor(ctx, color_pop) end
    if style_pop > 0 then ImGui.PopStyleVar(ctx, style_pop) end

    if open then
        reaper.defer(Loop)
    else
        SaveSettings()
        if is_session_active and not (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)) then 
            CancelAndRevert() 
        end
    end
end

reaper.defer(Loop)