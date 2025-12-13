--========================================================
-- @title JJK_Track Manager_Follow Group Name
-- @author Junki Kim
-- @version 0.5.5
--========================================================

local reaper = reaper

local function Safe_GetSelectedTrack(idx)
    return reaper.GetSelectedTrack(0, idx)
end

local function GetSelectedTrackCount()
    return reaper.CountSelectedTracks(0)
end

local function GetParentFolderTrack(track)
    if not track then return nil end
    
    local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1

    for i = idx - 1, 0, -1 do
        local tr = reaper.GetTrack(0, i)
        if tr then
            local d = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
            if d == 1 then
                return tr
            end
        end
    end
    return nil
end

local function FollowFolderName()
    local count = GetSelectedTrackCount()
    if count == 0 then 
        reaper.MB("Please select one or more tracks to rename.", "Info", 0)
        return 
    end

    reaper.Undo_BeginBlock()

    for i = 0, count - 1 do
        local track = Safe_GetSelectedTrack(i)
        if track then
            local depth_val = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if depth_val == 1 then 
                goto continue_loop 
            end
            local parent = GetParentFolderTrack(track)
            if parent then
                local retval, parent_name = reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
                
                if retval and parent_name ~= "" then
                    local new_name = string.format("%s_%02d", parent_name, i+1)
                    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
                end
            end
        end
        ::continue_loop::
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Batch Rename Tracks by Parent Folder", -1)
end

FollowFolderName()