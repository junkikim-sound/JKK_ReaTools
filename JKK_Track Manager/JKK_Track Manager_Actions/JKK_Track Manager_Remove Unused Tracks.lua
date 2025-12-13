--========================================================
-- @title JJK_Track Manager_Remove Unused Tracks
-- @author Junki Kim
-- @version 1.0.0
-- @description A tool for cleaning up the project track list by deleting empty standard tracks and unused folder track structures that contain no media items.
--========================================================

local reaper = reaper

local function Safe_GetTrack(proj, idx)
    return reaper.GetTrack(proj, idx)
end

local function TrackHasItems(track)
    if not track then return false end
    return reaper.CountTrackMediaItems(track) > 0
end

local function IsFolderStart(track)
    if not track then return false end
    return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
end

local function FolderIsEmpty(proj, start_index, track_count)
    local depth = 1
    
    local has_items = TrackHasItems(Safe_GetTrack(proj, start_index))
    if has_items then return false end

    for i = start_index + 1, track_count - 1 do
        local tr = Safe_GetTrack(proj, i)
        if not tr then break end
        
        local d = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        depth = depth + d
        
        if depth <= 0 then
            if i == start_index + 1 then
                return true
            else
                return false 
            end
        end
        
        if TrackHasItems(tr) then return false end
    end

    return true
end

local function DeleteEmptyTracksAndFolders()
    local proj = 0
    local track_count = reaper.CountTracks(proj)
    if track_count == 0 then return end

    reaper.Undo_BeginBlock()

    local i = track_count - 1
    while i >= 0 do
        local tr = Safe_GetTrack(proj, i)
        if tr then
            local folder_start = IsFolderStart(tr)
            local has_items = TrackHasItems(tr)

            if folder_start then
                if FolderIsEmpty(proj, i, track_count) then
                    reaper.DeleteTrack(tr)
                end
            else
                if not has_items then
                    reaper.DeleteTrack(tr)
                end
            end
        end
        i = i - 1
        track_count = reaper.CountTracks(proj) 
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Delete empty tracks and folders", -1)
end

DeleteEmptyTracksAndFolders()