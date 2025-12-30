--========================================================
-- @title JKK_Timeline_Toggle Master Render for Overlapping Regions
-- @author Junki Kim
-- @version 0.6.0
--========================================================

function main()
    local proj = 0
    
    local t_start, t_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    if t_start == t_end then 
        return 
    end

    local master_track = reaper.GetMasterTrack(proj)
    local num_markers, num_regions = reaper.CountProjectMarkers(proj)
    local total_count = num_markers + num_regions
    
    local has_overlap = false
    local i = 0
    while i < total_count do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if retval == 0 then break end
        
        if isrgn then
            if pos < t_end and rgnend > t_start then
                has_overlap = true
                break
            end
        end
        i = i + 1
    end

    if not has_overlap then 
        return 
    end

    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    i = 0
    while i < total_count do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if retval == 0 then break end

        if isrgn then
            if pos < t_end and rgnend > t_start then
                reaper.SetRegionRenderMatrix(proj, markrgnindexnumber, master_track, 1)
            else
                reaper.SetRegionRenderMatrix(proj, markrgnindexnumber, master_track, -1)
            end
        end
        i = i + 1
    end

    reaper.Undo_EndBlock("Set Region Matrix by Time Selection", -1)
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
end

main()