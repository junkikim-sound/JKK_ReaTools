--========================================================
-- @title JKK_WindowChrome
-- @author Junki Kim
-- @noindex
-- Shared borderless window chrome for standalone JKK scripts.
-- The host script owns Begin/End and its open/close lifecycle.
--========================================================
local R = reaper
local M = {}

function M.flags()
    return R.ImGui_WindowFlags_NoTitleBar() | R.ImGui_WindowFlags_NoCollapse()
end

-- Returns true when the user presses the custom close button.
-- No BeginChild/EndChild or window scope is introduced, so it can be used
-- safely in each standalone script's existing ImGui_Begin/End scope.
-- subtitle (optional): muted text right after the title (e.g. "Selected 3 Items").
-- Callers that omit it get exactly the previous header.
function M.header(ctx, title, id, subtitle)
    local avail_w = select(1, R.ImGui_GetContentRegionAvail(ctx))
    local start_x = R.ImGui_GetCursorPosX(ctx)
    local button_size = math.max(20, math.min(28, R.ImGui_GetFrameHeight(ctx)))

    R.ImGui_AlignTextToFramePadding(ctx)
    -- Match ReaTools panel headings (e.g. Controller) using the active
    -- JKK Theme's Important Text / text_accent color, not a fixed swatch.
    local theme = rawget(_G, 'JKK_Theme')
    local title_color = 0xE3DB8EFF
    if theme and type(theme.GetColor) == 'function' then
        title_color = theme.GetColor('accent') or title_color
    end
    R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), title_color)
    R.ImGui_Text(ctx, tostring(title))
    R.ImGui_PopStyleColor(ctx, 1)
    if subtitle and subtitle ~= '' then
        local sub_color = 0x9A9A9AFF
        if theme and type(theme.GetColor) == 'function' then
            sub_color = theme.GetColor('status') or sub_color
        end
        R.ImGui_SameLine(ctx, 0, 10)
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), sub_color)
        R.ImGui_Text(ctx, tostring(subtitle))
        R.ImGui_PopStyleColor(ctx, 1)
    end
    R.ImGui_SameLine(ctx, 0, 0)
    R.ImGui_SetCursorPosX(ctx, start_x + math.max(0, avail_w - button_size))
    local close = R.ImGui_Button(ctx, '✕##jkk_header_close_' .. tostring(id), button_size, button_size)
    R.ImGui_Separator(ctx)
    return close
end

return M
