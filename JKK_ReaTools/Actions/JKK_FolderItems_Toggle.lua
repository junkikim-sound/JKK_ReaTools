--========================================================
-- @title JKK_FolderItems_Toggle
-- @author Junki Kim
-- @version 1.0.0
-- @noindex
-- 마우스 아래 폴더(관리 폴더 아이템 / 폴더 트랙 Arrange 빈 공간 / 폴더 TCP)를 접기/펼치기
--  접기: 해당 폴더의 폴더 아이템별 독립 그룹
--  펼치기: 그룹 해제 후 여전히 접힌 하위 폴더 그룹을 즉시 재구성
-- 일반 아이템/트랙에서 Mouse Modifier 로 실행되면 백업된 원래 동작(검증된 action 만)으로 전달
--========================================================
local action_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local root_dir   = action_dir:gsub("[^\\/]+[\\/]$", "")
local Core       = dofile(root_dir .. "Modules/JKK_FolderItems_Core.lua")

reaper.defer(function() end)

local target = Core.resolve_mouse_target()
if target then
    if target.kind == "folder" then
        Core.toggle_folder(target.track)
    else
        Core.run_previous_behavior(target)
    end
end
