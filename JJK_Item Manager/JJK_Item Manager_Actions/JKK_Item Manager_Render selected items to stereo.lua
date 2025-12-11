--========================================================
-- @title JKK_Item Manager_Render Selected Items To Stereo
-- @author Junki Kim
-- @version 0.5.0
--========================================================
--========================================================
--  JKK_Item Manager - Render Selected Items to Stereo Stem
--  Clean Stable Version
--========================================================

local function Msg(s) reaper.ShowMessageBox(s, "Debug", 0) end

----------------------------------------------------------
-- 1. 선택된 아이템 수집
----------------------------------------------------------
local function CollectSelectedItems()
    local items = {}
    local count = reaper.CountSelectedMediaItems(0)
    if count == 0 then return nil end

    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then items[#items+1] = item end
    end
    return items
end

----------------------------------------------------------
-- 2. 아이템들의 트랙 목록 구하기 (중복 제거)
----------------------------------------------------------
local function CollectTracksFromItems(items)
    local tracks = {}
    local map = {}

    for _, item in ipairs(items) do
        local tr = reaper.GetMediaItem_Track(item)
        if tr and not map[tr] then
            map[tr] = true
            tracks[#tracks+1] = tr
        end
    end
    return tracks
end

----------------------------------------------------------
-- 3. 상위 폴더들을 모두 포함시키기
----------------------------------------------------------
local function AddParentFolders(tracks)
    local added = {}
    local result = {}

    for _, tr in ipairs(tracks) do
        local cur = tr
        while cur do
            if not added[cur] then
                added[cur] = true
                result[#result+1] = cur
            end
            local parent = reaper.GetParentTrack(cur)
            cur = parent
        end
    end
    return result
end

----------------------------------------------------------
-- 4. 트랙 복제
----------------------------------------------------------
local function DuplicateTracks(tracks)
    local duplicates = {}

    -- 원본을 기준으로 아래쪽에 붙여 넣기
    for _, tr in ipairs(tracks) do
        local idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
        reaper.InsertTrackAtIndex(idx + 1, true)
        local dup = reaper.GetTrack(0, idx + 1)

        -- 원본 FX 복사
        reaper.TrackList_AdjustWindows(false)
        reaper.CopyTrackFX(tr)
        reaper.PasteTrackFX(dup)

        duplicates[#duplicates+1] = { original = tr, duplicate = dup }
    end

    return duplicates
end

----------------------------------------------------------
-- 5. 복제된 트랙에서 선택되지 않은 아이템 삭제
----------------------------------------------------------
local function RemoveUnselectedItemsOnDuplicates(dupInfo, selectedItems)
    local selectedMap = {}
    for _, it in ipairs(selectedItems) do selectedMap[it] = true end

    for _, info in ipairs(dupInfo) do
        local dup = info.duplicate
        local itemCount = reaper.CountTrackMediaItems(dup)

        for i = itemCount - 1, 0, -1 do
            local item = reaper.GetTrackMediaItem(dup, i)
            -- 같은 GUID인지 비교
            if not selectedMap[item] then
                reaper.DeleteTrackMediaItem(dup, item)
            end
        end
    end
end

----------------------------------------------------------
-- 6. 복제된 모든 트랙을 하나의 폴더로 묶기
----------------------------------------------------------
local function GroupTracksIntoFolder(dupInfo)
    if #dupInfo == 0 then return nil end

    -- 가장 위에 새 폴더 트랙 생성
    local firstDup = dupInfo[1].duplicate
    local idx = reaper.GetMediaTrackInfo_Value(firstDup, "IP_TRACKNUMBER") - 1
    reaper.InsertTrackAtIndex(idx, true)
    local folder = reaper.GetTrack(0, idx)
    reaper.GetSetMediaTrackInfo_String(folder, "P_NAME", "RenderGroup", true)

    -- 폴더 시작
    reaper.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)

    -- 폴더 종료 (마지막 복제된 트랙에서 끝남)
    local lastDup = dupInfo[#dupInfo].duplicate
    reaper.SetMediaTrackInfo_Value(lastDup, "I_FOLDERDEPTH", -1)

    return folder
end

----------------------------------------------------------
-- 7. Render tracks to stereo stem tracks
----------------------------------------------------------
local function RenderFolder(folderTrack)
    if not folderTrack then return end

    reaper.SetOnlyTrackSelected(folderTrack)
    -- 41588 = Render tracks to stereo stem tracks (and mute originals)
    reaper.Main_OnCommand(41588, 0)

    -- 새 생성된 트랙(스테레오 스템)을 반환
    local trackCount = reaper.CountTracks(0)
    return reaper.GetTrack(0, trackCount - 1)
end

----------------------------------------------------------
-- 8. 스템 트랙을 원래 아이템 아래로 이동
----------------------------------------------------------
local function MoveStemTrackToOriginalItem(stemTrack, selectedItems)
    if not stemTrack then return end

    -- 첫 번째 선택 아이템의 트랙 아래로 이동
    local firstItem = selectedItems[1]
    local origTrack = reaper.GetMediaItem_Track(firstItem)
    local targetIndex = reaper.GetMediaTrackInfo_Value(origTrack, "IP_TRACKNUMBER")

    reaper.SetOnlyTrackSelected(stemTrack)
    reaper.ReorderSelectedTracks(targetIndex, 1)
end

----------------------------------------------------------
-- MAIN
----------------------------------------------------------
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local selectedItems = CollectSelectedItems()
if not selectedItems then
    Msg("선택된 아이템이 없습니다!")
    return
end

-- 아이템 → 트랙 → 상위 폴더 포함
local itemTracks = CollectTracksFromItems(selectedItems)
local withFolders = AddParentFolders(itemTracks)

-- 복제
local dupInfo = DuplicateTracks(withFolders)

-- 불필요한 아이템 제거
RemoveUnselectedItemsOnDuplicates(dupInfo, selectedItems)

-- 하나의 폴더로 묶기
local folder = GroupTracksIntoFolder(dupInfo)

-- 폴더 전체를 스테레오 스템으로 렌더
local stemTrack = RenderFolder(folder)

-- 원래 아이템 아래로 이동
MoveStemTrackToOriginalItem(stemTrack, selectedItems)

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Render selected items to stereo stem (JKK)", -1)
