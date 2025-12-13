--========================================================
-- @title JKK_Item Manager_Render Selected Items to Stereo
-- @author Junki Kim
-- @version 0.9.5
-- @description A tool for rendering (gluing) selected media items into a single new stereo media item.
--========================================================

local reaper = reaper

local selItemCount = reaper.CountSelectedMediaItems(0)
if selItemCount == 0 then
  reaper.ShowMessageBox("선택된 아이템이 없습니다.", "오류", 0)
  return
end

reaper.Undo_BeginBlock()

-- 1) 선택된 아이템이 속한 원본 트랙 수집
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

-- 2) 각 원본 트랙의 상위 폴더 트랙도 포함
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

-- 3) 프로젝트 상 트랙 순서(위→아래)대로 정렬
local function trackIndex(tr)
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
end
table.sort(targetTracksOrdered, function(a, b)
  return trackIndex(a) < trackIndex(b)
end)

-- 4) 프로젝트 맨 아래에 폴더 헤더 추가
local total = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(total, true)
local header = reaper.GetTrack(0, total)
reaper.GetSetMediaTrackInfo_String(header, "P_NAME", "JKK_TEMP_RENDER_HEADER", true)
reaper.SetMediaTrackInfo_Value(header, "I_FOLDERDEPTH", 1)

-- 5) 각 원본/폴더 트랙 복제 + 비선택 아이템 삭제
local duplicatedTracks = {}

-- 선택된 아이템의 GUID 집합 수집
local selectedGUID = {}
for i = 0, selItemCount - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  if ok then selectedGUID[guid] = true end
end

for _, src in ipairs(targetTracksOrdered) do
  -- 새 트랙 추가
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local newTr = reaper.GetTrack(0, idx)

  -- 트랙 상태 복사 (FX, routing, folder flags 등)
  local ok, chunk = reaper.GetTrackStateChunk(src, "", false)
  if ok and chunk then
    reaper.SetTrackStateChunk(newTr, chunk, false)
  end

  -- 트랙 이름 변경 (복제 표시)
  local ok2, nm = reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", "", false)
  local newName = (nm and nm ~= "") and ("JKK_DUP: " .. nm) or "JKK_DUP_TRACK"
  reaper.GetSetMediaTrackInfo_String(newTr, "P_NAME", newName, true)

  -- 이 트랙 안의 아이템 삭제: 원본에서 선택된 GUID가 아니면 삭제
  local itemCount = reaper.CountTrackMediaItems(newTr)
  for j = itemCount - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(newTr, j)
    local ok3, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok3 and guid and not selectedGUID[guid] then
      reaper.DeleteTrackMediaItem(newTr, it)
    end
  end

  table.insert(duplicatedTracks, newTr)
end

-- 6) 폴더 클로저 추가
local footerIndex = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(footerIndex, true)
local footer = reaper.GetTrack(0, footerIndex)
reaper.GetSetMediaTrackInfo_String(footer, "P_NAME", "JKK_TEMP_RENDER_FOOTER", true)
reaper.SetMediaTrackInfo_Value(footer, "I_FOLDERDEPTH", -1)

-- 7) 완료
reaper.UpdateArrange()
reaper.Undo_EndBlock("Duplicate & prune unselected items (JKK)", -1)
reaper.ShowMessageBox("완료: 복제된 트랙들 생성 + 비선택 아이템 삭제 + 임시 폴더로 그룹화됨.", "완료", 0)
