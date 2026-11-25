--========================================================
-- @title JKK_Variator_Preview
-- @author Junki Kim
-- @noindex
-- Sequential preview of the Arrange View clones for JKK_Variator.
--   * plays [start, end) of the requested range, auto-stops at the end
--     (or seeks back to start when Loop is on)
--   * REAPER Repeat is switched off while previewing so a project loop range
--     cannot redirect playback; Repeat, edit cursor and temporary solos are
--     restored afterwards unless the user changed them in the meantime
--   * only playback started by Variator is ever stopped by Variator
-- Auto-stop runs in the GUI defer loop: expect an overshoot of roughly one
-- defer interval (~30 ms) into the following gap.
--========================================================

local R = reaper
local Preview = {}
Preview.__index = Preview

function Preview.new(proj)
    return setmetatable({ proj = proj, state = nil, current = nil, message = nil }, Preview)
end

function Preview:is_playing() return self.state ~= nil end

local function solo_snapshot(proj)
    local t = {}
    for i = 0, R.CountTracks(proj) - 1 do
        local tr = R.GetTrack(proj, i)
        t[tr] = R.GetMediaTrackInfo_Value(tr, "I_SOLO")
    end
    return t
end

-- opts = { loop = bool, solo_tracks = { MediaTrack*... } | nil, index = n | nil }
function Preview:start(range_start, range_end, opts)
    local proj = self.proj
    if not range_start or not range_end or range_end <= range_start then return false, "Nothing to preview" end
    local ps = R.GetPlayStateEx(proj)
    if ps & 4 == 4 then return false, "Recording in progress: preview is disabled" end
    if self.state then self:stop() end
    if ps & 3 ~= 0 then R.OnStopButtonEx(proj) end   -- explicit Space press by the user

    local st = {
        start = range_start, ["end"] = range_end, loop = opts.loop, index = opts.index,
        t0 = R.time_precise(),
        cursor = R.GetCursorPositionEx(proj),
        repeat_on = R.GetSetRepeatEx(proj, -1) == 1,
    }
    if st.repeat_on then R.GetSetRepeatEx(proj, 0) end
    if opts.solo_tracks and #opts.solo_tracks > 0 then
        st.solo_before = solo_snapshot(proj)
        st.solo_set = {}
        local target = {}
        for _, tr in ipairs(opts.solo_tracks) do target[tr] = true end
        for tr, v in pairs(st.solo_before) do
            local want = target[tr] and 2 or 0     -- 2 = solo in place (keeps routing)
            if (target[tr] and v == 0) or (not target[tr] and v ~= 0) then
                R.SetMediaTrackInfo_Value(tr, "I_SOLO", want)
                st.solo_set[tr] = want
            end
        end
    end
    R.SetEditCurPos2(proj, range_start, false, false)
    R.OnPlayButtonEx(proj)
    self.state = st
    self.message = nil
    return true
end

function Preview:restore(st)
    local proj = self.proj
    if not R.ValidatePtr2(0, proj, "ReaProject*") then return end
    if st.solo_set then
        for tr, set_to in pairs(st.solo_set) do
            if R.ValidatePtr2(proj, tr, "MediaTrack*") and R.GetMediaTrackInfo_Value(tr, "I_SOLO") == set_to then
                R.SetMediaTrackInfo_Value(tr, "I_SOLO", st.solo_before[tr] or 0)
            end
        end
    end
    if st.repeat_on and R.GetSetRepeatEx(proj, -1) == 0 then R.GetSetRepeatEx(proj, 1) end
    R.SetEditCurPos2(proj, st.cursor, false, false)
end

-- Stop playback that Variator started and restore temporary state.
function Preview:stop()
    local st = self.state
    if not st then return end
    self.state, self.current = nil, nil
    if R.ValidatePtr2(0, self.proj, "ReaProject*") and R.GetPlayStateEx(self.proj) & 1 == 1 then
        R.OnStopButtonEx(self.proj)
    end
    self:restore(st)
end

-- Release ownership without stopping (user took over the transport).
function Preview:release()
    local st = self.state
    if not st then return end
    self.state, self.current = nil, nil
    if st.solo_set then
        st.cursor = R.GetCursorPositionEx(self.proj)   -- do not jump the user's cursor
        self:restore(st)
    end
end

-- Returns the playback position (audible) while previewing.
function Preview:tick(set_at)
    local st = self.state
    if not st then return nil end
    local proj = self.proj
    if not R.ValidatePtr2(0, proj, "ReaProject*") then self.state = nil; return nil end
    local ps = R.GetPlayStateEx(proj)
    if ps & 1 == 0 then
        if R.time_precise() - st.t0 > 0.3 then
            -- stopped by the user or by REAPER: restore our temporary state
            self.state, self.current = nil, nil
            self:restore(st)
        end
        return nil
    end
    local pos = R.GetPlayPositionEx(proj)
    if R.time_precise() - st.t0 > 0.3 and (pos < st.start - 0.25 or pos > st["end"] + 1.0) then
        self:release()   -- user seeked elsewhere: not our playback any more
        return nil
    end
    local seeking = st.seek_t and (R.time_precise() - st.seek_t) < 0.2
    if pos >= st["end"] and not seeking then
        if st.loop then
            R.SetEditCurPos2(proj, st.start, false, true)
            st.seek_t = R.time_precise()
        else
            self:stop()
            return nil
        end
    end
    self.current = set_at and set_at(pos) or nil
    return pos
end

return Preview
