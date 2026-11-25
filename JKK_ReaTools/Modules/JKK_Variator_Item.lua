--========================================================
-- @title JKK_Variator_Item
-- @author Junki Kim
-- @noindex
-- REAPER item layer for JKK_Variator:
--   * source snapshot + support checks
--   * clone creation from the ORIGINAL state chunk (new GUIDs, no group,
--     unselected) so every rebuild starts from the snapshot, never cumulative
--   * writing a plan: static take values, length/fades, take envelopes,
--     stretch markers (Dynamic Playrate), name, temporary ownership tag
-- Every write is verified where REAPER lets us read the result back; a
-- mismatch is reported as an error instead of being silently accepted.
--========================================================

local R = reaper
local M = {}

local dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
local VMath = dofile(dir .. "JKK_Variator_Math.lua")

M.TAG = "P_EXT:JKK_Variator_tmp"
-- Take pan envelope values are assumed to be inverted relative to D_PAN
-- (+1 = left). Not verified in REAPER yet: flip to 1 if a test shows otherwise.
M.PAN_ENV_SIGN = -1

M.ENV_NAMES = { volume = "Volume", pan = "Pan", pitch = "Pitch" }
M.ENV_TAGS  = { volume = "VOLENV", pan = "PANENV", pitch = "PITCHENV" }
local ENV_NEUTRAL = { volume = "1", pan = "0", pitch = "0" }

local AUDIO_TYPES = {
    WAVE = true, MP3 = true, FLAC = true, VORBIS = true, OGG = true, OPUS = true,
    AIFF = true, WAVPACK = true, CAF = true, W64 = true, RF64 = true,
}

----------------------------------------------------------
-- Chunk helpers
----------------------------------------------------------
function M.split_lines(chunk)
    local lines = {}
    for line in (chunk .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    while #lines > 0 and lines[#lines]:match("^%s*$") do lines[#lines] = nil end
    return lines
end

local function trim(s) return (s:match("^%s*(.-)%s*$")) end

-- Scan the ITEM chunk: depth-1 line indices of TAKE separators and the
-- closing ">" of the item.
function M.scan(lines)
    local depth, takes, close = 0, {}, #lines
    for i, raw in ipairs(lines) do
        local t = trim(raw)
        if depth == 1 and (t == "TAKE" or t:match("^TAKE%s")) then takes[#takes + 1] = i end
        if t:sub(1, 1) == "<" then
            depth = depth + 1
        elseif t == ">" then
            depth = depth - 1
            if depth == 0 then close = i end
        end
    end
    return takes, close
end

-- [first, last) line range of take `take_index` (0-based) at depth 1.
function M.take_range(lines, take_index)
    local takes, close = M.scan(lines)
    local first = (take_index == 0) and 2 or ((takes[take_index] or close) + 1)
    local last = takes[take_index + 1] or close
    return first, last
end

function M.chunk_has_env(lines, take_index, tag)
    local first, last = M.take_range(lines, take_index)
    local depth = 1
    for i = first, last - 1 do
        local t = trim(lines[i])
        if depth == 1 and (t == "<" .. tag or t:match("^<" .. tag .. "%s")) then return true end
        if t:sub(1, 1) == "<" then depth = depth + 1 elseif t == ">" then depth = depth - 1 end
    end
    return false
end

local GUID_KEYS = { IGUID = true, GUID = true, EGUID = true, FXID = true }

-- Build a clone chunk: GUIDs replaced (guid_fn(n) -> n-th GUID), item group
-- removed, unselected, and empty take envelopes added for `stubs` params.
function M.build_chunk(lines, take_index, guid_fn, stubs)
    local out, depth, n = {}, 0, 0
    local insert_at = nil
    if stubs and #stubs > 0 then
        local _, last = M.take_range(lines, take_index)
        insert_at = last
    end
    for i, raw in ipairs(lines) do
        if insert_at == i then
            for _, p in ipairs(stubs) do
                n = n + 1
                out[#out + 1] = "<" .. M.ENV_TAGS[p]
                out[#out + 1] = "EGUID " .. guid_fn(n)
                out[#out + 1] = "ACT 1 -1"
                out[#out + 1] = "VIS 1 1 1"
                out[#out + 1] = "LANEHEIGHT 0 0"
                out[#out + 1] = "ARM 0"
                out[#out + 1] = "DEFSHAPE 0 -1 -1"
                out[#out + 1] = "PT 0 " .. ENV_NEUTRAL[p] .. " 0"
                out[#out + 1] = ">"
            end
        end
        local t = trim(raw)
        local key = t:match("^(%S+)")
        local line = raw
        if key and GUID_KEYS[key] and t:match("{.-}") then
            n = n + 1
            line = key .. " " .. guid_fn(n)
        elseif depth == 1 and key == "GROUP" then
            line = nil
        elseif depth == 1 and key == "SEL" then
            line = "SEL 0"
        end
        if line then out[#out + 1] = line end
        if t:sub(1, 1) == "<" then depth = depth + 1 elseif t == ">" then depth = depth - 1 end
    end
    return table.concat(out, "\n") .. "\n"
end

----------------------------------------------------------
-- Snapshot
----------------------------------------------------------
local function item_guid(item)
    local _, g = R.GetSetMediaItemInfo_String(item, "GUID", "", false)
    return g
end
M.item_guid = item_guid

function M.snapshot(proj, item)
    local track = R.GetMediaItem_Track(item)
    local take = R.GetActiveTake(item)
    local guid = item_guid(item)
    local name = take and select(2, R.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)) or ""
    local label = (name ~= "" and name) or guid
    if not take then return nil, label, "empty item (no take)" end
    if R.TakeIsMIDI(take) then return nil, label, "MIDI take" end
    if R.GetMediaItemInfo_Value(item, "B_ALLTAKESPLAY") == 1 then return nil, label, "'Play all takes' is on" end
    local src = R.GetMediaItemTake_Source(take)
    if not src then return nil, label, "no source" end
    local stype = R.GetMediaSourceType(src, "")
    local root, section = src, false
    if stype == "SECTION" then
        section = true
        root = R.GetMediaSourceParent(src) or src
    end
    local rtype = R.GetMediaSourceType(root, "")
    if not AUDIO_TYPES[rtype] then return nil, label, "unsupported source type: " .. tostring(rtype) end
    local fname = R.GetMediaSourceFileName(root, "")
    if fname ~= "" and not R.file_exists(fname) then return nil, label, "missing source file" end
    if R.CF_GetMediaSourceOnline and not R.CF_GetMediaSourceOnline(root) then
        return nil, label, "offline source"
    end
    local ok_chunk, chunk = R.GetItemStateChunk(item, "", false)
    if not ok_chunk or chunk == "" then return nil, label, "cannot read item state" end

    local snap = {
        item = item, guid = guid, track = track, take = take, name = name, label = label,
        track_guid = R.GetTrackGUID(track),
        track_index = R.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"),
        take_guid = select(2, R.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)),
        take_index = math.floor(R.GetMediaItemInfo_Value(item, "I_CURTAKE")),
        pos = R.GetMediaItemInfo_Value(item, "D_POSITION"),
        len = R.GetMediaItemInfo_Value(item, "D_LENGTH"),
        soffs = R.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
        vol = R.GetMediaItemTakeInfo_Value(take, "D_VOL"),
        pan = R.GetMediaItemTakeInfo_Value(take, "D_PAN"),
        pitch = R.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
        rate = R.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
        ppitch = R.GetMediaItemTakeInfo_Value(take, "B_PPITCH"),
        fadein = R.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
        fadeout = R.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
        fadein_auto = R.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO"),
        fadeout_auto = R.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO"),
        snapoffs = R.GetMediaItemInfo_Value(item, "D_SNAPOFFSET"),
        group_id = math.floor(R.GetMediaItemInfo_Value(item, "I_GROUPID")),
        loopsrc = R.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1,
        section = section,
        lines = M.split_lines(chunk),
        markers = {}, env_exists = {}, env_in_chunk = {}, env_block = {},
    }
    if not (snap.len > 0) or not (snap.rate > 0) then return nil, label, "invalid length or playrate" end

    -- Dynamic Playrate restrictions (stretch-marker warp must stay monotonic).
    local reversed = false
    if R.BR_GetMediaSourceProperties then
        local okp, _, _, _, _, rev = R.BR_GetMediaSourceProperties(take)
        if okp then reversed = rev and true or false end
    elseif section then
        reversed = true   -- cannot tell without SWS: treat section sources conservatively
    end
    local src_len = R.GetMediaSourceLength(src)
    local n = R.GetTakeNumStretchMarkers(take)
    local slope_used = false
    for i = 0, n - 1 do
        local _, pos, srcpos = R.GetTakeStretchMarker(take, i)
        snap.markers[#snap.markers + 1] = { pos = pos, srcpos = srcpos }
        if R.GetTakeStretchMarkerSlope and math.abs(R.GetTakeStretchMarkerSlope(take, i)) > 1e-9 then slope_used = true end
    end
    local mono = true
    for i = 2, #snap.markers do
        if snap.markers[i].pos <= snap.markers[i - 1].pos or snap.markers[i].srcpos <= snap.markers[i - 1].srcpos then mono = false end
    end
    if reversed then
        snap.dynrate_block = "reversed source"
    elseif section then
        snap.dynrate_block = "section source"
    elseif snap.loopsrc and src_len and (snap.soffs < -1e-9 or snap.soffs + snap.len * snap.rate > src_len + 1e-6) then
        snap.dynrate_block = "looped source"
    elseif slope_used then
        snap.dynrate_block = "existing stretch marker slopes"
    elseif not mono then
        snap.dynrate_block = "existing stretch markers are not increasing"
    end

    for param, ename in pairs(M.ENV_NAMES) do
        local env = R.GetTakeEnvelopeByName(take, ename)
        local in_chunk = M.chunk_has_env(snap.lines, snap.take_index, M.ENV_TAGS[param])
        snap.env_in_chunk[param] = in_chunk
        if env then
            local _, ech = R.GetEnvelopeStateChunk(env, "", false)
            local act = ech and ech:match("\nACT (%-?%d)")
            if act == "0" then
                snap.env_block[param] = "existing " .. ename .. " envelope is bypassed"
            elseif not in_chunk then
                snap.env_block[param] = "cannot locate existing " .. ename .. " envelope in item state"
            else
                snap.env_exists[param] = true
            end
        elseif in_chunk then
            snap.env_block[param] = "unexpected " .. ename .. " envelope state"
        end
    end
    return snap
end

----------------------------------------------------------
-- Clone lifecycle
----------------------------------------------------------
function M.stub_params(snap, plan)
    local stubs = {}
    for _, p in ipairs({ "volume", "pan", "pitch" }) do
        if plan.env[p] and not snap.env_in_chunk[p] then stubs[#stubs + 1] = p end
    end
    return stubs
end

-- guids: array reused across rebuilds of the same clone (stable GUIDs).
function M.guid_provider(guids)
    return function(n)
        if not guids[n] then guids[n] = R.genGuid("") end
        return guids[n]
    end
end

function M.create(track, chunk)
    local item = R.AddMediaItemToTrack(track)
    if not item then return nil, "AddMediaItemToTrack failed" end
    if not R.SetItemStateChunk(item, chunk, false) then
        R.DeleteTrackMediaItem(track, item)
        return nil, "SetItemStateChunk failed"
    end
    return item
end

function M.reset(item, chunk)
    return R.SetItemStateChunk(item, chunk, false)
end

function M.delete(proj, item)
    if item and R.ValidatePtr2(proj, item, "MediaItem*") then
        local tr = R.GetMediaItem_Track(item)
        if tr then return R.DeleteTrackMediaItem(tr, item) end
    end
    return false
end

----------------------------------------------------------
-- Writers
----------------------------------------------------------
local function close(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-6) * math.max(1, math.abs(a), math.abs(b))
end

-- Offset between take time and stretch-marker source position, measured by
-- REAPER itself on a clone without markers (cached per source).
local function calibrate_offset(take, snap)
    if snap.sm_offset then return snap.sm_offset end
    local probe = snap.len * snap.rate * 0.37
    local idx = R.SetTakeStretchMarker(take, -1, probe)
    if not idx or idx < 0 then return nil end
    local _, pos, srcpos = R.GetTakeStretchMarker(take, idx)
    R.DeleteTakeStretchMarkers(take, idx, 1)
    snap.sm_offset = srcpos - pos
    return snap.sm_offset
end

local function write_stretch(take, snap, plan)
    local offset = 0
    if #snap.markers == 0 then
        offset = calibrate_offset(take, snap)
        if not offset then return "stretch marker probe failed" end
    end
    local markers, err = VMath.compose_markers(plan.tm, snap.rate, snap.markers, offset)
    if not markers then return err end
    local n = R.GetTakeNumStretchMarkers(take)
    if n > 0 then R.DeleteTakeStretchMarkers(take, 0, n) end
    for _, m in ipairs(markers) do
        local idx = R.SetTakeStretchMarker(take, -1, m.pos, m.srcpos)
        if not idx or idx < 0 then return "stretch marker rejected by REAPER" end
    end
    if R.GetTakeNumStretchMarkers(take) ~= #markers then return "stretch marker count mismatch" end
    for i, m in ipairs(markers) do
        local _, pos, srcpos = R.GetTakeStretchMarker(take, i - 1)
        if not close(pos, m.pos) or not close(srcpos, m.srcpos) then
            return "stretch marker verification failed"
        end
    end
    return nil
end

local function write_env(take, param, snap, plan)
    local env = R.GetTakeEnvelopeByName(take, M.ENV_NAMES[param])
    if not env then return "could not create take " .. M.ENV_NAMES[param] .. " envelope" end
    local mode = R.GetEnvelopeScalingMode(env)
    local conv = {
        from = function(v) return R.ScaleFromEnvelopeMode(mode, v) end,
        to = function(a) return R.ScaleToEnvelopeMode(mode, a) end,
        pan_sign = M.PAN_ENV_SIGN,
    }
    local orig = nil
    if snap.env_exists[param] then
        local r0, tm = snap.rate, plan.tm
        local function fwd(tau_o) return tm and (VMath.tm_forward(tm, tau_o / r0) * r0) or tau_o end
        local function inv(tau) return tm and (VMath.tm_inverse(tm, tau / r0) * r0) or tau end
        local taus = {}
        for i = 0, R.CountEnvelopePoints(env) - 1 do
            local _, time = R.GetEnvelopePoint(env, i)
            taus[#taus + 1] = fwd(time)
        end
        orig = {
            taus = taus,
            eval = function(tau)
                local _, v = R.Envelope_Evaluate(env, inv(tau), 48000, 1)
                return v
            end,
        }
    end
    -- All original values are sampled before anything is deleted.
    local pts, clamped = VMath.build_env_points(param, plan.env[param], plan.tau_end, orig, conv)
    R.DeleteEnvelopePointRange(env, -1e9, 1e9)
    for _, p in ipairs(pts) do
        R.InsertEnvelopePoint(env, p.time, p.value, p.shape, 0, false, true)
    end
    R.Envelope_SortPoints(env)
    if R.CountEnvelopePoints(env) ~= #pts then return M.ENV_NAMES[param] .. " envelope point count mismatch" end
    if clamped then plan.clamped[param] = true end
    return nil
end

-- opts = { name = string|nil, tag = string|nil }
-- Returns errors table (param -> message) merged into plan.errors.
function M.write(item, snap, plan, opts)
    local errors = {}
    local take = R.GetActiveTake(item)
    if not take then errors.item = "clone has no active take"; return errors end
    R.SetMediaItemTakeInfo_Value(take, "D_VOL", plan.vol)
    R.SetMediaItemTakeInfo_Value(take, "D_PAN", plan.pan)
    R.SetMediaItemTakeInfo_Value(take, "D_PITCH", plan.pitch)
    R.SetMediaItemTakeInfo_Value(take, "B_PPITCH", plan.ppitch)
    R.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", plan.rate)
    if plan.tm then
        -- marker calibration happens at the original length, before resizing
        local e = nil
        if #snap.markers == 0 and not snap.sm_offset then
            if not calibrate_offset(take, snap) then e = "stretch marker probe failed" end
        end
        R.SetMediaItemInfo_Value(item, "D_LENGTH", plan.length)
        e = e or write_stretch(take, snap, plan)
        if e then errors.playrate = e end
    else
        R.SetMediaItemInfo_Value(item, "D_LENGTH", plan.length)
    end
    R.SetMediaItemInfo_Value(item, "D_FADEINLEN", plan.fadein)
    R.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", plan.fadeout)
    R.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", plan.fadein_auto)
    R.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", plan.fadeout_auto)
    R.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", plan.snapoffs)
    for _, p in ipairs({ "volume", "pan", "pitch" }) do
        if plan.env[p] then
            local e = write_env(take, p, snap, plan)
            if e then errors[p] = e end
        end
    end
    if opts.name then R.GetSetMediaItemTakeInfo_String(take, "P_NAME", opts.name, true) end
    if opts.tag then R.GetSetMediaItemInfo_String(item, M.TAG, opts.tag, true) end
    return errors
end

return M
