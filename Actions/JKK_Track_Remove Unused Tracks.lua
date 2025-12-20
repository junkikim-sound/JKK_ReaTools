--========================================================
-- @title JJK_TrackTool_Remove Unused Tracks
-- @author Junki Kim
-- @version 0.5.5
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
            local tr = reaper.GetTrack(proj, i)
            if tr then
                local item_count = reaper.CountTrackMediaItems(tr)
                local fx_count = reaper.TrackFX_GetCount(tr)
                local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
                
                local folder_depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")

                if item_count == 0 and fx_count == 0 and (not name or name == "") then
                    if folder_depth ~= 1 then
                        reaper.DeleteTrack(tr)
                    end
                end
            end
            i = i - 1
        end

        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Delete empty tracks (Preserving folders)", -1)
    end


DeleteEmptyTracksAndFolders()