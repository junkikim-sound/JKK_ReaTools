--========================================================
-- @title JKK_Timeline_Rename Regions
-- @author Junki Kim
-- @version 0.5.5
--========================================================
local function GetTimeSelection()
    local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts == te then return nil end
    return ts, te
end

local function GetOverlappingRegions()
    local ts, te = GetTimeSelection()
    if not ts then 
        return nil 
    end

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

---------------------------------------------------------
-- Main
---------------------------------------------------------
local regions = GetOverlappingRegions()
if not regions or #regions == 0 then
    return
end

local captions = "New Name" 
local initial_values = " "

local input_ok, result_csv = reaper.GetUserInputs("Batch Rename Regions", 1, captions, initial_values)

if not input_ok or not result_csv or result_csv == "" then
    return
end

local RenameBaseName = result_csv 

if RenameBaseName and RenameBaseName ~= "" then
    reaper.Undo_BeginBlock()
    RenameRegions(regions, RenameBaseName)
    reaper.Undo_EndBlock("Batch Rename Regions (" .. RenameBaseName .. ")", -1)
    reaper.UpdateArrange()
end