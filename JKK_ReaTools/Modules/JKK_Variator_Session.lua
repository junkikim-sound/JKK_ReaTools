--========================================================
-- @title JKK_Variator_Session
-- @author Junki Kim
-- @noindex
-- Non-destructive session for JKK_Variator.
--   * selection snapshot at start (later selection changes are ignored)
--   * temporary clones tracked by key + GUID + ownership tag (P_EXT)
--   * dirty flag + throttled update; a clone is rebuilt only when its own
--     result signature changed, otherwise it is just moved
--   * preview edits never call the Undo API (no history entries)
--   * Apply: temporary clones are removed, then the identical result is
--     rebuilt from the same deterministic data inside ONE Undo block
--   * Cancel: idempotent; removes only items this session created
--========================================================

local R = reaper
local Session = {}
Session.__index = Session

local dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local Model  = dofile(dir .. "JKK_Variator_Model.lua")
local Layout = dofile(dir .. "JKK_Variator_Layout.lua")
local VMath  = dofile(dir .. "JKK_Variator_Math.lua")
local Item   = dofile(dir .. "JKK_Variator_Item.lua")
local Random = dofile(dir .. "JKK_Variator_Random.lua")

Session.EXT = "JKK_Variator"
Session.Model = Model
Session.Layout = Layout
Session.Item = Item

----------------------------------------------------------
-- Settings persistence (ExtState, no session data)
----------------------------------------------------------
local function bool_s(b) return b and "1" or "0" end

function Session.save_settings(s)
    -- mode / loop / solo / preserve_pitch are fixed (Model.FIXED) and not stored;
    -- count is not stored either (Variations always opens at 0)
    local parts = {
        "gap=" .. string.format("%.6g", s.gap),
        "gap_mode=" .. s.gap_mode, "gap_grid=" .. s.gap_grid,
        "keep_original=" .. bool_s(s.keep_original), "auto_rename=" .. bool_s(s.auto_rename),
        "include_original=" .. bool_s(s.include_original),
    }
    for _, name in ipairs(Model.PARAMS) do
        local p = s.params[name]
        parts[#parts + 1] = string.format("%s.enabled=%s", name, bool_s(p.enabled))
        parts[#parts + 1] = string.format("%s.amount=%.6g", name, p.amount)
        parts[#parts + 1] = string.format("%s.pmin=%d", name, p.pmin)
        parts[#parts + 1] = string.format("%s.pmax=%d", name, p.pmax)
        parts[#parts + 1] = string.format("%s.link=%s", name, bool_s(p.link))
        parts[#parts + 1] = string.format("%s.curve=%s", name, p.curve)
    end
    R.SetExtState(Session.EXT, "settings", table.concat(parts, ";"), true)
end

function Session.load_settings()
    local s = Model.default_settings()
    local raw = R.GetExtState(Session.EXT, "settings")
    if raw == "" then return s end
    for raw_key, v in raw:gmatch("([^=;]+)=([^;]*)") do
        local name, field = raw_key:match("^(%a+)%.([%a_]+)$")
        local target, k = s, raw_key
        if name and s.params[name] then target, k = s.params[name], field end
        local old = target[k]
        if type(old) == "boolean" then target[k] = (v == "1")
        elseif type(old) == "number" then target[k] = tonumber(v) or old
        elseif type(old) == "string" then target[k] = v end
    end
    s.count = 0   -- older versions stored count: ignore it
    return Model.sanitize(s)
end

----------------------------------------------------------
-- Leftover preview items from a crashed / killed session
----------------------------------------------------------
function Session.find_leftovers(proj, own_tag)
    local found = {}
    for i = 0, R.CountMediaItems(proj) - 1 do
        local it = R.GetMediaItem(proj, i)
        local _, tag = R.GetSetMediaItemInfo_String(it, Item.TAG, "", false)
        if tag ~= "" and tag ~= own_tag then found[#found + 1] = it end
    end
    return found
end

function Session.delete_leftovers(proj, list, label)
    R.Undo_BeginBlock2(proj)
    R.PreventUIRefresh(1)
    for _, it in ipairs(list) do Item.delete(proj, it) end
    R.PreventUIRefresh(-1)
    R.UpdateArrange()
    R.Undo_EndBlock2(proj, label, 4)
end

----------------------------------------------------------
-- Start
----------------------------------------------------------
-- Returns session, or nil + info { empty = true } / { unsupported = { {label, reason}, ... } }
function Session.start(settings)
    local proj = R.EnumProjects(-1)
    local n = R.CountSelectedMediaItems(proj)
    if n == 0 then return nil, { empty = true } end
    local snaps, unsupported = {}, {}
    for i = 0, n - 1 do
        local item = R.GetSelectedMediaItem(proj, i)
        local snap, label, reason = Item.snapshot(proj, item)
        if snap then snaps[#snaps + 1] = snap else unsupported[#unsupported + 1] = { label = label, reason = reason } end
    end
    if #unsupported > 0 then return nil, { unsupported = unsupported, supported = #snaps } end

    local self = setmetatable({}, Session)
    self.proj = proj
    self.snaps = snaps
    self.token = string.format("%x-%x", os.time(), math.floor((R.time_precise() * 1000) % 0x7FFFFFFF))
    local sources = {}
    for i, sp in ipairs(snaps) do
        sources[i] = { uid = sp.guid, guid = sp.guid, pos = sp.pos, len = sp.len,
                       track_key = sp.track_guid, track_index = sp.track_index }
    end
    self.model = Model.new(sources, Random.hash_string(self.token), settings)
    self.clones = {}         -- ckey -> { item, guid, guids, sig, pos, len }
    self.dirty = true
    self.layout = nil
    self.status = { errors = {}, clamped = {}, collisions = {}, warnings = {} }
    self.last_update, self.last_cost = -math.huge, 0
    self.undo_top = R.Undo_CanUndo2(proj) or ""
    self.foreign_undo = false
    self.committed, self.cleaned, self.paused, self.aborted = false, false, false, nil
    self.grid_key = nil
    self.on_layout_change = nil
    return self
end

function Session:mark() self.dirty = true end

----------------------------------------------------------
-- Grid Gap: set k starts k * N grid divisions after the left edge of the
-- originals (QN based, follows tempo changes). Sets may overlap.
----------------------------------------------------------
function Session:grid_step_qn()
    local _, div = R.GetSetProjectGrid(self.proj, false)
    div = tonumber(div) or 0.25
    if div <= 0 then div = 0.25 end
    return div * 4 * self.model.settings.gap_grid      -- division is in whole notes
end

function Session:grid_set_start(k, o_start)
    local qn0 = R.TimeMap2_timeToQN(self.proj, o_start)
    return R.TimeMap2_QNToTime(self.proj, qn0 + k * self:grid_step_qn())
end

-- Changes whenever the grid, the tempo map near the originals or N change.
function Session:current_grid_key()
    if self.model.settings.gap_mode ~= "grid" then return "time" end
    local o_start = Layout.original_range(self.model.sources)
    return string.format("%.9f|%.9f", self:grid_step_qn(), self:grid_set_start(1, o_start))
end

----------------------------------------------------------
-- Plans
----------------------------------------------------------
function Session:clone_list()
    local list = {}
    for _, u in ipairs(self.model:units()) do
        if u.src then
            list[#list + 1] = { unit = u.unit, k = u.k, src = u.src }
        else
            for i = 1, #self.snaps do list[#list + 1] = { unit = u.unit, k = u.k, src = i } end
        end
    end
    return list
end

function Session:clone_name(snap, k)
    if not self.model.settings.auto_rename then return nil end
    return string.format("%s_%02d", snap.name, k)
end

-- Pure part of an update: results, plans, layout (no project writes).
function Session:compute()
    local plans = {}
    for _, c in ipairs(self:clone_list()) do
        local snap = self.snaps[c.src]
        local r = self.model:resolve(c.unit, c.src)
        local ckey = Layout.clone_key(c.unit, snap.guid)
        local name = self:clone_name(snap, c.k)
        local sig = Model.result_signature(r) .. "|n:" .. tostring(name)
        local rec = self.clones[ckey]
        local plan
        if rec and rec.sig == sig and rec.plan then
            plan = rec.plan
        else
            plan = VMath.build_plan(snap, r.res, r.preserve_pitch)
        end
        plans[ckey] = { plan = plan, sig = sig, name = name, src = c.src, k = c.k, unit = c.unit }
    end
    local s = self.model.settings
    local grid = s.gap_mode == "grid"
    self.grid_key = self:current_grid_key()
    local layout = Layout.compute(self.model.sources, {
        mode = s.mode, count = s.count, gap = s.gap,
        length_of = function(unit, i) return plans[Layout.clone_key(unit, self.snaps[i].guid)].plan.length end,
        set_start = grid and function(k, o_start) return self:grid_set_start(k, o_start) end or nil,
    })
    return plans, layout
end

-- Items on the target tracks that are neither originals nor our clones.
function Session:existing_ranges(own)
    local by_track, seen_track = {}, {}
    for _, sp in ipairs(self.snaps) do own[sp.item] = true end
    for _, sp in ipairs(self.snaps) do
        local tr = sp.track
        if not seen_track[tr] and R.ValidatePtr2(self.proj, tr, "MediaTrack*") then
            seen_track[tr] = true
            local list = {}
            for j = 0, R.CountTrackMediaItems(tr) - 1 do
                local it = R.GetTrackMediaItem(tr, j)
                if not own[it] then
                    local p = R.GetMediaItemInfo_Value(it, "D_POSITION")
                    list[#list + 1] = { s = p, e = p + R.GetMediaItemInfo_Value(it, "D_LENGTH") }
                end
            end
            by_track[sp.track_guid] = list
        end
    end
    return by_track
end

local function summarize_errors(status, snap, plan, extra)
    for param, msg in pairs(plan.errors) do
        status.errors[#status.errors + 1] = { param = param, item = snap.label, msg = msg }
    end
    for param, msg in pairs(extra or {}) do
        status.errors[#status.errors + 1] = { param = param, item = snap.label, msg = msg }
    end
    for param in pairs(plan.clamped) do status.clamped[param] = (status.clamped[param] or 0) + 1 end
end

----------------------------------------------------------
-- Update (preview, no Undo)
----------------------------------------------------------
function Session:update()
    if self.cleaned or self.committed or self.aborted then return end
    local t0 = R.time_precise()
    self.dirty = false
    local plans, layout = self:compute()
    local status = { errors = {}, clamped = {}, collisions = {}, warnings = self.status.warnings }
    local moved = false

    R.PreventUIRefresh(1)
    local ok, err = xpcall(function()
        -- remove clones that are no longer wanted (Variations decrease, mode change)
        for ckey, rec in pairs(self.clones) do
            if not plans[ckey] then
                Item.delete(self.proj, rec.item)
                self.clones[ckey] = nil
                moved = true
            end
        end
        for _, pl in ipairs(layout.placements) do
            local p = plans[pl.ckey]
            local snap = self.snaps[pl.src]
            local rec = self.clones[pl.ckey]
            local valid = rec and R.ValidatePtr2(self.proj, rec.item, "MediaItem*")
            local write_errors = rec and rec.write_errors
            if not valid or rec.sig ~= p.sig then
                local guids = rec and rec.guids or {}
                local chunk = Item.build_chunk(snap.lines, snap.take_index, Item.guid_provider(guids), Item.stub_params(snap, p.plan))
                local item = valid and rec.item or nil
                if item then
                    if not Item.reset(item, chunk) then error("SetItemStateChunk failed") end
                else
                    local e
                    item, e = Item.create(snap.track, chunk)
                    if not item then error(e) end
                end
                write_errors = Item.write(item, snap, p.plan, { name = p.name, tag = self.token })
                local old_len = valid and rec.len or nil
                local old_pos = valid and rec.pos or nil
                rec = { item = item, guid = Item.item_guid(item), guids = guids, sig = p.sig, plan = p.plan,
                        pos = nil, len = p.plan.length, write_errors = write_errors }
                self.clones[pl.ckey] = rec
                if old_pos then
                    -- chunk reset restored the original position: put it back without
                    -- reporting a move unless the layout really changed
                    R.SetMediaItemInfo_Value(item, "D_POSITION", old_pos)
                    rec.pos = old_pos
                end
                if not old_len or math.abs(old_len - p.plan.length) > 1e-9 then moved = true end
            end
            if rec.pos == nil or math.abs(rec.pos - pl.pos) > 1e-9 then
                R.SetMediaItemInfo_Value(rec.item, "D_POSITION", pl.pos)
                rec.pos = pl.pos
                moved = true
            end
            summarize_errors(status, snap, p.plan, write_errors)
        end
    end, debug.traceback)
    R.PreventUIRefresh(-1)
    R.UpdateArrange()
    if not ok then
        status.errors[#status.errors + 1] = { param = "session", item = "", msg = tostring(err):match("^[^\n]*") }
        R.ShowConsoleMsg("[JKK_Variator] update error:\n" .. tostring(err) .. "\n")
    end

    local own = {}
    for _, rec in pairs(self.clones) do own[rec.item] = true end
    status.collisions = Layout.collisions(layout.placements, self:existing_ranges(own))
    self.layout = layout
    self.status = status
    self.last_update = R.time_precise()
    self.last_cost = self.last_update - t0
    if moved and self.on_layout_change then self.on_layout_change() end
end

-- Called every frame. mouse_down: a slider drag is in progress.
function Session:tick(mouse_down)
    if self.cleaned or self.committed then return end
    if not R.ValidatePtr2(0, self.proj, "ReaProject*") then
        self.aborted = "The session project was closed."
        self.cleaned = true
        return
    end
    self.paused = (R.EnumProjects(-1) ~= self.proj)
    if self.paused or self.aborted then return end
    -- external changes
    local warn = {}
    for _, sp in ipairs(self.snaps) do
        if not R.ValidatePtr2(self.proj, sp.item, "MediaItem*") or not R.ValidatePtr2(self.proj, sp.track, "MediaTrack*") then
            self.aborted = "An original item or its track was removed. The session was cancelled."
            self:cancel()
            return
        end
        if math.abs(R.GetMediaItemInfo_Value(sp.item, "D_POSITION") - sp.pos) > 1e-7
            or math.abs(R.GetMediaItemInfo_Value(sp.item, "D_LENGTH") - sp.len) > 1e-7 then
            warn.original_changed = true
        end
    end
    for _, rec in pairs(self.clones) do
        if not R.ValidatePtr2(self.proj, rec.item, "MediaItem*") then
            rec.sig = nil      -- recreate on next update
            self.dirty = true
        end
    end
    if not self.foreign_undo and (R.Undo_CanUndo2(self.proj) or "") ~= self.undo_top then
        self.foreign_undo = true
    end
    warn.foreign_undo = self.foreign_undo or nil
    self.status.warnings = warn
    if not self.dirty and self.grid_key and self:current_grid_key() ~= self.grid_key then
        self.dirty = true     -- project grid / tempo changed while using grid Gap
    end
    if self.dirty then
        local interval = math.max(0.04, self.last_cost * 1.5)
        if not mouse_down or (R.time_precise() - self.last_update) >= interval then self:update() end
    end
end

----------------------------------------------------------
-- Validation for Apply
----------------------------------------------------------
function Session:can_apply()
    if self.cleaned or self.committed then return false, "Session closed" end
    if self.aborted then return false, self.aborted end
    if self.paused then return false, "Switch back to the session project" end
    if self.model.settings.count < 1 then return false, "Set Variations to 1 or more." end
    if self.dirty then return false, "Updating..." end
    if #self.status.errors > 0 then return false, "Fix the errors above first" end
    if #self.status.collisions > 0 then return false, "Overlaps existing items" end
    return true
end

----------------------------------------------------------
-- Apply (single Undo point)
----------------------------------------------------------
function Session:delete_own_clones()
    for ckey, rec in pairs(self.clones) do
        if R.ValidatePtr2(self.proj, rec.item, "MediaItem*") and Item.item_guid(rec.item) == rec.guid then
            Item.delete(self.proj, rec.item)
        end
        self.clones[ckey] = nil
    end
    if R.ValidatePtr2(0, self.proj, "ReaProject*") then
        for i = R.CountMediaItems(self.proj) - 1, 0, -1 do
            local it = R.GetMediaItem(self.proj, i)
            local _, tag = R.GetSetMediaItemInfo_String(it, Item.TAG, "", false)
            if tag == self.token then Item.delete(self.proj, it) end
        end
    end
end

function Session:apply(label, failed_label)
    if self.dirty then self:update() end
    local ok_apply, why = self:can_apply()
    if not ok_apply then return false, why end
    local plans, layout = self:compute()
    local s = self.model.settings

    R.PreventUIRefresh(1)
    self:delete_own_clones()          -- preview state is never part of the Undo point
    R.Undo_BeginBlock2(self.proj)
    local created = {}
    local ok, err = xpcall(function()
        local max_gid = 0
        for i = 0, R.CountMediaItems(self.proj) - 1 do
            local g = R.GetMediaItemInfo_Value(R.GetMediaItem(self.proj, i), "I_GROUPID")
            if g > max_gid then max_gid = g end
        end
        local gid_map = {}
        local shared = {}
        for _, sp in ipairs(self.snaps) do
            if sp.group_id > 0 then shared[sp.group_id] = (shared[sp.group_id] or 0) + 1 end
        end
        for _, pl in ipairs(layout.placements) do
            local p = plans[pl.ckey]
            local snap = self.snaps[pl.src]
            local chunk = Item.build_chunk(snap.lines, snap.take_index, Item.guid_provider({}), Item.stub_params(snap, p.plan))
            local item, e = Item.create(snap.track, chunk)
            if not item then error(e) end
            created[#created + 1] = item
            local werr = Item.write(item, snap, p.plan, { name = p.name })
            for param, msg in pairs(werr) do error(param .. ": " .. msg) end
            R.SetMediaItemInfo_Value(item, "D_POSITION", pl.pos)
            -- rebuild item-group relations only inside one Group set
            if s.mode == "group" and snap.group_id > 0 and (shared[snap.group_id] or 0) > 1 then
                local key = pl.unit .. "/" .. snap.group_id
                if not gid_map[key] then max_gid = max_gid + 1; gid_map[key] = max_gid end
                R.SetMediaItemInfo_Value(item, "I_GROUPID", gid_map[key])
            end
        end
        if not s.keep_original then
            for _, sp in ipairs(self.snaps) do Item.delete(self.proj, sp.item) end
        end
        R.SelectAllMediaItems(self.proj, false)
        for _, it in ipairs(created) do R.SetMediaItemSelected(it, true) end
    end, debug.traceback)
    if not ok then
        for _, it in ipairs(created) do Item.delete(self.proj, it) end
    end
    R.PreventUIRefresh(-1)
    R.UpdateArrange()
    R.Undo_EndBlock2(self.proj, ok and label or failed_label, -1)
    if not ok then
        R.ShowConsoleMsg("[JKK_Variator] apply failed:\n" .. tostring(err) .. "\n")
        self.dirty = true
        return false, "Apply failed (see console). Nothing was kept."
    end
    self.committed = true
    return true
end

----------------------------------------------------------
-- Cancel (idempotent)
----------------------------------------------------------
function Session:cancel()
    if self.cleaned or self.committed then self.cleaned = true; return end
    self.cleaned = true
    if not R.ValidatePtr2(0, self.proj, "ReaProject*") then return end
    R.PreventUIRefresh(1)
    local ok, err = pcall(function() self:delete_own_clones() end)
    R.PreventUIRefresh(-1)
    R.UpdateArrange()
    if not ok then R.ShowConsoleMsg("[JKK_Variator] cleanup error: " .. tostring(err) .. "\n") end
end

function Session:clone_count()
    local n = 0
    for _ in pairs(self.clones) do n = n + 1 end
    return n
end

return Session
