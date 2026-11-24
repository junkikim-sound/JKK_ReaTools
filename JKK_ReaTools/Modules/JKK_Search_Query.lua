--========================================================
-- @title JKK_Search_Query
-- @author Junki Kim
-- @noindex
-- 검색어 매칭 / 점수 계산 / 정렬 / 하이라이트 범위 계산
--  * 공백으로 나눈 모든 토큰이 이름(또는 제조사·포맷·카테고리)에 포함되어야 매칭
--  * 단일 ASCII 토큰은 이니셜/퍼지 매칭 허용 (예: "rba" -> "RBass")
--  * 최근 사용 항목은 항상 결과 상단에 최근 순으로 표시
--========================================================

local M = {}

function M.Create(deps)
local Index = deps.index
local Store = deps.store
local Library = deps.library

local find, sub, byte = string.find, string.sub, string.byte

local KIND_BONUS = {
    fx = 30, chain = 22, template = 18, action = 10, track = 14,
    item = 6, marker = 8, region = 8, project = 5,
}

-- 각 범위(scope)에서 순회할 소스 목록
local ALL_SOURCES = Index.SOURCES
local SCOPE_SOURCES = {
    effects     = { "fx" },
    instruments = { "fx" },
    chains      = { "chain" },
    templates   = { "template" },
    actions     = { "action" },
    tracks      = { "track" },
    items       = { "item" },
    markers     = { "marker" },
    projects    = { "project" },
}

local Q = {}
Q.tokens = {}

----------------------------------------------------------
-- 토큰 / 매칭 유틸
----------------------------------------------------------
local function Tokenize(q)
    local tokens = {}
    for t in (q or ""):lower():gmatch("%S+") do tokens[#tokens + 1] = t end
    return tokens
end

local function IsAscii(s)
    return not find(s, "[\128-\255]")
end

local function IsWordStart(s, p)
    if p <= 1 then return true end
    local c = byte(s, p - 1)
    -- 영숫자가 아닌 문자 뒤(공백, -, _, (, / 등)는 단어 시작으로 본다
    return not ((c >= 48 and c <= 57) or (c >= 97 and c <= 122) or (c >= 65 and c <= 90))
end

local function FuzzyScore(s, t)
    local pos, last, score, starts = 1, -10, 0, 0
    for i = 1, #t do
        local p = find(s, sub(t, i, i), pos, true)
        if not p then return nil end
        if p == last + 1 then score = score + 3 end
        if IsWordStart(s, p) then score = score + 4; starts = starts + 1 end
        last, pos = p, p + 1
    end
    local need = (#t >= 3) and 2 or 1
    if starts < need then return nil end
    return score
end

local function FuzzyPositions(s, t)
    local out, pos = {}, 1
    for i = 1, #t do
        local p = find(s, sub(t, i, i), pos, true)
        if not p then return nil end
        out[#out + 1] = p
        pos = p + 1
    end
    return out
end

----------------------------------------------------------
-- 범위(scope) 필터
----------------------------------------------------------
local function FindNamed(arr, name)
    for _, v in ipairs(arr) do if v.name == name then return v end end
    return nil
end

local function FindFolder(id)
    for _, f in ipairs(Index.folders) do if f.id == id then return f end end
    return nil
end

local function BuildScopeFilter(scope)
    if scope == "all" then return nil, ALL_SOURCES end
    if scope == "recent" then
        return function(e) return Store.RecentRank(e.key) ~= nil end, ALL_SOURCES
    end
    if scope == "favorites" then
        return function(e) return Store.IsFavorite(e.key) end, ALL_SOURCES
    end
    if scope == "effects" then
        return function(e) return not e.is_instrument end, SCOPE_SOURCES.effects
    end
    if scope == "instruments" then
        return function(e) return e.is_instrument end, SCOPE_SOURCES.instruments
    end
    local cat = scope:match("^cat:(.*)$")
    if cat then
        local c = FindNamed(Index.categories, cat)
        local set = c and c.set or {}
        return function(e) return set[e] == true end, { "fx" }
    end
    local dev = scope:match("^dev:(.*)$")
    if dev then
        local d = FindNamed(Index.developers, dev)
        local set = d and d.set or {}
        return function(e) return set[e] == true end, { "fx" }
    end
    if scope == "new" and Library then
        return function(e) return Library.IsNew(e.key) end, { "fx" }
    end
    local tid = scope:match("^tag:(.*)$")
    if tid then
        local set = (Library and Library.TagSet(tid)) or {}
        return function(e) return set[e.key] == true end, ALL_SOURCES
    end
    local fid = scope:match("^folder:(.*)$")
    if fid then
        local f = FindFolder(fid)
        local set = f and f.set or {}
        return function(e) return set[e] == true end, { "fx", "chain" }
    end
    return nil, SCOPE_SOURCES[scope] or ALL_SOURCES
end

local FORMAT_SET = { VST = true, VST3 = true, CLAP = true, JS = true }

-- 검색창 왼쪽 타입 필터: 플러그인 포맷 + 항목 종류
local KIND_FILTER = {
    chain = { chain = true }, template = { template = true }, action = { action = true },
    track = { track = true }, item = { item = true }, marker = { marker = true, region = true },
    project = { project = true },
}

local function BuildFormatFilter(fmt)
    if not fmt or fmt == "all" then return nil end
    if fmt == "other" then
        return function(e) return e.kind == "fx" and not FORMAT_SET[e.fx_type] end
    end
    local kinds = KIND_FILTER[fmt]
    if kinds then
        return function(e) return kinds[e.kind] == true end
    end
    return function(e) return e.kind == "fx" and e.fx_type == fmt end
end

----------------------------------------------------------
-- 점수 계산
----------------------------------------------------------
local function ScoreEntry(e, tokens, qfull, allow_fuzzy)
    local lname = e.lname
    local score = 0
    for i = 1, #tokens do
        local t = tokens[i]
        local p = find(lname, t, 1, true)
        if p then
            if p == 1 then score = score + 120
            elseif IsWordStart(lname, p) then score = score + 90
            else score = score + 50 end
        elseif find(e.lsearch, t, 1, true) then
            score = score + 15
        elseif allow_fuzzy and #tokens == 1 and #t >= 2 and IsAscii(t) then
            local fs = FuzzyScore(lname, t)
            if not fs then return nil end
            score = score + fs
        else
            return nil
        end
    end
    if #tokens > 1 or score >= 50 then
        if lname == qfull then score = score + 400
        elseif sub(lname, 1, #qfull) == qfull then score = score + 200
        elseif #tokens > 1 and find(lname, qfull, 1, true) then score = score + 80 end
    end
    score = score - #lname * 0.15 + (KIND_BONUS[e.kind] or 0)
    if Store.IsFavorite(e.key) then score = score + 60 end
    return score
end

----------------------------------------------------------
-- 검색 실행
-- p = { query, scope, format }
-- 반환: entries 배열 (정렬 완료), recent_count (상단 최근 항목 수)
----------------------------------------------------------
function Q.Run(p)
    local tokens = Tokenize(p.query)
    Q.tokens = tokens
    local qfull = table.concat(tokens, " ")
    local allow_fuzzy = Store.Get("fuzzy")
    local hide_dupes = Store.Get("hide_vst2_dupes")
    local scope = p.scope or "all"
    local scope_pred, sources = BuildScopeFilter(scope)
    local fmt_pred = BuildFormatFilter(p.format)
    local skip_actions = (not Store.Get("search_actions")) and scope ~= "actions" and p.format ~= "action"

    local function Pass(e)
        if hide_dupes and e.has_vst3_twin and p.format ~= "VST" then return false end
        if skip_actions and e.kind == "action" then return false end
        if scope_pred and not scope_pred(e) then return false end
        if fmt_pred and not fmt_pred(e) then return false end
        return true
    end

    -- 검색어 없음: 기본 순서 + 최근/즐겨찾기 상단 고정
    if #tokens == 0 then
        local out, used = {}, {}
        local recent_count = 0
        for _, key in ipairs(Store.GetRecent()) do
            local e = Index.Find(key)
            if e and not used[e] and Pass(e) then
                out[#out + 1] = e; used[e] = true; recent_count = recent_count + 1
            end
        end
        if scope ~= "recent" then
            for _, key in ipairs(Store.GetFavorites()) do
                local e = Index.Find(key)
                if e and not used[e] and Pass(e) then out[#out + 1] = e; used[e] = true end
            end
            for _, src in ipairs(sources) do
                local list = Index.GetList(src)
                for i = 1, #list do
                    local e = list[i]
                    if not used[e] and Pass(e) then out[#out + 1] = e end
                end
            end
        end
        return out, recent_count
    end

    -- 검색어 있음: 점수 계산 후 정렬
    local res_e, res_s, res_r = {}, {}, {}
    local n = 0
    for _, src in ipairs(sources) do
        local list = Index.GetList(src)
        for i = 1, #list do
            local e = list[i]
            if Pass(e) then
                local s = ScoreEntry(e, tokens, qfull, allow_fuzzy)
                if s then
                    n = n + 1
                    res_e[n], res_s[n] = e, s
                    res_r[n] = Store.RecentRank(e.key) or 1e9
                end
            end
        end
    end

    local order = {}
    for i = 1, n do order[i] = i end
    table.sort(order, function(a, b)
        local ra, rb = res_r[a], res_r[b]
        if ra ~= rb then return ra < rb end
        local sa, sb = res_s[a], res_s[b]
        if sa ~= sb then return sa > sb end
        return a < b
    end)

    local out, recent_count = {}, 0
    for i = 1, n do
        local idx = order[i]
        out[i] = res_e[idx]
        if res_r[idx] < 1e9 then recent_count = recent_count + 1 end
    end
    return out, recent_count
end

----------------------------------------------------------
-- 하이라이트 범위 (바이트 단위, 정렬/병합 완료)
----------------------------------------------------------
-- 외부 제안 목록(MediaBrowser @ / !)의 하이라이트용 검색 조각 지정
function Q.SetHighlightTerm(term)
    term = tostring(term or ""):lower()
    Q.tokens = (term ~= "") and { term } or {}
end

function Q.Highlight(text_lower)
    local tokens = Q.tokens
    if #tokens == 0 then return nil end
    local ranges = {}
    for _, t in ipairs(tokens) do
        local p = find(text_lower, t, 1, true)
        if p then
            ranges[#ranges + 1] = { p, p + #t - 1 }
        elseif #tokens == 1 and IsAscii(t) and Store.Get("fuzzy") then
            local pos = FuzzyPositions(text_lower, t)
            if pos then
                for _, q in ipairs(pos) do ranges[#ranges + 1] = { q, q } end
            end
        end
    end
    if #ranges == 0 then return nil end
    table.sort(ranges, function(a, b) return a[1] < b[1] end)
    local merged = { ranges[1] }
    for i = 2, #ranges do
        local last, r = merged[#merged], ranges[i]
        if r[1] <= last[2] + 1 then
            if r[2] > last[2] then last[2] = r[2] end
        else
            merged[#merged + 1] = { r[1], r[2] }
        end
    end
    return merged
end

return Q
end

return M
