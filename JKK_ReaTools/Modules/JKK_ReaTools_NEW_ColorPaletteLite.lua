--========================================================
-- @title JKK_ReaTools_NEW_ColorPaletteLite
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper
local source = debug.getinfo(1, "S").source or ""
local script_dir = source:match("^@(.+[\\/])") or ""
local data_path = script_dir .. "JKK_ColorPalette_Data.lua"

local data_module, data_error
if reaper.file_exists(data_path) then
    local ok, result = pcall(dofile, data_path)
    if ok and type(result) == "table" then
        data_module = result
    else
        data_error = tostring(result)
    end
else
    data_error = "JKK_ColorPalette_Data.lua not found in Modules folder."
end

local default_palettes = data_module and data_module.default_palettes or {}
local user_palettes = {}
if data_module and type(data_module.LoadUserPalettes) == "function" then
    local ok, result = pcall(data_module.LoadUserPalettes)
    if ok and type(result) == "table" then
        user_palettes = result
    else
        data_error = "Could not load user palettes: " .. tostring(result)
    end
end

local ext_section = "JKK_ReaTools_ColorPalette"
local current_palette_idx = tonumber(reaper.GetExtState(ext_section, "palette_idx")) or 1
local apply_to_children = reaper.GetExtState(ext_section, "apply_to_children") == "1"

local function SaveState()
    reaper.SetExtState(ext_section, "palette_idx", tostring(current_palette_idx), true)
    reaper.SetExtState(ext_section, "apply_to_children", apply_to_children and "1" or "0", true)
end

local function GetAllPalettes()
    local all = {}
    for _, palette in ipairs(default_palettes or {}) do
        all[#all + 1] = palette
    end
    for _, palette in ipairs(user_palettes or {}) do
        all[#all + 1] = palette
    end
    return all
end

local function GetChildTracks(parent_track)
    local children = {}
    if not parent_track then return children end

    local parent_depth = reaper.GetTrackDepth(parent_track)
    local parent_index = (reaper.CSurf_TrackToID(parent_track, false) or 1) - 1
    for i = parent_index + 1, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if not track then break end
        if reaper.GetTrackDepth(track) > parent_depth then
            children[#children + 1] = track
        else
            break
        end
    end
    return children
end

local function GetTimelineTargets()
    local targets = {}
    if not (reaper.GetNumRegionsOrMarkers and reaper.GetRegionOrMarker
        and reaper.GetRegionOrMarkerInfo_Value) then
        return targets
    end

    local marker_count, region_count = reaper.GetNumRegionsOrMarkers(0)
    local total = (marker_count or 0) + (region_count or 0)
    local explicitly_selected = {}

    -- Prefer actual Region/Marker UI selection when it exists.
    for index = 0, total - 1 do
        local marker = reaper.GetRegionOrMarker(0, index, "")
        if marker and reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_UISEL") > 0 then
            explicitly_selected[#explicitly_selected + 1] = marker
        end
    end

    if #explicitly_selected > 0 then
        return explicitly_selected
    end

    -- Otherwise, when Timeline mode comes from a time selection, color every
    -- Region/Marker intersecting that range, matching the original palette.
    local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_end <= ts_start then return targets end

    for index = 0, total - 1 do
        local marker = reaper.GetRegionOrMarker(0, index, "")
        if marker then
            local is_region = reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_ISREGION") == 1
            local pos = reaper.GetRegionOrMarkerInfo_Value(0, marker, "D_STARTPOS")
            local ending = reaper.GetRegionOrMarkerInfo_Value(0, marker, "D_ENDPOS")
            local overlaps = is_region
                and pos < ts_end and ending > ts_start
                or (not is_region and pos >= ts_start and pos <= ts_end)
            if overlaps then targets[#targets + 1] = marker end
        end
    end
    return targets
end

local function GetTargetContext(mode, is_active)
    if not is_active then return "None", {}, "No active selection" end

    local targets = {}
    if mode == "Item" then
        for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            if item then targets[#targets + 1] = item end
        end
        return "Items", targets, string.format("Selected %d Items", #targets)
    elseif mode == "Track" then
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            if track then targets[#targets + 1] = track end
        end
        return "Tracks", targets, string.format("Selected %d Tracks", #targets)
    elseif mode == "Region/Marker" then
        targets = GetTimelineTargets()
        return "Markers", targets, string.format("Timeline Targets: %d", #targets)
    end
    return "None", {}, "No active selection"
end

local function ColorToNative(u32_color)
    if u32_color == 0 then return 0 end
    local r, g, b = reaper.ImGui_ColorConvertU32ToDouble4(u32_color)
    return reaper.ColorToNative(
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5)
    ) | 0x1000000
end

local function ApplyColor(u32_color, mode, is_active)
    local context_type, targets = GetTargetContext(mode, is_active)
    if context_type == "None" or #targets == 0 then return false end

    local native_color = ColorToNative(u32_color)
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    if context_type == "Items" then
        for _, item in ipairs(targets) do
            reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color)
            if apply_to_children then
                local track = reaper.GetMediaItem_Track(item)
                if track and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_end = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    for _, child_track in ipairs(GetChildTracks(track)) do
                        for j = 0, reaper.CountTrackMediaItems(child_track) - 1 do
                            local child_item = reaper.GetTrackMediaItem(child_track, j)
                            local child_pos = reaper.GetMediaItemInfo_Value(child_item, "D_POSITION")
                            local child_end = child_pos + reaper.GetMediaItemInfo_Value(child_item, "D_LENGTH")
                            if child_pos < item_end and child_end > item_pos then
                                reaper.SetMediaItemInfo_Value(child_item, "I_CUSTOMCOLOR", native_color)
                            end
                        end
                    end
                end
            end
        end
    elseif context_type == "Tracks" then
        for _, track in ipairs(targets) do
            reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", native_color)
            if apply_to_children and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                for _, child_track in ipairs(GetChildTracks(track)) do
                    reaper.SetMediaTrackInfo_Value(child_track, "I_CUSTOMCOLOR", native_color)
                end
            end
        end
    elseif context_type == "Markers" then
        for _, marker in ipairs(targets) do
            reaper.SetRegionOrMarkerInfo_Value(0, marker, "I_CUSTOMCOLOR", native_color)
        end
        if reaper.UpdateTimeline then reaper.UpdateTimeline() end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Apply Color Palette", -1)
    return true
end

local function GetPaletteName(palette)
    return (palette and palette.name and tostring(palette.name)) or "Unnamed Palette"
end

local function GetPaletteColor(palette, index)
    if not palette or type(palette.colors) ~= "table" then return 0 end
    return tonumber(palette.colors[index]) or 0
end

local function DrawPresetSelector(ctx, palettes)
    local available_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local spacing = 5
    local nav_width, random_width = 23, 30
    local combo_width = math.max(64, available_width - nav_width * 2 - random_width - spacing * 3)

    -- Use native ArrowButton widgets with unique IDs instead of literal
    -- angle-bracket labels. This avoids label/ID ambiguity in Dear ImGui.
    if reaper.ImGui_ArrowButton(ctx, "##JKKLitePalettePrevious", reaper.ImGui_Dir_Left()) then
        current_palette_idx = current_palette_idx - 1
        if current_palette_idx < 1 then current_palette_idx = #palettes end
        SaveState()
    end
    reaper.ImGui_SameLine(ctx, 0, spacing)

    local active_palette = palettes[current_palette_idx]
    reaper.ImGui_SetNextItemWidth(ctx, combo_width)
    local preview = " " .. GetPaletteName(active_palette)
    if reaper.ImGui_BeginCombo(ctx, "##JKKLitePaletteCombo", preview,
        reaper.ImGui_ComboFlags_HeightLargest()) then
        for index, palette in ipairs(palettes) do
            local selected = current_palette_idx == index
            if reaper.ImGui_Selectable(ctx, GetPaletteName(palette) .. "##palette_" .. index, selected) then
                current_palette_idx = index
                SaveState()
            end
            if selected then reaper.ImGui_SetItemDefaultFocus(ctx) end
        end
        reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_SameLine(ctx, 0, spacing)
    if reaper.ImGui_ArrowButton(ctx, "##JKKLitePaletteNext", reaper.ImGui_Dir_Right()) then
        current_palette_idx = current_palette_idx + 1
        if current_palette_idx > #palettes then current_palette_idx = 1 end
        SaveState()
    end
    reaper.ImGui_SameLine(ctx, 0, spacing)
    if reaper.ImGui_Button(ctx, "🎲", random_width, 22) then
        current_palette_idx = math.random(1, #palettes)
        SaveState()
    end
    return palettes[current_palette_idx]
end

local function DrawColorGrid(ctx, palette, mode, is_active)
    local available_width, available_height = reaper.ImGui_GetContentRegionAvail(ctx)
    local start_y = reaper.ImGui_GetCursorPosY(ctx)
    local frame_height = reaper.ImGui_GetFrameHeight(ctx)
    local narrow = available_width < 360
    local bottom_reserved = narrow and (frame_height * 3 + 56) or (frame_height + 60)
    local grid_height = math.max(36, available_height - bottom_reserved)

    local gap_x, gap_y = 4, 4
    local factors = { {24, 1}, {12, 2}, {8, 3}, {6, 4}, {4, 6}, {3, 8}, {2, 12} }
    local best_cols, best_rows, best_diff = 6, 4, math.huge
    for _, factor in ipairs(factors) do
        local cols, rows = factor[1], factor[2]
        local cell_w = (available_width - (cols - 1) * gap_x) / cols
        local cell_h = (grid_height - (rows - 1) * gap_y) / rows
        if cell_w >= 8 and cell_h >= 8 then
            local diff = math.abs(cell_w - cell_h)
            if diff < best_diff then
                best_diff = diff
                best_cols, best_rows = cols, rows
            end
        end
    end

    local cell_w = math.max(4, (available_width - (best_cols - 1) * gap_x) / best_cols)
    local cell_h = math.max(8, (grid_height - (best_rows - 1) * gap_y) / best_rows)
    reaper.ImGui_BeginDisabled(ctx, not is_active)
    for index = 1, 24 do
        local color = GetPaletteColor(palette, index)
        reaper.ImGui_PushID(ctx, "JKKLiteColor_" .. index)
        if reaper.ImGui_ColorButton(ctx, "##Color", color, 0, cell_w, cell_h) then
            ApplyColor(color, mode, is_active)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(color)
            local hex = string.format("#%02X%02X%02X%02X",
                math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                math.floor(b * 255 + 0.5), math.floor(a * 255 + 0.5))
            reaper.ImGui_SetTooltip(ctx, hex)
        end
        reaper.ImGui_PopID(ctx)
        if index % best_cols ~= 0 and index < 24 then
            reaper.ImGui_SameLine(ctx, 0, gap_x)
        end
    end
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_SetCursorPosY(ctx, start_y + grid_height)
end

local function DrawActionButtons(ctx, palette, mode, is_active)
    local available_width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    local spacing = 5
    local function StyledButton(label, width, height, callback)
        local use_palette_style = label ~= "Clear Color"
        if use_palette_style then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x24866FFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1F735FFF)
        end
        local clicked = reaper.ImGui_Button(ctx, label, width, height)
        if use_palette_style then reaper.ImGui_PopStyleColor(ctx, 3) end
        if clicked then callback() end
    end

    reaper.ImGui_BeginDisabled(ctx, not is_active)
    if available_width >= 360 then
        local clear_width = 82
        local action_width = math.max(90, (available_width - clear_width - spacing * 2) / 2)
        StyledButton("Random from Palette", action_width, 24, function()
            if palette then ApplyColor(GetPaletteColor(palette, math.random(1, 24)), mode, is_active) end
        end)
        reaper.ImGui_SameLine(ctx, 0, spacing)
        StyledButton("Absolute Random", action_width, 24, function()
            local color = (math.random(0, 255) << 24)
                | (math.random(0, 255) << 16)
                | (math.random(0, 255) << 8) | 255
            ApplyColor(color, mode, is_active)
        end)
        reaper.ImGui_SameLine(ctx, 0, spacing)
        StyledButton("Clear Color", clear_width, 24, function()
            ApplyColor(0, mode, is_active)
        end)
    else
        StyledButton("Random from Palette", available_width, 22, function()
            if palette then ApplyColor(GetPaletteColor(palette, math.random(1, 24)), mode, is_active) end
        end)
        StyledButton("Absolute Random", available_width, 22, function()
            local color = (math.random(0, 255) << 24)
                | (math.random(0, 255) << 16)
                | (math.random(0, 255) << 8) | 255
            ApplyColor(color, mode, is_active)
        end)
        StyledButton("Clear Color", available_width, 22, function()
            ApplyColor(0, mode, is_active)
        end)
    end
    reaper.ImGui_EndDisabled(ctx)
end

local function JKK_ColorPalette_Draw(ctx, mode, is_active)
    local palettes = GetAllPalettes()
    if #palettes == 0 then
        reaper.ImGui_Text(ctx, "No color palettes were found.")
        reaper.ImGui_TextWrapped(ctx, data_error or "Check JKK_ColorPalette_Data.lua.")
        return
    end

    if current_palette_idx < 1 or current_palette_idx > #palettes then
        current_palette_idx = 1
        SaveState()
    end

    local context_type, targets = GetTargetContext(mode, is_active)

    -- Selection context is already displayed by the ReaTools global status;
    -- start this panel directly with the preset selector.
    local palette = DrawPresetSelector(ctx, palettes)
    if not palette then return end
    reaper.ImGui_Spacing(ctx)

    DrawColorGrid(ctx, palette, mode, is_active)

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_BeginTable(ctx, "ApplyRowTable", 2, reaper.ImGui_TableFlags_SizingStretchProp()) then
        reaper.ImGui_TableSetupColumn(ctx, "Left", reaper.ImGui_TableColumnFlags_WidthStretch())
        reaper.ImGui_TableSetupColumn(ctx, "Right", reaper.ImGui_TableColumnFlags_WidthFixed(), 125)
        
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableSetColumnIndex(ctx, 0)
        local changed, new_value = reaper.ImGui_Checkbox(ctx, "Apply Children", apply_to_children)
        if changed then
            apply_to_children = new_value
            SaveState()
        end
        
        reaper.ImGui_TableSetColumnIndex(ctx, 1)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x233C4FFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x435665FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x042239FF)
        if reaper.ImGui_Button(ctx, "Open Color Palette##CustomAction", 125, 22) then
            local cmd_id = reaper.NamedCommandLookup("_RS21bfe323091eb5e55fefd971863023bc6e7449b0")
            if cmd_id ~= 0 then
                reaper.Main_OnCommand(cmd_id, 0)
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_EndTable(ctx)
    end

    DrawActionButtons(ctx, palette, mode, is_active)
end

return { JKK_ColorPalette_Draw = JKK_ColorPalette_Draw }