--========================================================
-- @title JKK_Search_Store
-- @author Junki Kim
-- @noindex
-- 설정 / 최근 사용 항목 / 즐겨찾기 영구 저장 (ExtState)
--========================================================

local RPR = reaper
local M = {}

local EXT_SECTION = "JKK_Search"
local LIST_SEP    = "\30"

----------------------------------------------------------
-- 설정 기본값
----------------------------------------------------------
local DEFAULTS = {
    close_after_run      = true,    -- 실행 후 창 닫기
    show_fx              = "float", -- "float" | "chain" | "none"  : FX 삽입 후 표시 방식
    insert_pos           = "end",   -- "end" | "start"             : FX 체인 삽입 위치
    target_mode          = "auto",  -- auto | tracks | items | master | newtrack | input
    open_at_mouse        = true,    -- 마우스 위치에서 창 열기
    close_on_unfocus     = false,   -- 포커스를 잃으면 창 닫기
    hide_vst2_dupes      = true,    -- VST3 버전이 있으면 VST2 숨기기
    fuzzy                = true,    -- 퍼지(이니셜) 매칭
    search_tracks        = true,
    search_items         = true,
    search_markers       = true,
    search_actions       = true,
    project_new_tab      = true,    -- 프로젝트를 새 탭에서 열기
    arm_instrument_track = true,    -- VSTi 새 트랙 생성 시 MIDI 입력/암 설정
    show_sidebar         = true,
    max_recent           = 40,
    font_scale           = 1.0,     -- JKK Search 전용 글자 크기 배율
    sidebar_w            = 210,     -- 우측 패널 너비 (px, 배율 적용 전)
    expanded_h           = 480,     -- 펼친 상태의 창 높이
    collapsed_h          = 96,      -- 접힌 상태(검색창만)의 창 높이 (자동 측정값)
    auto_expand          = true,    -- 검색어 입력 시 자동으로 결과 펼치기
    expanded             = false,   -- 결과 패널 펼침 상태 (사용자가 펼치면 기억)
    view_mode            = "compact", -- "compact" | "detailed" (이름 아래 제조사 표시)
    font_size            = 0,       -- JKK Search 전용 글자 크기(px). 0 = 테마 기본 크기
    last_scope           = "all",   -- 마지막으로 선택한 사이드 패널 항목 (재실행 시 복원)
    tree_open            = "",      -- 사이드 패널 대분류/그룹 펼침 상태 "browse=1;tags=0;..."
    mb_key               = "shift_enter", -- JKK MediaBrowser 현재 탭에서 검색하는 단축키
}
M.DEFAULTS = DEFAULTS

local settings = {}
local revision = 0

local function Decode(default, raw)
    if raw == nil or raw == "" then return default end
    local t = type(default)
    if t == "boolean" then return raw == "1" end
    if t == "number" then return tonumber(raw) or default end
    return raw
end

local function Encode(value)
    if type(value) == "boolean" then return value and "1" or "0" end
    return tostring(value)
end

function M.Load()
    for k, v in pairs(DEFAULTS) do
        settings[k] = Decode(v, RPR.GetExtState(EXT_SECTION, k))
    end
    revision = revision + 1
end

function M.Get(key)
    local v = settings[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

function M.Set(key, value)
    if settings[key] == value then return end
    settings[key] = value
    RPR.SetExtState(EXT_SECTION, key, Encode(value), true)
    revision = revision + 1
end

function M.ResetSettings()
    for k, v in pairs(DEFAULTS) do M.Set(k, v) end
end

-- 설정·최근·즐겨찾기가 바뀔 때마다 증가 (검색 결과 재계산 트리거)
function M.Revision() return revision end

----------------------------------------------------------
-- 최근 사용 항목 (Most-Recent-First)
----------------------------------------------------------
local recent_list = {}
local recent_rank = {}

local function SplitList(raw)
    local out = {}
    if raw and raw ~= "" then
        for part in raw:gmatch("[^" .. LIST_SEP .. "]+") do out[#out + 1] = part end
    end
    return out
end

local function RebuildRecentRank()
    recent_rank = {}
    for i, key in ipairs(recent_list) do recent_rank[key] = i end
end

local function SaveRecent()
    RPR.SetExtState(EXT_SECTION, "recent", table.concat(recent_list, LIST_SEP), true)
    RebuildRecentRank()
    revision = revision + 1
end

function M.GetRecent() return recent_list end
function M.RecentRank(key) return recent_rank[key] end

function M.PushRecent(key)
    if not key or key == "" then return end
    local out = { key }
    for _, k in ipairs(recent_list) do
        if k ~= key then out[#out + 1] = k end
    end
    local cap = math.max(5, math.floor(M.Get("max_recent")))
    while #out > cap do out[#out] = nil end
    recent_list = out
    SaveRecent()
end

function M.RemoveRecent(key)
    local out = {}
    for _, k in ipairs(recent_list) do
        if k ~= key then out[#out + 1] = k end
    end
    recent_list = out
    SaveRecent()
end

function M.ClearRecent()
    recent_list = {}
    SaveRecent()
end

----------------------------------------------------------
-- 즐겨찾기
----------------------------------------------------------
local favorites = {}
local favorite_order = {}

local function SaveFavorites()
    RPR.SetExtState(EXT_SECTION, "favorites", table.concat(favorite_order, LIST_SEP), true)
    revision = revision + 1
end

function M.IsFavorite(key) return favorites[key] == true end
function M.GetFavorites() return favorite_order end

function M.ToggleFavorite(key)
    if not key then return end
    if favorites[key] then
        favorites[key] = nil
        local out = {}
        for _, k in ipairs(favorite_order) do
            if k ~= key then out[#out + 1] = k end
        end
        favorite_order = out
    else
        favorites[key] = true
        favorite_order[#favorite_order + 1] = key
    end
    SaveFavorites()
end

----------------------------------------------------------
-- 초기 로드
----------------------------------------------------------
M.Load()
recent_list = SplitList(RPR.GetExtState(EXT_SECTION, "recent"))
RebuildRecentRank()
favorite_order = SplitList(RPR.GetExtState(EXT_SECTION, "favorites"))
for _, k in ipairs(favorite_order) do favorites[k] = true end

return M
