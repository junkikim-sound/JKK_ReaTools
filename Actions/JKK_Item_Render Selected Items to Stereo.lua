--========================================================
-- @title JKK_ItemTool_Render Selected Items to Stereo
-- @author Junki Kim
-- @version 0.6.0
--========================================================

local reaper = reaper

local selItemCount = reaper.CountSelectedMediaItems(0)
if selItemCount == 0 then return end

----------------------------------------------------------
-- 1. Calculate the total time range of selected items
----------------------------------------------------------
local sel_start = math.huge
local sel_end = -math.huge

for i = 0, selItemCount - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  sel_start = math.min(sel_start, pos)
  sel_end = math.max(sel_end, pos + len)
end

reaper.Undo_BeginBlock()

----------------------------------------------------------
-- 2. Collect tracks and their parent folders
----------------------------------------------------------
local originalTracksList = {}
local originalTracksMap = {}
for i = 0, selItemCount - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local tr = reaper.GetMediaItem_Track(item)
  if not originalTracksMap[tostring(tr)] then
    originalTracksMap[tostring(tr)] = true
    table.insert(originalTracksList, tr)
  end
end

local function collectParents(track)
  local parents = {}
  local cur = track
  while true do
    local parent = reaper.GetParentTrack(cur)
    if not parent then break end
    table.insert(parents, parent)
    cur = parent
  end
  return parents
end

local targetTracksOrdered = {}
local targetTracksSet = {}
for _, tr in ipairs(originalTracksList) do
  local items = {tr, table.unpack(collectParents(tr))}
  for _, t in ipairs(items) do
    if not targetTracksSet[tostring(t)] then
      targetTracksSet[tostring(t)] = true
      table.insert(targetTracksOrdered, t)
    end
  end
end

-- Sort tracks by their actual index in the project
table.sort(targetTracksOrdered, function(a, b)
  return reaper.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER")
end)

----------------------------------------------------------
-- 3. Create temporary structure (Header - Duplicated Tracks - Footer)
----------------------------------------------------------
local total = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(total, true)
local header = reaper.GetTrack(0, total)
reaper.GetSetMediaTrackInfo_String(header, "P_NAME", "JKK_TEMP_HEADER", true)
reaper.SetMediaTrackInfo_Value(header, "I_FOLDERDEPTH", 1)

local header_idx = reaper.GetMediaTrackInfo_Value(header, "IP_TRACKNUMBER") - 1

-- Store GUIDs of selected items to keep them during pruning
local selectedGUID = {}
for i = 0, selItemCount - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  selectedGUID[guid] = true
end

-- Duplicate tracks and remove unselected items
for _, src in ipairs(targetTracksOrdered) do
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local newTr = reaper.GetTrack(0, idx)
  local _, chunk = reaper.GetTrackStateChunk(src, "", false)
  reaper.SetTrackStateChunk(newTr, chunk, false)
  
  -- Rename duplicated tracks for identification
  local _, nm = reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", "", false)
  reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", "JKK_DUP:" .. (nm or ""), true)

  -- Delete items that were not part of the initial selection
  for j = reaper.CountTrackMediaItems(newTr) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(newTr, j)
    local _, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if not selectedGUID[guid] then reaper.DeleteTrackMediaItem(newTr, it) end
  end
end

-- Create Footer track to close the folder
reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
local footer = reaper.GetTrack(0, reaper.CountTracks(0)-1)
reaper.GetSetMediaTrackInfo_String(footer, "P_NAME", "JKK_TEMP_FOOTER", true)
reaper.SetMediaTrackInfo_Value(footer, "I_FOLDERDEPTH", -1)

----------------------------------------------------------
-- 4. Perform Render and Post-processing
----------------------------------------------------------
reaper.SetOnlyTrackSelected(header)
reaper.Main_OnCommand(40788, 0) -- Action: Render tracks to stereo stem tracks

local result_track = reaper.GetTrack(0, header_idx)
if result_track then
  reaper.GetSetMediaTrackInfo_String(result_track, "P_NAME", "JKK_Render Result", true)
  
  local r_item = reaper.GetTrackMediaItem(result_track, 0)
  if r_item then
    -- Trim end
    reaper.SplitMediaItem(r_item, sel_end)
    local next_it = reaper.GetTrackMediaItem(result_track, 1)
    if next_it then reaper.DeleteTrackMediaItem(result_track, next_it) end
    
    -- Trim start
    local curr_it = reaper.GetTrackMediaItem(result_track, 0)
    if reaper.SplitMediaItem(curr_it, sel_start) then
      reaper.DeleteTrackMediaItem(result_track, reaper.GetTrackMediaItem(result_track, 0))
    end
    
    -- Snap position to original start
    local final_it = reaper.GetTrackMediaItem(result_track, 0)
    if final_it then reaper.SetMediaItemInfo_Value(final_it, "D_POSITION", sel_start) end
  end
end

----------------------------------------------------------
-- 5. Automatic Cleanup of Temporary Tracks
----------------------------------------------------------
for i = reaper.CountTracks(0) - 1, 0, -1 do
  local track = reaper.GetTrack(0, i)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  
  if name:match("JKK_TEMP_") or name:match("JKK_DUP:") then
    reaper.DeleteTrack(track)
  end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Render Selected Items and Cleanup (JKK)", -1)