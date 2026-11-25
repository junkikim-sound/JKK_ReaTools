--========================================================
-- @title JKK_Variator_UI
-- @author Junki Kim
-- @noindex
-- ReaImGui view for JKK_Variator. Draws inside the host's Begin/End and
-- only edits settings / calls session + preview methods; all project work
-- happens in JKK_Variator_Session (dirty flag, throttled).
--
-- Wide layout: every parameter is one row
--   [x] Name | Value +/- | Points Min | Points Max | Link | Curve | Randomize
-- Group mode, no preview Loop, Solo Preview on, Preserve Pitch off are fixed
-- (Model.FIXED). Variations opens at 0; Gap right-click toggles seconds / grid.
--========================================================

local R = reaper
local UI = {}

local PARAM_TITLES = { volume = "Volume", pan = "Pan", pitch = "Pitch", playrate = "Playrate" }
local VALUE_FMT = {
    volume   = "± %.1f dB",
    pan      = "± %.0f%%",
    pitch    = "± %.1f st",
    playrate = "± %.0f%%",
}

function UI.Create(deps)
    local Theme, Session, Preview, Undo = deps.theme, deps.session, deps.preview, deps.undo
    local Model, Layout = Session.Model, Session.Layout
    local view = {}

    local app = {
        session = nil, info = nil, preview = nil,
        msg = nil, confirm = nil, confirm_open = false,
        nav_index = 0, reset_counter = 0, close = false,
    }
    view.app = app

    function view.SetSession(session, info)
        app.session, app.info = session, info
        if session then
            app.preview = Preview.new(session.proj)
            session.on_layout_change = function()
                if app.preview and app.preview:is_playing() then app.preview:stop() end
            end
        end
    end

    -- Header subtitle: "Selected N Items" (nil when there is no session)
    function view.HeaderInfo()
        local session = app.session
        if not session then
            if app.info and app.info.empty then return "No items selected." end
            return nil
        end
        if session.aborted then return nil end
        local n = #session.snaps
        return string.format("Selected %d Item%s", n, n == 1 and "" or "s")
    end

    ------------------------------------------------------
    -- small helpers
    ------------------------------------------------------
    local s = 1
    local function S(v) return v * s end

    local function text_w(ctx, t)
        local w = R.ImGui_CalcTextSize(ctx, t)
        return w or 0
    end

    local function text_muted(ctx, t)
        R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), Theme.GetColor("status"))
        R.ImGui_TextWrapped(ctx, t)
        R.ImGui_PopStyleColor(ctx, 1)
    end

    local function text_warn(ctx, t)
        Theme.PushText(ctx, "accent")
        R.ImGui_TextWrapped(ctx, t)
        Theme.PopText(ctx)
    end

    -- Centered single line (wraps normally when wider than the window).
    -- kind: "muted" | "warn"
    local function text_center(ctx, t, kind)
        local x0 = R.ImGui_GetCursorPosX(ctx)
        local avail = select(1, R.ImGui_GetContentRegionAvail(ctx))
        local w = text_w(ctx, t)
        if kind == "warn" then Theme.PushText(ctx, "accent")
        else R.ImGui_PushStyleColor(ctx, R.ImGui_Col_Text(), Theme.GetColor("status")) end
        if w <= avail then
            R.ImGui_SetCursorPosX(ctx, x0 + math.floor((avail - w) / 2))
            R.ImGui_Text(ctx, t)
        else
            R.ImGui_TextWrapped(ctx, t)
        end
        if kind == "warn" then Theme.PopText(ctx) else R.ImGui_PopStyleColor(ctx, 1) end
    end

    -- Only the Link checkbox has a tooltip.
    local function tooltip(ctx, t)
        if R.ImGui_IsItemHovered(ctx, R.ImGui_HoveredFlags_AllowWhenDisabled()) then R.ImGui_SetTooltip(ctx, t) end
    end

    local function ask(title, text, ok_label, on_ok)
        app.confirm = { title = title, text = text, ok = ok_label, on_ok = on_ok }
        app.confirm_open = false
    end

    local function stop_preview()
        if app.preview then app.preview:stop() end
    end

    ------------------------------------------------------
    -- preview control (Solo Preview always on, never loops)
    ------------------------------------------------------
    local function solo_tracks(session)
        local list, seen = {}, {}
        for _, sp in ipairs(session.snaps) do
            if not seen[sp.track] then seen[sp.track] = true; list[#list + 1] = sp.track end
        end
        return list
    end

    local function start_preview(index)
        local session = app.session
        if session.paused then return end
        if session.dirty then session:update() end
        local layout = session.layout
        if not layout or #layout.sets == 0 then return end
        local a, b = Layout.preview_range(layout, session.model.settings.include_original, index)
        local ok, err = app.preview:start(a, b, { loop = false, solo_tracks = solo_tracks(session), index = index })
        app.msg = (not ok) and err or nil
        if ok and index then app.nav_index, app.heard = index, index end
    end

    local function toggle_preview()
        if app.preview:is_playing() then stop_preview() else start_preview(nil) end
    end

    -- ◀ / ▶ step from the variation that is playing right now (or was heard
    -- last), and wrap around at both ends.
    local function nav(delta)
        local session = app.session
        local n = session.layout and #session.layout.sets or 0
        if n == 0 then return end
        local cur = app.preview:is_playing() and app.preview.current or nil
        local base = cur or app.heard or 0
        local i = base + delta
        if i < 1 then i = n end
        if i > n then i = 1 end
        start_preview(i)
    end

    ------------------------------------------------------
    -- actions
    ------------------------------------------------------
    local function do_reset()
        local session = app.session
        stop_preview()
        app.reset_counter = app.reset_counter + 1
        local count = session.model.settings.count      -- Reset keeps the number of variations
        session.model:reset(session.model.seed + 7919 * app.reset_counter)
        session.model.settings.count = count
        app.nav_index, app.heard = 0, nil
        session:mark()
    end

    local function do_apply()
        local session = app.session
        stop_preview()
        local ok, err = session:apply(Undo.Label("variator.apply"), Undo.Label("variator.apply_failed"))
        if ok then
            Session.save_settings(session.model.settings)
            app.close = true
        else
            app.msg = err
        end
    end

    ------------------------------------------------------
    -- layout metrics (column grid shared by every row)
    ------------------------------------------------------
    local M = {}
    local function metrics(ctx)
        M.x0 = R.ImGui_GetCursorPosX(ctx)
        M.avail = select(1, R.ImGui_GetContentRegionAvail(ctx))
        M.fh = R.ImGui_GetFrameHeight(ctx)
        M.sp = select(1, R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_ItemSpacing()))
        M.inner = select(1, R.ImGui_GetStyleVar(ctx, R.ImGui_StyleVar_ItemInnerSpacing()))
        M.nav_w = math.floor(M.fh * 1.25)
        -- column A: enable checkbox + name (also row labels)
        -- text_w(): width only (CalcTextSize returns several values; never pass it as a last argument)
        M.colA = math.floor(M.fh + M.inner + text_w(ctx, "Playrate") + S(16))
        M.link_w = math.floor(M.fh + M.inner + text_w(ctx, "Link"))
        M.curve_w = math.floor(text_w(ctx, "Smooth") + S(24))
        M.rb = math.floor(M.fh * 1.4)
        local rest = M.avail - M.colA - M.link_w - M.curve_w - M.rb - 5 * M.sp
        M.wB = math.floor(rest * 0.4)
        M.wC = math.floor((rest - M.wB) / 2)
        M.wC2 = rest - M.wB - M.wC
        M.xB = M.x0 + M.colA
        M.xC = M.xB + M.wB + M.sp
        M.xLink = M.xC + M.wC + M.sp + M.wC2 + M.sp
    end

    local function row_label(ctx, label)
        R.ImGui_SetCursorPosX(ctx, M.x0)
        R.ImGui_AlignTextToFramePadding(ctx)
        R.ImGui_Text(ctx, label)
        R.ImGui_SameLine(ctx, 0, 0)
        R.ImGui_SetCursorPosX(ctx, M.xB)
    end

    ------------------------------------------------------
    -- sections
    ------------------------------------------------------
    -- Right-click on a slider = back to its initial value.
    local function right_clicked(ctx) return R.ImGui_IsItemClicked(ctx, 1) end

    local function draw_top(ctx, session)
        local st = session.model.settings
        -- Variations + Gap centered in the window (item count is in the header);
        -- a little extra space above so the gap matches the one below the row
        R.ImGui_SetCursorPosY(ctx, R.ImGui_GetCursorPosY(ctx) + S(4))
        R.ImGui_SetCursorPosX(ctx, M.x0 + math.floor((M.avail - (2 * M.wB + M.sp)) / 2))

        local min_count = session.model:max_locked_k()
        R.ImGui_SetNextItemWidth(ctx, M.wB)
        local ch, v = R.ImGui_SliderInt(ctx, "##count", st.count, min_count, Model.COUNT_MAX, "Variations %d",
            R.ImGui_SliderFlags_AlwaysClamp())
        if ch then st.count = math.max(min_count, v); session:mark() end
        if right_clicked(ctx) and st.count ~= min_count then st.count = min_count; session:mark() end

        -- Gap: seconds after each set, or N grid steps from the left edge of all
        -- originals. Right-click on Gap switches seconds / grid (not a reset).
        R.ImGui_SameLine(ctx, 0, M.sp)
        R.ImGui_SetNextItemWidth(ctx, M.wB)
        if st.gap_mode == "grid" then
            local chg, n = R.ImGui_SliderInt(ctx, "##gapgrid", st.gap_grid, 1, Model.GAP_GRID_MAX,
                "Gap %d", R.ImGui_SliderFlags_AlwaysClamp())
            if chg then st.gap_grid = math.max(1, n); session:mark() end
        else
            local chg, g = R.ImGui_SliderDouble(ctx, "##gap", st.gap, 0, Model.GAP_MAX, "Gap %.2f s")
            if chg then st.gap = math.max(0, g); session:mark() end
        end
        if R.ImGui_IsItemClicked(ctx, 1) then
            st.gap_mode = (st.gap_mode == "grid") and "time" or "grid"
            session:mark()
        end
    end

    local function param_messages(session, name)
        local seen, out = {}, {}
        for _, e in ipairs(session.status.errors) do
            if e.param == name and not seen[e.msg] then
                seen[e.msg] = true
                out[#out + 1] = e.msg .. ((e.item ~= "") and (" (" .. e.item .. ")") or "")
            end
        end
        local c = session.status.clamped[name]
        if c then
            out[#out + 1] = string.format("Limited to the valid range on %d clone%s.", c, c == 1 and "" or "s")
        end
        return out
    end

    local function draw_param(ctx, session, name)
        local p = session.model.settings.params[name]
        local clamp_flag = R.ImGui_SliderFlags_AlwaysClamp()
        R.ImGui_PushID(ctx, name)

        R.ImGui_SetCursorPosX(ctx, M.x0)
        local ch, en = R.ImGui_Checkbox(ctx, PARAM_TITLES[name], p.enabled)
        if ch then p.enabled = en; session:mark() end
        R.ImGui_SameLine(ctx, 0, 0)
        R.ImGui_SetCursorPosX(ctx, M.xB)

        R.ImGui_BeginDisabled(ctx, not p.enabled)
        R.ImGui_SetNextItemWidth(ctx, M.wB)
        local c1, amt = R.ImGui_SliderDouble(ctx, "##amount", p.amount, 0, Model.AMOUNT_MAX[name], VALUE_FMT[name], clamp_flag)
        if c1 then p.amount = amt; Model.sanitize_param(name, p); session:mark() end
        if right_clicked(ctx) then p.amount = Model.DEFAULT_AMOUNT[name]; Model.sanitize_param(name, p); session:mark() end

        R.ImGui_SameLine(ctx, 0, M.sp)
        R.ImGui_SetNextItemWidth(ctx, M.wC)
        local c3, pmin = R.ImGui_SliderInt(ctx, "##pmin", p.pmin, 0, Model.POINTS_MAX, "Points Min %d", clamp_flag)
        if c3 then p.pmin = pmin; Model.sanitize_param(name, p, "pmin"); session:mark() end
        if right_clicked(ctx) then p.pmin = 0; Model.sanitize_param(name, p, "pmin"); session:mark() end
        R.ImGui_SameLine(ctx, 0, M.sp)
        R.ImGui_SetNextItemWidth(ctx, M.wC2)
        local c4, pmax = R.ImGui_SliderInt(ctx, "##pmax", p.pmax, 0, Model.POINTS_MAX, "Points Max %d", clamp_flag)
        if c4 then p.pmax = pmax; Model.sanitize_param(name, p, "pmax"); session:mark() end
        -- Points Max reset to 0 also pulls Min down to 0 (sanitize limits the edited side)
        if right_clicked(ctx) then p.pmax = 0; Model.sanitize_param(name, p, "pmax"); session:mark() end

        R.ImGui_SameLine(ctx, 0, 0)
        R.ImGui_SetCursorPosX(ctx, M.xLink)
        local c5, link = R.ImGui_Checkbox(ctx, "Link", p.link)
        if c5 then p.link = link; session:mark() end
        tooltip(ctx, "Share one random sample across the layers of a set.")

        if name ~= "playrate" then
            R.ImGui_SameLine(ctx, 0, M.sp)
            if R.ImGui_Button(ctx, (p.curve == "smooth" and "Smooth" or "Linear") .. "##curve", M.curve_w, M.fh) then
                p.curve = (p.curve == "smooth") and "linear" or "smooth"
                session:mark()
            end
        end

        R.ImGui_SameLine(ctx, 0, 0)
        R.ImGui_SetCursorPosX(ctx, M.x0 + M.avail - M.rb)
        if R.ImGui_Button(ctx, "↻##rnd", M.rb, M.fh) then
            session.model:randomize(name)
            session:mark()
        end
        R.ImGui_EndDisabled(ctx)

        if p.enabled then
            for _, m in ipairs(param_messages(session, name)) do
                R.ImGui_SetCursorPosX(ctx, M.xB)
                text_warn(ctx, m)
            end
        end
        R.ImGui_PopID(ctx)
    end

    -- natural spacing (not aligned to the slider columns)
    local function draw_options(ctx, session)
        local st = session.model.settings
        local gap = S(20)
        R.ImGui_SetCursorPosX(ctx, M.x0)
        local c1, ko = R.ImGui_Checkbox(ctx, "Keep Original", st.keep_original)
        if c1 then st.keep_original = ko end
        R.ImGui_SameLine(ctx, 0, gap)
        local c2, ar = R.ImGui_Checkbox(ctx, "Auto Rename", st.auto_rename)
        if c2 then st.auto_rename = ar; session:mark() end
        R.ImGui_SameLine(ctx, 0, gap)
        local c3, inc = R.ImGui_Checkbox(ctx, "Include Original", st.include_original)
        if c3 then st.include_original = inc end
        if not st.keep_original then
            text_warn(ctx, string.format("Apply will remove the %d original item%s.", #session.snaps, #session.snaps == 1 and "" or "s"))
        end
    end

    -- ◀ [Preview (Space)] ▶, centered in the window
    local function draw_preview(ctx, session)
        local playing = app.preview:is_playing()
        local transport_w = M.colA + M.wB
        R.ImGui_SetCursorPosX(ctx, M.x0 + math.floor((M.avail - transport_w) / 2))
        if Theme.NavButton(ctx, "##prev_set", "left", M.nav_w, M.fh) then nav(-1) end
        R.ImGui_SameLine(ctx, 0, M.sp)
        if playing then Theme.PushButton(ctx, "highlight") end
        if R.ImGui_Button(ctx, (playing and "Stop" or "Preview") .. " (Space)##transport", transport_w - 2 * M.nav_w - 2 * M.sp, M.fh) then
            toggle_preview()
        end
        if playing then Theme.PopButton(ctx) end
        R.ImGui_SameLine(ctx, 0, M.sp)
        if Theme.NavButton(ctx, "##next_set", "right", M.nav_w, M.fh) then nav(1) end
        if app.msg then text_warn(ctx, app.msg) end
    end

    local function lock_button(ctx, session, unit, label, w, src_list, playing)
        local locked = session.model:is_locked(unit)
        local kind = locked and "highlight" or (playing and "confirm" or nil)
        if kind then Theme.PushButton(ctx, kind) end
        if R.ImGui_Button(ctx, label .. "##lk_" .. unit, w, M.fh) then
            if locked then session.model:unlock(unit) else session.model:lock(unit, src_list) end
            session:mark()
        end
        if kind then Theme.PopButton(ctx) end
    end

    -- Lock buttons (one per variation), centered, right above the action buttons
    local function draw_locks(ctx, session)
        local count = session.model.settings.count
        if count < 1 then
            -- same height as one row of Lock buttons, so nothing jumps when they appear
            local y = R.ImGui_GetCursorPosY(ctx)
            local th = select(2, R.ImGui_CalcTextSize(ctx, "Set Variations to 1 or more.")) or M.fh
            R.ImGui_SetCursorPosY(ctx, y + math.floor((M.fh - th) / 2))
            text_center(ctx, "Set Variations to 1 or more.", "muted")
            R.ImGui_SetCursorPosY(ctx, y)
            R.ImGui_Dummy(ctx, 1, M.fh)
            return
        end
        local bw = math.floor(text_w(ctx, "00") + S(14))
        local playing_set = app.preview and app.preview:is_playing() and app.preview.current or nil
        local all = {}
        for i = 1, #session.snaps do all[i] = i end
        local per_row = math.max(1, math.floor((M.avail + M.sp) / (bw + M.sp)))
        local k = 1
        while k <= count do
            local n = math.min(per_row, count - k + 1)
            local row_w = n * bw + (n - 1) * M.sp
            R.ImGui_SetCursorPosX(ctx, M.x0 + math.floor((M.avail - row_w) / 2))
            for j = 0, n - 1 do
                if j > 0 then R.ImGui_SameLine(ctx, 0, M.sp) end
                local kk = k + j
                lock_button(ctx, session, Layout.unit_key("group", nil, kk), string.format("%02d", kk), bw, all, playing_set == kk)
            end
            k = k + n
        end
    end

    local function draw_status(ctx, session)
        local w = session.status.warnings or {}
        local n_col = #session.status.collisions
        if n_col > 0 then
            text_warn(ctx, string.format("%d clone%s overlap existing items. Increase Gap or move those items.",
                n_col, n_col == 1 and "" or "s"))
        end
        for _, e in ipairs(session.status.errors) do
            if e.param == "session" or e.param == "item" then text_warn(ctx, e.msg) end
        end
        if w.original_changed then text_warn(ctx, "An original item was moved or resized. Results still use the start snapshot.") end
        if w.foreign_undo then text_center(ctx, "Other edits were made during this session; undoing them may bring back preview clones.", "muted") end
        local can, why = session:can_apply()
        -- the "Variations 0" hint lives in the Lock row instead
        if not can and why and why ~= "Updating..." and session.model.settings.count >= 1 then text_warn(ctx, why) end
    end

    local function draw_buttons(ctx, session)
        local can = session:can_apply()
        local bh = math.floor(M.fh * 1.6)
        local rnd_w = math.floor(M.colA + M.wB)
        local reset_w = math.floor(M.wC)
        -- order: Reset | Randomize | Apply
        R.ImGui_SetCursorPosX(ctx, M.x0)
        if R.ImGui_Button(ctx, "Reset##all", reset_w, bh) then
            if session.model:any_locked() then
                ask("Reset", "Reset clears every Lock and restores the default settings with new random results.",
                    "Reset", do_reset)
            else
                do_reset()
            end
        end
        R.ImGui_SameLine(ctx, 0, M.sp)
        Theme.PushButton(ctx, "primary")
        if R.ImGui_Button(ctx, "Randomize##all", rnd_w - M.sp, bh) then
            session.model:randomize(nil)
            session:mark()
        end
        Theme.PopButton(ctx)

        R.ImGui_SameLine(ctx, 0, M.sp)
        R.ImGui_BeginDisabled(ctx, not can)
        Theme.PushButton(ctx, "confirm")
        local apply_w = M.x0 + M.avail - R.ImGui_GetCursorPosX(ctx)
        if R.ImGui_Button(ctx, "Apply##apply", apply_w, bh) then
            if not session.model.settings.keep_original then
                ask("Apply", string.format("Apply creates the clones and removes the %d original item%s.\nOne Undo restores everything.",
                    #session.snaps, #session.snaps == 1 and "" or "s"), "Apply", do_apply)
            else
                do_apply()
            end
        end
        Theme.PopButton(ctx)
        R.ImGui_EndDisabled(ctx)
    end

    local function draw_confirm(ctx)
        local c = app.confirm
        if not c then return end
        local id = "##variator_confirm"
        if not app.confirm_open then
            R.ImGui_OpenPopup(ctx, id)
            app.confirm_open = true
        end
        local flags = R.ImGui_WindowFlags_AlwaysAutoResize() | R.ImGui_WindowFlags_NoTitleBar() | R.ImGui_WindowFlags_NoMove()
        if R.ImGui_BeginPopupModal(ctx, id, nil, flags) then
            Theme.PushText(ctx, "accent")
            R.ImGui_Text(ctx, c.title)
            Theme.PopText(ctx)
            R.ImGui_Separator(ctx)
            R.ImGui_Text(ctx, c.text)
            R.ImGui_Spacing(ctx)
            local tw = math.max(text_w(ctx, c.text), S(260))
            local bw = math.floor((tw - M.sp) / 2)
            local done, run = false, false
            Theme.PushButton(ctx, "confirm")
            if R.ImGui_Button(ctx, c.ok .. "##cf_ok", bw, M.fh) then done, run = true, true end
            Theme.PopButton(ctx)
            R.ImGui_SameLine(ctx, 0, M.sp)
            if R.ImGui_Button(ctx, "Cancel##cf_cancel", tw - bw - M.sp, M.fh) then done = true end
            if R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape(), false) then done = true end
            if done then
                R.ImGui_CloseCurrentPopup(ctx)
                app.confirm, app.confirm_open = nil, false
                if run then c.on_ok() end
            end
            R.ImGui_EndPopup(ctx)
        else
            app.confirm, app.confirm_open = nil, false
        end
    end

    local function draw_info(ctx, info)
        metrics(ctx)
        if info and info.empty then
            -- "No items selected." is shown in the header
            text_center(ctx, "Select one or more audio items, then run JKK Variator again.", "muted")
        elseif info and info.unsupported then
            text_warn(ctx, "Some selected items cannot be varied. Nothing was created.")
            for i, u in ipairs(info.unsupported) do
                if i > 12 then text_muted(ctx, string.format("... and %d more", #info.unsupported - 12)); break end
                R.ImGui_TextWrapped(ctx, "- " .. u.label .. ": " .. u.reason)
            end
            text_muted(ctx, "Deselect those items and run JKK Variator again.")
        elseif info and info.aborted then
            text_warn(ctx, info.aborted)
        end
        R.ImGui_Spacing(ctx)
        if R.ImGui_Button(ctx, "Close##info_close", M.avail, M.fh) then app.close = true end
    end

    ------------------------------------------------------
    -- frame
    ------------------------------------------------------
    -- Returns true when the window should close (Cancel or after Apply).
    function view.Draw(ctx, scale)
        s = scale or 1
        local session = app.session
        if not session or session.aborted then
            draw_info(ctx, session and { aborted = session.aborted } or app.info)
        else
            metrics(ctx)
            app.preview:tick(function(t) return session.layout and Layout.set_at(session.layout, t) end)
            -- remember the last variation actually heard (◀ / ▶ step from it)
            if app.preview:is_playing() and app.preview.current and app.preview.current >= 1 then
                app.heard = app.preview.current
            end
            if session.paused and app.preview:is_playing() then stop_preview() end

            R.ImGui_BeginDisabled(ctx, session.paused)
            draw_top(ctx, session)
            R.ImGui_Separator(ctx)
            for _, name in ipairs(Model.PARAMS) do draw_param(ctx, session, name) end
            R.ImGui_Separator(ctx)
            draw_options(ctx, session)
            R.ImGui_Separator(ctx)
            draw_status(ctx, session)
            draw_preview(ctx, session)
            draw_locks(ctx, session)
            draw_buttons(ctx, session)
            R.ImGui_EndDisabled(ctx)
            if session.paused then text_warn(ctx, "The session project is not active. Switch back to continue.") end
            draw_confirm(ctx)

            -- keyboard: Space = preview toggle, Esc = cancel (window focus, no active widget/popup)
            local focused = R.ImGui_IsWindowFocused(ctx, R.ImGui_FocusedFlags_RootAndChildWindows())
            if focused and not app.confirm and not R.ImGui_IsAnyItemActive(ctx) then
                if R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Space(), false) and not session.paused then toggle_preview() end
                if R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape(), false) then app.close = true end
            end
            session:tick(R.ImGui_IsMouseDown(ctx, 0) and R.ImGui_IsAnyItemActive(ctx))
        end
        if not session or session.aborted then
            local focused = R.ImGui_IsWindowFocused(ctx, R.ImGui_FocusedFlags_RootAndChildWindows())
            if focused and R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape(), false) then app.close = true end
        end
        return app.close
    end

    -- Every non-Apply exit path ends here (idempotent).
    function view.Shutdown()
        local session = app.session
        if app.preview then pcall(function() app.preview:stop() end) end
        if session then
            if not session.committed then pcall(function() session:cancel() end) end
            pcall(Session.save_settings, session.model.settings)
        end
    end

    return view
end

return UI
