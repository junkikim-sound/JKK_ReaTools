--========================================================
-- @title JKK_I18n
-- @author Junki Kim
-- @noindex
--========================================================
-- Shared UI language for every JKK script.
--   ExtState "JKK_ReaTools" / "language" = "en" | "ko"  (persisted)
-- Only long explanatory English (tooltips, descriptions) is translated.
-- Short UI words ("Volume", "Gap", "Group", ...) stay English on purpose.
--
-- Usage:
--   local I18n = dofile(module_dir .. "JKK_I18n.lua")
--   reaper.ImGui_SetTooltip(ctx, I18n.T("English sentence"))
-- T() returns the Korean text when the language is "ko" and a translation
-- exists, otherwise the original English.  The language is re-read from
-- ExtState at most every 0.25 s, so a switch made in another script (or in
-- another copy of this module) applies live without any per-call cost.

local reaper = reaper

local I18n = {}

local SECTION, KEY = "JKK_ReaTools", "language"
local POLL_INTERVAL = 0.25

I18n.LANGUAGES = {
    { id = "en", label = "English" },
    { id = "ko", label = "한국어" },
}

local cached_lang = nil
local last_poll = -1

local function Now()
    return (reaper.time_precise and reaper.time_precise()) or os.clock()
end

function I18n.GetLanguage()
    local now = Now()
    if cached_lang == nil or (now - last_poll) >= POLL_INTERVAL then
        last_poll = now
        local v = reaper.GetExtState(SECTION, KEY)
        cached_lang = (v == "ko") and "ko" or "en"
    end
    return cached_lang
end

function I18n.SetLanguage(lang)
    lang = (lang == "ko") and "ko" or "en"
    reaper.SetExtState(SECTION, KEY, lang, true)
    cached_lang = lang
    last_poll = Now()
end

function I18n.IsKorean()
    return I18n.GetLanguage() == "ko"
end

---------------------------------------------------------
-- Korean table (key = exact English text used in code)
---------------------------------------------------------
local ko = {
    ------------------------------------------------ JKK_ReaTools (main)
    ["Selection & Range Detection"] = "선택 항목 감지 방법 설정",
    ["Drag onto another panel title to swap their places."]
        = "다른 패널 제목 위로 드래그하면 두 패널의 위치가 서로 바뀝니다.",
    ["Relative: each item/track keeps its own value and moves by the same amount"]
        = "Relative: 각 아이템/트랙이 자기 값을 유지한 채 같은 양만큼 변경됩니다",
    ["Absolute: every selected item/track gets the same value"]
        = "Absolute: 선택한 모든 아이템/트랙에 같은 값이 적용됩니다",
    ["Choose what to target when Time Selection changes:\n- Ignore: Do not change target mode\n- Regions / Markers: Target regions & markers inside range\n- Items in Range: Auto-select media items overlapping range"]
        = "Time Selection이 바뀔 때 무엇을 대상으로 할지 선택합니다:\n- Ignore: 대상 모드를 바꾸지 않음\n- Regions / Markers: 범위 안의 리전/마커를 대상으로 함\n- Items in Range: 범위와 겹치는 미디어 아이템을 자동 선택",
    ["Choose what to target when Loop Points change:\n- Ignore: Do not change target mode\n- Regions / Markers: Target regions & markers inside loop\n- Items in Range: Auto-select media items overlapping loop"]
        = "Loop Points가 바뀔 때 무엇을 대상으로 할지 선택합니다:\n- Ignore: 대상 모드를 바꾸지 않음\n- Regions / Markers: 루프 안의 리전/마커를 대상으로 함\n- Items in Range: 루프와 겹치는 미디어 아이템을 자동 선택",
    ["When on, clicking an item in the arrange view also selects its track."]
        = "켜면 어레인지 뷰에서 아이템을 클릭할 때 그 아이템의 트랙도 함께 선택됩니다.",
    ["Language for long tooltips and descriptions.\nShort UI labels stay in English."]
        = "긴 툴팁과 설명문의 언어입니다.\n짧은 UI 이름은 영어 그대로 표시됩니다.",
    ["All panels are hidden. Turn them on in Settings."]
        = "모든 패널이 숨겨져 있습니다. Settings에서 패널을 켜주세요.",

    ------------------------------------------------ RenamerLite
    ["Click: one region around each group of overlapping items (longest extent),\nnamed from the text field\nShift+Click: one region per item, named after the item"]
        = "클릭: 겹치는 아이템 묶음마다 리전을 하나씩 만듭니다 (가장 긴 범위 기준).\n이름은 텍스트 필드의 내용을 사용합니다.\nShift+클릭: 아이템마다 리전을 하나씩 만들고, 아이템 이름을 리전 이름으로 사용합니다.",

    ------------------------------------------------ ItemTool
    ["Checked: End-to-Start\nUnchecked: Start-to-Start"]
        = "체크: 앞 아이템의 끝 ~ 다음 아이템의 시작 사이 간격 (End-to-Start)\n해제: 아이템 시작점 ~ 시작점 사이 간격 (Start-to-Start)",
    ["Checked: Move overlapping items as one group\nUnchecked: Move items individually"]
        = "체크: 겹치는 아이템들을 한 그룹으로 묶어서 이동\n해제: 아이템을 하나씩 개별로 이동",
    ["Use each item's first visible take marker as its arrange point (falls back to the item start if there is none).\nGroup ON: overlapping items move as one group, markers aligned within it.\nGroup OFF: items are placed one by one from the left, marker to marker."]
        = "각 아이템에서 처음 보이는 테이크 마커를 정렬 기준점으로 사용합니다 (마커가 없으면 아이템 시작점).\nGroup ON: 겹치는 아이템이 한 그룹으로 이동하고, 그룹 안에서 마커끼리 정렬됩니다.\nGroup OFF: 왼쪽부터 아이템을 하나씩 마커 대 마커로 배치합니다.",
    ["One take marker per non-silent region using Split Dyn's current Threshold / Min Length.\nEach marker is placed at the loudest audio sample in that region.\nNo items are moved. Existing user markers are preserved."]
        = "Split Dyn의 현재 Threshold / Min Length 기준으로, 소리가 있는 구간마다 테이크 마커를 하나씩 추가합니다.\n마커는 그 구간에서 가장 큰 샘플 위치에 놓입니다.\n아이템은 움직이지 않으며, 기존에 직접 만든 마커는 유지됩니다.",
    ["Delete ALL take markers from every take of the selected items.\nManual markers are also deleted. Undo is supported."]
        = "선택한 아이템의 모든 테이크에서 테이크 마커를 전부 삭제합니다.\n직접 만든 마커도 함께 삭제됩니다. Undo로 되돌릴 수 있습니다.",
    ["Right-click to toggle (Grid -> Sec -> RPM)"] = "우클릭으로 단위 전환 (Grid -> Sec -> RPM)",
    ["Right-click to toggle (Grid <-> Sec)"] = "우클릭으로 단위 전환 (Grid <-> Sec)",

    -- JKK_Search registers its own strings with I18n.Add() (JKK_Search_UI.lua).
}

I18n.ko = ko

function I18n.T(text)
    if text == nil then return "" end
    if I18n.GetLanguage() ~= "ko" then return text end
    return ko[text] or text
end

-- Register extra translations from another module (only fills missing keys).
function I18n.Add(tbl)
    if type(tbl) ~= "table" then return end
    for k, v in pairs(tbl) do
        if ko[k] == nil then ko[k] = v end
    end
end

return I18n
