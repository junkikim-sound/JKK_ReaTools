--============================================================
-- JKK_Track Manager - Batch Rename Tracks by Parent Folder
--============================================================

local ctx = reaper.ImGui_CreateContext("Batch Rename Tracks by Parent Folder")

--============================================================
-- Helper Functions
--============================================================

-- 안전하게 GetTrack 호출
local function Safe_GetTrack(idx)
    return reaper.GetSelectedTrack(0, idx)
end

-- 선택된 트랙 개수
local function GetSelectedTrackCount()
    return reaper.CountSelectedTracks(0)
end

-- 상위 폴더(그룹) 트랙 찾기
local function GetParentFolderTrack(track)
    if not track then return nil end
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1

    -- 현재 트랙 바로 위 트랙부터 검색
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

-- 선택된 트랙 이름 일괄 변경
local function FollowFolderName()
    local count = GetSelectedTrackCount()
    if count == 0 then return end

    reaper.Undo_BeginBlock()

    for i = 0, count - 1 do
        local track = Safe_GetTrack(i)
        if track then
            local parent = GetParentFolderTrack(track)
            if parent then
                local retval, parent_name = reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
                if retval then
                    local new_name = string.format("%s_%02d", parent_name, i+1)
                    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
                end
            end
        end
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Batch Rename Tracks by Parent Folder", -1)
end
