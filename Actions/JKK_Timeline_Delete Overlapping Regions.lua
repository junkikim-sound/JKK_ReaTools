--========================================================
-- @title JKK_Timeline_Delete Overlapping Regions
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
                rgnEnd = rgnEnd
            }
        end
    end

    return list
end

---------------------------------------------------------
-- Functions: Delete Overlapping Regions
---------------------------------------------------------
local function DeleteOverlappingRegions(regions)
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
-- Main
---------------------------------------------------------
local regions = GetOverlappingRegions()
if not regions or #regions == 0 then
    if GetTimeSelection() then
    end
    return
end

DeleteOverlappingRegions(regions)