--========================================================
-- @title JKK_Track_Create Parallel FX Group
-- @author Junki Kim
-- @version 0.5.5
--========================================================

function main()
    local parent_track = reaper.GetSelectedTrack(0, 0)
    if not parent_track then 
        return 
    end

    local folder_depth = reaper.GetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH")
    
    if folder_depth == 1 then
        return
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- IP_TRACKNUMBER returns 1-based index
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") 
    local _, parent_name = reaper.GetSetMediaTrackInfo_String(parent_track, "P_NAME", "", false)
    if parent_name == "" then parent_name = "Track" end

    local suffixes = {"_Dry", "_Wet_01", "_Wet_02", "_Wet_03"}
    local new_tracks = {}

    for i, suffix in ipairs(suffixes) do
        local insert_idx = parent_idx + (i - 1)
        reaper.InsertTrackAtIndex(insert_idx, true)
        
        local new_tr = reaper.GetTrack(0, insert_idx)
        reaper.GetSetMediaTrackInfo_String(new_tr, "P_NAME", parent_name .. suffix, true)
        table.insert(new_tracks, new_tr)
    end

    local dry_track = new_tracks[1]
    local last_wet_track = new_tracks[4]

    reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
    reaper.SetMediaTrackInfo_Value(last_wet_track, "I_FOLDERDEPTH", -1)

    local item_count = reaper.CountTrackMediaItems(parent_track)
    for i = item_count - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(parent_track, i)
        reaper.MoveMediaItemToTrack(item, dry_track)
    end

    for i = 2, 4 do 
        local wet_tr = new_tracks[i]
        local send_idx = reaper.CreateTrackSend(dry_track, wet_tr)
        
        reaper.SetTrackSendInfo_Value(dry_track, 0, send_idx, "I_SENDMODE", 1) 
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Create Parallel FX Routing", -1)
end

main()