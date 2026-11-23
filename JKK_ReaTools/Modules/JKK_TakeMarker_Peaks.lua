-- @noindex
-- JKK Take Marker Peak Detection
-- Standalone processing module. No UI and no nvk-ReaScripts dependency.
-- The reference nvk_TAKES script calls take:Clips(true) for EVERY take;
-- its variation detector is in the external nvk_FOLDER_ITEMS library (not in the ZIP).
local r = reaper
local Undo = dofile(((debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or "") .. "JKK_UndoLabels.lua")
local M = {}

-- User-tunable analysis defaults (seconds unless otherwise stated).
M.CONFIG = {
    absolute_threshold = 0.006, -- compatibility only: NOT used for region rejection
    max_take_seconds = 900, -- safety limit: 15 minutes per take
    max_channels = 16,
    samples_per_block = 4096, -- streaming audio samples per read
    marker_prefix = "", -- visible names are 01, 02, 03... (no prefix)
    end_marker_guard_seconds = 0.012, -- ignore false final peaks within 12 ms of item edge
}

-- Threshold and Min Length are consumed by the ORIGINAL Split Dyn detector
-- supplied as a callback. Peak scanning never changes that detector or
-- introduces a second silence threshold.
function M.ConfigFromSplitDyn(threshold, min_length)
    local c = {}
    for k, v in pairs(M.CONFIG) do c[k] = v end
    c.absolute_threshold = math.max(0, tonumber(threshold) or 0.01)
    return c
end

local OWNED_KEY = "P_EXT:JKK_GENERATED_PEAK_MARKERS_V1"
local LEGACY_PREFIX = "JKK Peak " -- migrate markers made by the previous patch


-- Turn the EXACT silence ranges returned by Split Dyn / Guide into the
-- complementary intervals that survive silence removal. All times here are
-- ITEM-RELATIVE seconds. No independent variation threshold is used.
-- This function is pure so it can be regression-tested outside REAPER.
function M.BuildKeptRegions(item_length, silences, short_piece_divisor)
    item_length = tonumber(item_length) or 0
    if item_length <= 0 or type(silences) ~= "table" then return {} end
    local removed = {}
    for _, region in ipairs(silences) do
        local a = tonumber(region.start)
        local b = tonumber(region["end"])
        if a and b and a < b then
            a = math.max(0, math.min(item_length, a))
            b = math.max(0, math.min(item_length, b))
            if b > a then removed[#removed + 1] = {start = a, ["end"] = b} end
        end
    end
    table.sort(removed, function(a, b) return a.start < b.start end)
    local kept, cursor = {}, 0
    for _, region in ipairs(removed) do
        if region.start > cursor + 1e-7 then
            kept[#kept + 1] = {start = cursor, ["end"] = region.start}
        end
        cursor = math.max(cursor, region["end"])
    end
    if item_length > cursor + 1e-7 then
        kept[#kept + 1] = {start = cursor, ["end"] = item_length}
    end
    -- Keep every real silence-separated interval. Do not predict Split Dyn's
    -- deleteShortItems(3) here: that function works on the currently selected
    -- split items (and its average can depend on the selection), not solely
    -- on this one item's region list. An approximate reimplementation was
    -- silently DROPPING valid variations and therefore take markers.
    -- Optional legacy filtering is retained for compatibility/testing only.
    if short_piece_divisor and short_piece_divisor > 0 and #kept > 1 then
        local total = 0
        for _, region in ipairs(kept) do total = total + region["end"] - region.start end
        local min_length = total / #kept / short_piece_divisor
        local filtered = {}
        for _, region in ipairs(kept) do
            if region["end"] - region.start >= min_length then
                filtered[#filtered + 1] = region
            end
        end
        return filtered
    end
    return kept
end

-- getSilenceTime() is the EXISTING Split Dyn function and must remain untouched.
-- Depending on how REAPER reports a take accessor's start, its silence times
-- can be item-local or project timestamps. Interpret them ONLY here, where
-- they are used for read-only peak analysis; Split Dyn and Guide are unchanged.
-- An unambiguous project-time interval is shifted back by item position.
function M.NormalizeSilenceTimes(item_position, item_length, raw_silences, accessor_origin)
    if type(raw_silences) ~= "table" then return nil, "no silence data" end
    if #raw_silences == 0 then return {} end
    local function overlap(a, b, lo, hi)
        return math.max(0, math.min(b, hi) - math.max(a, lo))
    end
    local local_score, project_score = 0, 0
    local finite_count = 0
    for _, v in ipairs(raw_silences) do
        local a, b = tonumber(v.start), tonumber(v["end"])
        if a and b and a == a and b == b and a < b then
            finite_count = finite_count + 1
            local_score = local_score + overlap(a, b, 0, item_length)
            project_score = project_score + overlap(a, b,
                item_position, item_position + item_length)
        end
    end
    if finite_count == 0 then
        return nil, "invalid silence intervals"
    end
    local shift = 0
    -- The original getSilenceTime() converts samples to seconds by ADDING
    -- GetAudioAccessorStartTime(). When available, that exact origin is
    -- therefore a much stronger coordinate reference than item position.
    if accessor_origin and accessor_origin == accessor_origin then
        local origin_score = 0
        for _, v in ipairs(raw_silences) do
            local a, b = tonumber(v.start), tonumber(v["end"])
            if a and b and a < b then
                origin_score = origin_score + overlap(a, b,
                    accessor_origin, accessor_origin + item_length)
            end
        end
        if origin_score > 0 and origin_score >= local_score - 1e-5
            and origin_score >= project_score - 1e-5 then
            shift = accessor_origin
        elseif project_score > local_score + 1e-5 then
            shift = item_position
        end
        if math.max(local_score, project_score, origin_score) <= 0 then
            return nil, "silence intervals outside selected item"
        end
    else
        if item_position ~= 0 and project_score > local_score + 1e-5 then
            shift = item_position
        end
        if local_score <= 0 and project_score <= 0 then
            return nil, "silence intervals outside selected item"
        end
    end
    local out = {}
    for _, v in ipairs(raw_silences) do
        local a, b = tonumber(v.start), tonumber(v["end"])
        if a and b and a == a and b == b and b > a then
            out[#out + 1] = { start = a - shift, ["end"] = b - shift }
        end
    end
    return out
end

local function info(take, key)
    return r.GetMediaItemTakeInfo_Value(take, key)
end

local function has_stretch_markers(take)
    return r.GetTakeNumStretchMarkers and r.GetTakeNumStretchMarkers(take) > 0
end

local function source_duration(take)
    local src = r.GetMediaItemTake_Source(take)
    if not src then return nil end
    local len = r.GetMediaSourceLength(src)
    return (len and len > 0) and len or nil
end

-- Only linear source<->item mappings are applied.  For stretch-marker takes
-- return nil, rather than silently creating/using inaccurately placed markers.
function M.ItemOffsetToSource(take, item, item_offset)
    if has_stretch_markers(take) then return nil end
    local rate = info(take, "D_PLAYRATE")
    local start = info(take, "D_STARTOFFS")
    if not rate or rate <= 0 or not start then return nil end
    local srcpos = start + item_offset * rate
    if r.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1 then
        local len = source_duration(take)
        if len then srcpos = srcpos % len end
    end
    return srcpos
end

-- Leftmost VISIBLE marker, not the marker with the lowest raw source position.
-- Ignore markers outside trimmed items. Looping can repeat source markers.
function M.GetFirstVisibleMarkerOffset(item)
    local take = r.GetActiveTake(item)
    if not take or has_stretch_markers(take) then return 0 end
    local rate = info(take, "D_PLAYRATE")
    local start = info(take, "D_STARTOFFS")
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    if not rate or rate <= 0 or not start or not length or length <= 0 then return 0 end
    local loops = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1
    local src_len = loops and source_duration(take) or nil
    local best = nil
    local count = r.GetNumTakeMarkers and r.GetNumTakeMarkers(take) or 0
    for i = 0, count - 1 do
        local srcpos = r.GetTakeMarker(take, i)
        if srcpos and srcpos >= 0 then
            if src_len then
                -- earliest occurrence at or after the current take start offset
                srcpos = srcpos + math.ceil((start - srcpos) / src_len) * src_len
            end
            local relative = (srcpos - start) / rate
            if relative >= -0.00001 and relative <= length + 0.00001 then
                relative = math.max(0, math.min(length, relative))
                if not best or relative < best then best = relative end
            end
        end
    end
    return best or 0
end

-- Search the *actual audio samples* only inside the kept intervals.
-- Unlike the old 10 ms envelope, this does not re-detect variations or
-- interpolate a marker into a removed/silent interval.
-- Each returned offset is ITEM-RELATIVE, NOT a project or source timestamp.
function M.FindPeaksInKeptRegions(item, take, regions, cfg)
    cfg = cfg or M.CONFIG
    if type(regions) ~= "table" then return nil, "no keep regions" end
    local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    if not item_pos or not item_len or item_len <= 0
        or item_len > cfg.max_take_seconds then
        return nil, "invalid/long item"
    end
    local source = r.GetMediaItemTake_Source(take)
    if not source then return nil, "no media source" end
    local source_channels = r.GetMediaSourceNumChannels(source)
    if not source_channels or source_channels < 1 then
        return nil, "no audio channels"
    end
    local channels = math.min(source_channels, cfg.max_channels)
    local native_sr = r.GetMediaSourceSampleRate and r.GetMediaSourceSampleRate(source)
    local sample_rate = (native_sr and native_sr > 0) and math.floor(native_sr + 0.5) or 48000
    local accessor = r.CreateTakeAudioAccessor and r.CreateTakeAudioAccessor(take)
    if not accessor then return nil, "could not open audio accessor" end

    local ok, peaks_or_error = pcall(function()
        local peaks = {}
        local block_size = math.max(256, cfg.samples_per_block or 4096)
        local buffer = r.new_array(block_size * channels)
        -- Always use the SAME audio-accessor time origin as the untouched
        -- Split Dyn getSilenceTime() function. Using item D_POSITION here
        -- gave incorrect peaks if the accessor time base differed.
        local access_start = r.GetAudioAccessorStartTime(accessor)
        local access_end = r.GetAudioAccessorEndTime(accessor)
        if type(access_start) ~= "number" or type(access_end) ~= "number"
            or access_end <= access_start then
            error("invalid audio accessor time bounds")
        end
        local play_start = access_start
        local play_end = math.min(access_start + item_len, access_end)
        for _, region in ipairs(regions) do
            local a = math.max(play_start, access_start + region.start)
            local b = math.min(play_end, access_start + region["end"])
            if b > a then
                local frames_total = math.max(1,
                    math.floor((b - a) * sample_rate + 1e-6))
                local strongest, peak_offset = -1, nil
                local received_audio = false
                for base = 0, frames_total - 1, block_size do
                    local frames = math.min(block_size, frames_total - base)
                    buffer.clear()
                    local got = r.GetAudioAccessorSamples(accessor, sample_rate,
                        channels, a + base / sample_rate, frames, buffer)
                    if got == -1 then error("audio accessor read failed") end
                    if got == 1 then
                        received_audio = true
                        for frame = 0, frames - 1 do
                        for ch = 1, channels do
                            local amplitude = math.abs(buffer[frame * channels + ch])
                            if amplitude > strongest then
                                strongest = amplitude
                                peak_offset = (a - access_start) + (base + frame) / sample_rate
                            end
                        end
                    end
                    end -- got == 1
                end
                -- Exactly ONE peak for each retained, readable interval.
                -- The old amplitude gate could silently omit a variation,
                -- even when Split Dyn's own region detector retained it.
                if not received_audio or peak_offset == nil then
                    error("retained region contains no readable audio: "
                        .. string.format("%.4f-%.4f", region.start, region["end"]))
                end
                peaks[#peaks + 1] = {
                    offset = math.max(region.start,
                        math.min(region["end"], peak_offset)),
                    amplitude = strongest,
                }
            end
        end
        return peaks
    end)
    r.DestroyAudioAccessor(accessor)
    if not ok then return nil, tostring(peaks_or_error) end
    return peaks_or_error
end

-- The untouched Split Dyn detector may report a silence ending just short
-- of the item boundary due to sample/downsampling granularity. Complementing
-- that interval creates a tiny, effectively empty final "kept" region; the
-- peak reader then picks its first (often zero-valued) sample, producing a
-- spurious marker at the extreme right edge.
--
-- Do NOT remove the final marker unconditionally: a real last variation still
-- needs its peak. Only suppress the LAST candidate if (a) it is within the
-- boundary guard, (b) its region is just a tiny boundary remainder, or
-- (c) its peak never exceeds Split Dyn's threshold after earlier regions.
-- All other regions, and Split Dyn/Guide themselves, stay untouched.
function M.FilterTrailingBoundaryArtifact(peaks, regions, item_length, cfg)
    cfg = cfg or M.CONFIG
    local guard = math.max(0, tonumber(cfg.end_marker_guard_seconds) or 0.012)
    local threshold = math.max(0, tonumber(cfg.absolute_threshold) or 0)
    local result, skipped = {}, 0
    for i, peak in ipairs(peaks) do
        local region = regions[i]
        local is_final = i == #peaks and i == #regions
        local near_item_end = peak.offset >= item_length - guard
        local leftover_sliver = region and region.start >= item_length - guard
        local silent_trailing_region = #regions > 1 and region
            and region.start > 0 and (peak.amplitude or 0) <= threshold
        if is_final and (near_item_end or leftover_sliver or silent_trailing_region) then
            skipped = skipped + 1
        else
            result[#result + 1] = peak
        end
    end
    return result, skipped
end

-- Number-only names such as "01" may also be user-created. Track our own
-- generated markers in persistent per-take extension data, matching BOTH
-- the saved name and source position before deletion. This survives reloads,
-- without relying on or deleting arbitrary numeric user markers.
local function owned_markers(take)
    if not r.GetSetMediaItemTakeInfo_String then return {} end
    local ok, data = r.GetSetMediaItemTakeInfo_String(take, OWNED_KEY, "", false)
    if not ok or not data or data == "" then return {} end
    local saved = {}
    for name, pos in data:gmatch("([^|:]+):([%d%.eE%+%-]+)|") do
        local p = tonumber(pos)
        if p then saved[#saved + 1] = {name = name, pos = p} end
    end
    return saved
end

local function marker_is_ours(name, pos, owned)
    for _, entry in ipairs(owned) do
        if entry.name == name and math.abs(pos - entry.pos) < 0.00001 then
            return true
        end
    end
    return false
end

local function old_generated_marker(name)
    return name and name:sub(1, #LEGACY_PREFIX) == LEGACY_PREFIX
        and name:sub(#LEGACY_PREFIX + 1):match("^%d+$") ~= nil
end

local function replace_generated_markers(take, positions, cfg)
    local owned = owned_markers(take)
    -- Replace old "JKK Peak NN" markers from the previous version and new
    -- numeric markers registered by this module. Preserve everything else.
    for i = r.GetNumTakeMarkers(take) - 1, 0, -1 do
        local pos, name = r.GetTakeMarker(take, i)
        if old_generated_marker(name) or marker_is_ours(name, pos, owned) then
            r.DeleteTakeMarker(take, i)
        end
    end
    local new_owned = {}
    for i, srcpos in ipairs(positions) do
        local name = string.format("%02d", i)
        local idx = r.SetTakeMarker(take, -1, name, srcpos)
        -- REAPER returns -1 on failure. Only record successfully created
        -- markers, so an unrelated manual marker can never be claimed.
        if idx and idx >= 0 then
            new_owned[#new_owned + 1] = name .. ":" .. string.format("%.15g", srcpos) .. "|"
        end
    end
    if r.GetSetMediaItemTakeInfo_String then
        r.GetSetMediaItemTakeInfo_String(take, OWNED_KEY,
            table.concat(new_owned), true)
    end
end

-- `get_silences(item, take)` MUST use the same Split Dyn/Guide detector.
-- It supplies ITEM-RELATIVE intervals that Split Dyn would delete. If it
-- cannot analyse a take, we SKIP rather than invent markers from another
-- detector. Keeps all take/selected-item iteration from the previous version.
function M.AddMarkersToSelectedItems(cfg, get_silences)
    cfg = cfg or M.CONFIG
    local summary = {items = 0, takes = 0, variations = 0,
        skipped = 0, unchanged = 0, errors = {}, regions = 0}
    if type(get_silences) ~= "function" then
        error("Peak Marker needs the shared Split Dyn silence detector")
    end
    local count = r.CountSelectedMediaItems(0)
    if count == 0 then return summary end
    local plans = {}
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        summary.items = summary.items + 1
        for j = 0, r.CountTakes(item) - 1 do
            local take = r.GetTake(item, j)
            if not take or r.TakeIsMIDI(take) or has_stretch_markers(take) then
                summary.skipped = summary.skipped + 1
            else
                local ok, silences = pcall(get_silences, item, take)
                if not ok or type(silences) ~= "table" then
                    summary.skipped = summary.skipped + 1
                    summary.errors[#summary.errors + 1] = "Split Dyn analysis unavailable"
                else
                    local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local item_position = r.GetMediaItemInfo_Value(item, "D_POSITION")
                    local origin = nil
                    if r.CreateTakeAudioAccessor and r.GetAudioAccessorStartTime then
                        local temp_accessor = r.CreateTakeAudioAccessor(take)
                        if temp_accessor then
                            origin = r.GetAudioAccessorStartTime(temp_accessor)
                            r.DestroyAudioAccessor(temp_accessor)
                        end
                    end
                    local normalized, coord_error = M.NormalizeSilenceTimes(
                        item_position, item_length, silences, origin)
                    -- An empty silence list is valid: a single retained region.
                    if not normalized then
                        summary.skipped = summary.skipped + 1
                        summary.errors[#summary.errors + 1] = coord_error
                    else
                    local kept = M.BuildKeptRegions(item_length, normalized)
                    local peaks, read_error = M.FindPeaksInKeptRegions(item, take, kept, cfg)
                    if not peaks or #peaks ~= #kept then
                        summary.skipped = summary.skipped + 1
                        summary.errors[#summary.errors + 1] = read_error or "region/peak mismatch"
                    else
                        -- Ignore only the false LAST boundary marker. Keep
                        -- genuine final variations elsewhere in the item.
                        local accepted, trailing_removed =
                            M.FilterTrailingBoundaryArtifact(peaks, kept, item_length, cfg)
                        summary.trailing_removed = (summary.trailing_removed or 0)
                            + trailing_removed
                        summary.regions = summary.regions + #accepted
                        local positions, seen = {}, {}
                        for _, peak in ipairs(accepted) do
                            local srcpos = M.ItemOffsetToSource(take, item, peak.offset)
                            if srcpos then
                                -- Preserve chronology of surviving regions.
                                local slot = math.floor(srcpos * 100000 + 0.5)
                                if not seen[slot] then
                                    positions[#positions + 1] = srcpos
                                    seen[slot] = true
                                end
                            end
                        end
                        -- Do not partially replace markers if a source offset
                        -- could not be mapped or two loop iterations would
                        -- collapse onto the same source location.
                        if #positions == #accepted then
                            plans[#plans + 1] = {take = take, positions = positions}
                            summary.takes = summary.takes + 1
                            summary.variations = summary.variations + #positions
                        else
                            summary.skipped = summary.skipped + 1
                            summary.errors[#summary.errors + 1] =
                                "source mapping collision / unsupported loop"
                        end
                    end
                    end -- normalized
                end
            end
        end
    end
    if #plans > 0 then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        local okay, err = pcall(function()
            for _, plan in ipairs(plans) do
                replace_generated_markers(plan.take, plan.positions, cfg)
            end
        end)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
        r.Undo_EndBlock(Undo.Label("take_marker.create_peak_markers"), -1)
        if not okay then error(err) end
    end
    return summary
end

return M
