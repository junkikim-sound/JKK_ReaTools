--========================================================
-- @title JKK_ColorPalette_UI
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper

local data_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") .. "JKK_ColorPalette_Data.lua"
local data_module = reaper.file_exists(data_path) and dofile(data_path) or nil

local default_palettes = data_module and data_module.default_palettes or {}
local user_palettes = data_module and data_module.LoadUserPalettes() or {}

local ext_section = "JKK_ColorPalette_State"
local current_palette_idx = tonumber(reaper.GetExtState(ext_section, "palette_idx")) or 1
local auto_close = (reaper.GetExtState(ext_section, "auto_close") == "1")
local apply_to_children = (reaper.GetExtState(ext_section, "apply_to_children") == "1")
local is_editing_name = false
local editing_name_str = ""

-- 실시간 행동(최근 선택) 추적용 변수
local target_mode = "None"
local last_item_cnt, last_track_cnt = -1, -1
local last_item_hash, last_track_hash = "", ""
local last_ts_start, last_ts_end = -1, -1
local last_cursor_ctx = -1

local function SaveState()
    reaper.SetExtState(ext_section, "palette_idx", tostring(current_palette_idx), true)
    reaper.SetExtState(ext_section, "auto_close", auto_close and "1" or "0", true)
    reaper.SetExtState(ext_section, "apply_to_children", apply_to_children and "1" or "0", true)
end

local function GetChildTracks(parent_track)
    local children = {}
    local p_depth = reaper.GetTrackDepth(parent_track)
    local p_idx = reaper.CSurf_TrackToID(parent_track, false)
    local count = reaper.CountTracks(0)
    for i = p_idx, count - 1 do
        local t = reaper.GetTrack(0, i)
        if reaper.GetTrackDepth(t) > p_depth then 
            table.insert(children, t)
        else 
            break 
        end
    end
    return children
end

local function TruncateName(name, max_len)
    if not name then return "" end
    if string.len(name) > max_len then
        return string.sub(name, 1, max_len) .. "..."
    end
    return name
end

-- 현재 target_mode 기반 텍스트 및 개수 포맷팅 (Region/Marker 이름 포함)
local function FormatSelectionContextResult()
    local cur_item_cnt = reaper.CountSelectedMediaItems(0)
    local cur_track_cnt = reaper.CountSelectedTracks(0)
    local cur_ts_start, cur_ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local max_chars = 30

    if target_mode == "Items" and cur_item_cnt > 0 then
        local sel_item = reaper.GetSelectedMediaItem(0, 0)
        local take = sel_item and reaper.GetActiveTake(sel_item)
        local name = take and reaper.GetTakeName(take) or "Item"
        return "Items", cur_item_cnt, string.format("Selected %d Items (%s)", cur_item_cnt, TruncateName(name, max_chars))
        
    elseif target_mode == "Tracks" and cur_track_cnt > 0 then
        local sel_track = reaper.GetSelectedTrack(0, 0)
        local name = "Track"
        if sel_track then
            local retval, tr_name = reaper.GetTrackName(sel_track)
            if retval and tr_name and tr_name ~= "" then name = tr_name end
        end
        return "Tracks", cur_track_cnt, string.format("Selected %d Tracks (%s)", cur_track_cnt, TruncateName(name, max_chars))
        
    elseif target_mode == "Markers" and cur_ts_start ~= cur_ts_end then
        local count = 0
        local first_name = ""
        local i = 0
        while true do
            local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
            if retval == 0 then break end
            if (isrgn and not (rgnend < cur_ts_start or pos > cur_ts_end)) or (not isrgn and (pos >= cur_ts_start and pos <= cur_ts_end)) then
                count = count + 1
                if count == 1 then
                    first_name = (name and name ~= "") and name or "Region/Marker"
                end
            end
            i = i + 1
        end
        if count > 0 then 
            return "Markers", count, string.format("Selected %d Regions/Markers (%s)", count, TruncateName(first_name, max_chars)) 
        end
    end
    
    return "None", 0, "No Selection"
end

-- 마우스 릴리즈 감지 및 TCP / 작업 영역 개별 추적 로직
local function GetSelectionContext(ctx)
    local is_mouse_down = false
    if reaper.JS_Mouse_GetState then
        is_mouse_down = (reaper.JS_Mouse_GetState(1) == 1)
    elseif ctx then
        is_mouse_down = reaper.ImGui_IsMouseDown(ctx, 0)
    end

    if is_mouse_down then
        return FormatSelectionContextResult()
    end

    local cursor_ctx = reaper.GetCursorContext2(true) -- 0: TCP, 1: Arrange(작업영역), 2: Envelopes/Ruler
    local cur_item_cnt = reaper.CountSelectedMediaItems(0)
    local cur_track_cnt = reaper.CountSelectedTracks(0)
    local cur_ts_start, cur_ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

    local cur_item_hash = ""
    for i = 0, cur_item_cnt - 1 do
        cur_item_hash = cur_item_hash .. tostring(reaper.GetSelectedMediaItem(0, i)) .. ","
    end

    local cur_track_hash = ""
    for i = 0, cur_track_cnt - 1 do
        cur_track_hash = cur_track_hash .. tostring(reaper.GetSelectedTrack(0, i)) .. ","
    end

    local item_changed = (cur_item_cnt ~= last_item_cnt) or (cur_item_hash ~= last_item_hash)
    local track_changed = (cur_track_cnt ~= last_track_cnt) or (cur_track_hash ~= last_track_hash)
    local ts_changed = (cur_ts_start ~= last_ts_start) or (cur_ts_end ~= last_ts_end)
    local ctx_changed = (cursor_ctx ~= last_cursor_ctx)
    
    local anything_changed = item_changed or track_changed or ts_changed or ctx_changed

    if anything_changed then
        if ts_changed and cur_ts_start ~= cur_ts_end then
            target_mode = "Markers"
        elseif item_changed and cur_item_cnt > 0 then
            target_mode = "Items"
        elseif track_changed and cursor_ctx == 0 and cur_track_cnt > 0 then
            target_mode = "Tracks"
        else
            if cursor_ctx == 0 then
                target_mode = (cur_track_cnt > 0) and "Tracks" or "None"
            elseif cursor_ctx == 1 then
                target_mode = (cur_item_cnt > 0) and "Items" or "None"
            elseif cursor_ctx == 2 then
                target_mode = (cur_ts_start ~= cur_ts_end) and "Markers" or "None"
            end
        end

        if target_mode == "Markers" then
            local count = 0
            local i = 0
            while true do
                local retval, isrgn, pos, rgnend = reaper.EnumProjectMarkers3(0, i)
                if retval == 0 then break end
                if (isrgn and not (rgnend < cur_ts_start or pos > cur_ts_end)) or (not isrgn and (pos >= cur_ts_start and pos <= cur_ts_end)) then
                    count = count + 1
                    break
                end
                i = i + 1
            end
            if count == 0 then target_mode = "None" end
        end

        last_item_cnt, last_item_hash = cur_item_cnt, cur_item_hash
        last_track_cnt, last_track_hash = cur_track_cnt, cur_track_hash
        last_ts_start, last_ts_end = cur_ts_start, cur_ts_end
        last_cursor_ctx = cursor_ctx
    end

    return FormatSelectionContextResult()
end

local function ApplyColor(u32_color, ctx)
    local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(u32_color)
    local native_color = (u32_color == 0) and 0 or (reaper.ColorToNative(math.floor(r*255), math.floor(g*255), math.floor(b*255)) | 0x1000000)
    
    local ctx_type, cnt = GetSelectionContext(ctx)
    if ctx_type == "None" then return false end
    
    reaper.Undo_BeginBlock()
    
    if ctx_type == "Items" then
        for i = 0, cnt - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color)
            if apply_to_children then
                local track = reaper.GetMediaItem_Track(item)
                if reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                    local p_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local p_end = p_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    for _, c_track in ipairs(GetChildTracks(track)) do
                        for j = 0, reaper.CountTrackMediaItems(c_track) - 1 do
                            local c_item = reaper.GetTrackMediaItem(c_track, j)
                            local c_pos = reaper.GetMediaItemInfo_Value(c_item, "D_POSITION")
                            local c_end = c_pos + reaper.GetMediaItemInfo_Value(c_item, "D_LENGTH")
                            if c_pos < p_end and c_end > p_pos then
                                reaper.SetMediaItemInfo_Value(c_item, "I_CUSTOMCOLOR", native_color)
                            end
                        end
                    end
                end
            end
        end
    elseif ctx_type == "Tracks" then
        for i = 0, cnt - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", native_color)
            if apply_to_children and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                for _, c_track in ipairs(GetChildTracks(track)) do
                    reaper.SetMediaTrackInfo_Value(c_track, "I_CUSTOMCOLOR", native_color)
                end
            end
        end
    elseif ctx_type == "Markers" then
        local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local i = 0
        while true do
            local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers3(0, i)
            if retval == 0 then break end
            if (isrgn and not (rgnend < ts_start or pos > ts_end)) or (not isrgn and (pos >= ts_start and pos <= ts_end)) then
                reaper.SetProjectMarker4(0, idx, isrgn, pos, rgnend, name, native_color)
            end
            i = i + 1
        end
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Apply Color Palette", -1)
    
    return auto_close 
end

local function HSVtoHSL(h, s, v)
    local l = v * (1 - s / 2)
    local sl = 0
    if l > 0 and l < 1 then sl = (v - l) / math.min(l, 1 - l) end
    return h, sl, l
end

function JKK_ColorPalette_Draw(ctx)
    local should_close = false
    local total_palettes = #default_palettes + #user_palettes
    if current_palette_idx > total_palettes or current_palette_idx < 1 then 
        current_palette_idx = 1 
    end

    local current_palette_list = (current_palette_idx <= #default_palettes) and default_palettes or user_palettes
    local local_idx = (current_palette_idx <= #default_palettes) and current_palette_idx or (current_palette_idx - #default_palettes)
    local active_palette = current_palette_list[local_idx]

    local ctx_type, _, ctx_desc = GetSelectionContext(ctx)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xE3DB8EFF)
    reaper.ImGui_Text(ctx, ctx_desc)
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "<", 25, 23) then
        current_palette_idx = current_palette_idx - 1
        if current_palette_idx < 1 then current_palette_idx = total_palettes end
        SaveState()
    end
    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_SetNextItemWidth(ctx, 220)
    if reaper.ImGui_BeginCombo(ctx, "##PaletteCombo", " " .. active_palette.name, reaper.ImGui_ComboFlags_HeightLargest()) then
        for i, p in ipairs(default_palettes) do
            if reaper.ImGui_Selectable(ctx, " " .. p.name, current_palette_idx == i) then
                current_palette_idx = i; SaveState()
            end
        end
        reaper.ImGui_Separator(ctx)
        for i, p in ipairs(user_palettes) do
            local global_i = #default_palettes + i
            if reaper.ImGui_Selectable(ctx, " " .. p.name, current_palette_idx == global_i) then
                current_palette_idx = global_i; SaveState()
            end
        end
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_Selectable(ctx, " + Add Palette (Copy Current)") then
            local new_pal = { name = "User_" .. active_palette.name, colors = {} }
            for _, c in ipairs(active_palette.colors) do table.insert(new_pal.colors, c) end
            table.insert(user_palettes, new_pal)
            data_module.SaveUserPalettes(user_palettes)
            current_palette_idx = #default_palettes + #user_palettes
            SaveState()
        end
        reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, ">", 25, 23) then
        current_palette_idx = current_palette_idx + 1
        if current_palette_idx > total_palettes then current_palette_idx = 1 end
        SaveState()
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "🎲##RandPal", 30, 23) then
        current_palette_idx = math.random(1, total_palettes)
        SaveState()
    end

    if current_palette_idx > #default_palettes then
        reaper.ImGui_SameLine(ctx)
        if is_editing_name then
            reaper.ImGui_SetNextItemWidth(ctx, 110)
            local changed, new_text = reaper.ImGui_InputText(ctx, "##EditName", editing_name_str)
            if changed then editing_name_str = new_text end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Save", 45, 23) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
                active_palette.name = editing_name_str
                data_module.SaveUserPalettes(user_palettes)
                is_editing_name = false
            end
        else
            if reaper.ImGui_Button(ctx, "Edit", 45, 23) then
                is_editing_name = true
                editing_name_str = active_palette.name
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Del", 40, 23) then
                table.remove(user_palettes, local_idx)
                data_module.SaveUserPalettes(user_palettes)
                current_palette_idx = 1
                SaveState()
            end
        end
    else
        is_editing_name = false
    end
    reaper.ImGui_Spacing(ctx)

    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local cur_y = reaper.ImGui_GetCursorPosY(ctx)
    local win_h = reaper.ImGui_GetWindowHeight(ctx)
    
    local bottom_h = 95 
    local pad_y = 8
    local grid_h = win_h - bottom_h - pad_y - cur_y
    if grid_h < 40 then grid_h = 40 end

    local spacing_x, spacing_y = 8, 4
    local best_cols, best_rows = 12, 2
    local best_diff = 999999
    
    local factors = {{24,1}, {12,2}, {8,3}, {6,4}, {4,6}, {3,8}, {2,12}}
    for _, f in ipairs(factors) do
        local c, r = f[1], f[2]
        local w = (avail_w - (c - 1) * spacing_x) / c
        local h = (grid_h - (r - 1) * spacing_y) / r
        if w > 5 and h > 5 then
            local diff = math.abs(w - h)
            if diff < best_diff then
                best_diff = diff
                best_cols = c
                best_rows = r
            end
        end
    end

    local cell_w = (avail_w - (best_cols - 1) * spacing_x) / best_cols
    local cell_h = (grid_h - (best_rows - 1) * spacing_y) / best_rows

    for i = 1, 24 do
        local col_u32 = active_palette.colors[i]
        reaper.ImGui_PushID(ctx, "ColorCell_" .. i)
        if reaper.ImGui_ColorButton(ctx, "##Btn", col_u32, 0, cell_w, cell_h) then
            if ApplyColor(col_u32, ctx) then should_close = true end
        end
        
        if reaper.ImGui_IsItemHovered(ctx) then
            local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(col_u32)
            local h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
            local hh, ss, ll = HSVtoHSL(h, s, v)
            local hex = string.format("#%02X%02X%02X%02X", math.floor(r*255), math.floor(g*255), math.floor(b*255), math.floor(a*255))
            reaper.ImGui_SetTooltip(ctx, string.format("HEX: %s\nRGBA: %.0f, %.0f, %.0f, %.0f\nHSL: %.0f, %.2f, %.2f", hex, r*255, g*255, b*255, a*255, hh*360, ss, ll))
        end

        if current_palette_idx > #default_palettes and reaper.ImGui_IsItemClicked(ctx, 1) then
            reaper.ImGui_OpenPopup(ctx, "ColorEditPopup")
        end
        if reaper.ImGui_BeginPopup(ctx, "ColorEditPopup") then
            reaper.ImGui_Text(ctx, "Edit Color")
            local changed, new_col = reaper.ImGui_ColorPicker4(ctx, "##EditColor", col_u32, reaper.ImGui_ColorEditFlags_AlphaBar() | reaper.ImGui_ColorEditFlags_DisplayHex() | reaper.ImGui_ColorEditFlags_DisplayRGB() | reaper.ImGui_ColorEditFlags_DisplayHSV())
            if changed then
                active_palette.colors[i] = new_col
                data_module.SaveUserPalettes(user_palettes)
            end
            reaper.ImGui_EndPopup(ctx)
        end
        reaper.ImGui_PopID(ctx)

        if i % best_cols ~= 0 then reaper.ImGui_SameLine(ctx) end
    end

    local target_y = win_h - bottom_h - pad_y
    if reaper.ImGui_GetCursorPosY(ctx) < target_y then
        reaper.ImGui_SetCursorPosY(ctx, target_y)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    local c1, v1 = reaper.ImGui_Checkbox(ctx, " Apply to Children", apply_to_children)
    if c1 then apply_to_children = v1; SaveState() end
    reaper.ImGui_SameLine(ctx, avail_w / 2 + 10)
    local c2, v2 = reaper.ImGui_Checkbox(ctx, " Auto Close", auto_close)
    if c2 then auto_close = v2; SaveState() end
    reaper.ImGui_Spacing(ctx)

    local clear_w = 90
    local rnd_w = (avail_w - clear_w - (spacing_x * 2)) / 2
    local btn_h = 45 

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x24866FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1F735FFF)

    if reaper.ImGui_Button(ctx, "Random from Palette", rnd_w, btn_h) then
        if active_palette and #active_palette.colors > 0 then
            if ApplyColor(active_palette.colors[math.random(1, 24)], ctx) then should_close = true end
        end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Absolute Random", rnd_w, btn_h) then
        local rnd_u32 = (math.random(0,255)<<24) | (math.random(0,255)<<16) | (math.random(0,255)<<8) | 255
        if ApplyColor(rnd_u32, ctx) then should_close = true end
    end
    
    reaper.ImGui_PopStyleColor(ctx, 3)

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Clear Color", clear_w, btn_h) then 
        if ApplyColor(0, ctx) then should_close = true end
    end
    
    return should_close
end

return { JKK_ColorPalette_Draw = JKK_ColorPalette_Draw }