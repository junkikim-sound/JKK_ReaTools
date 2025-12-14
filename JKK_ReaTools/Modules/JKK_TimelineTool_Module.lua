--========================================================
-- @title JKK_TimelineTool_Module
-- @author Junki Kim
-- @version 0.5.7
-- @noindex
--========================================================

local open = true

local theme_path = reaper.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_Theme/JKK_Theme.lua"
local theme_module = nil
if reaper.file_exists(theme_path) then
    theme_module = dofile(theme_path)
end

local ApplyTheme = theme_module and theme_module.ApplyTheme or function(ctx) return 0, 0 end
local style_pop_count, color_pop_count

-- Color Palette Data (24 Colors)
local region_colors = {
  {10,70,57}, {14,96,78},  {21,139,114}, {23,156,128},  {69,171,148},  {162,202,189}, {121,18,19}, {156,23,24},  {168,58,59},  {179,93,93},  {202,162,162}, {221,195,195},
  {10,43,70}, {15,64,104}, {23,96,156},  {102,143,182}, {171,186,207}, {225,230,237}, {88,114,47}, {125,162,67}, {159,206,85}, {184,239,99}, {205,244,152}, {226,248,200},
}

local create_base_name = ""
local rename_base_name = ""
local selectedColor = nil
local MAX_NAME_LEN = 256

---------------------------------------------------------
-- Functions: Timeline Helpers
---------------------------------------------------------
local function GetTimeSelection()
    local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts == te then return nil end
    return ts, te
end

local function GetOverlappingRegions()
    local ts, te = GetTimeSelection()
    if not ts then return nil end

    local _, numMarkers, numRegions = reaper.CountProjectMarkers(0)
    local total = numMarkers + numRegions

    local list = {}

    for i = 0, total - 1 do
        local retval, isRegion, pos, rgnEnd, name, index, color =
            reaper.EnumProjectMarkers3(0, i)

        if isRegion and rgnEnd > ts and pos < te then
            list[#list+1] = {
                index = index,
                pos = pos,
                rgnEnd = rgnEnd,
                name = name,
                color = color
            }
        end
    end

    return list
end

---------------------------------------------------------
-- Functions: Rename Overlapping Regions
---------------------------------------------------------
local function RenameRegions(regionList, baseName)
    if not baseName or baseName == "" then return end
    for i, rgn in ipairs(regionList) do
        local newName = string.format("%s_%02d", baseName, i)
        reaper.SetProjectMarker3(0, rgn.index, true, rgn.pos, rgn.rgnEnd, newName, rgn.color)
    end
end

local function ApplyChanges()
    local regions = GetOverlappingRegions()
    if not regions or #regions == 0 then
        return
    end

    reaper.Undo_BeginBlock()
    RenameRegions(regions, rename_base_name)
    reaper.Undo_EndBlock("Batch Edit Regions", -1)
end

---------------------------------------------------------
-- Functions: Delete Overlapping Regions
---------------------------------------------------------
local function DeleteOverlappingRegions()
    local regions = GetOverlappingRegions()
    if not regions or #regions == 0 then return end

    reaper.Undo_BeginBlock()

    for i = #regions, 1, -1 do
        local rgn = regions[i]
        reaper.DeleteProjectMarker(0, rgn.index, true)
    end

    reaper.Undo_EndBlock("Delete Overlapping Regions", -1)
    reaper.UpdateArrange()
end

---------------------------------------------------------
-- Functions: Delete All Regions
---------------------------------------------------------
local function DeleteAllRegions()
    local _, numMarkers, numRegions = reaper.CountProjectMarkers(0)
    local total = numMarkers + numRegions

    if numRegions == 0 then return end

    reaper.Undo_BeginBlock()

    for i = total - 1, 0, -1 do
        local _, isRegion, _, _, _, index = reaper.EnumProjectMarkers3(0, i)
        if isRegion then
            reaper.DeleteProjectMarker(0, index, true)
        end
    end

    reaper.Undo_EndBlock("Delete All Regions", -1)
    reaper.UpdateArrange()
end

---------------------------------------------------------
-- Function: Region Color
---------------------------------------------------------
local function SetRegionColors(colorTable)
    if colorTable == nil then return end

    local regions = GetOverlappingRegions()
    if not regions or #regions == 0 then
        return
    end

    local newColor
    
    if colorTable == 0 then
        newColor = 0
    
    elseif type(colorTable) == "table" and #colorTable >= 3 then
        local r, g, b = colorTable[1], colorTable[2], colorTable[3]
        newColor = reaper.ColorToNative(r, g, b) | 0x1000000
    
    else
        return
    end

    reaper.Undo_BeginBlock()
    for _, rgn in ipairs(regions) do
        reaper.SetProjectMarker3(0, rgn.index, true, rgn.pos, rgn.rgnEnd, rgn.name, newColor)
    end
    reaper.Undo_EndBlock("Recolor Regions", -1)
end

---------------------------------------------------------
-- UI_Module 
---------------------------------------------------------
function JKK_TimelineTool_Draw(ctx)
    reaper.ImGui_Text(ctx, 'Create a TIME SELECTION to use this feature.')
    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Region Actions')

    changed, rename_base_name = reaper.ImGui_InputTextMultiline(ctx, '##RenameRegionBaseName', rename_base_name, 292, 22)
    reaper.ImGui_SameLine(ctx, 0, 16)
    
    if reaper.ImGui_Button(ctx, "Rename Regions", 116, 22) then
        ApplyChanges()
    end
    reaper.ImGui_Spacing(ctx)
    
    if reaper.ImGui_Button(ctx, "Delete Regions in Time Selection", 208, 22) then
        DeleteOverlappingRegions()
    end
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Delete All Regions", 208, 22) then
        DeleteAllRegions()
    end
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Spacing(ctx)

    -- ========================================================
    reaper.ImGui_SeparatorText(ctx, 'Region Color Pallete')
    local columns = 12
    for i, col in ipairs(region_colors) do
        local r, g, b = col[1], col[2], col[3]
        local packed = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, 1)

        reaper.ImGui_PushID(ctx, "col"..i)

        if reaper.ImGui_ColorButton(ctx, "##Color", packed, 0, 30, 30) then
            selectedColor = col
            SetRegionColors(selectedColor)
        end

        reaper.ImGui_PopID(ctx)

        if i % columns ~= 0 then
            reaper.ImGui_SameLine(ctx)
        end
    end
end
return {
    JKK_TimelineTool_Draw = JKK_TimelineTool_Draw,
}