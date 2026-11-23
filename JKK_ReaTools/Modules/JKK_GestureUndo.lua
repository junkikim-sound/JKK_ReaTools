--========================================================
-- @title JKK_GestureUndo
-- @author Junki Kim
-- @noindex
--========================================================
-- Named undo points for sliders in a deferred ReaImGui window.
--
-- IMPORTANT: A gesture can last across many reaper.defer() invocations.
-- Do NOT leave Undo_BeginBlock2() open across those callbacks: the pairing
-- can fall back to an anonymous "ReaScript: Run" entry in REAPER.
-- Instead, apply the parameter change live and issue exactly one named
-- Undo_OnStateChangeEx2() on release, edit completion, context switch or exit.
-- The flag limits the snapshot to what the slider actually edits:
--   1 = track controls (volume / pan / width)
--   4 = media items, including takes / positions / lengths
-- No history point is created if no slider value was changed.

local R = reaper
local M = {}
local active = nil

local function get_project()
    if R.EnumProjects then
        local project = R.EnumProjects(-1)
        if project then return project end
    end
    return 0
end

local function project_is_valid(project)
    if project == 0 then return true end
    -- If a project tab was closed during a drag, do not pass a stale pointer
    -- into REAPER's undo system. For project pointers, ValidatePtr2 ignores
    -- its first argument.
    return (not R.ValidatePtr2) or R.ValidatePtr2(0, project, 'ReaProject*')
end

local function finish()
    if not active then return false end
    local pending = active
    active = nil
    if not project_is_valid(pending.project) then return false end
    R.Undo_OnStateChangeEx2(pending.project, pending.label, pending.flags, -1)
    return true
end

function M.Begin(label, flags)
    assert(type(label) == 'string' and label ~= '', 'Undo gesture requires a label')
    flags = flags or -1
    assert(type(flags) == 'number', 'Undo gesture requires a numeric state flag')
    local project = get_project()
    if active and active.label == label and active.project == project then
        active.seen_this_frame = true
        return
    end
    if active then finish() end
    active = {label = label, flags = flags, project = project, seen_this_frame = true}
end

function M.FrameStart()
    if active then active.seen_this_frame = false end
end

function M.Touch(label)
    if active and active.label == label then active.seen_this_frame = true end
end

function M.FinishItem(ctx, label)
    if not active or active.label ~= label then return end
    active.seen_this_frame = true
    if R.ImGui_IsItemDeactivated(ctx) or
       (not R.ImGui_IsItemActive(ctx) and not R.ImGui_IsMouseDown(ctx, 0)) then
        finish()
    end
end

function M.FinishLabel(label)
    if active and active.label == label then return finish() end
    return false
end

function M.FinishIdle(ctx)
    if not active then return end
    -- Finish even if the slider is no longer drawn after switching panels.
    if not R.ImGui_IsMouseDown(ctx, 0) and
       (not active.seen_this_frame or not R.ImGui_IsAnyItemActive(ctx)) then
        finish()
    end
end

function M.Finish() return finish() end
function M.IsOpen() return active ~= nil end

return M
