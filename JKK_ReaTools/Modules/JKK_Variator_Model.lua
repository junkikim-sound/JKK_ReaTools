--========================================================
-- @title JKK_Variator_Model
-- @author Junki Kim
-- @noindex
-- Settings, generations, Link and Lock for JKK_Variator (pure Lua).
-- The model turns (settings, seed, generation counters, locks) into the
-- per-clone random results; it never touches the project.
--========================================================

local Model = {}
Model.__index = Model

local function load_module(name)
    local dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
    return dofile(dir .. name)
end
local Random = load_module("JKK_Variator_Random.lua")
local Layout = load_module("JKK_Variator_Layout.lua")

Model.PARAMS = { "volume", "pan", "pitch", "playrate" }
Model.MIN_DT = 0.002          -- seconds: minimum distance between random points
Model.POINTS_MAX = 12
Model.COUNT_MAX = 12
Model.GAP_MAX = 10
Model.GAP_GRID_MAX = 64       -- grid Gap: number of grid divisions between set starts

Model.RANGES = {
    volume   = { lo = -24, hi = 24,  unit = "dB" },
    pan      = { lo = -100, hi = 100, unit = "%" },
    pitch    = { lo = -24, hi = 24,  unit = "st" },
    playrate = { lo = -75, hi = 200, unit = "%" },
}

-- One symmetric amount per parameter: the random value range is -amount .. +amount.
-- Playrate stops at 75 so the slowest variation (-75 %) keeps a valid rate.
Model.AMOUNT_MAX = { volume = 24, pan = 100, pitch = 24, playrate = 75 }

local DEFAULT_AMOUNT = { volume = 3, pan = 30, pitch = 2, playrate = 10 }
Model.DEFAULT_AMOUNT = DEFAULT_AMOUNT   -- slider right-click resets to these

-- Fixed product decisions (no UI): Group mode, no preview loop, solo preview
-- always on, playrate never preserves pitch.
Model.FIXED = { mode = "group", loop = false, solo = true, preserve_pitch = false }

function Model.default_settings()
    local s = {
        -- Variations always opens at 0 (count is never stored)
        count = 0, gap = 0.5, mode = Model.FIXED.mode,
        gap_mode = "time", gap_grid = 1,   -- "time": seconds after each set; "grid": N grid steps from the left edge
        keep_original = true, auto_rename = false,
        include_original = false, loop = Model.FIXED.loop, solo = Model.FIXED.solo,
        params = {},
    }
    for _, name in ipairs(Model.PARAMS) do
        local a = DEFAULT_AMOUNT[name]
        s.params[name] = {
            enabled = true, amount = a, vmin = -a, vmax = a, pmin = 0, pmax = 0,
            link = false, curve = "linear",
        }
    end
    s.params.playrate.preserve_pitch = Model.FIXED.preserve_pitch
    return s
end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep_copy(x) end
    return t
end
Model.deep_copy = deep_copy

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Keep every setting inside its valid range. `edited` = "pmin" or "pmax" tells
-- which side the user moved so an invalid Points Min/Max is limited, never swapped.
-- The value range always follows the symmetric amount (-amount .. +amount).
function Model.sanitize_param(name, p, edited)
    local a = tonumber(p.amount)
    if not a then a = math.max(math.abs(tonumber(p.vmin) or 0), math.abs(tonumber(p.vmax) or 0)) end
    p.amount = clamp(math.abs(a), 0, Model.AMOUNT_MAX[name])
    p.vmin, p.vmax = -p.amount, p.amount
    p.pmin = clamp(math.floor(tonumber(p.pmin) or 0), 0, Model.POINTS_MAX)
    p.pmax = clamp(math.floor(tonumber(p.pmax) or 0), 0, Model.POINTS_MAX)
    if p.pmin > p.pmax then
        if edited == "pmax" then p.pmax = p.pmin else p.pmin = p.pmax end
    end
    if p.curve ~= "smooth" then p.curve = "linear" end
    p.enabled = p.enabled and true or false
    p.link = p.link and true or false
    return p
end

function Model.sanitize(s)
    s.count = clamp(math.floor(tonumber(s.count) or 0), 0, Model.COUNT_MAX)
    s.gap = clamp(tonumber(s.gap) or 0.5, 0, 3600)
    if s.gap_mode ~= "grid" then s.gap_mode = "time" end
    s.gap_grid = clamp(math.floor(tonumber(s.gap_grid) or 1), 1, Model.GAP_GRID_MAX)
    s.mode, s.loop, s.solo = Model.FIXED.mode, Model.FIXED.loop, Model.FIXED.solo
    for _, name in ipairs(Model.PARAMS) do
        s.params[name] = Model.sanitize_param(name, s.params[name] or {})
    end
    s.params.playrate.preserve_pitch = Model.FIXED.preserve_pitch
    return s
end

-- sources: array of { uid, len, pos, track_key, track_index, guid }
function Model.new(sources, seed, settings)
    local self = setmetatable({}, Model)
    self.sources = sources
    self.seed = seed or 1
    self.settings = Model.sanitize(settings and deep_copy(settings) or Model.default_settings())
    self.gens = {}     -- gens[unit][param] = integer
    self.locks = {}    -- locks[unit] = { [src_uid] = frozen result }
    local min_len = math.huge
    for _, src in ipairs(sources) do if src.len < min_len then min_len = src.len end end
    self.min_len = min_len
    return self
end

function Model:units()
    local out, s = {}, self.settings
    if s.mode == "group" then
        for k = 1, s.count do out[#out + 1] = { unit = Layout.unit_key("group", nil, k), k = k } end
    else
        for i, src in ipairs(self.sources) do
            for k = 1, s.count do
                out[#out + 1] = { unit = Layout.unit_key("individual", src.uid, k), k = k, src = i }
            end
        end
    end
    return out
end

function Model:gen(unit, param)
    local g = self.gens[unit]
    return g and g[param] or 0
end

function Model:min_du(param, src_index)
    local p = self.settings.params[param]
    local linked = p.link and self.settings.mode == "group"
    local len = linked and self.min_len or self.sources[src_index].len
    if not (len > 0) then return 1 end
    return Model.MIN_DT / len
end

-- Live (unlocked) results for one clone.
function Model:resolve_live(unit, src_index)
    local s = self.settings
    local src = self.sources[src_index]
    local res = {}
    for _, name in ipairs(Model.PARAMS) do
        local p = s.params[name]
        local key = Random.source_key(p.link, s.mode, src.uid)
        local base = Random.base(self.seed, unit, name, self:gen(unit, name), key)
        res[name] = Random.resolve_param(p, base, self:min_du(name, src_index))
    end
    return { res = res, preserve_pitch = s.params.playrate.preserve_pitch and true or false }
end

function Model:resolve(unit, src_index)
    local lock = self.locks[unit]
    if lock then
        local frozen = lock[self.sources[src_index].uid]
        if frozen then return frozen end
    end
    return self:resolve_live(unit, src_index)
end

function Model:is_locked(unit) return self.locks[unit] ~= nil end

function Model:lock(unit, src_indices)
    local frozen = {}
    for _, i in ipairs(src_indices) do
        frozen[self.sources[i].uid] = deep_copy(self:resolve_live(unit, i))
    end
    self.locks[unit] = frozen
end

function Model:unlock(unit) self.locks[unit] = nil end

function Model:any_locked()
    return next(self.locks) ~= nil
end

-- Highest variation number that is locked (count cannot go below it).
function Model:max_locked_k()
    local m = 0
    for unit in pairs(self.locks) do
        local k = tonumber(unit:match(":(%d+)$"))
        if k and k > m then m = k end
    end
    return m
end

-- Randomize one parameter (or all enabled ones when param == nil) for every
-- unlocked variation that currently exists.
function Model:randomize(param)
    local names = param and { param } or Model.PARAMS
    for _, u in ipairs(self:units()) do
        if not self.locks[u.unit] then
            local g = self.gens[u.unit]
            if not g then g = {}; self.gens[u.unit] = g end
            for _, name in ipairs(names) do
                if param or self.settings.params[name].enabled then
                    g[name] = (g[name] or 0) + 1
                end
            end
        end
    end
end

function Model:set_mode(mode)
    if mode == self.settings.mode then return end
    self.settings.mode = mode
    self.locks = {}
end

function Model:reset(seed)
    self.seed = seed or (self.seed + 1)
    self.settings = Model.default_settings()
    self.gens = {}
    self.locks = {}
end

----------------------------------------------------------
-- Signatures (detect which clones really changed)
----------------------------------------------------------
local function num(v) return string.format("%.9g", v) end

function Model.result_signature(r)
    local parts = {}
    for _, name in ipairs(Model.PARAMS) do
        local x = r.res[name]
        if not x or x.kind == "off" then
            parts[#parts + 1] = name .. ":off"
        elseif x.kind == "static" then
            parts[#parts + 1] = name .. ":s" .. num(x.d)
        elseif x.kind == "error" then
            parts[#parts + 1] = name .. ":e" .. x.msg
        else
            local p = { name .. ":d" .. (x.curve or "") }
            for _, pt in ipairs(x.pts) do p[#p + 1] = num(pt.u) .. "/" .. num(pt.d) end
            parts[#parts + 1] = table.concat(p, ",")
        end
    end
    parts[#parts + 1] = r.preserve_pitch and "pp1" or "pp0"
    return table.concat(parts, "|")
end

return Model
