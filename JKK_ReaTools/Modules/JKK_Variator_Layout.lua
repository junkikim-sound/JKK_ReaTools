--========================================================
-- @title JKK_Variator_Layout
-- @author Junki Kim
-- @noindex
-- Group / Individual placement, Gap and collision detection (pure Lua).
--
-- Group (spec 3.2):
--   original_start = min(pos), original_end = max(pos + len)
--   rel[i]         = pos[i] - original_start
--   set_start[1]   = original_end + gap
--   set_start[k+1] = max(end of set k) + gap
--   item_pos[k,i]  = set_start[k] + rel[i]
-- Individual (spec 3.3): sources ordered by start, track order, GUID; each
--   source's clones follow each other after the last original end.
--========================================================

local M = {}

function M.unit_key(mode, src_uid, k)
    if mode == "group" then return string.format("g:%d", k) end
    return string.format("i:%s:%d", tostring(src_uid), k)
end

function M.clone_key(unit, src_uid)
    return unit .. "#" .. tostring(src_uid)
end

function M.original_range(sources)
    local s, e = math.huge, -math.huge
    for _, src in ipairs(sources) do
        if src.pos < s then s = src.pos end
        if src.pos + src.len > e then e = src.pos + src.len end
    end
    return s, e
end

function M.individual_order(sources)
    local order = {}
    for i = 1, #sources do order[i] = i end
    table.sort(order, function(a, b)
        local A, B = sources[a], sources[b]
        if math.abs(A.pos - B.pos) > 1e-9 then return A.pos < B.pos end
        if (A.track_index or 0) ~= (B.track_index or 0) then return (A.track_index or 0) < (B.track_index or 0) end
        return tostring(A.guid) < tostring(B.guid)
    end)
    return order
end

-- opts = { mode = "group"|"individual", count = n, gap = s,
--          length_of = function(unit, src_index, k) -> final length,
--          set_start = function(k, o_start) -> start | nil }
-- set_start (Group only, grid Gap): set k starts at a fixed time measured from
-- the left edge of all originals, regardless of lengths (sets may overlap).
function M.compute(sources, opts)
    local gap = math.max(0, opts.gap or 0)
    local count = math.max(0, math.floor(opts.count or 0))
    local o_start, o_end = M.original_range(sources)
    local out = {
        original = { start = o_start, ["end"] = o_end },
        placements = {}, sets = {},
    }
    if opts.mode == "group" then
        local cursor = o_end + gap
        for k = 1, count do
            local unit = M.unit_key("group", nil, k)
            if opts.set_start then cursor = opts.set_start(k, o_start) end
            local set_end = cursor
            for i, src in ipairs(sources) do
                local len = opts.length_of(unit, i, k)
                local pos = cursor + (src.pos - o_start)
                out.placements[#out.placements + 1] = {
                    unit = unit, k = k, src = i, pos = pos, len = len,
                    track_key = src.track_key, ckey = M.clone_key(unit, src.uid),
                }
                if pos + len > set_end then set_end = pos + len end
            end
            out.sets[#out.sets + 1] = {
                unit = unit, k = k, start = cursor, ["end"] = set_end,
                label = string.format("%02d", k),
            }
            cursor = set_end + gap
        end
    else
        local cursor = o_end + gap
        local order = M.individual_order(sources)
        for oi, i in ipairs(order) do
            local src = sources[i]
            for k = 1, count do
                local unit = M.unit_key("individual", src.uid, k)
                local len = opts.length_of(unit, i, k)
                out.placements[#out.placements + 1] = {
                    unit = unit, k = k, src = i, pos = cursor, len = len,
                    track_key = src.track_key, ckey = M.clone_key(unit, src.uid),
                }
                out.sets[#out.sets + 1] = {
                    unit = unit, k = k, src = i, start = cursor, ["end"] = cursor + len,
                    label = string.format("%d-%02d", oi, k),
                }
                cursor = cursor + len + gap
            end
        end
    end
    return out
end

-- existing = { [track_key] = { {s=, e=, name=}, ... } } (items that are neither
-- originals nor session clones). Touching ranges are not collisions.
function M.collisions(placements, existing, eps)
    eps = eps or 1e-7
    local hits = {}
    for _, p in ipairs(placements) do
        local list = existing[p.track_key]
        if list then
            local ps, pe = p.pos, p.pos + p.len
            for _, it in ipairs(list) do
                if ps < it.e - eps and it.s < pe - eps then
                    hits[#hits + 1] = { placement = p, other = it }
                    break
                end
            end
        end
    end
    return hits
end

-- Preview plan: list of playable segments in arrangement order.
-- index = nil -> all variations (+ original if requested), contiguous range.
function M.preview_range(layout, include_original, index)
    local sets = layout.sets
    if #sets == 0 then return nil end
    if index then
        local s = sets[index]
        if not s then return nil end
        return s.start, s["end"]
    end
    local start = include_original and layout.original.start or sets[1].start
    local stop = sets[#sets]["end"]
    for _, s in ipairs(sets) do if s["end"] > stop then stop = s["end"] end end   -- grid Gap may overlap
    return start, stop
end

-- Which set (index) contains time t; 0 = original range, nil = gap/outside.
-- Overlapping sets (grid Gap): the latest-started set wins.
function M.set_at(layout, t)
    for i = #layout.sets, 1, -1 do
        local s = layout.sets[i]
        if t >= s.start - 1e-9 and t < s["end"] then return i end
    end
    local o = layout.original
    if t >= o.start and t < o["end"] then return 0 end
    return nil
end

return M
