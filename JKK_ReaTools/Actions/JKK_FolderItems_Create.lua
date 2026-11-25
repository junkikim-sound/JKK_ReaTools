--========================================================
-- @title JKK_FolderItems_Create
-- @author Junki Kim
-- @version 1.0.0
-- @noindex
-- 선택된 폴더 트랙에만 폴더 아이템을 생성/갱신 (깊은 폴더부터)
-- 하위 모든 트랙 아이템(하위 폴더 아이템 포함)의 시간 범위를 겹침 기준으로 병합하고,
-- 기존 폴더 아이템은 삭제/재생성 없이 위치와 길이만 맞춘다.
--========================================================
local action_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local root_dir   = action_dir:gsub("[^\\/]+[\\/]$", "")
local Core       = dofile(root_dir .. "Modules/JKK_FolderItems_Core.lua")

reaper.defer(function() end)
Core.run_create()
