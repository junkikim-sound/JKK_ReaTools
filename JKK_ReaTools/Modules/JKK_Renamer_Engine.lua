--========================================================
-- @title JKK_Renamer_Engine
-- @author Junki Kim
-- @noindex
--========================================================
-- Renamer Queue(파이프라인) 변환 엔진.
-- reaper API를 전혀 사용하지 않는 순수 함수 모음이라 REAPER 밖에서도 mock 테스트가 가능하다.
--
-- step = { op = "replace" | "insert" | ..., on = true, <op별 필드> }
-- E.Run(name, steps, opts, ctx) -> final_name, stages, errors
--   opts.keep_ext : 확장자를 떼어 놓고 단계들을 적용한 뒤 다시 붙인다
--   opts.suffix   : 마지막에 (확장자 앞) 붙일 문자열 (공유 Number(_nn) 옵션용)
--   ctx.index / ctx.count : 대상 순번 / 대상 수 (Number 단계)
--   ctx.vars      : $source, $track 같은 토큰 값 (호스트가 채워 넣음)
--   stages[i]     : i번째 단계를 거친 결과 (비활성 단계는 false)
--   errors[i]     : i번째 단계 오류 메시지 (잘못된 Lua 패턴 등)

local E = {}

---------------------------------------------------------
-- 문자열 유틸
---------------------------------------------------------
local SEP_CHARS = { [" "] = true, ["_"] = true, ["-"] = true }

-- 단어 문자: ASCII 영숫자 또는 멀티바이트(한글 등) 바이트
local function IsWordByte(b)
    return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

local function ToInt(v, default, min_v, max_v)
    local n = math.floor(tonumber(v) or default)
    if min_v and n < min_v then n = min_v end
    if max_v and n > max_v then n = max_v end
    return n
end

-- UTF-8 글자 시작 바이트 위치 목록 (잘못된 바이트도 1글자로 취급해 안전하게 진행)
local function CharStarts(s)
    local starts, i, n = {}, 1, #s
    while i <= n do
        starts[#starts + 1] = i
        local j = i + 1
        if s:byte(i) >= 0xC0 then
            while j <= n do
                local c = s:byte(j)
                if c < 0x80 or c > 0xBF then break end
                j = j + 1
            end
        end
        i = j
    end
    return starts
end

-- 단어 목록 { {s=, e=}, ... }  (구분자: 공백, _, -, . 등 영숫자/멀티바이트가 아닌 모든 문자)
local function Words(s)
    local words = {}
    for ws, we in s:gmatch("()[%w\128-\255]+()") do
        words[#words + 1] = { s = ws, e = we - 1 }
    end
    return words
end

-- $source, $track 처럼 호스트가 넘겨준 토큰만 치환한다. 모르는 $토큰은 그대로 둔다.
local function ExpandTokens(text, vars, escape_pct)
    if not vars or not text:find("$", 1, true) then return text end
    return (text:gsub("%$(%a+)", function(key)
        local v = vars[key]
        if v == nil then return nil end
        v = tostring(v)
        if escape_pct then v = v:gsub("%%", "%%%%") end
        return v
    end))
end

-- Lua 패턴 모드의 바꿀 문자열: %0 = 전체 매치, %1~%9 = 캡처, %% = %
local function ExpandRepl(repl, whole, caps)
    return (repl:gsub("%%([%d%%])", function(c)
        if c == "%" then return "%" end
        local k = tonumber(c)
        if k == 0 or (k == 1 and #caps == 0) then return whole end
        local v = caps[k]
        if v == nil then return "" end
        return tostring(v)
    end))
end

-- needle의 모든 매치 { {s=, e=, caps=} } 반환. 패턴 오류면 nil, err
-- o.pattern(Lua 패턴) / o.ignore_case(대소문자 무시, 리터럴 모드만) / o.whole_word
local function FindAll(text, needle, o)
    local res = {}
    if needle == nil or needle == "" then return res end
    o = o or {}
    local hay, pat, plain = text, needle, true
    if o.pattern then
        plain = false
    elseif o.ignore_case then
        hay, pat = text:lower(), needle:lower()
    end
    local anchored = (not plain) and pat:sub(1, 1) == "^"
    local pos, n = 1, #text
    while pos <= n + 1 do
        local r = table.pack(pcall(string.find, hay, pat, pos, plain))
        if not r[1] then return nil, "Invalid pattern" end
        local s, e = r[2], r[3]
        if not s then break end
        if e < s then
            -- 빈 매치는 건너뛴다 (무한 루프 방지)
            pos = s + 1
        else
            local ok = true
            if o.whole_word then
                ok = not IsWordByte(text:byte(s - 1)) and not IsWordByte(text:byte(e + 1))
            end
            if ok then
                local caps = {}
                for k = 4, r.n do caps[#caps + 1] = r[k] end
                res[#res + 1] = { s = s, e = e, caps = caps }
                pos = e + 1
            else
                pos = s + 1
            end
        end
        if anchored then break end
    end
    return res
end

-- 앞에서 n번째 / 뒤에서 n번째 하나만 고른다
local function PickNth(matches, n, from_end)
    if from_end then return matches[#matches - n + 1] end
    return matches[n]
end

local function Splice(text, picks, make)
    local out, cursor = {}, 1
    for _, m in ipairs(picks) do
        out[#out + 1] = text:sub(cursor, m.s - 1)
        out[#out + 1] = make(m)
        cursor = m.e + 1
    end
    out[#out + 1] = text:sub(cursor)
    return table.concat(out)
end

-- 삽입 위치 주변에서 쓸 구분자 추정 (" ", "_", "-")
local function DetectSep(base, m, side)
    local before_c = (m.s > 1) and base:sub(m.s - 1, m.s - 1) or ""
    local after_c = base:sub(m.e + 1, m.e + 1)
    local first, second = before_c, after_c
    if side == "after" then first, second = after_c, before_c end
    if SEP_CHARS[first] then return first end
    if SEP_CHARS[second] then return second end
    return base:match("[ _%-]") or " "
end

-- 매치(또는 단어) m의 앞/뒤에 text 삽입. auto_sep이면 단어와 붙지 않게 구분자를 끼운다
local function InsertAround(base, m, side, text, auto_sep)
    if side == "before" then
        local ins = text
        if auto_sep and IsWordByte(base:byte(m.s)) and not SEP_CHARS[text:sub(-1)] then
            ins = text .. DetectSep(base, m, "before")
        end
        return base:sub(1, m.s - 1) .. ins .. base:sub(m.s)
    end
    local ins = text
    if auto_sep and IsWordByte(base:byte(m.e)) and not SEP_CHARS[text:sub(1, 1)] then
        ins = DetectSep(base, m, "after") .. text
    end
    return base:sub(1, m.e) .. ins .. base:sub(m.e + 1)
end

local function TitleWord(word, keep_caps)
    if keep_caps and word:find("%a") and word == word:upper() then return word end
    return (word:lower():gsub("^%l", string.upper))
end

---------------------------------------------------------
-- 확장자
---------------------------------------------------------
-- "metal impact.wav" -> "metal impact", ".wav"
-- 마지막 점 뒤 1~5자 영숫자 + 글자 1개 이상일 때만 확장자로 본다 ("Vol.2" 등은 제외)
function E.SplitExt(name)
    local b, e = name:match("^(.+)(%.%w+)$")
    if b and #e <= 6 and e:find("%a") then return b, e end
    return name, ""
end

---------------------------------------------------------
-- 단계(Operation) 정의
---------------------------------------------------------
local OPS = {}

OPS.replace = {
    label = "Replace",
    defaults = { find = "", with = "", occ = "all", n = 1, from_end = false,
                 ignore_case = false, whole_word = false, pattern = false },
    apply = function(st, base, ext, c)
        if st.find == "" then return base, ext end
        local matches, err = FindAll(base, st.find, st)
        if not matches then return base, ext, err end
        local picks = matches
        if st.occ == "nth" then
            local m = PickNth(matches, ToInt(st.n, 1, 1), st.from_end)
            picks = m and { m } or {}
        end
        if #picks == 0 then return base, ext end
        local repl = ExpandTokens(st.with, c.vars, st.pattern)
        return Splice(base, picks, function(m)
            if st.pattern then return ExpandRepl(repl, base:sub(m.s, m.e), m.caps) end
            return repl
        end), ext
    end,
}

-- where: "start" | "end" (n = 앞/뒤에서 떨어진 칸 수, unit = "char" | "word")
--        "before" | "after" (find 문자열의 nth 번째 매치 앞/뒤, from_end면 뒤에서 셈)
OPS.insert = {
    label = "Insert",
    defaults = { text = "", where = "start", n = 0, unit = "char", find = "", nth = 1,
                 from_end = false, ignore_case = false, whole_word = false, auto_sep = true },
    apply = function(st, base, ext, c)
        local text = ExpandTokens(st.text, c.vars)
        if text == "" then return base, ext end
        local where = st.where
        if where == "start" or where == "end" then
            local n = ToInt(st.n, 0, 0)
            if st.unit == "word" then
                local words = Words(base)
                if #words == 0 then
                    return (where == "start") and (text .. base) or (base .. text), ext
                end
                local k, side
                if where == "start" then
                    if n >= #words then k, side = #words, "after" else k, side = n + 1, "before" end
                else
                    if n >= #words then k, side = 1, "before" else k, side = #words - n, "after" end
                end
                return InsertAround(base, words[k], side, text, st.auto_sep), ext
            end
            local starts = CharStarts(base)
            local count = #starts
            if n > count then n = count end
            local chars_before = (where == "start") and n or (count - n)
            local bytepos = (chars_before >= count) and (#base + 1) or starts[chars_before + 1]
            return base:sub(1, bytepos - 1) .. text .. base:sub(bytepos), ext
        end
        local matches, err = FindAll(base, st.find, st)
        if not matches then return base, ext, err end
        local m = PickNth(matches, ToInt(st.nth, 1, 1), st.from_end)
        if not m then return base, ext end
        return InsertAround(base, m, (where == "after") and "after" or "before", text, st.auto_sep), ext
    end,
}

-- what: "digits" | "non_digits" | "trailing_num" | "first" | "last"
OPS.remove = {
    label = "Remove",
    defaults = { what = "digits", n = 1 },
    apply = function(st, base, ext)
        local what = st.what
        if what == "digits" then return (base:gsub("%d", "")), ext end
        if what == "non_digits" then return (base:gsub("%D", "")), ext end
        if what == "trailing_num" then return (base:gsub("[%s_%-%.]*%d+$", "")), ext end
        local n = ToInt(st.n, 1, 0)
        local starts = CharStarts(base)
        if n >= #starts then return "", ext end
        if n == 0 then return base, ext end
        if what == "first" then return base:sub(starts[n + 1]), ext end
        if what == "last" then return base:sub(1, starts[#starts - n + 1] - 1), ext end
        return base, ext
    end,
}

-- mode: "lower" | "upper" | "title" | "title_keep" | "sentence"
OPS.case = {
    label = "Case",
    defaults = { mode = "title", split_underscore = false },
    apply = function(st, base, ext)
        local mode = st.mode
        if mode == "lower" then return base:lower(), ext end
        if mode == "upper" then return base:upper(), ext end
        if mode == "sentence" then
            return (base:lower():gsub("^(%A*)(%a)", function(p, ch) return p .. ch:upper() end)), ext
        end
        local keep = (mode == "title_keep")
        local word_pat = st.split_underscore and "([^%s_]+)" or "([^%s]+)"
        return (base:gsub(word_pat, function(w) return TitleWord(w, keep) end)), ext
    end,
}

OPS.camel = {
    label = "Split camelCase",
    defaults = { sep = " " },
    apply = function(st, base, ext)
        local sep = (st.sep or " "):gsub("%%", "%%%%")
        local out = base:gsub("([%l%d])(%u)", "%1" .. sep .. "%2")
        out = out:gsub("(%u)(%u%l)", "%1" .. sep .. "%2")
        return out, ext
    end,
}

OPS.cleanup = {
    label = "Clean Up",
    defaults = { collapse_spaces = true, collapse_seps = true, trim_edges = true },
    apply = function(st, base, ext)
        local s = base
        if st.collapse_spaces then s = s:gsub("%s+", " ") end
        if st.collapse_seps then
            -- Lua 패턴은 역참조(%1) 반복을 지원하지 않으므로 구분자별로 처리
            s = s:gsub("__+", "_")
            s = s:gsub("%-%-+", "-")
            s = s:gsub("%.%.+", ".")
        end
        if st.trim_edges then
            s = s:gsub("^[%s_%-%.]+", "")
            s = s:gsub("[%s_%-%.]+$", "")
        end
        return s, ext
    end,
}

-- position: "suffix" | "prefix"
OPS.number = {
    label = "Number",
    defaults = { position = "suffix", start = 1, step = 1, pad = 2, sep = "_" },
    apply = function(st, base, ext, c)
        local value = ToInt(st.start, 1) + ((c.index or 1) - 1) * ToInt(st.step, 1)
        local num = string.format("%0" .. ToInt(st.pad, 2, 1, 8) .. "d", value)
        local sep = st.sep or ""
        if st.position == "prefix" then return num .. sep .. base, ext end
        return base .. sep .. num, ext
    end,
}

-- from: "source" (테이크 원본 파일 이름) | "track" | "text" ($source/$track 토큰 사용 가능)
OPS.set = {
    label = "Set Name",
    defaults = { from = "source", text = "" },
    apply = function(st, base, ext, c)
        local vars = c.vars or {}
        local v
        if st.from == "source" then v = vars.source
        elseif st.from == "track" then v = vars.track
        else v = ExpandTokens(st.text or "", vars) end
        if v == nil or v == "" then return base, ext end
        if c.keep_ext then return E.SplitExt(v) end
        return v, ext
    end,
}

-- mode: "remove" | "lower" | "upper" | "set"
OPS.ext = {
    label = "Extension",
    defaults = { mode = "remove", text = "" },
    apply = function(st, base, ext, c)
        local b, e = base, ext
        if not c.keep_ext then b, e = E.SplitExt(base) end
        local mode = st.mode
        if mode == "remove" then e = ""
        elseif mode == "lower" then e = e:lower()
        elseif mode == "upper" then e = e:upper()
        elseif mode == "set" then
            local t = (st.text or ""):gsub("^%.+", "")
            if t ~= "" then e = "." .. t end
        end
        if c.keep_ext then return b, e end
        return b .. e, ext
    end,
}

E.OPS = OPS
E.OP_ORDER = { "replace", "insert", "remove", "case", "camel", "cleanup", "number", "set", "ext" }

function E.OpLabel(op)
    return OPS[op] and OPS[op].label or tostring(op)
end

-- 기본값 채우기 (저장된 프리셋에 새 필드가 없을 때도 안전하게)
function E.Normalize(st)
    local def = OPS[st.op]
    if not def then return st end
    for k, v in pairs(def.defaults) do
        if st[k] == nil or type(st[k]) ~= type(v) then st[k] = v end
    end
    if st.on == nil then st.on = true end
    return st
end

function E.NewStep(op, fields)
    local st = { op = op, on = true }
    if fields then
        for k, v in pairs(fields) do st[k] = v end
    end
    return E.Normalize(st)
end

function E.CopyStep(st)
    local copy = {}
    for k, v in pairs(st) do copy[k] = v end
    return copy
end

---------------------------------------------------------
-- 실행
---------------------------------------------------------
function E.ApplyStep(st, base, ext, c)
    local def = OPS[st.op]
    if not def then return base, ext end
    local ok, nb, ne, err = pcall(def.apply, st, base, ext, c)
    if not ok then return base, ext, tostring(nb) end
    return nb or base, ne or ext, err
end

function E.Run(name, steps, opts, ctx)
    opts, ctx = opts or {}, ctx or {}
    local keep = opts.keep_ext and true or false
    local c = { index = ctx.index or 1, count = ctx.count or 1, vars = ctx.vars or {}, keep_ext = keep }
    local base, ext = name or "", ""
    if keep then base, ext = E.SplitExt(base) end
    local stages, errors = {}, {}
    for i, st in ipairs(steps or {}) do
        if st.on ~= false and OPS[st.op] then
            local err
            base, ext, err = E.ApplyStep(st, base, ext, c)
            if err then errors[i] = err end
            stages[i] = base .. ext
        else
            stages[i] = false
        end
    end
    if opts.suffix and opts.suffix ~= "" then base = base .. opts.suffix end
    return base .. ext, stages, errors
end

---------------------------------------------------------
-- 단계 요약 (Queue 목록 표시용)
---------------------------------------------------------
local function Q(s)
    s = tostring(s or "")
    if #s > 24 then
        local starts = CharStarts(s)
        if #starts > 20 then s = s:sub(1, starts[21] - 1) .. "…" end
    end
    return '"' .. s .. '"'
end

local function Ordinal(n, from_end)
    return "#" .. ToInt(n, 1, 1) .. (from_end and " from end" or "")
end

function E.Describe(st)
    local op = st.op
    if op == "replace" then
        if st.find == "" then return "Replace (empty)" end
        local s = "Replace " .. Q(st.find) .. " → " .. Q(st.with)
        if st.occ == "nth" then s = s .. " (" .. Ordinal(st.n, st.from_end) .. ")" end
        return s
    elseif op == "insert" then
        if st.text == "" then return "Insert (empty)" end
        local n = ToInt(st.n, 0, 0)
        if st.where == "start" or st.where == "end" then
            if n == 0 then return ((st.where == "start") and "Prefix " or "Suffix ") .. Q(st.text) end
            local unit = (st.unit == "word") and (n == 1 and "word" or "words") or (n == 1 and "char" or "chars")
            return "Insert " .. Q(st.text) .. " " .. n .. " " .. unit .. " from " .. st.where
        end
        if st.find == "" then return "Insert " .. Q(st.text) .. " (no anchor)" end
        return "Insert " .. Q(st.text) .. " " .. st.where .. " " .. Q(st.find)
            .. " (" .. Ordinal(st.nth, st.from_end) .. ")"
    elseif op == "remove" then
        local what = st.what
        if what == "digits" then return "Remove digits" end
        if what == "non_digits" then return "Keep digits only" end
        if what == "trailing_num" then return "Remove trailing number" end
        return "Remove " .. what .. " " .. ToInt(st.n, 1, 0) .. " chars"
    elseif op == "case" then
        local names = { lower = "lowercase", upper = "UPPERCASE", title = "Title Case",
                        title_keep = "Title Case (keep CAPS)", sentence = "Sentence case" }
        return "Case: " .. (names[st.mode] or st.mode)
    elseif op == "camel" then
        return "Split camelCase"
    elseif op == "cleanup" then
        return "Clean up spaces / separators"
    elseif op == "number" then
        local sample = string.format("%0" .. ToInt(st.pad, 2, 1, 8) .. "d", ToInt(st.start, 1))
        if st.position == "prefix" then return "Number " .. sample .. (st.sep or "") .. "…" end
        return "Number …" .. (st.sep or "") .. sample
    elseif op == "set" then
        if st.from == "source" then return "Name = source file" end
        if st.from == "track" then return "Name = track name" end
        return "Name = " .. Q(st.text)
    elseif op == "ext" then
        if st.mode == "set" then return "Extension → ." .. tostring(st.text or ""):gsub("^%.+", "") end
        local names = { remove = "remove", lower = "lowercase", upper = "UPPERCASE" }
        return "Extension: " .. (names[st.mode] or st.mode)
    end
    return E.OpLabel(op)
end

---------------------------------------------------------
-- 직렬화 (ExtState 저장용: 줄바꿈 없는 한 줄 문자열)
---------------------------------------------------------
local function Esc(s)
    return (tostring(s):gsub("[%%;,=|\r\n\t]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

local function Unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function E.Serialize(steps)
    local parts = { "v1" }
    for _, st in ipairs(steps or {}) do
        local keys = {}
        for k in pairs(st) do
            if type(k) == "string" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        local fields = {}
        for _, k in ipairs(keys) do
            local v, enc = st[k], nil
            local tv = type(v)
            if tv == "boolean" then enc = "b:" .. (v and "1" or "0")
            elseif tv == "number" then enc = "n:" .. tostring(v)
            elseif tv == "string" then enc = "s:" .. Esc(v) end
            if enc then fields[#fields + 1] = Esc(k) .. "=" .. enc end
        end
        parts[#parts + 1] = table.concat(fields, ",")
    end
    return table.concat(parts, ";")
end

function E.Deserialize(str)
    if type(str) ~= "string" or str:sub(1, 3) ~= "v1;" and str ~= "v1" then return nil end
    local steps, first = {}, true
    for chunk in (str .. ";"):gmatch("([^;]*);") do
        if first then
            first = false
        elseif chunk ~= "" then
            local st = {}
            for field in chunk:gmatch("[^,]+") do
                local k, t, v = field:match("^([^=]*)=(%a):(.*)$")
                if k then
                    k = Unesc(k)
                    if t == "b" then st[k] = (v == "1")
                    elseif t == "n" then st[k] = tonumber(v)
                    elseif t == "s" then st[k] = Unesc(v) end
                end
            end
            if st.op and OPS[st.op] then steps[#steps + 1] = E.Normalize(st) end
        end
    end
    return steps
end

-- 프리셋 목록 { {name=, data=}, ... } <-> 한 줄 문자열
function E.SerializePresets(list)
    local parts = {}
    for _, p in ipairs(list or {}) do
        parts[#parts + 1] = Esc(p.name) .. "=" .. Esc(p.data)
    end
    return table.concat(parts, "|")
end

function E.DeserializePresets(str)
    local list = {}
    if type(str) ~= "string" or str == "" then return list end
    for entry in str:gmatch("[^|]+") do
        local name, data = entry:match("^([^=]*)=(.*)$")
        if name then list[#list + 1] = { name = Unesc(name), data = Unesc(data) } end
    end
    return list
end

return E
