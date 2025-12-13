--========================================================
-- @title JKK_Item Manager_Render Selected Items to Stereo
-- @author Junki Kim
-- @version 0.5.5
--========================================================

local reaper = reaper

local selItemCount = reaper.CountSelectedMediaItems(0)
if selItemCount == 0 then
  return
end

----------------------------------------------------------
-- Values
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

local sel_length = sel_end - sel_start

reaper.Undo_BeginBlock()

local originalTracksMap = {}
local originalTracksList = {}
for i = 0, selItemCount - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local tr = reaper.GetMediaItem_Track(item)
  local key = tostring(tr)
  if not originalTracksMap[key] then
    originalTracksMap[key] = true
    table.insert(originalTracksList, tr)
  end
end

----------------------------------------------------------
-- Function: Collect Parents
----------------------------------------------------------
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

local targetTracksSet = {}
local targetTracksOrdered = {}
for _, tr in ipairs(originalTracksList) do
  local k = tostring(tr)
  if not targetTracksSet[k] then
    targetTracksSet[k] = true
    table.insert(targetTracksOrdered, tr)
  end
  local parents = collectParents(tr)
  for _, p in ipairs(parents) do
    local pk = tostring(p)
    if not targetTracksSet[pk] then
      targetTracksSet[pk] = true
      table.insert(targetTracksOrdered, p)
    end
  end
end

----------------------------------------------------------
-- Function: Render
----------------------------------------------------------
local function trackIndex(tr)
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
end
table.sort(targetTracksOrdered, function(a, b)
  return trackIndex(a) < trackIndex(b)
end)

-- Header
local total = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(total, true)
local header = reaper.GetTrack(0, total)
reaper.GetSetMediaTrackInfo_String(header, "P_NAME", "JKK_TEMP_RENDER_HEADER", true)
reaper.SetMediaTrackInfo_Value(header, "I_FOLDERDEPTH", 1)
local header_initial_index = reaper.GetMediaTrackInfo_Value(header, "IP_TRACKNUMBER") - 1 -- 렌더 트랙이 삽입될 위치

local selectedGUID = {}
for i = 0, selItemCount - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  if ok then selectedGUID[guid] = true end
end

-- Track Orderd
for _, src in ipairs(targetTracksOrdered) do
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local newTr = reaper.GetTrack(0, idx)

  local ok, chunk = reaper.GetTrackStateChunk(src, "", false)
  if ok and chunk then
    reaper.SetTrackStateChunk(newTr, chunk, false)
  end

  local ok2, nm = reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", "", false)
  local newName = (nm and nm ~= "") and ("JKK_DUP: " .. nm) or "JKK_DUP_TRACK"
  reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", newName, true)

  local itemCount = reaper.CountTrackMediaItems(newTr)
  for j = itemCount - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(newTr, j)
    local ok3, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok3 and guid and not selectedGUID[guid] then
      reaper.DeleteTrackMediaItem(newTr, it)
    end
  end
end

-- Footer
local footerIndex = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(footerIndex, true)
local footer = reaper.GetTrack(0, footerIndex)
reaper.GetSetMediaTrackInfo_String(footer, "P_NAME", "JKK_TEMP_RENDER_FOOTER", true)
reaper.SetMediaTrackInfo_Value(footer, "I_FOLDERDEPTH", -1)

reaper.UpdateArrange()

-- Render
reaper.SetOnlyTrackSelected(header) 
reaper.Main_OnCommand(40788, 0) -- Action ID 40788: Render tracks to stereo stem tracks

local render_track = reaper.GetTrack(0, header_initial_index) 

if render_track then
  reaper.GetSetMediaTrackInfo_String(
    render_track,
    "P_NAME",
    "JKK_Render Result", 
    true
  )
  
  local render_item_count = reaper.CountTrackMediaItems(render_track)
  if render_item_count > 0 then
    local render_item = reaper.GetTrackMediaItem(render_track, 0) 
    
    local trim_start_pos = sel_start
    local trim_end_pos = sel_end
    
    if reaper.SplitMediaItem(render_item, trim_end_pos) then
      local next_item = reaper.GetTrackMediaItem(render_track, 1)
      if next_item then
        reaper.DeleteTrackMediaItem(render_track, next_item)
      end
    end
    
    local current_item = reaper.GetTrackMediaItem(render_track, 0)
    if current_item and reaper.SplitMediaItem(current_item, trim_start_pos) then
      local prev_item = reaper.GetTrackMediaItem(render_track, 0)
      if prev_item then
        reaper.DeleteTrackMediaItem(render_track, prev_item)
      end
    end
    
    local final_item = reaper.GetTrackMediaItem(render_track, 0)
    if final_item then
      reaper.SetMediaItemInfo_Value(final_item, "D_POSITION", sel_start)
    end
  end
end

local current_track_count = reaper.CountTracks(0)

for i = current_track_count - 1, header_initial_index + 1, -1 do
    local track = reaper.GetTrack(0, i)
    
    if track then
        local ok, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        
        if ok and (name:match("JKK_TEMP_RENDER_HEADER") or name:match("JKK_TEMP_RENDER_FOOTER") or name:match("JKK_DUP:")) then
            reaper.DeleteTrack(track)
        end
    end
end

reaper.UpdateArrange() 

reaper.Undo_EndBlock("Duplicate & prune unselected items, Auto-Render, Trim & Rename, AND Auto-Delete (JKK)", -1)