--========================================================
-- @title JKK_FolderItems_Core
-- @author Junki Kim
-- @noindex
-- JKK Folder Items 공통 모듈 (모듈 테이블 반환, 전역 없음)
--  - 순수 로직: 시간 구간 병합 / 기존 아이템 매칭 / 활성 그룹 계산 / 충돌 검출
--  - REAPER 연동: 프로젝트 모델 읽기, Create / Toggle 계획 및 적용
--  - Mouse Modifier: Toggle 명령 ID 확인, 백업/복원, 일반 대상 fallback
--========================================================

local M = {}

local R = reaper

M.TITLE = "JKK Folder Items"
M.EPS = 1e-9
M.SCHEMA = "1"
M.MAX_GROUP_ID = 2147483647
M.UNDO_FLAGS = -1

M.KEY = {
    MARK     = "P_EXT:JKK_FOLDER_ITEM",
    SCHEMA   = "P_EXT:JKK_FOLDER_ITEM_SCHEMA",
    OWNER    = "P_EXT:JKK_FI_GROUP_OWNER",
    ASSIGNED = "P_EXT:JKK_FI_ASSIGNED_GROUP",
    ORIGINAL = "P_EXT:JKK_FI_ORIGINAL_GROUP",
    SELF     = "P_EXT:JKK_FI_SELF",
}

local EPS = M.EPS
local KEY = M.KEY

-- 모듈 경로 (Modules/ 의 상위 = JKK_ReaTools 루트)
local module_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+[\\/])") or ""
M.ROOT_DIR = module_dir:gsub("[^\\/]+[\\/]$", "")
M.TOGGLE_FILE = "JKK_FolderItems_Toggle.lua"

local function undo_label(key)
    local ok, Undo = pcall(dofile, module_dir .. "JKK_UndoLabels.lua")
    if ok and type(Undo) == "table" then return Undo.Label(key) end
    error("JKK_UndoLabels.lua 를 불러올 수 없습니다: " .. tostring(Undo))
end

----------------------------------------------------------
-- 순수 로직 (REAPER 없이 테스트 가능)
----------------------------------------------------------

function M.overlaps(a_s, a_e, b_s, b_e, eps)
    eps = eps or EPS
    return a_s < b_e - eps and b_s < a_e - eps
end

-- intervals: { {s=, e=}, ... } → 겹침으로 연결된 Time Island 목록 (시작순, 상호 비겹침)
-- 끝과 시작이 정확히 맞닿는 구간은 별도 영역으로 둔다.
function M.merge_intervals(intervals, eps)
    eps = eps or EPS
    local v = {}
    for _, it in ipairs(intervals or {}) do
        if it.s and it.e and (it.e - it.s) > eps then v[#v + 1] = { s = it.s, e = it.e } end
    end
    table.sort(v, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        return a.e < b.e
    end)
    local out, cur = {}, nil
    for _, it in ipairs(v) do
        if not cur then
            cur = { s = it.s, e = it.e }
        elseif it.s < cur.e - eps then
            if it.e > cur.e then cur.e = it.e end
        else
            out[#out + 1] = cur
            cur = { s = it.s, e = it.e }
        end
    end
    if cur then out[#out + 1] = cur end
    return out
end

local function same_range(a_s, a_e, b_s, b_e, eps)
    eps = eps or EPS
    return math.abs(a_s - b_s) <= eps and math.abs(a_e - b_e) <= eps
end
M.same_range = same_range

-- existing: { {key=, s=, e=}, ... }  islands: { {s=, e=}, ... }
-- 반환: { pairs = { {ex=i, isl=j}, ... }, unmatched_existing = {i...}, unmatched_islands = {j...} }
-- 1) 정확 일치 우선 2) 양수 겹침 후보를 (겹침↓, IoU↓, 시작거리↑, 기존시작↑, 새시작↑, key↑) 순으로 탐욕 매칭
-- 겹치지 않는 영역은 근접해도 매칭하지 않는다.
function M.match_existing(existing, islands, eps)
    eps = eps or EPS
    local ex_used, isl_used, result = {}, {}, {}

    for j, isl in ipairs(islands) do
        for i, ex in ipairs(existing) do
            if not ex_used[i] and same_range(ex.s, ex.e, isl.s, isl.e, eps) then
                ex_used[i] = true; isl_used[j] = true
                result[#result + 1] = { ex = i, isl = j }
                break
            end
        end
    end

    local cands = {}
    for i, ex in ipairs(existing) do
        if not ex_used[i] then
            for j, isl in ipairs(islands) do
                if not isl_used[j] then
                    local ov = math.min(ex.e, isl.e) - math.max(ex.s, isl.s)
                    if ov > eps then
                        local union = math.max(ex.e, isl.e) - math.min(ex.s, isl.s)
                        cands[#cands + 1] = {
                            i = i, j = j, ov = ov,
                            iou = union > 0 and ov / union or 0,
                            dist = math.abs(ex.s - isl.s),
                            ex_s = ex.s, isl_s = isl.s, key = tostring(ex.key or i),
                        }
                    end
                end
            end
        end
    end
    table.sort(cands, function(a, b)
        if math.abs(a.ov - b.ov) > eps then return a.ov > b.ov end
        if math.abs(a.iou - b.iou) > 1e-12 then return a.iou > b.iou end
        if math.abs(a.dist - b.dist) > eps then return a.dist < b.dist end
        if a.ex_s ~= b.ex_s then return a.ex_s < b.ex_s end
        if a.isl_s ~= b.isl_s then return a.isl_s < b.isl_s end
        return a.key < b.key
    end)
    for _, c in ipairs(cands) do
        if not ex_used[c.i] and not isl_used[c.j] then
            ex_used[c.i] = true; isl_used[c.j] = true
            result[#result + 1] = { ex = c.i, isl = c.j }
        end
    end

    local ue, ui = {}, {}
    for i = 1, #existing do if not ex_used[i] then ue[#ue + 1] = i end end
    for j = 1, #islands do if not isl_used[j] then ui[#ui + 1] = j end end
    table.sort(result, function(a, b) return a.isl < b.isl end)
    return { pairs = result, unmatched_existing = ue, unmatched_islands = ui }
end

----------------------------------------------------------
-- 모델: 트랙 트리 + 아이템 (순수 테이블; REAPER 또는 테스트에서 구성)
--  model.tracks[i] = { idx, ptr, parent, children, level, is_folder, compact, name, selected, items = {key...} }
--  model.items[key] = { key, ptr, guid, track, s, e, group, locked, marker, is_fi, name,
--                       managed, owner_key, assigned, original, base_group, clear_meta, external, deleted, virtual }
--  model.order = { key... } (프로젝트 전체 아이템)
----------------------------------------------------------

local function is_closed(compact) return (compact or 0) >= 1 end
M.is_closed = is_closed

local function descendant_tracks(model, idx, out)
    out = out or {}
    for _, c in ipairs(model.tracks[idx].children) do
        out[#out + 1] = c
        descendant_tracks(model, c, out)
    end
    return out
end
M.descendant_tracks = descendant_tracks

local function live_items_on(model, tidx)
    local list = {}
    for _, key in ipairs(model.tracks[tidx].items) do
        local it = model.items[key]
        if it and not it.deleted then list[#list + 1] = it end
    end
    return list
end

local function descendant_items(model, idx)
    local list = {}
    for _, ti in ipairs(descendant_tracks(model, idx)) do
        for _, it in ipairs(live_items_on(model, ti)) do
            if (it.e - it.s) > EPS then list[#list + 1] = it end
        end
    end
    return list
end
M.descendant_items = descendant_items

local function folder_items_of(model, idx)
    local list = {}
    if not model.tracks[idx].is_folder then return list end
    for _, it in ipairs(live_items_on(model, idx)) do
        if it.is_fi then list[#list + 1] = it end
    end
    table.sort(list, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        if a.e ~= b.e then return a.e < b.e end
        return a.key < b.key
    end)
    return list
end
M.folder_items_of = folder_items_of

-- 가장 바깥쪽 접힌 조상 (include_self 이면 자기 자신 포함). closed_fn(idx) → bool
function M.outermost_closed(model, idx, closed_fn, include_self)
    local found = nil
    if include_self and model.tracks[idx].is_folder and closed_fn(idx) then found = idx end
    local p = model.tracks[idx].parent
    while p do
        if closed_fn(p) then found = p end
        p = model.tracks[p].parent
    end
    return found
end

-- 활성 그룹 계산 (재귀). 반환: groups, conflicts
--  group = { owner = FI key, folder = track idx, members = {key...}, set = {key=true} }
--  conflict = { kind = "fi_overlap"|"multi"|"partial", folder, items = {key...}, ... }
-- 규칙:
--  - 열린 폴더: 자식 폴더들의 그룹을 합친다 (펼쳐진 경로는 계속 탐색).
--  - 접힌 폴더: 자신의 각 Folder Item = FI + 시간상 겹치는 모든 하위 아이템.
--    하위 그룹이 상위 그룹과 겹치지 않으면 보존, 하나의 상위 그룹에 완전히 포함되면 흡수,
--    부분적으로 걸치면 충돌. 하위 충돌은 관련 아이템이 모두 상위 그룹에 흡수될 때만 무시.
--  - 멤버가 FI 자신뿐인 그룹은 만들지 않는다.
local function groups_of(model, idx, closed_fn)
    local t = model.tracks[idx]
    local child_groups, child_conf = {}, {}
    for _, c in ipairs(t.children) do
        if model.tracks[c].is_folder then
            local g, cf = groups_of(model, c, closed_fn)
            for _, x in ipairs(g) do child_groups[#child_groups + 1] = x end
            for _, x in ipairs(cf) do child_conf[#child_conf + 1] = x end
        end
    end
    if not (t.is_folder and closed_fn(idx)) then return child_groups, child_conf end

    local fis = folder_items_of(model, idx)
    if #fis == 0 then return child_groups, child_conf end

    local conf = {}
    for a = 1, #fis do
        for b = a + 1, #fis do
            if M.overlaps(fis[a].s, fis[a].e, fis[b].s, fis[b].e) then
                conf[#conf + 1] = { kind = "fi_overlap", folder = idx, items = { fis[a].key, fis[b].key } }
            end
        end
    end

    local desc = descendant_items(model, idx)
    local own, owner_of, multi_seen = {}, {}, {}
    for gi, f in ipairs(fis) do
        local g = { owner = f.key, folder = idx, members = { f.key }, set = { [f.key] = true } }
        for _, d in ipairs(desc) do
            if M.overlaps(d.s, d.e, f.s, f.e) then
                g.members[#g.members + 1] = d.key
                g.set[d.key] = true
                local prev = owner_of[d.key]
                if prev and prev ~= gi then
                    if not multi_seen[d.key] then
                        multi_seen[d.key] = true
                        conf[#conf + 1] = { kind = "multi", folder = idx, items = { d.key },
                                            fis = { fis[prev].key, f.key } }
                    end
                elseif not prev then
                    owner_of[d.key] = gi
                end
            end
        end
        own[gi] = g
    end

    local result = {}
    for _, g in ipairs(child_groups) do
        local inside, owners, n_owner = 0, {}, 0
        for _, k in ipairs(g.members) do
            local o = owner_of[k]
            if o then
                inside = inside + 1
                if not owners[o] then owners[o] = true; n_owner = n_owner + 1 end
            end
        end
        if inside == 0 then
            result[#result + 1] = g
        elseif not (inside == #g.members and n_owner == 1) then
            conf[#conf + 1] = { kind = "partial", folder = idx, child_folder = g.folder,
                                items = { g.owner }, child_owner = g.owner }
        end
    end
    for _, c in ipairs(child_conf) do
        local all_in = true
        for _, k in ipairs(c.items) do
            if not owner_of[k] then all_in = false; break end
        end
        if not all_in then conf[#conf + 1] = c end
    end
    for _, g in ipairs(own) do
        if #g.members >= 2 then result[#result + 1] = g end
    end
    return result, conf
end
M.groups_of = groups_of

-- 그룹 변경 계획: roots 서브트리에 대한 목표 그룹과 diff 대상 아이템
-- extra_owner_keys: 이 FI(삭제 예정 등)를 소유자로 기록한 아이템도 diff 에 포함
function M.plan_groups(model, roots, closed_fn, extra_owner_keys)
    local plan = { groups = {}, conflicts = {}, diff = {}, in_diff = {}, desired = {} }
    local seen_root = {}
    local scope_fi = {}
    local function add_diff(key)
        local it = model.items[key]
        if it and not it.deleted and not plan.in_diff[key] then
            plan.in_diff[key] = true
            plan.diff[#plan.diff + 1] = key
        end
    end
    for _, root in ipairs(roots) do
        if not seen_root[root] then
            seen_root[root] = true
            local g, c = groups_of(model, root, closed_fn)
            for _, x in ipairs(g) do plan.groups[#plan.groups + 1] = x end
            for _, x in ipairs(c) do plan.conflicts[#plan.conflicts + 1] = x end
            local tracks = descendant_tracks(model, root)
            table.insert(tracks, 1, root)
            for _, ti in ipairs(tracks) do
                for _, it in ipairs(live_items_on(model, ti)) do
                    add_diff(it.key)
                    if it.is_fi then scope_fi[it.key] = true end
                end
            end
        end
    end
    for _, k in ipairs(extra_owner_keys or {}) do scope_fi[k] = true end
    -- 범위 밖으로 이동했지만 범위 안 FI 소유로 기록된 아이템
    for _, key in ipairs(model.order) do
        local it = model.items[key]
        if it and not it.deleted and it.managed and it.owner_key ~= "" and scope_fi[it.owner_key] then
            add_diff(key)
        end
    end
    -- 동일 아이템의 중복 배정 검증 (groups_of 가 보장하지만 방어적으로 재확인)
    for _, g in ipairs(plan.groups) do
        for _, k in ipairs(g.members) do
            if plan.desired[k] and plan.desired[k] ~= g then
                plan.conflicts[#plan.conflicts + 1] = { kind = "multi", folder = g.folder, items = { k },
                                                        fis = { plan.desired[k].owner, g.owner } }
            else
                plan.desired[k] = g
                add_diff(k)
            end
        end
    end
    -- 외부 편집 감지: 관리 아이템인데 현재 Group ID 가 마지막 기록과 다름
    plan.external = {}
    for _, key in ipairs(plan.diff) do
        local it = model.items[key]
        if it.managed and it.group ~= it.assigned then plan.external[#plan.external + 1] = key end
    end
    return plan
end

-- 외부 편집된 아이템의 현재 그룹을 새 기준(원래 User Group)으로 채택
function M.adopt_external(model, keys)
    for _, key in ipairs(keys) do
        local it = model.items[key]
        it.managed = false
        it.base_group = it.group
        it.clear_meta = true
    end
end

-- Group ID 할당 (재사용 가능한 기존 관리 ID 우선, 아니면 max+1)
function M.assign_group_ids(model, plan)
    local max_id, holders, reserved_orig = 0, {}, {}
    for _, key in ipairs(model.order) do
        local it = model.items[key]
        if it and not it.deleted then
            local g = it.group or 0
            if g > 0 then
                holders[g] = holders[g] or {}
                holders[g][#holders[g] + 1] = key
                if g > max_id then max_id = g end
            end
            if it.managed and (it.original or 0) > 0 then
                reserved_orig[it.original] = true
                if it.original > max_id then max_id = it.original end
            end
            if (it.base_group or 0) > max_id then max_id = it.base_group end
        end
    end
    table.sort(plan.groups, function(a, b)
        if a.folder ~= b.folder then return a.folder < b.folder end
        local oa, ob = model.items[a.owner], model.items[b.owner]
        if oa.s ~= ob.s then return oa.s < ob.s end
        return a.owner < b.owner
    end)
    local taken = {}
    for _, g in ipairs(plan.groups) do
        g.gid = nil
        local owner = model.items[g.owner]
        local cand = nil
        if owner.managed and owner.owner_key == owner.key and owner.group == owner.assigned and owner.group > 0 then
            cand = owner.group
        end
        if cand and not taken[cand] and not reserved_orig[cand] then
            local ok = true
            for _, hk in ipairs(holders[cand] or {}) do
                if not g.set[hk] then
                    local h = model.items[hk]
                    local d = plan.desired[hk]
                    if not (plan.in_diff[hk] and h.managed and h.group == h.assigned and d ~= g) then
                        ok = false; break
                    end
                end
            end
            if ok then g.gid = cand end
        end
        if not g.gid then
            max_id = max_id + 1
            if max_id > M.MAX_GROUP_ID then return false, "사용 가능한 Group ID 가 없습니다." end
            g.gid = max_id
        end
        taken[g.gid] = true
    end
    return true
end

-- 실제 쓰기 목록 계산 (변경이 필요한 아이템만)
function M.compute_changes(model, plan)
    local changes = {}
    for _, key in ipairs(plan.diff) do
        local it = model.items[key]
        local g = plan.desired[key]
        if g then
            if it.managed then
                if it.group ~= g.gid or it.assigned ~= g.gid or it.owner_key ~= g.owner then
                    changes[#changes + 1] = { kind = "update", key = key, gid = g.gid, owner = g.owner }
                end
            else
                changes[#changes + 1] = { kind = "adopt", key = key, gid = g.gid, owner = g.owner,
                                          original = it.base_group or it.group or 0 }
            end
        elseif it.managed or it.clear_meta then
            changes[#changes + 1] = { kind = "release", key = key,
                                      restore = (it.managed and it.original) or it.base_group or it.group or 0 }
        end
    end
    return changes
end

----------------------------------------------------------
-- 충돌 / 이름 표시
----------------------------------------------------------

local function track_name(model, idx)
    local t = model.tracks[idx]
    if not t then return "?" end
    if t.name and t.name ~= "" then return t.name end
    return "Track " .. tostring(idx)
end
M.track_name = track_name

local function fmt_time(sec)
    if R and R.format_timestr_pos then
        local ok, s = pcall(R.format_timestr_pos, sec, "", -1)
        if ok and s and s ~= "" then return s end
    end
    return string.format("%.3fs", sec)
end
M.fmt_time = fmt_time

function M.item_label(model, key)
    local it = model.items[key]
    if not it then return "?" end
    local name = it.name
    if (not name or name == "") and it.ptr and R and R.GetActiveTake then
        local ok, take = pcall(R.GetActiveTake, it.ptr)
        if ok and take then
            local ok2, tn = pcall(R.GetTakeName, take)
            if ok2 then name = tn end
        end
    end
    if not name or name == "" then name = it.is_fi and track_name(model, it.track) or "Empty item" end
    return string.format("'%s' [%s ~ %s] (%s)", name, fmt_time(it.s), fmt_time(it.e), track_name(model, it.track))
end

function M.describe_conflicts(model, conflicts)
    local lines = {}
    local max_lines = 8
    for i, c in ipairs(conflicts) do
        if i > max_lines then
            lines[#lines + 1] = string.format("... 외 %d건", #conflicts - max_lines)
            break
        end
        local folder = track_name(model, c.folder)
        if c.kind == "fi_overlap" then
            lines[#lines + 1] = string.format("- 폴더 '%s': 폴더 아이템 %s 와 %s 의 범위가 겹칩니다.",
                folder, M.item_label(model, c.items[1]), M.item_label(model, c.items[2]))
        elseif c.kind == "multi" then
            lines[#lines + 1] = string.format("- 폴더 '%s': 아이템 %s 가 두 폴더 아이템과 동시에 겹칩니다.",
                folder, M.item_label(model, c.items[1]))
        elseif c.kind == "partial" then
            lines[#lines + 1] = string.format("- 폴더 '%s': 하위 폴더 '%s' 의 그룹(%s)이 상위 폴더 아이템 경계에 일부만 걸쳐 있습니다.",
                folder, track_name(model, c.child_folder), M.item_label(model, c.child_owner))
        else
            lines[#lines + 1] = "- 알 수 없는 충돌"
        end
    end
    return table.concat(lines, "\n")
end

----------------------------------------------------------
-- REAPER 읽기/쓰기 헬퍼
----------------------------------------------------------

local function get_ext(item, key)
    local ok, v = R.GetSetMediaItemInfo_String(item, key, "", false)
    if ok and v then return v end
    return ""
end
local function set_ext(item, key, value)
    R.GetSetMediaItemInfo_String(item, key, value, true)
end
M.get_ext = get_ext

local function to_int(x)
    x = tonumber(x)
    if not x then return nil end
    return math.floor(x + 0.5)
end

function M.is_recording()
    return R.GetPlayState and (to_int(R.GetPlayState()) & 4) ~= 0
end

function M.track_index(track)
    return to_int(R.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
end

-- 현재 활성 프로젝트의 트랙 트리와 모든 아이템을 읽는다 (Lua 캐시를 신뢰하지 않고 매 실행마다 재구성)
function M.read_model()
    local model = { tracks = {}, items = {}, order = {} }
    local n = R.CountTracks(0)
    local stack = {}
    for i = 1, n do
        local tr = R.GetTrack(0, i - 1)
        local depth = to_int(R.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")) or 0
        local _, name = R.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        local t = {
            idx = i, ptr = tr, parent = stack[#stack], children = {}, level = #stack,
            is_folder = depth > 0,
            compact = to_int(R.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT")) or 0,
            selected = (R.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) ~= 0,
            name = name or "", items = {},
        }
        model.tracks[i] = t
        if t.parent then
            local pc = model.tracks[t.parent].children
            pc[#pc + 1] = i
        end
        if depth > 0 then
            stack[#stack + 1] = i
        elseif depth < 0 then
            for _ = 1, -depth do
                if #stack > 0 then stack[#stack] = nil end
            end
        end
    end

    for i = 1, n do
        local t = model.tracks[i]
        local cnt = R.CountTrackMediaItems(t.ptr)
        for j = 0, cnt - 1 do
            local item = R.GetTrackMediaItem(t.ptr, j)
            local _, guid = R.GetSetMediaItemInfo_String(item, "GUID", "", false)
            local key = guid ~= "" and guid or ("ptr:" .. tostring(item))
            if model.items[key] then key = key .. "#" .. tostring(#model.order + 1) end
            local s = R.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = R.GetMediaItemInfo_Value(item, "D_LENGTH")
            local marker = get_ext(item, KEY.MARK) == "1"
            local it = {
                key = key, ptr = item, guid = guid, track = i, s = s, e = s + len,
                group = to_int(R.GetMediaItemInfo_Value(item, "I_GROUPID")) or 0,
                locked = ((to_int(R.GetMediaItemInfo_Value(item, "C_LOCK")) or 0) & 1) ~= 0,
                marker = marker, is_fi = marker and t.is_folder,
            }
            if it.is_fi then
                -- 이름 = 활성 take 이름 (렌더 $item 와일드카드와 동일). take 가 없는 구버전은 notes 첫 줄
                it.ntakes = R.CountTakes(item)
                local take = it.ntakes > 0 and R.GetActiveTake(item) or nil
                if take then
                    local _, tn = R.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                    it.name = tn or ""
                else
                    local _, notes = R.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
                    it.notes = notes or ""
                    it.name = it.notes:match("^[^\r\n]*") or ""
                end
            end
            local assigned = tonumber(get_ext(item, KEY.ASSIGNED))
            if assigned then
                it.managed = true
                it.assigned = to_int(assigned)
                it.owner_key = get_ext(item, KEY.OWNER)
                it.original = to_int(get_ext(item, KEY.ORIGINAL)) or 0
                it.self = get_ext(item, KEY.SELF)
                if it.self ~= "" and it.self ~= guid then
                    -- 복제/split/붙여넣기로 메타데이터만 복사된 아이템: 원본 그룹 복원 금지
                    it.copy = true
                    it.managed = false
                    it.clear_meta = true
                    it.base_group = (it.group == it.assigned) and 0 or it.group
                end
            else
                it.managed = false
                it.owner_key = ""
            end
            if it.base_group == nil then it.base_group = it.managed and it.original or it.group end
            model.items[key] = it
            model.order[#model.order + 1] = key
            t.items[#t.items + 1] = key
        end
    end
    return model
end

-- 그룹 변경 적용. 쓰기 횟수 반환
function M.apply_changes(model, changes)
    local writes = 0
    for _, ch in ipairs(changes) do
        local it = model.items[ch.key]
        local item = it and it.ptr
        if not (item and R.ValidatePtr2(0, item, "MediaItem*")) then
            error("아이템 포인터가 유효하지 않습니다: " .. tostring(ch.key))
        end
        if ch.kind == "adopt" or ch.kind == "update" then
            local owner_guid = model.items[ch.owner].guid
            if ch.kind == "adopt" then
                set_ext(item, KEY.ORIGINAL, tostring(ch.original))
                set_ext(item, KEY.SELF, it.guid)
            end
            set_ext(item, KEY.OWNER, owner_guid)
            set_ext(item, KEY.ASSIGNED, tostring(ch.gid))
            if it.group ~= ch.gid then
                R.SetMediaItemInfo_Value(item, "I_GROUPID", ch.gid)
                it.group = ch.gid
            end
            it.managed, it.assigned, it.owner_key = true, ch.gid, ch.owner
            if ch.kind == "adopt" then it.original = ch.original end
        elseif ch.kind == "release" then
            if it.group ~= ch.restore then
                R.SetMediaItemInfo_Value(item, "I_GROUPID", ch.restore)
                it.group = ch.restore
            end
            set_ext(item, KEY.OWNER, "")
            set_ext(item, KEY.ASSIGNED, "")
            set_ext(item, KEY.ORIGINAL, "")
            set_ext(item, KEY.SELF, "")
            it.managed, it.clear_meta = false, false
        end
        writes = writes + 1
    end
    return writes
end

local function msg(text, kind)
    return R.ShowMessageBox(text, M.TITLE, kind or 0)
end
M.msg = msg

-- 외부 편집 / 충돌 처리 공통: 성공 시 plan 반환, 중단 시 nil
local function finalize_plan(model, build_plan)
    local plan = build_plan()
    if #plan.conflicts > 0 then
        msg("폴더 아이템 범위가 현재 하위 아이템과 맞지 않아 아무것도 변경하지 않았습니다.\n\n"
            .. M.describe_conflicts(model, plan.conflicts)
            .. "\n\n해당 폴더를 선택해 Create 를 실행한 뒤 다시 시도하세요.\n"
            .. "Create 로도 해결되지 않으면 폴더 아이템 범위를 직접 조정해 주세요.")
        return nil
    end
    if #plan.external > 0 then
        local names = {}
        for i, k in ipairs(plan.external) do
            if i > 6 then names[#names + 1] = string.format("... 외 %d개", #plan.external - 6); break end
            names[#names + 1] = "- " .. M.item_label(model, k)
        end
        local r = msg("다음 아이템의 Group ID 가 JKK Folder Items 가 마지막으로 지정한 값과 다릅니다 (외부에서 그룹 편집됨).\n\n"
            .. table.concat(names, "\n")
            .. "\n\n현재 그룹을 새 기준(원래 User Group)으로 채택하고 계속할까요?\n"
            .. "[아니요] 를 누르면 아무것도 변경하지 않습니다.", 4)
        if r ~= 6 then return nil end
        M.adopt_external(model, plan.external)
        plan = build_plan()
        if #plan.conflicts > 0 or #plan.external > 0 then
            msg("그룹 계획을 다시 계산하는 중 충돌이 발견되어 아무것도 변경하지 않았습니다.\n\n"
                .. M.describe_conflicts(model, plan.conflicts))
            return nil
        end
    end
    local ok, err = M.assign_group_ids(model, plan)
    if not ok then msg(err); return nil end
    plan.changes = M.compute_changes(model, plan)
    return plan
end

-- 쓰기 단계 공통 래퍼: Undo 1개, PreventUIRefresh 균형, 오류 시 이번 실행 변경분만 되돌림
local function run_write(label_key, fn)
    local state = { writes = 0 }
    local label = undo_label(label_key) -- 정의되지 않은 키는 Undo 블록을 열기 전에 오류
    R.Undo_BeginBlock2(0)
    R.PreventUIRefresh(1)
    local ok, err = pcall(fn, state)
    R.PreventUIRefresh(-1)
    if ok then
        R.Undo_EndBlock2(0, label, M.UNDO_FLAGS)
        R.UpdateArrange()
        return true
    end
    R.Undo_EndBlock2(0, label, M.UNDO_FLAGS)
    if state.writes > 0 and R.Undo_DoUndo2 then R.Undo_DoUndo2(0) end
    R.UpdateArrange()
    msg("작업 중 오류가 발생했습니다." .. (state.writes > 0 and " 이번 실행의 변경분을 되돌렸습니다." or "")
        .. "\n\n" .. tostring(err))
    return false
end

local function warn_grouping_disabled()
    if not R.GetToggleCommandState then return end
    -- 1156 =Options: Toggle item grouping and track media/razor edit grouping
    if R.GetToggleCommandState(1156) == 0 then
        if R.GetExtState("JKK_FolderItems", "grouping_warned") ~= "1" then
            R.SetExtState("JKK_FolderItems", "grouping_warned", "1", false)
            msg("REAPER 의 Item Grouping 옵션이 꺼져 있어 그룹 이동이 동작하지 않을 수 있습니다.\n"
                .. "(Options > Item grouping / 툴바의 그룹 버튼)\n\n전역 옵션은 자동으로 바꾸지 않습니다.")
        end
    end
end

----------------------------------------------------------
-- Create
----------------------------------------------------------

-- 순수 계획: model 을 계획된 상태(가상 모델)로 변경하고 작업 목록 반환
function M.plan_create(model)
    local targets = {}
    for i, t in ipairs(model.tracks) do
        if t.selected and t.is_folder then targets[#targets + 1] = i end
    end
    table.sort(targets, function(a, b)
        local la, lb = model.tracks[a].level, model.tracks[b].level
        if la ~= lb then return la > lb end
        return a < b
    end)
    local plan = { targets = targets, updates = {}, creates = {}, deletes = {}, locked = {}, name_fix = {} }
    local new_n = 0
    for _, idx in ipairs(targets) do
        local inputs = {}
        for _, it in ipairs(descendant_items(model, idx)) do inputs[#inputs + 1] = { s = it.s, e = it.e } end
        local islands = M.merge_intervals(inputs)
        local existing = folder_items_of(model, idx)
        local res = M.match_existing(existing, islands)
        for _, p in ipairs(res.pairs) do
            local it, isl = existing[p.ex], islands[p.isl]
            if not same_range(it.s, it.e, isl.s, isl.e) then
                if it.locked then
                    plan.locked[#plan.locked + 1] = it.key
                else
                    plan.updates[#plan.updates + 1] = { key = it.key, old_s = it.s, old_e = it.e, s = isl.s, e = isl.e }
                    it.s, it.e = isl.s, isl.e
                end
            end
        end
        for _, i in ipairs(res.unmatched_existing) do
            local it = existing[i]
            if it.locked then
                plan.locked[#plan.locked + 1] = it.key
            else
                plan.deletes[#plan.deletes + 1] = it.key
                it.deleted = true
            end
        end
        -- take 없이 만들어진 기존 폴더 아이템: 이름을 붙일 수 있도록 빈 take 추가 (잠긴 아이템은 건드리지 않음)
        for _, it in ipairs(existing) do
            if not it.deleted and not it.locked and (it.ntakes or 1) == 0 then
                plan.name_fix[#plan.name_fix + 1] = it.key
            end
        end
        for _, j in ipairs(res.unmatched_islands) do
            new_n = new_n + 1
            local key = "new:" .. new_n
            local isl = islands[j]
            local it = {
                key = key, track = idx, s = isl.s, e = isl.e, group = 0, locked = false,
                marker = true, is_fi = true, managed = false, owner_key = "", base_group = 0,
                virtual = true, name = model.tracks[idx].name, guid = "",
            }
            model.items[key] = it
            model.order[#model.order + 1] = key
            local ti = model.tracks[idx].items
            ti[#ti + 1] = key
            plan.creates[#plan.creates + 1] = key
        end
    end
    -- 그룹 재구성 범위: 대상 폴더(또는 그것을 지배하는) 가장 바깥 접힌 폴더
    local closed_fn = function(i) return is_closed(model.tracks[i].compact) end
    local roots, seen = {}, {}
    for _, idx in ipairs(targets) do
        local r = M.outermost_closed(model, idx, closed_fn, true)
        if r and not seen[r] then seen[r] = true; roots[#roots + 1] = r end
    end
    plan.roots = roots
    plan.closed_fn = closed_fn
    return plan
end

-- 소스 없는 빈 take 를 추가해 이름을 붙인다 (소리 없음, MIDI/오디오 소스 생성 안 함).
-- 이름은 take 이름이므로 F2/Item properties 에서 바꿀 수 있고 렌더 $item 와일드카드에 쓰인다.
local function add_named_take(item, name)
    local take = R.AddTakeToMediaItem(item)
    if not take then error("폴더 아이템에 take 를 추가할 수 없습니다.") end
    R.GetSetMediaItemTakeInfo_String(take, "P_NAME", name or "", true)
    return take
end

function M.run_create()
    if M.is_recording() then
        msg("녹음 중에는 폴더 아이템을 생성/갱신할 수 없습니다.")
        return false
    end
    local model = M.read_model()
    local cp = M.plan_create(model)
    if #cp.targets == 0 then return false end

    if #cp.locked > 0 then
        local names = {}
        for i, k in ipairs(cp.locked) do
            if i > 6 then names[#names + 1] = string.format("... 외 %d개", #cp.locked - 6); break end
            names[#names + 1] = "- " .. M.item_label(model, k)
        end
        msg("잠긴 폴더 아이템의 이동/길이 변경/삭제가 필요해 작업을 중단했습니다 (아무것도 변경하지 않음).\n\n"
            .. table.concat(names, "\n") .. "\n\n잠금을 직접 해제한 뒤 다시 실행하세요.")
        return false
    end

    if #cp.deletes > 0 then
        local names = {}
        for i, k in ipairs(cp.deletes) do
            if i > 8 then names[#names + 1] = string.format("... 외 %d개", #cp.deletes - 8); break end
            names[#names + 1] = "- " .. M.item_label(model, k)
        end
        local r = msg(string.format("병합/이동/하위 아이템 없음으로 기존 폴더 아이템 %d개를 삭제해야 합니다.\n\n%s\n\n계속할까요? (취소하면 아무것도 변경하지 않습니다)",
            #cp.deletes, table.concat(names, "\n")), 1)
        if r ~= 1 then return false end
    end

    local gplan = finalize_plan(model, function()
        return M.plan_groups(model, cp.roots, cp.closed_fn, cp.deletes)
    end)
    if not gplan then return false end

    if #cp.updates == 0 and #cp.creates == 0 and #cp.deletes == 0 and #cp.name_fix == 0 and #gplan.changes == 0 then
        return true -- 변경 없음: Undo 를 만들지 않는다
    end

    local closed_with_groups = #gplan.groups > 0
    local ok = run_write("folder_items.create", function(state)
        for _, u in ipairs(cp.updates) do
            local it = model.items[u.key]
            if not R.ValidatePtr2(0, it.ptr, "MediaItem*") then error("폴더 아이템이 유효하지 않습니다.") end
            R.SetMediaItemInfo_Value(it.ptr, "D_POSITION", u.s)
            R.SetMediaItemInfo_Value(it.ptr, "D_LENGTH", u.e - u.s)
            state.writes = state.writes + 1
        end
        for _, k in ipairs(cp.deletes) do
            local it = model.items[k]
            if R.ValidatePtr2(0, it.ptr, "MediaItem*") then
                R.DeleteTrackMediaItem(model.tracks[it.track].ptr, it.ptr)
                state.writes = state.writes + 1
            end
        end
        for _, k in ipairs(cp.creates) do
            local it = model.items[k]
            local tr = model.tracks[it.track].ptr
            local item = R.AddMediaItemToTrack(tr)
            if not item then error("폴더 아이템을 만들 수 없습니다.") end
            state.writes = state.writes + 1
            R.SetMediaItemInfo_Value(item, "D_POSITION", it.s)
            R.SetMediaItemInfo_Value(item, "D_LENGTH", it.e - it.s)
            R.SetMediaItemInfo_Value(item, "B_UISEL", 0)
            set_ext(item, KEY.MARK, "1")
            set_ext(item, KEY.SCHEMA, M.SCHEMA)
            add_named_take(item, model.tracks[it.track].name or "")
            local _, guid = R.GetSetMediaItemInfo_String(item, "GUID", "", false)
            it.ptr, it.guid = item, guid
        end
        for _, k in ipairs(cp.name_fix) do
            local it = model.items[k]
            if R.ValidatePtr2(0, it.ptr, "MediaItem*") and R.CountTakes(it.ptr) == 0 then
                local name = it.name ~= "" and it.name or (model.tracks[it.track].name or "")
                add_named_take(it.ptr, name)
                -- notes 가 이름 한 줄뿐이면 비워서 이름이 두 번 보이지 않게 (여러 줄 메모는 보존)
                if it.notes and it.notes == name then
                    R.GetSetMediaItemInfo_String(it.ptr, "P_NOTES", "", true)
                end
                state.writes = state.writes + 1
            end
        end
        state.writes = state.writes + M.apply_changes(model, gplan.changes)
    end)
    if ok and closed_with_groups then warn_grouping_disabled() end
    return ok
end

----------------------------------------------------------
-- Toggle
----------------------------------------------------------

function M.toggle_folder(track)
    if M.is_recording() then
        msg("녹음 중에는 폴더 Toggle 을 실행할 수 없습니다.")
        return false
    end
    local model = M.read_model()
    local idx = M.track_index(track)
    local t = idx and model.tracks[idx]
    if not (t and t.is_folder) then return false end

    local collapsing = not is_closed(t.compact)
    local new_compact = collapsing and 2 or 0
    local closed_fn = function(i)
        if i == idx then return is_closed(new_compact) end
        return is_closed(model.tracks[i].compact)
    end
    local root = M.outermost_closed(model, idx, closed_fn, false) or idx

    local plan = finalize_plan(model, function()
        return M.plan_groups(model, { root }, closed_fn)
    end)
    if not plan then return false end

    local select_keys = {}
    if collapsing then
        for _, g in ipairs(plan.groups) do
            if g.folder == idx then
                for _, k in ipairs(g.members) do select_keys[#select_keys + 1] = k end
            end
        end
    end

    local ok = run_write(collapsing and "folder_items.collapse" or "folder_items.expand", function(state)
        R.SetMediaTrackInfo_Value(t.ptr, "I_FOLDERCOMPACT", new_compact)
        state.writes = state.writes + 1
        state.writes = state.writes + M.apply_changes(model, plan.changes)
        for _, k in ipairs(select_keys) do
            local it = model.items[k]
            if it.ptr and R.ValidatePtr2(0, it.ptr, "MediaItem*") then R.SetMediaItemSelected(it.ptr, true) end
        end
        R.TrackList_AdjustWindows(false)
    end)
    if ok and collapsing and #select_keys > 0 then warn_grouping_disabled() end
    return ok
end

----------------------------------------------------------
-- Mouse 대상 판별
----------------------------------------------------------

M.CTX_ITEM  = "MM_CTX_ITEM_DBLCLK"
M.CTX_TRACK = "MM_CTX_TRACK_DBLCLK"
M.CTX_TCP   = "MM_CTX_TCP_DBLCLK"

-- 현재 눌린 보조키 → Mouse Modifier flag (1 shift, 2 ctrl, 4 alt, 8 win). JS 미설치 시 nil
function M.current_modifier_flag()
    if not R.JS_Mouse_GetState then return nil end
    local s = to_int(R.JS_Mouse_GetState(4 | 8 | 16 | 32)) or 0
    local f = 0
    if s & 8 ~= 0 then f = f + 1 end
    if s & 4 ~= 0 then f = f + 2 end
    if s & 16 ~= 0 then f = f + 4 end
    if s & 32 ~= 0 then f = f + 8 end
    return f
end

local function is_folder_track(tr)
    return tr and (R.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0) > 0
end

-- 반환: { kind = "folder"|"other", track, context, flag } 또는 nil(비대상 영역)
function M.resolve_mouse_target()
    if not (R.GetMousePosition and R.GetThingFromPoint) then return nil end
    local x, y = R.GetMousePosition()
    local flag = M.current_modifier_flag()

    local item = R.GetItemFromPoint and R.GetItemFromPoint(x, y, true)
    if item then
        local tr = R.GetMediaItemTrack(item)
        if is_folder_track(tr) and get_ext(item, KEY.MARK) == "1" then
            return { kind = "folder", track = tr, context = M.CTX_ITEM, flag = flag }
        end
        return { kind = "other", context = M.CTX_ITEM, flag = flag }
    end

    local tr, info = R.GetThingFromPoint(x, y)
    info = info or ""
    if info == "tcp" then
        if not tr then return nil end
        if is_folder_track(tr) then return { kind = "folder", track = tr, context = M.CTX_TCP, flag = flag } end
        return { kind = "other", context = M.CTX_TCP, flag = flag }
    elseif info == "arrange" then
        if not tr then return nil end
        if R.GetTrackFromPoint then
            local tr2, env = R.GetTrackFromPoint(x, y)
            if tr2 ~= tr or (to_int(env) or 0) ~= 0 then return nil end -- 엔벨로프 레인 등
        end
        if is_folder_track(tr) then return { kind = "folder", track = tr, context = M.CTX_TRACK, flag = flag } end
        return { kind = "other", context = M.CTX_TRACK, flag = flag }
    end
    return nil
end

----------------------------------------------------------
-- Mouse Modifier: 문자열 분류 / Toggle 명령 / 백업
----------------------------------------------------------

M.SETUP_NS = "JKK_FolderItems_Setup"
M.CONTEXTS = {
    { id = M.CTX_ITEM,  label = "Media item - Double click" },
    { id = M.CTX_TRACK, label = "Track (Arrange) - Double click" },
    { id = M.CTX_TCP,   label = "Track control panel - Double click" },
}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- 반환 { type = "none"|"command"|"named"|"builtin"|"ambiguous"|"unknown", id, name, raw }
function M.mm_classify(raw)
    local s = trim(raw)
    if s == "" or s == "0" or s == "0 m" or s == "0 c" then return { type = "none", raw = s } end
    local n = s:match("^(%d+)%s+c$")
    if n then return { type = "command", id = tonumber(n), raw = s } end
    n = s:match("^(%d+)%s+m$")
    if n then return { type = "builtin", id = tonumber(n), raw = s } end
    if s:match("^%d+$") then return { type = "ambiguous", id = tonumber(s), raw = s } end
    if s:match("^_?[%w_%-]+$") and s:match("%a") then
        local name = s:sub(1, 1) == "_" and s or ("_" .. s)
        return { type = "named", name = name, raw = s }
    end
    return { type = "unknown", raw = s }
end

local function norm_named(s)
    s = trim(s):gsub("%s+c$", "")
    if s:sub(1, 1) == "_" then s = s:sub(2) end
    return s:lower()
end

-- raw 가 Toggle 명령을 가리키는가 (named 는 "_RS..." 형식)
function M.mm_is_toggle(raw, named, cmd)
    if not named or named == "" then return false end
    local c = M.mm_classify(raw)
    if c.type == "named" then return norm_named(c.name) == norm_named(named) end
    if c.type == "command" and cmd and cmd ~= 0 then return c.id == cmd end
    return false
end

-- Main_OnCommand 로 안전하게 재실행할 수 있는 원래 동작인가
function M.mm_fallback_supported(raw)
    local c = M.mm_classify(raw)
    return c.type == "command" or c.type == "named", c
end

local function norm_path(p)
    p = tostring(p or ""):gsub("\\", "/"):gsub("/+", "/")
    return p:lower()
end

function M.toggle_script_path(root_dir)
    return (root_dir or M.ROOT_DIR) .. "Actions/" .. M.TOGGLE_FILE
end

-- reaper-kb.ini 를 읽기 전용으로 조회해 Main section 에 등록된 Toggle 의 named ID 를 찾는다
local function find_in_kb(path)
    local kb = R.GetResourcePath() .. "/reaper-kb.ini"
    local f = io.open(kb, "r")
    if not f then return nil end
    local target = norm_path(path)
    local scripts = norm_path(R.GetResourcePath() .. "/Scripts/")
    local found = {}
    for line in f:lines() do
        local sec, id, rest = line:match("^SCR%s+%d+%s+(%d+)%s+(%S+)%s+(.*)$")
        if sec == "0" and id then
            local p = rest:match('"([^"]*)"%s*$') or rest:match("(%S+)%s*$") or ""
            local np = norm_path(p)
            if not (np:match("^%a:/") or np:sub(1, 1) == "/") then np = scripts .. np end
            if np == target then found[#found + 1] = id end
        end
    end
    f:close()
    for _, id in ipairs(found) do
        local named = id:sub(1, 1) == "_" and id or ("_" .. id)
        local cmd = R.NamedCommandLookup(named)
        if cmd and cmd ~= 0 then return named, cmd, #found end
    end
    return nil
end

-- 반환 info = { path, exists, named, cmd, registered, error }
-- register=true 이면 미등록 시 AddRemoveReaScript 로 Main section 에 등록 (동일 경로 재등록 시 기존 ID 반환)
function M.resolve_toggle_command(root_dir, register)
    local info = { path = M.toggle_script_path(root_dir) }
    info.exists = R.file_exists(info.path)
    if not info.exists then
        info.error = "Toggle 스크립트를 찾을 수 없습니다: " .. info.path
        return info
    end
    local named, cmd, dup = find_in_kb(info.path)
    if named then
        info.named, info.cmd, info.registered, info.duplicates = named, cmd, true, dup
        return info
    end
    if not register then
        info.error = "Toggle 액션이 아직 Action List 에 등록되지 않았습니다 (Set 시 자동 등록)."
        return info
    end
    local c = R.AddRemoveReaScript(true, 0, info.path, true)
    if not c or c == 0 then
        info.error = "AddRemoveReaScript 등록에 실패했습니다."
        return info
    end
    local rn = R.ReverseNamedCommandLookup(c)
    if not rn or rn == "" then
        info.error = "등록된 Toggle 의 named command ID 를 확인할 수 없습니다."
        return info
    end
    info.named = rn:sub(1, 1) == "_" and rn or ("_" .. rn)
    info.cmd = R.NamedCommandLookup(info.named)
    info.registered = info.cmd ~= nil and info.cmd ~= 0
    if not info.registered then info.error = "등록된 Toggle 명령을 다시 조회할 수 없습니다." end
    return info
end

local function bkey(ctx, flag, field) return string.format("%s.%d.%s", ctx, flag, field) end

function M.mm_read_backup(ctx, flag)
    if not R.HasExtState(M.SETUP_NS, bkey(ctx, flag, "schema")) then return nil end
    return {
        raw = R.GetExtState(M.SETUP_NS, bkey(ctx, flag, "raw")),
        nomove = R.GetExtState(M.SETUP_NS, bkey(ctx, flag, "nomove")),
        assigned = R.GetExtState(M.SETUP_NS, bkey(ctx, flag, "assigned")),
        schema = R.GetExtState(M.SETUP_NS, bkey(ctx, flag, "schema")),
    }
end

function M.mm_write_backup(ctx, flag, b)
    R.SetExtState(M.SETUP_NS, bkey(ctx, flag, "raw"), b.raw or "", true)
    R.SetExtState(M.SETUP_NS, bkey(ctx, flag, "nomove"), b.nomove or "", true)
    R.SetExtState(M.SETUP_NS, bkey(ctx, flag, "assigned"), b.assigned or "", true)
    R.SetExtState(M.SETUP_NS, bkey(ctx, flag, "schema"), M.SCHEMA, true)
end

function M.mm_delete_backup(ctx, flag)
    for _, f in ipairs({ "raw", "nomove", "assigned", "schema" }) do
        R.DeleteExtState(M.SETUP_NS, bkey(ctx, flag, f), true)
    end
end

function M.mm_get(ctx, flag)
    local ok, v = pcall(R.GetMouseModifier, ctx, flag)
    if ok then return v or "" end
    return nil
end

-- Toggle 을 등록한다. confirm_overwrite(old_backup) → bool : 남아 있는 이전 백업을 덮어쓸지
-- 반환 ok, message, undo_record
function M.mm_set(ctx, flag, tinfo, confirm_overwrite)
    if not (tinfo and tinfo.named) then return false, "Toggle 명령 ID 미확인" end
    local cur = M.mm_get(ctx, flag)
    if cur == nil then return false, "이 context 를 읽을 수 없습니다 (미지원)." end
    if M.mm_is_toggle(cur, tinfo.named, tinfo.cmd) then return true, "이미 등록됨", nil end

    local prev_backup = M.mm_read_backup(ctx, flag)
    if prev_backup and confirm_overwrite and not confirm_overwrite(prev_backup, cur) then
        return false, "취소됨 (기존 백업 유지)"
    end
    M.mm_write_backup(ctx, flag, {
        raw = cur, nomove = M.mm_get(ctx, flag | 1024) or "", assigned = tinfo.named,
    })
    local undo = { ctx = ctx, flag = flag, prev_raw = cur, prev_backup = prev_backup }

    local verified = false
    for _, candidate in ipairs({ tinfo.named, (tinfo.named:gsub("^_", "")) }) do
        pcall(R.SetMouseModifier, ctx, flag, candidate)
        if M.mm_is_toggle(M.mm_get(ctx, flag), tinfo.named, tinfo.cmd) then verified = true; break end
    end
    if verified then return true, "등록됨", undo end
    M.mm_rollback(undo)
    return false, "등록 후 read-back 검증 실패 (원래 설정으로 복원함)"
end

-- mm_set 이 이번 실행에서 바꾼 것을 원래대로
function M.mm_rollback(undo)
    if not undo then return true end
    pcall(R.SetMouseModifier, undo.ctx, undo.flag, undo.prev_raw)
    if undo.prev_backup then
        M.mm_write_backup(undo.ctx, undo.flag, undo.prev_backup)
    else
        M.mm_delete_backup(undo.ctx, undo.flag)
    end
    return norm_named(M.mm_get(undo.ctx, undo.flag) or "") == norm_named(undo.prev_raw)
end

-- 반환 status("restored"|"no_backup"|"skipped"|"failed"), message
function M.mm_restore(ctx, flag, tinfo)
    local b = M.mm_read_backup(ctx, flag)
    if not b then return "no_backup", "백업 없음" end
    local cur = M.mm_get(ctx, flag)
    local named = (tinfo and tinfo.named) or b.assigned
    local cmd = tinfo and tinfo.cmd or (named ~= "" and R.NamedCommandLookup(named)) or nil
    if not M.mm_is_toggle(cur, named, cmd) then
        return "skipped", "현재 설정이 Toggle 이 아님 (외부에서 변경됨) - 건너뜀"
    end
    -- 백업된 원래 액션(스크립트/커스텀 액션)이 더 이상 존재하지 않으면 No action 으로 되돌리고 끝낸다
    local bc = M.mm_classify(b.raw)
    if bc.type == "named" and (R.NamedCommandLookup(bc.name) or 0) == 0 then
        pcall(R.SetMouseModifier, ctx, flag, "0") -- 알 수 없는 값 = No action
        if M.mm_is_toggle(M.mm_get(ctx, flag), named, cmd) then
            return "failed", "No action 으로 되돌리지 못했습니다 (Toggle 유지, 백업 보존)"
        end
        M.mm_delete_backup(ctx, flag)
        return "restored", "원래 액션이 없어 No action 으로 복원됨"
    end
    pcall(R.SetMouseModifier, ctx, flag, b.raw)
    local after = M.mm_get(ctx, flag) or ""
    if norm_named(after) ~= norm_named(b.raw) then
        pcall(R.SetMouseModifier, ctx, flag, cur) -- 반쯤 바뀐 상태를 남기지 않음
        return "failed", "복원 read-back 불일치 (Toggle 유지, 백업 보존): " .. after
    end
    if b.nomove ~= "" then
        local nm = M.mm_get(ctx, flag | 1024)
        if nm and norm_named(nm) ~= norm_named(b.nomove) then pcall(R.SetMouseModifier, ctx, flag | 1024, b.nomove) end
    end
    M.mm_delete_backup(ctx, flag)
    return "restored", "복원됨"
end

----------------------------------------------------------
-- 일반 대상 더블클릭 fallback (검증된 Main action / custom action 만)
----------------------------------------------------------

local function self_command()
    local _, _, _, cmd = R.get_action_context()
    cmd = to_int(cmd) or 0
    local named = nil
    if cmd ~= 0 then
        local rn = R.ReverseNamedCommandLookup(cmd)
        if rn and rn ~= "" then named = rn:sub(1, 1) == "_" and rn or ("_" .. rn) end
    end
    return named, cmd
end

function M.run_previous_behavior(target)
    if not (target and target.context and R.GetMouseModifier) then return false end
    local named, cmd = self_command()
    if not named then
        local info = M.resolve_toggle_command(nil, false)
        named, cmd = info.named, info.cmd
    end
    if not named then return false end

    local flag = target.flag
    if flag == nil then
        -- JS 미설치: Toggle 이 등록된 flag 가 하나뿐일 때만 그 flag 로 간주
        local hits = {}
        for f = 0, 15 do
            if M.mm_is_toggle(M.mm_get(target.context, f), named, cmd) then hits[#hits + 1] = f end
        end
        if #hits ~= 1 then return false end
        flag = hits[1]
    end
    -- 실제로 이 context/flag 의 Mouse Modifier 로 실행된 경우에만 (키보드 실행 시 엉뚱한 동작 방지)
    if not M.mm_is_toggle(M.mm_get(target.context, flag), named, cmd) then return false end
    local b = M.mm_read_backup(target.context, flag)
    if not b then return false end
    local ok, c = M.mm_fallback_supported(b.raw)
    if not ok then return false end
    local id = c.type == "command" and c.id or R.NamedCommandLookup(c.name)
    if not id or id == 0 or id == cmd then return false end
    if c.type == "named" and norm_named(c.name) == norm_named(named) then return false end
    R.Main_OnCommand(id, 0)
    return true
end

return M
