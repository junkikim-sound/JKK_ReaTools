--========================================================
-- @title JKK_Loopmaker
-- @author Junki Kim
-- @version 1.2.3
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
    shape_idx = 1, -- [수정] 기본 커브 인덱스를 1 (Inverted quadratic)로 설정
    
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
    local color = 0x068FC3FF
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
        ImGui.TextColored(ctx, 0x808080FF, "Select Curve Shape:")
        ImGui.Spacing(ctx)
        for idx = 0, 6 do
            ImGui.PushID(ctx, idx)
            local is_active = (current_shape == idx)
            if is_active then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x068FC388)
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x068FC3FF)
            end
            local clicked = ImGui.Button(ctx, "##curve_btn", 44, 32)
            local p_min_x, p_min_y = ImGui.GetItemRectMin(ctx)
            local p_max_x, p_max_y = ImGui.GetItemRectMax(ctx)
            local dl = ImGui.GetWindowDrawList(ctx)
            local x0, x1 = p_min_x + 6, p_max_x - 6
            local y_top, y_bot = p_min_y + 5, p_max_y - 5
            local w, h = x1 - x0, y_bot - y_top
            local line_col = is_active and 0xFFFFFFFF or 0xEDEDEDFF
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
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
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

function FindZeroCrossing(item, approx_pos)
    local take = reaper.GetActiveTake(item)
    if not take then return approx_pos end
    local accessor = reaper.CreateTakeAudioAccessor(take)
    local srate = 44100
    local window = 0.04
    local start_time = approx_pos - (window / 2)
    local buffer = reaper.new_array(math.floor(window * srate))
    reaper.GetAudioAccessorSamples(accessor, srate, 1, start_time, math.floor(window * srate), buffer)
    reaper.DestroyAudioAccessor(accessor)
    
    local tbl = buffer.table()
    local closest, min_val = approx_pos, 9999
    for i = 1, #tbl - 1 do
        if (tbl[i] <= 0 and tbl[i+1] >= 0) or (tbl[i] >= 0 and tbl[i+1] <= 0) then
            if math.abs(tbl[i]) < min_val then
                min_val = math.abs(tbl[i])
                closest = start_time + (i / srate)
            end
        end
    end
    return closest
end

-- ==========================================
-- 5. 프리뷰 코어 로직
-- ==========================================
function CheckAndSyncSelection()
    local cur_valid, cur_err, cur_items = InitialValidate()
    if not is_session_active then
        if cur_valid then InitSession(cur_items) else is_valid = false; err_msg = cur_err end
        return
    end
    if is_session_active and not cur_valid then
        CancelAndRevert(); is_session_active = false; is_valid = false; err_msg = cur_err
        return
    end
    if is_session_active and cur_valid then
        local changed = (#cur_items ~= #target_items)
        if not changed then
            for i, it in ipairs(cur_items) do
                if it ~= target_items[i] then changed = true; break end
            end
        end
        if changed then CancelAndRevert(); InitSession(cur_items) end
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

-- ==========================================
-- [Tab 1] Loopmaker 프로세싱 (Wrap-Around Crossfade 위치 중앙 정렬)
-- ==========================================
-- REAPER의 Media Item Defaults에 지정된 자동 페이드 및
-- Split crossfade 옵션을 루프 생성 중에만 비활성화한다.
-- splitautoxfade bitfield:
--   &1 = Overlap and crossfade items when splitting
--   &8 = Create automatic fade-in/fade-out for new items (0=ON, 1=OFF)
-- 원래 설정 문자열을 그대로 보관했다가 반드시 복원한다.
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

-- 아이템의 자동 페이드를 확실히 제거한다.
local function ClearItemAutoFades(item)
    if not item then return end
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", 0)
end

-- 수동 페이드 길이를 지정하고 자동 페이드는 항상 제거한다.
local function SetLoopItemFades(item, fade_in, fade_out)
    if not item then return end
    ClearItemAutoFades(item)
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", math.max(0, fade_in or 0))
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.max(0, fade_out or 0))
end

-- ==========================================
-- [Tab 1] Loopmaker 프로세싱
-- Wrap-around 지점을 크로스페이드가 없는 아이템 내부에 배치
-- ==========================================
function UpdatePreviewLoop(cursor_mode)
    local first_start, first_end, first_xfade = 0, 0, 0
    local first_result_set = false
    local start_base = original_env.cursor
    local eps = 0.000001

    -- 사용자 Preferences와 무관하게 생성/분할한다.
    local old_splitautoxfade = BeginLoopmakerNoAutoFades()

    for i, orig_item in ipairs(target_items) do
        local prev_track = preview_tracks[i]
        local orig_len = target_meta[i].len
        local loop_len = math.max(0.01, cfg.loop_len)

        -- 요청한 크로스페이드 길이의 상한
        local requested_fade = math.max(0, math.min(
            cfg.fade_len,
            orig_len * 0.45,
            loop_len * 0.45
        ))

        local tile_count = 1
        local step_len = loop_len
        local actual_fade = 0

        if orig_len > loop_len + eps then
            -- 원본 하나만으로 루프 전체 + 크로스페이드 구간을 만들 수 있다.
            -- 원본의 실제 여유 길이까지만 크로스페이드를 사용한다.
            tile_count = 1
            step_len = loop_len
            actual_fade = math.min(requested_fade, orig_len - loop_len)
        elseif requested_fade <= eps then
            -- 크로스페이드가 0이면 원본 길이를 초과하지 않는 최소 개수로 반복한다.
            tile_count = math.max(1, math.ceil(loop_len / math.max(orig_len, 0.01)))
            step_len = loop_len / tile_count
            actual_fade = 0
        else
            -- 필요한 반복 횟수를 충분히 탐색한다.
            -- 이전의 짝수 개수/512개 제한을 제거해 짧은 원본에서도
            -- 목표 구간 전체를 빈틈없이 채울 수 있도록 한다.
            local max_count = math.max(2,
                math.ceil(loop_len / math.max(0.01, requested_fade / 0.9)) + 4)
            max_count = math.min(max_count, 10000)

            local best_count, best_step, best_fade = nil, nil, -1

            for count = 2, max_count do
                local candidate_step = loop_len / count
                -- 타일 길이(step + fade)가 원본 길이를 넘지 않게 한다.
                -- 한 타일 안에서 양쪽 페이드가 과도하게 겹치는 것도 방지한다.
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
                -- 유효한 오버랩을 만들 수 없는 경우에도 모든 구간을
                -- 아이템 길이 제한 안에서 정확하게 연결한다.
                tile_count = math.max(1, math.ceil(loop_len / math.max(orig_len, 0.01)))
                step_len = loop_len / tile_count
                actual_fade = 0
            end
        end

        -- 타일 길이는 모든 반복에서 동일하다.
        local tile_len = step_len + actual_fade
        if tile_len > orig_len then
            actual_fade = math.max(0, orig_len - step_len)
            tile_len = step_len + actual_fade
        end
        tile_len = math.max(0.01, tile_len)

        -- 중요:
        -- 루프 시작점(S)을 타일의 한가운데(페이드가 없는 영역)에 둔다.
        -- 따라서 첫 크로스페이드는 S 이후, 마지막 크로스페이드는 S+L 이전에만 생긴다.
        -- N개의 타일 간격 합은 정확히 loop_len이다.
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

            -- SetItemStateChunk / 새 아이템 기본 설정에서 넘어온 자동 페이드를 제거.
            SetLoopItemFades(tile_item, actual_fade, actual_fade)
            reaper.SetMediaItemInfo_Value(tile_item, "C_FADEINSHAPE", cfg.shape_idx)
            reaper.SetMediaItemInfo_Value(tile_item, "C_FADEOUTSHAPE", cfg.shape_idx)

            placed_tiles[#placed_tiles + 1] = tile_item
        end

        -- 첫 타일만 루프 시작점에서 정확히 분할한다.
        -- 자동 split-crossfade 설정은 위에서 껐으며, 분할 직후 길이/위치도 강제로 정렬한다.
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

                    -- 왼쪽 조각은 루프 끝으로 이동한다.
                    -- 절단면에는 수동/자동 페이드를 모두 두지 않는다.
                    reaper.SetMediaItemInfo_Value(seam_tile, "D_POSITION", seam_item_pos)
                    reaper.SetMediaItemInfo_Value(seam_tile, "D_LENGTH", left_len)
                    SetLoopItemFades(seam_tile, actual_fade, 0)
                    reaper.SetMediaItemInfo_Value(seam_tile, "C_FADEINSHAPE", cfg.shape_idx)
                    reaper.SetMediaItemInfo_Value(seam_tile, "C_FADEOUTSHAPE", cfg.shape_idx)

                    -- 오른쪽 조각은 루프 시작에 정확히 맞춘다.
                    reaper.SetMediaItemInfo_Value(right_item, "D_POSITION", start_base)
                    reaper.SetMediaItemInfo_Value(right_item, "D_LENGTH", right_len)
                    SetLoopItemFades(right_item, 0, actual_fade)
                    reaper.SetMediaItemInfo_Value(right_item, "C_FADEINSHAPE", cfg.shape_idx)
                    reaper.SetMediaItemInfo_Value(right_item, "C_FADEOUTSHAPE", cfg.shape_idx)

                    -- 왼쪽 조각의 끝은 정확히 루프 끝과 일치한다.
                    reaper.SetMediaItemInfo_Value(seam_tile, "D_POSITION", seam_item_pos + loop_len)
                else
                    -- 예외 상황에서 루프 경계를 가로지르는 아이템이 남지 않도록
                    -- 실패 상태를 명확히 알린다. 정상적인 유효 위치에서는 발생하지 않는다.
                    reaper.ShowConsoleMsg("[JKK_Loopmaker] Warning: failed to split the wrap-around tile at loop start.\n")
                end
            else
                reaper.ShowConsoleMsg("[JKK_Loopmaker] Warning: wrap-around split position is outside the first tile.\n")
            end
        end

        -- 나머지 타일은 내부 크로스페이드만 유지한다.
        -- 모든 타일에 자동 페이드가 남아 있지 않은지 마지막으로 확인한다.
        for _, tile_item in ipairs(placed_tiles) do
            if reaper.ValidatePtr(tile_item, "MediaItem*") then
                ClearItemAutoFades(tile_item)
            end
        end

        if not first_result_set then
            first_start = start_base
            first_end = start_base + loop_len
            -- 첫 번째 내부 크로스페이드의 중심.
            -- loop start 자체에는 크로스페이드가 걸치지 않는다.
            first_xfade = start_base + (step_len * 0.5)
            first_result_set = true
        end
    end

    -- 작업 중에만 변경했던 REAPER 사용자 환경설정을 원래대로 복원한다.
    EndLoopmakerNoAutoFades(old_splitautoxfade)

    if first_end > 0 then
        reaper.GetSet_LoopTimeRange(true, false, first_start, first_end, false)
        local start_cursor = math.max(first_start,
            (cursor_mode == "xfade" and first_xfade or first_end) - 1.0)
        reaper.SetEditCurPos(start_cursor, false, false)
        if reaper.GetToggleCommandState(1068) == 0 then reaper.Main_OnCommand(1068, 0) end
    end
end

-- ==========================================
-- [Tab 2] Sequencer 프로세싱 (Cursor-Based Placement)
-- ==========================================
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

-- ==========================================
-- Dispatcher & Dynamic Visibility
-- ==========================================
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
        -- Glue로 새 아이템을 만드는 순간에도 자동 페이드가 추가되지 않도록 한다.
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
            -- 최종 루프의 양 끝에는 어떠한 미세 페이드도 남기지 않는다.
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
    
    -- [수정] 창 제목 'JKK_Loopmaker v2.5' -> 'JKK_Loopmaker' 깔끔하게 수정
    local visible, open = ImGui.Begin(ctx, 'JKK_Loopmaker', true, ImGui.WindowFlags_NoCollapse)
    
    if visible then
        local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then open = false end
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Space) then reaper.Main_OnCommand(40044, 0) end
        if is_valid and enter_pressed then ApplyAndClose(); open = false end

        local avail_w = ImGui.GetContentRegionAvail(ctx)
        
        -- [수정] 상단 텍스트 문구 변경
        ImGui.TextColored(ctx, 0xE3DB8EFF, string.format("Selected %d items", #target_items))
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
                
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Length")
                ImGui.SameLine(ctx, label_w)
                ImGui.SetNextItemWidth(ctx, avail_w - label_w)
                local changed_len, new_len = ImGui.SliderDouble(ctx, "##loop_len", cfg.loop_len, 1.0, 30.0, "%.1f s")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then new_len = 5.0; changed_len = true end
                if changed_len then cfg.loop_len = new_len; SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (changed_len and ImGui.IsMouseClicked(ctx, 1)) then UpdatePreview("end") end
                
                ImGui.AlignTextToFramePadding(ctx)
                ImGui.Text(ctx, "Crossfade")
                ImGui.SameLine(ctx, label_w)
                local btn_w, spacing = 38, 10
                ImGui.SetNextItemWidth(ctx, avail_w - label_w - btn_w - spacing)
                local changed_fade, new_fade = ImGui.SliderDouble(ctx, "##fade_len", cfg.fade_len, 0.1, 5.0, "%.2f s")
                if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then new_fade = 1.0; changed_fade = true end
                if changed_fade then cfg.fade_len = new_fade; SaveSettings() end
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (changed_fade and ImGui.IsMouseClicked(ctx, 1)) then UpdatePreview("xfade") end
                
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
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or (c_len and ImGui.IsMouseClicked(ctx, 1)) then UpdatePreview() end
                
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
                if ImGui.IsItemDeactivatedAfterEdit(ctx) or c_val then UpdatePreview() end
                
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
                
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x068FC388)
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x068FC3FF)
                if ImGui.Button(ctx, "Shuffle", shuffle_w, ImGui.GetFrameHeight(ctx)) then
                    cfg.seq_seed = cfg.seq_seed + 1
                    SaveSettings(); UpdatePreview()
                end
                ImGui.PopStyleColor(ctx, 2)

                ImGui.EndTabItem(ctx)
            end
            ImGui.EndTabBar(ctx)
        end -- EndTabBar
        
        -- ==========================================
        -- 하단 고정 앵커 영역 (공통 옵션 + 경고문 + 실행 버튼)
        -- ==========================================
        local fh = ImGui.GetFrameHeight(ctx)
        local sp_y = 5
        local btn_height = 45
        local label_w = 90

        -- 탭 종류와 상관없이 항상 3개 항목(Vol, Handling, Glue/Dummy) 기준 고정 높이 계산
        local bottom_h = btn_height + (fh + sp_y) * 3 + 15
        if not is_valid then
            bottom_h = bottom_h + ImGui.GetTextLineHeight(ctx) + sp_y
        end

        -- 남은 여백이 높이보다 클 경우 커서를 하단으로 정렬
        local _, c_avail_h = ImGui.GetContentRegionAvail(ctx)
        if c_avail_h > bottom_h then 
            ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + c_avail_h - bottom_h) 
        end
        
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)
        
        -- 1. Preview Vol
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
        
        -- 2. Handling
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
        
        -- 3. Glue Checkbox (Loopmaker 탭) / 더미 여백 (Sequencer 탭)
        if cfg.active_tab == 0 then
            ImGui.SetCursorPosX(ctx, label_w)
            local changed_glue, new_glue = ImGui.Checkbox(ctx, "Glue final result into single item", cfg.glue_res)
            if changed_glue then cfg.glue_res = new_glue; SaveSettings() end
        else
            -- Sequencer 탭일 땐 체크박스 1개 높이(fh)만큼 투명 여백을 배치해 UI 덜컹거림 방지
            ImGui.Dummy(ctx, 0, fh)
        end
        
        -- 4. 경고 메시지
        if not is_valid then
            ImGui.TextColored(ctx, 0xFFFF00FF, "[!] " .. err_msg)
            ImGui.BeginDisabled(ctx, true)
        end
        
        -- 5. 메인 실행 버튼
        ImGui.PushFont(ctx, font_btn)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x24866FFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x2A9A80FF)
        
        local btn_text = (cfg.active_tab == 0) and " Make Loop " or " Arrange Items "
        if ImGui.Button(ctx, btn_text, -1, btn_height) then
            ApplyAndClose(); open = false
        end
        
        ImGui.PopStyleColor(ctx, 2); ImGui.PopFont(ctx)
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