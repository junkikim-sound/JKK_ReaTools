--========================================================
-- @title JKK_FolderItems_GroupTracks
-- @author Junki Kim
-- @version 1.0.0
-- @noindex
-- 선택된 트랙들을 새 상위(폴더) 트랙 하나로 묶는다.
--  * 새 폴더 트랙은 선택된 트랙 중 가장 위에 있는 트랙 자리(같은 계층)에 만들어진다.
--  * 선택된 트랙이 폴더라면 그 하위 트랙들도 함께 옮겨진다.
--  * 선택이 떨어져 있어도(사이에 다른 트랙이 있어도) 선택된 것만 모아서 묶는다.
--  * 끝나면 새 폴더 트랙만 선택된 상태가 된다. Undo 1회로 되돌릴 수 있다.
--========================================================
local R = reaper
local TITLE = "JKK Folder Items - Group Tracks"
local NEW_FOLDER_NAME = "Group"

local action_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local root_dir   = action_dir:gsub("[^\\/]+[\\/]$", "")
local Undo       = dofile(root_dir .. "Modules/JKK_UndoLabels.lua")

local function TrackIndex(track)
    return math.floor(R.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") + 0.5) - 1
end

-- 선택된 폴더 트랙의 하위 트랙도 선택에 포함 (폴더가 자식과 함께 이동하도록)
local function SelectFolderChildren(selected)
    local total = R.CountTracks(0)
    for _, track in ipairs(selected) do
        if R.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
            local depth = 1
            local j = TrackIndex(track) + 1
            while depth > 0 and j < total do
                local child = R.GetTrack(0, j)
                R.SetTrackSelected(child, true)
                depth = depth + R.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
                j = j + 1
            end
        end
    end
end

local function Main()
    local count = R.CountSelectedTracks(0)
    if count == 0 then
        R.ShowMessageBox("묶을 트랙을 하나 이상 선택하세요.", TITLE, 0)
        return
    end
    if not R.ReorderSelectedTracks then
        R.ShowMessageBox("이 REAPER 버전에는 ReorderSelectedTracks API가 없습니다.\nREAPER를 업데이트하세요.", TITLE, 0)
        return
    end

    local selected = {}
    for i = 0, count - 1 do selected[#selected + 1] = R.GetSelectedTrack(0, i) end
    local first_idx = TrackIndex(selected[1]) -- GetSelectedTrack은 위에서부터 순서대로

    R.Undo_BeginBlock2(0)
    R.PreventUIRefresh(1)

    SelectFolderChildren(selected)

    -- 1) 가장 위 선택 트랙 자리에 새 트랙을 만든다 (같은 계층에 들어간다)
    R.InsertTrackAtIndex(first_idx, true)
    local parent = R.GetTrack(0, first_idx)
    R.SetTrackSelected(parent, false)
    R.GetSetMediaTrackInfo_String(parent, "P_NAME", NEW_FOLDER_NAME, true)

    -- 2) 선택된 트랙 전부를 새 트랙 바로 아래로 옮기며 그 자식으로 만든다
    --    (makePrevFolder = 1: beforeTrackIdx 바로 앞 트랙 = 새 트랙의 자식으로)
    R.ReorderSelectedTracks(first_idx + 1, 1)

    -- 3) 새 폴더 트랙만 선택
    R.SetOnlyTrackSelected(parent)
    R.SetMixerScroll(parent)

    R.PreventUIRefresh(-1)
    R.TrackList_AdjustWindows(false)
    R.UpdateArrange()
    R.Undo_EndBlock2(0, Undo.Label("folder_items.group_tracks"), -1)
end

R.defer(function() end) -- 액션 실행 시 불필요한 Undo 지점이 생기지 않게
Main()
