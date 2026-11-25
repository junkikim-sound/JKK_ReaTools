--========================================================
-- @title JKK_Variator_Random
-- @author Junki Kim
-- @noindex
-- Deterministic sampling for JKK_Variator (pure Lua, no reaper calls).
--
-- Every random number is a pure function of
--   seed + unit (variation) + parameter + generation + source key
--   + sample kind + stable sample index + retry attempt.
-- Nothing is drawn per frame and nothing has to be stored: the same keys
-- always reproduce the same sample, so Variations decrease/increase, Gap,
-- Value range, Points range, Enabled and Link toggles reuse samples.
--========================================================

local M = {}

M.KIND_COUNT  = 1   -- q in [0,1): number of points
M.KIND_POS    = 2   -- u in [0,1): normalized position of point j
M.KIND_VALUE  = 3   -- r in [0,1): value ratio of point j
M.KIND_STATIC = 4   -- r in [0,1): static (Points = 0) value ratio

M.MAX_ATTEMPTS = 64
M.LINK_KEY = "~linked~"

local MASK = 0xFFFFFFFF

local function fmix32(h)
    h = h & MASK
    h = h ~ (h >> 16)
    h = (h * 0x85EBCA6B) & MASK
    h = h ~ (h >> 13)
    h = (h * 0xC2B2AE35) & MASK
    h = h ~ (h >> 16)
    return h
end

local function combine(h, v)
    return fmix32(((h * 31) + (math.tointeger(v) or 0) + 0x9E3779B9) & MASK)
end

-- FNV-1a 32 bit
function M.hash_string(s)
    s = tostring(s)
    local h = 0x811C9DC5
    for i = 1, #s do
        h = ((h ~ s:byte(i)) * 0x01000193) & MASK
    end
    return h
end

-- Base hash for one sample stream.
function M.base(seed, unit, param, gen, src_key)
    local h = fmix32(math.tointeger(seed) or M.hash_string(seed))
    h = combine(h, M.hash_string(unit))
    h = combine(h, M.hash_string(param))
    h = combine(h, math.tointeger(gen) or 0)
    h = combine(h, M.hash_string(src_key))
    return h
end

-- Uniform [0,1) with 24-bit resolution.
function M.unit(base, kind, index, attempt)
    local h = combine(base, kind)
    h = combine(h, index or 0)
    h = combine(h, attempt or 0)
    return (h >> 8) / 16777216.0
end

-- N = min + floor(q * (max - min + 1)), clamped to [min, max].
function M.map_count(q, pmin, pmax)
    if pmax < pmin then pmax = pmin end
    local n = pmin + math.floor(q * (pmax - pmin + 1))
    if n > pmax then n = pmax end
    if n < pmin then n = pmin end
    return n
end

function M.map_value(r, vmin, vmax)
    return vmin + r * (vmax - vmin)
end

-- Resolve one parameter of one item of one variation.
--   p      : { enabled, vmin, vmax, pmin, pmax, curve }
--   base   : M.base(...)
--   min_du : minimum normalized distance between points and from edges
-- Returns one of:
--   { kind = "off" }
--   { kind = "static",  d = delta }
--   { kind = "dynamic", n = N, pts = { {u=, d=, idx=}, ... } (sorted by u), curve = }
--   { kind = "error",   msg = "..." }
function M.resolve_param(p, base, min_du)
    if not p.enabled then return { kind = "off" } end
    local n = M.map_count(M.unit(base, M.KIND_COUNT, 0, 0), p.pmin, p.pmax)
    if n == 0 then
        return { kind = "static", d = M.map_value(M.unit(base, M.KIND_STATIC, 0, 0), p.vmin, p.vmax) }
    end
    min_du = min_du or 0
    if min_du < 0 then min_du = 0 end
    -- N points + 2 edge margins must fit with min_du spacing.
    if (n + 1) * min_du >= 1 then
        return { kind = "error", msg = string.format("item too short for %d points", n) }
    end
    local margin = min_du
    local span = 1 - 2 * margin
    local accepted = {}
    for j = 1, n do
        local found = nil
        for a = 0, M.MAX_ATTEMPTS - 1 do
            local u = margin + M.unit(base, M.KIND_POS, j, a) * span
            local ok = true
            for k = 1, #accepted do
                if math.abs(accepted[k].u - u) < min_du then ok = false; break end
            end
            if ok then found = u; break end
        end
        if not found then
            return { kind = "error", msg = string.format("cannot place %d distinct points", n) }
        end
        accepted[#accepted + 1] = {
            u = found,
            d = M.map_value(M.unit(base, M.KIND_VALUE, j, 0), p.vmin, p.vmax),
            idx = j,
        }
    end
    table.sort(accepted, function(a, b) return a.u < b.u end)
    return { kind = "dynamic", n = n, pts = accepted, curve = p.curve or "linear" }
end

-- Source key used for a stream: shared inside one variation set when Link is
-- ON (Group mode only), otherwise the item's own stable identity.
function M.source_key(link, mode, src_uid)
    if link and mode == "group" then return M.LINK_KEY end
    return tostring(src_uid)
end

return M
