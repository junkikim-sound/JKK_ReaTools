--========================================================
-- @title JKK_Variator_Math
-- @author Junki Kim
-- @noindex
-- Pure calculations for JKK_Variator (no reaper calls):
--   * static relative values (Volume / Pan / Pitch / Playrate)
--   * random curve evaluation with copied boundary anchors
--   * Dynamic Playrate time map  T(t) = integral[0,t] 1/m(s) ds
--   * stretch marker composition with an existing warp
--   * envelope composition with an existing take envelope
--
-- Time units used by the writer (see JKK_Variator_Item.lua):
--   t   original item time (seconds from item start, before variation)
--   T   output item time after Dynamic Playrate
--   tau "take time" = item time * take playrate. Stretch marker positions
--       and take envelope point times are assumed to use tau.
--========================================================

local M = {}

M.RATE_MIN = 0.01
M.RATE_MAX = 10.0
M.MARKER_MAX_REL_STEP = 0.01   -- max relative rate change inside one stretch segment
M.MARKER_CAP = 512
M.ENV_MAX_SAMPLES = 256
M.ENV_MIN_STEP = 0.005         -- seconds (tau) between composition samples

local EPS = 1e-9

local function clamp(v, lo, hi)
    if v < lo then return lo, true end
    if v > hi then return hi, true end
    return v, false
end
M.clamp = clamp

function M.db_to_gain(db) return 10 ^ (db / 20) end

----------------------------------------------------------
-- Random curve
----------------------------------------------------------
-- Boundary anchors copy the first / last random value. They are NOT part of
-- the random point count.
function M.with_anchors(pts)
    local out = {}
    if #pts == 0 then return out end
    out[1] = { u = 0, d = pts[1].d, anchor = true }
    for i = 1, #pts do out[#out + 1] = { u = pts[i].u, d = pts[i].d, idx = pts[i].idx } end
    out[#out + 1] = { u = 1, d = pts[#pts].d, anchor = true }
    return out
end

-- Smooth = smoothstep between neighbouring points: monotone inside each
-- segment, so it never overshoots the two point values.
function M.curve_eval(pts, u, curve)
    local n = #pts
    if n == 0 then return 0 end
    if u <= pts[1].u then return pts[1].d end
    if u >= pts[n].u then return pts[n].d end
    for i = 1, n - 1 do
        local a, b = pts[i], pts[i + 1]
        if u <= b.u then
            local w = b.u - a.u
            local x = (w > 0) and ((u - a.u) / w) or 1
            if curve == "smooth" then x = x * x * (3 - 2 * x) end
            return a.d + (b.d - a.d) * x
        end
    end
    return pts[n].d
end

----------------------------------------------------------
-- Static values (relative to the original snapshot, never cumulative)
----------------------------------------------------------
function M.static_values(snap, res, preserve_pitch)
    local out = {
        vol = snap.vol, pan = snap.pan, pitch = snap.pitch,
        rate = snap.rate, ppitch = snap.ppitch, mult = 1, clamped = {}, errors = {},
    }
    local r = res.volume
    if r and r.kind == "static" then out.vol = snap.vol * M.db_to_gain(r.d) end
    r = res.pan
    if r and r.kind == "static" then
        local v, c = clamp(snap.pan + r.d / 100, -1, 1)
        out.pan = v
        if c then out.clamped.pan = true end
    end
    r = res.pitch
    if r and r.kind == "static" then out.pitch = snap.pitch + r.d end
    r = res.playrate
    if r and (r.kind == "static" or r.kind == "dynamic") then
        out.ppitch = preserve_pitch and 1 or 0
    end
    if r and r.kind == "static" then
        local mult = 1 + r.d / 100
        if not (mult > 0) then
            out.errors.playrate = "playrate multiplier must be > 0"
        else
            local rate, c = clamp(snap.rate * mult, M.RATE_MIN, M.RATE_MAX)
            out.rate = rate
            out.mult = rate / snap.rate
            if c then out.clamped.playrate = true end
        end
    end
    return out
end

----------------------------------------------------------
-- Dynamic Playrate time map
----------------------------------------------------------
-- pts: sorted random points {u, d} (d in relative %), L0: original length.
-- m(t) = 1 + d(t)/100, linear between anchored points on the ORIGINAL axis.
function M.build_timemap(pts, L0)
    if not (L0 and L0 > 0) then return nil, "invalid item length" end
    local a = M.with_anchors(pts)
    if #a == 0 then return nil, "no points" end
    local nodes = {}
    for i = 1, #a do
        local m = 1 + a[i].d / 100
        if not (m > 0) or m ~= m or m == math.huge then
            return nil, "playrate multiplier must stay > 0"
        end
        local t = a[i].u * L0
        if #nodes > 0 and t <= nodes[#nodes].t + EPS then
            nodes[#nodes].m = m   -- coincident node: keep the later value
        else
            nodes[#nodes + 1] = { t = t, m = m }
        end
    end
    nodes[1].T = 0
    for i = 2, #nodes do
        local p, q = nodes[i - 1], nodes[i]
        q.T = p.T + M.seg_integral(p.m, q.m, q.t - p.t, q.t - p.t)
    end
    return { nodes = nodes, L0 = L0, out_len = nodes[#nodes].T }
end

-- integral[0,x] ds / (ma + k s), k = (mb - ma) / dt
function M.seg_integral(ma, mb, dt, x)
    if dt <= 0 then return 0 end
    local k = (mb - ma) / dt
    if math.abs(k * dt) < 1e-12 * ma then return x / ma end
    return math.log((ma + k * x) / ma) / k
end

local function find_seg(nodes, key, v)
    local lo, hi = 1, #nodes - 1
    if hi < 1 then return 1 end
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if nodes[mid][key] <= v then lo = mid else hi = mid - 1 end
    end
    return lo
end

function M.tm_forward(tm, t)
    local nodes = tm.nodes
    if #nodes == 1 then return t / nodes[1].m end
    if t <= 0 then return t / nodes[1].m end
    if t >= tm.L0 then return tm.out_len + (t - tm.L0) / nodes[#nodes].m end
    local i = find_seg(nodes, "t", t)
    local a, b = nodes[i], nodes[i + 1]
    return a.T + M.seg_integral(a.m, b.m, b.t - a.t, t - a.t)
end

function M.tm_inverse(tm, T)
    local nodes = tm.nodes
    if #nodes == 1 then return T * nodes[1].m end
    if T <= 0 then return T * nodes[1].m end
    if T >= tm.out_len then return tm.L0 + (T - tm.out_len) * nodes[#nodes].m end
    local i = find_seg(nodes, "T", T)
    local a, b = nodes[i], nodes[i + 1]
    local dt = b.t - a.t
    local y = T - a.T
    local k = (b.m - a.m) / dt
    if math.abs(k * dt) < 1e-12 * a.m then return a.t + y * a.m end
    return a.t + a.m * (math.exp(k * y) - 1) / k
end

-- Marker times on the original axis: every node plus subdivisions so that the
-- rate changes by at most max_rel inside one constant-speed stretch segment.
function M.tm_sample_times(tm, max_rel, cap)
    max_rel = max_rel or M.MARKER_MAX_REL_STEP
    cap = cap or M.MARKER_CAP
    local nodes = tm.nodes
    local subs, total = {}, 0
    for i = 1, #nodes - 1 do
        local a, b = nodes[i], nodes[i + 1]
        local rel = math.abs(b.m - a.m) / math.min(a.m, b.m)
        local n = math.max(1, math.ceil(rel / max_rel - 1e-9))
        subs[i] = n
        total = total + n
    end
    if total > cap then
        for i = 1, #subs do subs[i] = math.max(1, math.floor(subs[i] * cap / total)) end
    end
    local ts = { nodes[1].t }
    for i = 1, #nodes - 1 do
        local a, b = nodes[i], nodes[i + 1]
        for s = 1, subs[i] do ts[#ts + 1] = a.t + (b.t - a.t) * s / subs[i] end
    end
    return ts
end

-- Original source mapping tau -> source position. Without markers the take
-- plays at slope 1 from src_offset. With markers: piecewise linear, slope 1
-- outside the first / last marker.
function M.make_src_map(orig_markers, src_offset)
    if not orig_markers or #orig_markers == 0 then
        return function(tau) return src_offset + tau end
    end
    local mk = orig_markers
    return function(tau)
        if tau <= mk[1].pos then return mk[1].srcpos + (tau - mk[1].pos) end
        local n = #mk
        if tau >= mk[n].pos then return mk[n].srcpos + (tau - mk[n].pos) end
        for i = 1, n - 1 do
            local a, b = mk[i], mk[i + 1]
            if tau <= b.pos then
                local w = b.pos - a.pos
                if w <= 0 then return b.srcpos end
                return a.srcpos + (b.srcpos - a.srcpos) * (tau - a.pos) / w
            end
        end
        return mk[n].srcpos
    end
end

-- Compose the variation warp with the original warp.
-- Returns list of { pos = tau_out, srcpos = source } markers (strictly
-- increasing in both), or nil, error.
function M.compose_markers(tm, r0, orig_markers, src_offset)
    local ts = M.tm_sample_times(tm)
    for _, mk in ipairs(orig_markers or {}) do
        local t = mk.pos / r0
        if t > EPS and t < tm.L0 - EPS then ts[#ts + 1] = t end
    end
    table.sort(ts)
    local uniq = {}
    for _, t in ipairs(ts) do
        if #uniq == 0 or t - uniq[#uniq] > 1e-7 then uniq[#uniq + 1] = t end
    end
    local src = M.make_src_map(orig_markers, src_offset)
    local out = {}
    for i, t in ipairs(uniq) do
        local pos = M.tm_forward(tm, t) * r0
        local sp = src(t * r0)
        if pos ~= pos or sp ~= sp or pos == math.huge or sp == math.huge then
            return nil, "invalid stretch marker value"
        end
        if i > 1 and (pos <= out[#out].pos or sp <= out[#out].srcpos) then
            return nil, "stretch markers are not strictly increasing"
        end
        out[#out + 1] = { pos = pos, srcpos = sp, t = t }
    end
    return out
end

----------------------------------------------------------
-- Envelope composition
----------------------------------------------------------
-- conv = { from = native->amplitude, to = amplitude->native, pan_sign = +/-1 }
function M.neutral_native(param, conv)
    if param == "volume" then return conv.to(1) end
    return 0
end

function M.compose_native(param, native, d, conv)
    if param == "volume" then
        local amp = conv.from(native)
        return conv.to(amp * M.db_to_gain(d)), false
    elseif param == "pan" then
        local s = conv.pan_sign or 1
        local p, c = clamp(s * native + d / 100, -1, 1)
        return s * p, c
    end
    return native + d, false
end

-- env_plan : { pts = sorted random points, curve = "linear"|"smooth" }
-- tau_end  : output envelope length in tau
-- orig     : nil (no original envelope) or
--            { taus = { output tau of original points }, eval = function(tau_out) -> native }
-- Returns points { time, value, shape }, clamped flag.
function M.build_env_points(param, env_plan, tau_end, orig, conv)
    local pts = M.with_anchors(env_plan.pts)
    local out, clamped = {}, false
    if not orig then
        local shape = (env_plan.curve == "smooth") and 2 or 0
        local neutral = M.neutral_native(param, conv)
        for _, p in ipairs(pts) do
            local v, c = M.compose_native(param, neutral, p.d, conv)
            clamped = clamped or c
            out[#out + 1] = { time = p.u * tau_end, value = v, shape = shape }
        end
        return out, clamped
    end
    -- With an existing envelope: union of breakpoints + bounded resampling,
    -- linear segments. This is a sampled approximation, not lossless.
    local times = { 0, tau_end }
    for _, p in ipairs(pts) do times[#times + 1] = p.u * tau_end end
    for _, t in ipairs(orig.taus or {}) do
        if t > 0 and t < tau_end then times[#times + 1] = t end
    end
    table.sort(times)
    local step = math.max(M.ENV_MIN_STEP, tau_end / M.ENV_MAX_SAMPLES)
    local uniq = {}
    for _, t in ipairs(times) do
        if #uniq == 0 or t - uniq[#uniq] > 1e-7 then uniq[#uniq + 1] = t end
    end
    local dense = { uniq[1] }
    for i = 2, #uniq do
        local a, b = uniq[i - 1], uniq[i]
        local n = math.floor((b - a) / step)
        for s = 1, n do dense[#dense + 1] = a + (b - a) * s / (n + 1) end
        dense[#dense + 1] = b
    end
    for _, t in ipairs(dense) do
        local d = M.curve_eval(pts, (tau_end > 0) and (t / tau_end) or 0, env_plan.curve)
        local v, c = M.compose_native(param, orig.eval(t), d, conv)
        clamped = clamped or c
        out[#out + 1] = { time = t, value = v, shape = 0 }
    end
    return out, clamped
end

----------------------------------------------------------
-- Full plan for one clone (pure)
----------------------------------------------------------
-- snap : source snapshot (numbers only are used here)
-- res  : { volume=, pan=, pitch=, playrate= } results from Random.resolve_param
-- Returns plan with .errors (param -> message) and .clamped (param -> true).
function M.build_plan(snap, res, preserve_pitch)
    local sv = M.static_values(snap, res, preserve_pitch)
    local plan = {
        vol = sv.vol, pan = sv.pan, pitch = sv.pitch, rate = sv.rate, ppitch = sv.ppitch,
        errors = sv.errors, clamped = sv.clamped, env = {}, length = snap.len,
    }
    for _, name in ipairs({ "volume", "pan", "pitch", "playrate" }) do
        local r = res[name]
        if r and r.kind == "error" then plan.errors[name] = r.msg end
    end
    local pr = res.playrate
    if pr and pr.kind == "dynamic" then
        if snap.dynrate_block then
            plan.errors.playrate = "Dynamic Playrate not supported: " .. snap.dynrate_block
        else
            local tm, err = M.build_timemap(pr.pts, snap.len)
            if not tm then
                plan.errors.playrate = err
            else
                plan.tm = tm
                plan.length = tm.out_len
            end
        end
    elseif pr and pr.kind == "static" and not plan.errors.playrate then
        plan.length = snap.len / sv.mult
    end
    for _, name in ipairs({ "volume", "pan", "pitch" }) do
        local r = res[name]
        if r and r.kind == "dynamic" then
            local block = snap.env_block and snap.env_block[name]
            if block then
                plan.errors[name] = block
            else
                plan.env[name] = { pts = r.pts, curve = r.curve }
            end
        end
    end
    -- Fades / snap offset follow the length change.
    local f = (snap.len > 0) and (plan.length / snap.len) or 1
    plan.fadein = (snap.fadein or 0) * f
    plan.fadeout = (snap.fadeout or 0) * f
    -- auto (crossfade) lengths can be negative = "none": keep those as they are
    local fa, fb = snap.fadein_auto or 0, snap.fadeout_auto or 0
    plan.fadein_auto = (fa > 0) and fa * f or fa
    plan.fadeout_auto = (fb > 0) and fb * f or fb
    plan.snapoffs = (snap.snapoffs or 0) * f
    local sum = plan.fadein + plan.fadeout
    if sum > plan.length and sum > 0 then
        local k = plan.length / sum
        plan.fadein, plan.fadeout = plan.fadein * k, plan.fadeout * k
        plan.clamped.fade = true
    end
    -- Envelope time scale (tau per output second).
    plan.env_rate = plan.rate
    plan.tau_end = plan.length * plan.rate
    return plan
end

return M
