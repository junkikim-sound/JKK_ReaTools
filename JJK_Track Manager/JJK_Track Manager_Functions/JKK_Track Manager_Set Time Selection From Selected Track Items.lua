--========================================================
-- @title JKK_Track Manager_Set Time Selection From Selected Track Items
-- @author Junki Kim
-- @version 1.0.0
--========================================================

-- Helpers
local function GetTrackCount() return reaper.CountTracks(0) end

local function CalcTrackLevelByIndex(idx)
    local level = 0
    for i = 0, idx do
        local tr = reaper.GetTrack(0, i)
        if not tr then break end
        local d = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        level = level + d
    end
    return level
end

local function GetSortedSelectedTracksWithLevel()
    local out = {}
    local selcnt = reaper.CountSelectedTracks(0)
    for i = 0, selcnt - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        local idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
        local level = CalcTrackLevelByIndex(idx) 
        table.insert(out, {track = tr, idx = idx, level = level})
    end
    table.sort(out, function(a,b) return a.idx < b.idx end)
    return out
end

-- =================================================================================
-- Get Full Folder Range Indices By Index
-- =================================================================================
local function GetFullFolderRangeIndicesByIndex(start_idx)
    local tr = reaper.GetTrack(0, start_idx)
    if not tr then return {start_idx} end

    local folderDepth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    
    if folderDepth <= 0 then
        return {start_idx}
    end
    
    local L_parent = 0
    if start_idx > 0 then
        L_parent = CalcTrackLevelByIndex(start_idx - 1)
    end
    
    local start_level = CalcTrackLevelByIndex(start_idx)
    
    local out = {start_idx}
    local folder_level = start_level

    local trackCount = GetTrackCount()
    for i = start_idx + 1, trackCount - 1 do
        local t = reaper.GetTrack(0, i)
        if not t then break end
        local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
        
        folder_level = folder_level + d
        table.insert(out, i)
        
        if folder_level <= L_parent then
            break
        end
    end

    return out
end

local function GetItemRangeFromTrackIndices(indices)
    local min_pos = math.huge
    local max_end = -math.huge
    for _, idx in ipairs(indices) do
        local tr = reaper.GetTrack(0, idx)
        if tr then
            local cnt = reaper.CountTrackMediaItems(tr)
            for j = 0, cnt - 1 do
                local item = reaper.GetTrackMediaItem(tr, j)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                if pos < min_pos then min_pos = pos end
                if pos + len > max_end then max_end = pos + len end
            end
        end
    end
    if min_pos == math.huge then return nil, nil end
    return min_pos, max_end
end

-- =================================================================================
-- Get Top Level Selected Tracks 
-- =================================================================================
local function GetTopLevelSelectedTracks()
    local sel = GetSortedSelectedTracksWithLevel()
    return sel 
end

------------------------------------------------------------
-- Main Action: Time Selection
------------------------------------------------------------
local function Action_TimeSelection()
    reaper.Undo_BeginBlock()
    local topSel = GetTopLevelSelectedTracks() 
    
    if #topSel == 0 then 
        reaper.Undo_EndBlock("JKK: TimeSelection (none)", -1) 
        return 
    end
    
    local idxSet = {}
    for _, e in ipairs(topSel) do
        local indices = GetFullFolderRangeIndicesByIndex(e.idx)
        for _, ii in ipairs(indices) do idxSet[ii] = true end
    end

    local indicesList = {}
    for k,_ in pairs(idxSet) do table.insert(indicesList, k) end
    table.sort(indicesList)

    local min_pos, max_end = GetItemRangeFromTrackIndices(indicesList)
    
    if min_pos then
        reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
    end

    reaper.Undo_EndBlock("JKK: TimeSelection (merged all selected tracks)", -1)
end

Action_TimeSelection()