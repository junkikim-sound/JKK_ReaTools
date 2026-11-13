--========================================================
-- @title JKK_Theme
-- @author Junki Kim
-- @version 1.0.0
-- @provides
--     [nomain] Modules/JKK_Theme_Core.lua
--========================================================

local RPR = reaper
local info = debug.getinfo(1, "S")
local script_dir = info.source:match("@?(.*[\\/])") or ""

local core_candidates = {
    script_dir .. "Modules/JKK_Theme_Core.lua",
    script_dir .. "JKK_Theme_Core.lua",
    RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/Modules/JKK_Theme_Core.lua",
    RPR.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_Theme_Core.lua",
}

local core_path = nil
for _, path in ipairs(core_candidates) do
    if RPR.file_exists(path) then
        core_path = path
        break
    end
end

if not core_path then
    RPR.ShowMessageBox("JKK_Theme_Core.lua를 찾을 수 없습니다.\nModules 폴더 위치를 확인해 주세요.", "JKK_Theme Error", 0)
    return
end

local Theme = _G.JKK_Theme or dofile(core_path)

-- REAPER Action List에서 직접 실행된 경우에만 에디터 창을 단독으로 연다.
-- (다른 스크립트에서 dofile/require로 불러온 경우 debug.getinfo(2, "S")가 존재함)
if debug.getinfo(2, "S") == nil then
    if not RPR.ImGui_CreateContext then
        local imgui_shim = RPR.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua"
        if RPR.file_exists(imgui_shim) then
            dofile(imgui_shim)("0.9")
        end
    end
    Theme.OpenEditor()
end

return Theme