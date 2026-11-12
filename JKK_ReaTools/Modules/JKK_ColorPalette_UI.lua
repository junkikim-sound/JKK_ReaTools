--========================================================
-- @title JKK_ColorPalette_UI
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local data_path = script_dir .. "JKK_ColorPalette_Data.lua"
local data_module = reaper.file_exists(data_path) and dofile(data_path) or nil
local sel_path = script_dir .. "JKK_SelectionManager.lua"
local sel_mgr = _G.JKK_SelectionManager or (reaper.file_exists(sel_path) and dofile(sel_path))

local theme = _G.JKK_Theme or {}
local PushButton = theme.PushButton or function(c, kind)
    reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_Button(), 0x24866FFF)
    reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
    reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_ButtonActive(), 0x1F735FFF)
end
local PopButton = theme.PopButton or function(c)
    reaper.ImGui_PopStyleColor(c, 3)
end
local PushText = theme.PushText or function(c, role)
    reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_Text(), 0xE3DB8EFF)
end
local PopText = theme.PopText or function(c)
    reaper.ImGui_PopStyleColor(c, 1)
end

local default_palettes = data_module and data_module.default_palettes or {}
local user_palettes = data_module and data_module.LoadUserPalettes() or {}

-- ColorPaletteLite와 동일한 ExtState 섹션 공유
local ext_section = "JKK_ReaTools_ColorPalette"
local current_palette_idx = tonumber(reaper.GetExtState(ext_section, "palette_idx")) or 1
local auto_close = (reaper.GetExtState(ext_section, "auto_close") == "1")
local apply_to_children = (reaper.GetExtState(ext_section, "apply_to_children") == "1")
local is_editing_name = false
local editing_name_str = ""

local function SaveState(user_palettes_modified)
    reaper.SetExtState(ext_section, "palette_idx", tostring(current_palette_idx), true)
    reaper.SetExtState(ext_section, "auto_close", auto_close and "1" or "0", true)
    reaper.SetExtState(ext_section, "apply_to_children", apply_to_children and "1" or "0", true)
    if user_palettes_modified then
        reaper.SetExtState(ext_section, "user_palettes_rev", tostring(reaper.time_precise()), true)
    end
end

-- ColorPaletteLite와 프리셋 및 옵션 실시간 동기화
local function SyncSharedState()
    local ext_idx = tonumber(reaper.GetExtState(ext_section, "palette_idx"))
    if ext_idx and ext_idx >= 1 and ext_idx ~= current_palette_idx then
        current_palette_idx = ext_idx
    end

    local ext_children = (reaper.GetExtState(ext_section, "apply_to_children") == "1")
    if ext_children ~= apply_to_children then
        apply_to_children = ext_children
    end
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
    if #name > max_len then return name:sub(1, max_len) .. "..." end
    return name
end

local function GetSelectionContext(is_imgui_focused)
    local mode, is_active = sel_mgr.Update(is_imgui_focused)
    if not is_active or mode == "None" then
        return "None", 0, "No Selection"
    end

    local max_chars = 30
    if mode == "Item" then
        local items = sel_mgr.GetSelectedItems()
        local cnt = #items
        local take = cnt > 0 and reaper.GetActiveTake(items[1]) or nil
        local name = take and reaper.GetTakeName(take) or "Item"
        return "Items", cnt, string.format("Selected %d Items (%s)", cnt, TruncateName(name, max_chars))

    elseif mode == "Track" then
        local tracks = sel_mgr.GetSelectedTracks()
        local cnt = #tracks
        local _, name = reaper.GetTrackName(tracks[1])
        return "Tracks", cnt, string.format("Selected %d Tracks (%s)", cnt, TruncateName(name, max_chars))

    elseif mode == "Region/Marker" then
        local sel_r, sel_m = sel_mgr.GetSelectedRegionMarkers()
        if #sel_r == 0 and #sel_m == 0 then
            sel_r, sel_m = sel_mgr.GetTimeSelectionRegionMarkers()
        end
        local cnt = #sel_r + #sel_m
        if cnt > 0 then
            local type_str = (#sel_r > 0 and #sel_m > 0) and "Region/Marker" or (#sel_r > 0 and "Region" or "Marker")
            local first = sel_r[1] or sel_m[1]
            local first_name = (first.name ~= "") and first.name or type_str
            return "Markers", cnt, string.format("Selected %d %s (%s)", cnt, type_str, TruncateName(first_name, max_chars))
        end
        return "None", 0, "No Regions/Markers in Time Selection"
    end
    return "None", 0, "No Selection"
end

local function ApplyColor(u32_color, is_imgui_focused)
    local r, g, b = reaper.ImGui_ColorConvertU32ToDouble4(u32_color)
    local native_color = (u32_color == 0) and 0 or (reaper.ColorToNative(math.floor(r*255 + 0.5), math.floor(g*255 + 0.5), math.floor(b*255 + 0.5)) | 0x1000000)
    
    local ctx_type, cnt = GetSelectionContext(is_imgui_focused)
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
        local sel_r, sel_m = sel_mgr.GetSelectedRegionMarkers()
        if #sel_r == 0 and #sel_m == 0 then
            sel_r, sel_m = sel_mgr.GetTimeSelectionRegionMarkers()
        end
        for _, entry in ipairs(sel_r) do
            reaper.SetProjectMarker4(0, entry.index, true, entry.pos, entry.rgnend, entry.name, native_color)
        end
        for _, entry in ipairs(sel_m) do
            reaper.SetProjectMarker4(0, entry.index, false, entry.pos, entry.rgnend, entry.name, native_color)
        end
        if reaper.UpdateTimeline then reaper.UpdateTimeline() end
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
    SyncSharedState()

    local is_focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
    local should_close = false
    local total_palettes = #default_palettes + #user_palettes
    if current_palette_idx > total_palettes or current_palette_idx < 1 then 
        current_palette_idx = 1 
    end

    local current_palette_list = (current_palette_idx <= #default_palettes) and default_palettes or user_palettes
    local local_idx = (current_palette_idx <= #default_palettes) and current_palette_idx or (current_palette_idx - #default_palettes)
    local active_palette = current_palette_list[local_idx]

    local _, _, ctx_desc = GetSelectionContext(is_focused)

    PushText(ctx, "accent")
    reaper.ImGui_Text(ctx, ctx_desc)
    PopText(ctx)
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
            SaveState(true)
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
                SaveState(true)
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
                SaveState(true)
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
            if ApplyColor(col_u32, is_focused) then should_close = true end
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
                SaveState(true)
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

    PushButton(ctx, "confirm")

    if reaper.ImGui_Button(ctx, "Random from Palette", rnd_w, btn_h) then
        if active_palette and #active_palette.colors > 0 then
            if ApplyColor(active_palette.colors[math.random(1, 24)], is_focused) then should_close = true end
        end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Absolute Random", rnd_w, btn_h) then
        local rnd_u32 = (math.random(0,255)<<24) | (math.random(0,255)<<16) | (math.random(0,255)<<8) | 255
        if ApplyColor(rnd_u32, is_focused) then should_close = true end
    end

    PopButton(ctx)

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Clear Color", clear_w, btn_h) then 
        if ApplyColor(0, is_focused) then should_close = true end
    end
    
    return should_close
end

return { JKK_ColorPalette_Draw = JKK_ColorPalette_Draw }