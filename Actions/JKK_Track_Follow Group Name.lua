--========================================================
-- @title JJK_TrackTool_Follow Group Name
-- @author Junki Kim
-- @version 0.5.6
--========================================================

local reaper = reaper

local function Safe_GetTrack(idx)
        return reaper.GetSelectedTrack(0, idx)
    end

    local function GetSelectedTrackCount()
        return reaper.CountSelectedTracks(0)
    end

    local function GetParentFolderTrack(track)
        if not track then return nil end
        local target_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        
        for i = target_idx - 1, 0, -1 do
            local tr = reaper.GetTrack(0, i)
            if tr then
                local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
                if depth == 1 then
                    local check_depth = 1
                    local is_parent = false
                    for j = i + 1, target_idx do
                        local sub_tr = reaper.GetTrack(0, j)
                        if j == target_idx then
                            if check_depth >= 1 then is_parent = true end
                            break
                        end
                        check_depth = check_depth + reaper.GetMediaTrackInfo_Value(sub_tr, "I_FOLDERDEPTH")
                        if check_depth <= 0 then break end
                    end
                    if is_parent then return tr end
                end
            end
        end
        return nil
    end

    local function FollowFolderName()
        local count = reaper.CountSelectedTracks(0)
        if count == 0 then return end

        reaper.Undo_BeginBlock()

        local parent_counters = {}

        for i = 0, count - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            if track then
                local parent = GetParentFolderTrack(track)
                
                if parent then
                    local parent_guid = reaper.GetTrackGUID(parent)
                    
                    if not parent_counters[parent_guid] then
                        parent_counters[parent_guid] = 1
                    else
                        parent_counters[parent_guid] = parent_counters[parent_guid] + 1
                    end

                    local current_idx = parent_counters[parent_guid]
                    local retval, parent_name = reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
                    
                    if retval and parent_name ~= "" then
                        local new_name = string.format("%s_%02d", parent_name, current_idx)
                        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
                    end
                end
            end
        end

        reaper.UpdateArrange()
        reaper.Undo_EndBlock("Rename Selected Tracks by Parent (Smart Numbering)", -1)
    end

FollowFolderName()