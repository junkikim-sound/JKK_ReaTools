--========================================================
-- @title JKK_ReaTools_NEW_ColorPaletteLite
-- @author Junki Kim
-- @noindex
--========================================================

local reaper = reaper
local source = debug.getinfo(1, "S").source or ""
local script_dir = source:match("^@(.+[\\/])") or ""
local data_path = script_dir .. "JKK_ColorPalette_Data.lua"
local sel_path = script_dir .. "JKK_SelectionManager.lua"
local sel_mgr = _G.JKK_SelectionManager or (reaper.file_exists(sel_path) and dofile(sel_path))

local function PushThemeButton(ctx, kind)
    local theme = _G.JKK_Theme
    if theme and theme.PushButton then
        theme.PushButton(ctx, kind)
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x24866FFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1F735FFF)
    end
end

local function PopThemeButton(ctx)
    local theme = _G.JKK_Theme
    if theme and theme.PopButton then
        theme.PopButton(ctx)
    else
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
end

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

-- UI zoom factor published by JKK_ReaTools (1.0 = original design size).
local function S(v) return v * (JKK_UI_SCALE or 1) end

local ext_section = "JKK_ReaTools_ColorPalette"
local current_palette_idx = tonumber(reaper.GetExtState(ext_section, "palette_idx")) or 1
local apply_to_children = reaper.GetExtState(ext_section, "apply_to_children") == "1"

local function SaveState()
    reaper.SetExtState(ext_section, "palette_idx", tostring(current_palette_idx), true)
    reaper.SetExtState(ext_section, "apply_to_children", apply_to_children and "1" or "0", true)
end

local last_user_palettes_rev = ""

-- 스탠드얼론 ColorPalette와 프리셋 및 옵션 실시간 동기화
local function SyncSharedState()
    local ext_idx = tonumber(reaper.GetExtState(ext_section, "palette_idx"))
    if ext_idx and ext_idx >= 1 and ext_idx ~= current_palette_idx then
        current_palette_idx = ext_idx
    end

    local ext_children = (reaper.GetExtState(ext_section, "apply_to_children") == "1")
    if ext_children ~= apply_to_children then
        apply_to_children = ext_children
    end

    -- 스탠드얼론에서 유저 팔레트를 추가/삭제/이름변경 했을 때 갱신
    if data_module and type(data_module.LoadUserPalettes) == "function" then
        local ext_rev = reaper.GetExtState(ext_section, "user_palettes_rev")
        if ext_rev ~= last_user_palettes_rev then
            last_user_palettes_rev = ext_rev
            local ok, result = pcall(data_module.LoadUserPalettes)
            if ok and type(result) == "table" then
                user_palettes = result
            end
        end
    end
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

local function GetPaletteName(palette)
    return (palette and palette.name and tostring(palette.name)) or "Unnamed Palette"
end

local function GetPaletteColor(palette, index)
    if not palette or type(palette.colors) ~= "table" then return 0 end
    return tonumber(palette.colors[index]) or 0
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

local function GetTargetContext(mode, is_active)
    if not is_active then return "None", {}, "No active selection" end
    if mode == "Item" then
        local targets = sel_mgr.GetSelectedItems()
        return "Items", targets, string.format("Selected %d Items", #targets)
    elseif mode == "Track" then
        local targets = sel_mgr.GetSelectedTracks()
        return "Tracks", targets, string.format("Selected %d Tracks", #targets)
    elseif mode == "Region/Marker" then
        local sel_r, sel_m = sel_mgr.GetSelectedRegionMarkers()
        local list = (#sel_r > 0 or #sel_m > 0) and {} or nil
        if list then
            for _, v in ipairs(sel_r) do list[#list + 1] = v.pm end
            for _, v in ipairs(sel_m) do list[#list + 1] = v.pm end
        else
            local ts_r, ts_m = sel_mgr.GetTimeSelectionRegionMarkers()
            list = {}
            for _, v in ipairs(ts_r) do list[#list + 1] = v.pm end
            for _, v in ipairs(ts_m) do list[#list + 1] = v.pm end
        end
        return "Markers", list, string.format("Timeline Targets: %d", #list)
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

local RECENT_MAX = 8
local recent_colors = {}
do
    local saved = reaper.GetExtState(ext_section, "recent_colors")
    for hex in saved:gmatch("[^,]+") do
        local value = tonumber(hex, 16)
        if value and #recent_colors < RECENT_MAX then recent_colors[#recent_colors + 1] = value end
    end
end

local wheel_color = tonumber(reaper.GetExtState(ext_section, "wheel_color"), 16) or recent_colors[1] or 0x068FC3FF
local wheel_pending = false

local function SaveRecentColors()
    local parts = {}
    for i, color in ipairs(recent_colors) do parts[i] = string.format("%08X", color) end
    reaper.SetExtState(ext_section, "recent_colors", table.concat(parts, ","), true)
    reaper.SetExtState(ext_section, "wheel_color", string.format("%08X", wheel_color), true)
end

local function RememberColor(color)
    if color == 0 then return end
    for i = #recent_colors, 1, -1 do
        if recent_colors[i] == color then table.remove(recent_colors, i) end
    end
    table.insert(recent_colors, 1, color)
    while #recent_colors > RECENT_MAX do table.remove(recent_colors) end
    SaveRecentColors()
end

local function ApplyAndRemember(color, mode, is_active)
    if ApplyColor(color, mode, is_active) then RememberColor(color) end
end

local function RandomOpaqueColor()
    return (math.random(0, 255) << 24) | (math.random(0, 255) << 16) | (math.random(0, 255) << 8) | 255
end

local function ShowHexTooltip(ctx, color)
    if reaper.ImGui_IsItemHovered(ctx) then
        local r, g, b = reaper.ImGui_ColorConvertU32ToDouble4(color)
        reaper.ImGui_SetTooltip(ctx, string.format("#%02X%02X%02X",
            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
    end
end

local COLOR_MENU_ID = "##JKKLiteColorMenu"

local function DrawColorMenu(ctx, mode, is_active)
    if not reaper.ImGui_BeginPopup(ctx, COLOR_MENU_ID) then return end

    if reaper.ImGui_MenuItem(ctx, "Apply to Children", nil, apply_to_children) then
        apply_to_children = not apply_to_children
        SaveState()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Also color the children of folder tracks\n(and child items under folder items).")
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_MenuItem(ctx, "Clear Recent Colors", nil, false, #recent_colors > 0) then
        recent_colors = {}
        SaveRecentColors()
    end
    if reaper.ImGui_MenuItem(ctx, "Open Color Palette...") then
        local cmd_id = reaper.NamedCommandLookup("_RS21bfe323091eb5e55fefd971863023bc6e7449b0")
        if cmd_id ~= 0 then reaper.Main_OnCommand(cmd_id, 0) end
    end

    reaper.ImGui_EndPopup(ctx)
end

local function JKK_ColorPalette_Draw(ctx, mode, is_active)
    SyncSharedState()

    local available_width, available_height = reaper.ImGui_GetContentRegionAvail(ctx)
    local frame_height = reaper.ImGui_GetFrameHeight(ctx)
    local _, spacing_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    spacing_y = spacing_y or S(6)
    local spacing_x = spacing_y

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
    local active_palette = palettes[current_palette_idx]

    local main_height = math.max(S(60), available_height - frame_height - spacing_y * 1.5)
    local wheel_size = math.min(main_height - S(4), available_width * 0.35)
    if wheel_size < S(60) then wheel_size = S(60) end
    local right_width = math.max(S(1), available_width - wheel_size - spacing_x)

    local no_scroll_flags = reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    local child_flags_none = reaper.ImGui_ChildFlags_None and reaper.ImGui_ChildFlags_None() or 0

    -- [좌측] 휠 (Gradient 영역)
    if reaper.ImGui_BeginChild(ctx, "ColorWheelArea", wheel_size, main_height, child_flags_none, no_scroll_flags) then
        local flags = reaper.ImGui_ColorEditFlags_PickerHueWheel()
            | reaper.ImGui_ColorEditFlags_NoSidePreview()
            | reaper.ImGui_ColorEditFlags_NoInputs()
            | reaper.ImGui_ColorEditFlags_NoAlpha()
            | reaper.ImGui_ColorEditFlags_NoLabel()
            | reaper.ImGui_ColorEditFlags_NoSmallPreview()
            | reaper.ImGui_ColorEditFlags_NoTooltip()

        reaper.ImGui_SetNextItemWidth(ctx, wheel_size)
        local changed, new_color = reaper.ImGui_ColorPicker4(ctx, "##JKKLiteWheel", wheel_color, flags)
        if changed then
            wheel_color = (new_color & 0xFFFFFF00) | 0xFF
            wheel_pending = true
        end
        if reaper.ImGui_IsItemClicked(ctx, 1) then reaper.ImGui_OpenPopup(ctx, COLOR_MENU_ID) end
        
        if wheel_pending and not reaper.ImGui_IsMouseDown(ctx, 0) then
            wheel_pending = false
            if is_active then
                ApplyAndRemember(wheel_color, mode, is_active)
            else
                SaveRecentColors()
            end
        end
        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_SameLine(ctx, 0, spacing_x)

    -- [우측] 프리셋 셀렉터 및 팔레트 그리드 영역
    if reaper.ImGui_BeginChild(ctx, "ColorPaletteArea", right_width, main_height, child_flags_none, no_scroll_flags) then
        local nav_width = S(23)
        local rnd_width = S(28)
        local combo_width = math.max(S(40), right_width - nav_width * 2 - rnd_width - spacing_x * 3)

        if reaper.ImGui_ArrowButton(ctx, "##JKKLitePalettePrev", reaper.ImGui_Dir_Left()) then
            current_palette_idx = current_palette_idx - 1
            if current_palette_idx < 1 then current_palette_idx = #palettes end
            SaveState()
        end
        reaper.ImGui_SameLine(ctx, 0, spacing_x)
        
        reaper.ImGui_SetNextItemWidth(ctx, combo_width)
        if reaper.ImGui_BeginCombo(ctx, "##JKKLitePaletteCombo", " " .. GetPaletteName(active_palette), reaper.ImGui_ComboFlags_HeightLargest()) then
            for index, palette in ipairs(palettes) do
                if reaper.ImGui_Selectable(ctx, GetPaletteName(palette) .. "##pal_" .. index, current_palette_idx == index) then
                    current_palette_idx = index
                    SaveState()
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        
        reaper.ImGui_SameLine(ctx, 0, spacing_x)
        if reaper.ImGui_ArrowButton(ctx, "##JKKLitePaletteNext", reaper.ImGui_Dir_Right()) then
            current_palette_idx = current_palette_idx + 1
            if current_palette_idx > #palettes then current_palette_idx = 1 end
            SaveState()
        end
        
        reaper.ImGui_SameLine(ctx, 0, spacing_x)
        if reaper.ImGui_Button(ctx, "🎲", rnd_width, frame_height) then
            current_palette_idx = math.random(1, #palettes)
            SaveState()
        end

        reaper.ImGui_Spacing(ctx)
        
        local current_y = reaper.ImGui_GetCursorPosY(ctx)
        local grid_height = math.max(S(20), main_height - current_y - S(2)) - 10
        
        local gap_x, gap_y = S(4), S(4)
        local cols, rows = 6, 4
        local cell_w = math.max(S(4), (right_width - (cols - 1) * gap_x) / cols)
        local cell_h = math.max(S(6), (grid_height - (rows - 1) * gap_y) / rows)

        reaper.ImGui_BeginDisabled(ctx, not is_active)
        for index = 1, 24 do
            local color = GetPaletteColor(active_palette, index)
            reaper.ImGui_PushID(ctx, "PalColor_" .. index)
            if reaper.ImGui_ColorButton(ctx, "##PalCol", color, 0, cell_w, cell_h) then
                ApplyAndRemember(color, mode, is_active)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                local r, g, b = reaper.ImGui_ColorConvertU32ToDouble4(color)
                reaper.ImGui_SetTooltip(ctx, string.format("#%02X%02X%02X", math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5)))
            end
            reaper.ImGui_PopID(ctx)
            if index % cols ~= 0 and index < 24 then
                reaper.ImGui_SameLine(ctx, 0, gap_x)
            end
        end
        reaper.ImGui_EndDisabled(ctx)

        reaper.ImGui_EndChild(ctx)
    end

    -- [하단] Recent Colors + 랜덤/클리어 3종 버튼 + 메뉴
    local menu_width = frame_height
    local btn_pal_rnd = S(58)
    local btn_all_rnd = S(58)
    local btn_clear   = S(46)
    
    local action_btns_width = btn_pal_rnd + btn_all_rnd + btn_clear + menu_width + (spacing_x * 4)
    local swatch = frame_height
    
    local fit = math.floor((available_width - action_btns_width) / (swatch + S(4)))
    local count = math.max(0, math.min(#recent_colors, fit))
    
    reaper.ImGui_SetCursorPosY(ctx, math.max(reaper.ImGui_GetCursorPosY(ctx), available_height - frame_height))

    for index = 1, count do
        local color = recent_colors[index]
        if index > 1 then reaper.ImGui_SameLine(ctx, 0, S(4)) end
        reaper.ImGui_PushID(ctx, "JKKLiteRecent_" .. index)
        if reaper.ImGui_ColorButton(ctx, "##Recent", color, reaper.ImGui_ColorEditFlags_NoTooltip(), swatch, swatch) then
            wheel_color = color
            if is_active then ApplyAndRemember(color, mode, is_active) end
        end
        ShowHexTooltip(ctx, color)
        reaper.ImGui_PopID(ctx)
    end
    if count == 0 then
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextDisabled(ctx, "Recent")
    end

    reaper.ImGui_SameLine(ctx, 0, 0)
    reaper.ImGui_SetCursorPosX(ctx, math.max(0, available_width - action_btns_width + spacing_x))

    reaper.ImGui_BeginDisabled(ctx, not is_active)
    
    PushThemeButton(ctx, "confirm")
    if reaper.ImGui_Button(ctx, "Pal Rnd", btn_pal_rnd, frame_height) then
        if active_palette then ApplyAndRemember(GetPaletteColor(active_palette, math.random(1, 24)), mode, is_active) end
    end
    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then reaper.ImGui_SetTooltip(ctx, "Random from Palette") end

    reaper.ImGui_SameLine(ctx, 0, spacing_x)

    if reaper.ImGui_Button(ctx, "All Rnd", btn_all_rnd, frame_height) then
        local color = RandomOpaqueColor()
        wheel_color = color
        ApplyAndRemember(color, mode, is_active)
    end
    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then reaper.ImGui_SetTooltip(ctx, "Absolute Random") end
    PopThemeButton(ctx)
    
    reaper.ImGui_SameLine(ctx, 0, spacing_x)

    if reaper.ImGui_Button(ctx, "Clear", btn_clear, frame_height) then
        ApplyColor(0, mode, is_active)
    end
    if reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then reaper.ImGui_SetTooltip(ctx, "Clear Color") end
    
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_SameLine(ctx, 0, spacing_x)

    if reaper.ImGui_Button(ctx, "...##JKKLiteColorMenuButton", menu_width, frame_height) then
        reaper.ImGui_OpenPopup(ctx, COLOR_MENU_ID)
    end
    DrawColorMenu(ctx, mode, is_active)
end

return { JKK_ColorPalette_Draw = JKK_ColorPalette_Draw }