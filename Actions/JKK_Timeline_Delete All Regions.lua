--========================================================
-- @title JKK_Timeline_Delete All Regions
-- @author Junki Kim
-- @version 0.5.5
--========================================================
local function DeleteAllRegions()
    local _, numMarkers, numRegions = reaper.CountProjectMarkers(0)
    
    if numRegions == 0 then 
        return 
    end

    local total = numMarkers + numRegions

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
-- Main
---------------------------------------------------------
DeleteAllRegions()