--========================================================
-- @title JJK_TrackTool_Remove Unused Tracks
-- @author Junki Kim
-- @version 0.6.0
--========================================================

local function IsTrackUnused(track)
    if reaper.CountTrackMediaItems(track) > 0 then return false end
    if reaper.GetTrackNumSends(track, -1) > 0 then return false end
    if reaper.GetTrackNumSends(track, 1) > 0 then return false end
    if reaper.GetTrackNumSends(track, 0) > 0 then return false end
    if reaper.GetMediaTrackInfo_Value(track, 'I_RECARM') == 1 then return false end
    if reaper.CountTrackEnvelopes(track) > 0 then return false end

    return true
end

local function Main()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local saved_tracks = {}
    local sel_count = reaper.CountSelectedTracks(0)
    for i = 0, sel_count - 1 do
        table.insert(saved_tracks, reaper.GetSelectedTrack(0, i))
    end

    reaper.Main_OnCommand(40297, 0)

    local trackCount = reaper.CountTracks(0)
    
    for i = trackCount - 1, 0, -1 do
        local track = reaper.GetTrack(0, i)
        local folder_depth = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
        
        if folder_depth == 1 then
            local childUsed = false
            local depth = reaper.GetTrackDepth(track)
            local trackidx = i + 1
            
            while trackidx < trackCount do
                local child = reaper.GetTrack(0, trackidx)
                local childDepth = reaper.GetTrackDepth(child)
                
                if childDepth <= depth then break end
                
                if not reaper.IsTrackSelected(child) then
                    childUsed = true
                    break
                end
                trackidx = trackidx + 1
            end
            
            if not childUsed then
                if IsTrackUnused(track) then
                    reaper.SetTrackSelected(track, true)
                end
            end
        else
            if IsTrackUnused(track) then
                reaper.SetTrackSelected(track, true)
            end
        end
    end

    reaper.Main_OnCommand(40005, 0)
    for _, tr in ipairs(saved_tracks) do
        if reaper.ValidatePtr(tr, 'MediaTrack*') then
            reaper.SetTrackSelected(tr, true)
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Delete Unused Tracks (Smart)", -1)
end

Main()