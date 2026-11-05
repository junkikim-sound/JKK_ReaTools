--========================================================
-- @title JKK_Renderer
-- @author Junki Kim
-- @version 1.0.0
-- @provides 
--     [nomain] Modules/JKK_Theme.lua
--========================================================

local r = reaper

local ctx = r.ImGui_CreateContext("JKK_Render")
local font = r.ImGui_CreateFont('Arial', 14)
local font_btn = r.ImGui_CreateFont('Arial', 18)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_btn)

-- =======================================================
-- Theme Module Integration
-- =======================================================
local theme_path = r.GetResourcePath() .. "/Scripts/JKK_ReaTools/JKK_ReaTools/Modules/JKK_Theme.lua"
local ApplyTheme = (r.file_exists(theme_path) and dofile(theme_path).ApplyTheme) or function(ctx) return 0, 0 end

-- Format Lists
local src_list = " Master mix\0 Selected tracks (stems)\0 Selected Regions (Matrix)\0 Selected Regions (Time Selection)\0 Selected media items (Grouped)\0 Selected media items (Separately)\0"
local bnd_list = " Entire project\0 Time selection\0"
local sr_items = {"8000", "11025", "16000", "22050", "32000", "44100", "48000", "88200", "96000", "176400", "192000"}
local sr_values = {8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000}
local format_list = " WAV\0 AIFF\0 FLAC\0 MP3\0 OGG Opus\0 OGG Vorbis\0 Video (MP4)\0"

local vid_size_list = " UHD (3840 x 2160)\0 QHD (2560 x 1440)\0 FHD (1920 x 1080)\0 HD (1024 x 720)\0 SD (640 x 480)\0"
local vid_sizes_w = {3840, 2560, 1920, 1024, 640}
local vid_sizes_h = {2160, 1440, 1080, 720, 480}

local vid_fps_list = " 24fps\0 25fps\0 29.97fps\0 50fps\0 59.94fps\0 60fps\0"
local vid_fps_vals = {24, 25, 29.97, 50, 59.94, 60}

local fade_shape_names = {
  "Linear",
  "Inverted quadratic",
  "Quadratic",
  "Inverted quartic",
  "Quartic",
  "Cosine S-curve",
  "Quartic S-curve"
}

-- 탭 기본 데이터 생성
local function CreateDefaultTabState(name)
  return {
    name = name or "Render 1",
    render_source = 4,
    render_bounds = 0,
    bounds_start = 0.0,
    bounds_end = 0.0,
    sr_idx = 7,       -- 7 = 48000 (0 = Auto)
    custom_sr = 48000,
    channels = 2,     -- 2 = Stereo (0 = Auto)
    format_idx = 0,
    bit_depth_idx = 2,
    opus_bitrate = 256,
    vorbis_quality = 0.80,
    vid_size_idx = 2,
    vid_fps_idx = 5,
    file_directory = r.GetProjectPath("") .. "/Rendered",
    file_pattern = "$item",
    enable_tail = false,
    tail_len = 1.000,
    enable_fadein = false,
    fadein_len = 0.000,
    fadein_shape = 0,
    enable_fadeout = false,
    fadeout_len = 0.000,
    fadeout_shape = 0,
    enable_norm = false,
    norm_val = -24.0,
    enable_limit = false,
    limit_val = 0.0,
    via_master = false,
    embed_take_marker = true,
    preserve_meta = true,
    embed_meta = false,
    auto_close = false,
    add_to_proj = false,
    add_to_queue = false,
    enter_to_render = false,
    open_folder = false,
  }
end

local tabs = { CreateDefaultTabState("Default") }
local favorites = {}
local active_tab_idx = 1
local rename_tab_target = nil
local rename_input_buf = ""
local fav_name_buf = ""
local open = true

-- =======================================================
-- SAVE / LOAD SYSTEM (REAPER ExtState)
-- =======================================================
local function SerializeTable(val)
  local t = type(val)
  if t == "number" or t == "boolean" then
    return tostring(val)
  elseif t == "string" then
    return string.format("%q", val)
  elseif t == "table" then
    local str = "{"
    for k, v in pairs(val) do
      local k_str = type(k) == "number" and "["..k.."]" or '["'..k..'"]'
      str = str .. k_str .. "=" .. SerializeTable(v) .. ","
    end
    return str .. "}"
  else
    return "nil"
  end
end

local function SaveAllExtState()
  r.SetExtState("JKK_CustomRender", "TabData", SerializeTable(tabs), true)
  r.SetExtState("JKK_CustomRender", "FavData", SerializeTable(favorites), true)
  r.SetExtState("JKK_CustomRender", "DataVersion", "2", true)
end

local function LoadAllExtState()
  if r.HasExtState("JKK_CustomRender", "TabData") then
    local str = r.GetExtState("JKK_CustomRender", "TabData")
    if str and str ~= "" then
      local func = load("return " .. str)
      if func then
        local success, loaded_tabs = pcall(func)
        if success and type(loaded_tabs) == "table" and #loaded_tabs > 0 then tabs = loaded_tabs end
      end
    end
  end
  if r.HasExtState("JKK_CustomRender", "FavData") then
    local str = r.GetExtState("JKK_CustomRender", "FavData")
    if str and str ~= "" then
      local func = load("return " .. str)
      if func then
        local success, loaded_favs = pcall(func)
        if success and type(loaded_favs) == "table" then favorites = loaded_favs end
      end
    end
  end

  if r.GetExtState("JKK_CustomRender", "DataVersion") ~= "2" then
    if r.HasExtState("JKK_CustomRender", "TabData") then
      for _, tab in ipairs(tabs) do
        if tab.render_source == 3 then
          tab.render_source = 4
        elseif tab.render_source == 4 then
          tab.render_source = 5
        end
      end
    end
  end
end

LoadAllExtState()
r.atexit(SaveAllExtState)

-- =======================================================
-- HELPER FUNCTIONS
-- =======================================================
local function Base64Encode(data)
  local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local result = {}
  for i = 1, #data, 3 do
    local a = data:byte(i) or 0
    local b = data:byte(i + 1) or 0
    local c = data:byte(i + 2) or 0
    local n = (a << 16) | (b << 8) | c
    local i1 = ((n >> 18) & 63) + 1
    local i2 = ((n >> 12) & 63) + 1
    local i3 = ((n >> 6) & 63) + 1
    local i4 = (n & 63) + 1
    result[#result + 1] = alphabet:sub(i1, i1)
    result[#result + 1] = alphabet:sub(i2, i2)
    result[#result + 1] = (i + 1 <= #data) and alphabet:sub(i3, i3) or '='
    result[#result + 1] = (i + 2 <= #data) and alphabet:sub(i4, i4) or '='
  end
  return table.concat(result)
end

local function GetRenderFormatString(tab)
  local fmt = tab.format_idx
  local raw_cfg

  if fmt == 0 then
    local depth_map = { [0]=8, [1]=16, [2]=24, [3]=0x21, [4]=0x20, [5]=0x40 }
    local d = depth_map[tab.bit_depth_idx] or 24
    raw_cfg = 'evaw' .. string.char(d, 1, 1)
  elseif fmt == 1 then
    local depth_map = { [0]=8, [1]=16, [2]=24, [3]=32 }
    local d = depth_map[tab.bit_depth_idx] or 24
    raw_cfg = 'ffia' .. string.char(d, 1, 1)
  elseif fmt == 2 then
    local depth_map = { [0]=16, [1]=24, [2]=32 }
    local d = depth_map[tab.bit_depth_idx] or 24
    raw_cfg = 'calf' .. string.char(d, 0, 0, 0, 5, 0, 0, 0)
  elseif fmt == 3 then
    raw_cfg = 'l3pm' .. string.char(
      0x40, 0x01, 0, 0,
      0, 0, 0, 0,
      0x0A, 0, 0, 0,
      0xFF, 0xFF, 0xFF, 0xFF,
      0x04, 0, 0, 0,
      0x40, 0x01, 0, 0, 0, 0, 0, 0
    )
  elseif fmt == 4 then return 'SggO'
  elseif fmt == 5 then return 'vggo'
  elseif fmt == 6 then
    local w = vid_sizes_w[tab.vid_size_idx + 1] or 1920
    local h = vid_sizes_h[tab.vid_size_idx + 1] or 1080
    local fps = vid_fps_vals[tab.vid_fps_idx + 1] or 60

    raw_cfg = string.pack("<c4 c8 i4 i4 i4 i4 i4 f i4 i4 c2",
      " FMW",
      string.rep("\0", 8),
      8,
      0,
      320,
      w,
      h,
      fps,
      1,
      95,
      "\0\0"
    )
  else return 'evaw' end

  return Base64Encode(raw_cfg)
end

local function GetRenderFormatExtension(tab)
  local extensions = { [0] = ".wav", [1] = ".aif", [2] = ".flac", [3] = ".mp3", [4] = ".opus", [5] = ".ogg", [6] = ".mp4" }
  return extensions[tab.format_idx] or ".wav"
end

local function SmartShortenPath(ctx, path, max_w)
  if not path or path == "" then return "" end
  local norm = path:gsub("/", "\\")
  local text_w, _ = r.ImGui_CalcTextSize(ctx, norm)
  
  if text_w <= max_w then return norm end
  
  local parts = {}
  for part in norm:gmatch("[^\\]+") do table.insert(parts, part) end
  if #parts <= 2 then return norm end
  
  local root = parts[1]
  if norm:sub(2,2) == ":" then root = parts[1] .. "\\" end
  
  for keep_end = #parts - 1, 1, -1 do
    local end_str = ""
    for k = #parts - keep_end + 1, #parts do
      end_str = end_str .. "\\" .. parts[k]
    end
    local candidate = root .. "\\..." .. end_str
    local cw, _ = r.ImGui_CalcTextSize(ctx, candidate)
    if cw <= max_w then return candidate end
  end
  
  return root .. "\\...\\" .. parts[#parts]
end

local function EvaluateFadePoint(shape, t)
  t = math.max(0, math.min(1, t))
  if shape == 0 then return t
  elseif shape == 1 then return 1 - (1 - t) ^ 2
  elseif shape == 2 then return t ^ 2
  elseif shape == 3 then return 1 - (1 - t) ^ 4
  elseif shape == 4 then return t ^ 4
  elseif shape == 5 then return (1 - math.cos(math.pi * t)) * 0.5
  elseif shape == 6 then return (t * (2 - t)) ^ 2
  end
  return t
end

local function PushAccentButtonStyle(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x233C4FFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x435665FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x042239FF)
end

local function PopAccentButtonStyle(ctx)
  r.ImGui_PopStyleColor(ctx, 3)
end

local function DrawFadeCurveButton(ctx, str_id, shape_idx, is_fade_out)
  local btn_w, btn_h = 26, 20
  local clicked = r.ImGui_Button(ctx, "##" .. str_id, btn_w, btn_h)
  local right_clicked = r.ImGui_IsItemClicked(ctx, 1)
  
  local p_min_x, p_min_y = r.ImGui_GetItemRectMin(ctx)
  local p_max_x, p_max_y = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  
  local pad_x, pad_y = 5, 4
  local x0, x1 = p_min_x + pad_x, p_max_x - pad_x
  local y_top, y_bot = p_min_y + pad_y, p_max_y - pad_y
  local w, h = x1 - x0, y_bot - y_top
  
  local color = 0x068FC3FF
  local steps = 12
  
  for i = 0, steps - 1 do
    local t1 = i / steps
    local t2 = (i + 1) / steps
    local val1 = EvaluateFadePoint(shape_idx, is_fade_out and (1 - t1) or t1)
    local val2 = EvaluateFadePoint(shape_idx, is_fade_out and (1 - t2) or t2)
    r.ImGui_DrawList_AddLine(dl, x0 + t1 * w, y_bot - val1 * h, x0 + t2 * w, y_bot - val2 * h, color, 1.5)
  end
  return clicked, right_clicked
end

local function DrawFadeCurveSelectorPopup(ctx, popup_id, current_shape, is_fade_out)
  local selected_shape = nil
  if r.ImGui_BeginPopup(ctx, popup_id) then
    r.ImGui_TextColored(ctx, 0x808080FF, "Select Curve Shape:")
    r.ImGui_Spacing(ctx)
    local cols = 3
    for idx = 0, 6 do
      r.ImGui_PushID(ctx, idx)
      local is_active = (current_shape == idx)
      if is_active then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x068FC388)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x068FC3FF)
      end
      
      local btn_w, btn_h = 44, 32
      local clicked = r.ImGui_Button(ctx, "##curve_btn", btn_w, btn_h)
      local p_min_x, p_min_y = r.ImGui_GetItemRectMin(ctx)
      local p_max_x, p_max_y = r.ImGui_GetItemRectMax(ctx)
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local pad_x, pad_y = 6, 5
      local x0, x1 = p_min_x + pad_x, p_max_x - pad_x
      local y_top, y_bot = p_min_y + pad_y, p_max_y - pad_y
      local w, h = x1 - x0, y_bot - y_top
      local line_col = is_active and 0xFFFFFFFF or 0xEDEDEDFF
      
      local steps = 16
      for s = 0, steps - 1 do
        local t1 = s / steps
        local t2 = (s + 1) / steps
        local val1 = EvaluateFadePoint(idx, is_fade_out and (1 - t1) or t1)
        local val2 = EvaluateFadePoint(idx, is_fade_out and (1 - t2) or t2)
        r.ImGui_DrawList_AddLine(dl, x0 + t1 * w, y_bot - val1 * h, x0 + t2 * w, y_bot - val2 * h, line_col, 2.0)
      end
      if is_active then r.ImGui_PopStyleColor(ctx, 2) end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, fade_shape_names[idx + 1]) end
      if clicked then selected_shape = idx; r.ImGui_CloseCurrentPopup(ctx) end
      
      r.ImGui_PopID(ctx)
      if (idx + 1) % cols ~= 0 then r.ImGui_SameLine(ctx) end
    end
    r.ImGui_EndPopup(ctx)
  end
  return selected_shape
end

-- =======================================================
-- Auto Detection Helpers
-- =======================================================
local function GetItemSampleRate(item)
  if not item then return 0 end
  local take = r.GetActiveTake(item)
  if take and not r.TakeIsMIDI(take) then
    local src = r.GetMediaItemTake_Source(take)
    if src then return r.GetMediaSourceSampleRate(src) or 0 end
  end
  return 0
end

local function GetTrackChannels(track)
  if not track then return 2 end
  return r.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2
end

-- =======================================================
-- REAPER RENDER SETTINGS INJECTION ENGINE
-- =======================================================
local function ApplyRenderSettingsToProject(tab, p_item)
  local proj = 0
  local dir = (tab.file_directory == "" or tab.file_directory:match("^%s*$")) and "" or tab.file_directory
  r.GetSetProjectInfo_String(proj, "RENDER_FILE", dir, true)
  r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", tab.file_pattern, true)
  
  local settings_val = 0
  if tab.render_source == 0 then settings_val = settings_val | 0
  elseif tab.render_source == 1 then
    if tab.via_master then settings_val = settings_val | 128 else settings_val = settings_val | 3 end
  elseif tab.render_source == 2 or tab.render_source == 3 then settings_val = settings_val | 8
  elseif tab.render_source == 4 or tab.render_source == 5 then
    if tab.via_master then settings_val = settings_val | 64 else settings_val = settings_val | 32 end
  end

  if tab.embed_take_marker and (tab.render_source == 4 or tab.render_source == 5) then settings_val = settings_val | 1024 end
  
  if tab.embed_meta then settings_val = settings_val | 512 end
  if tab.preserve_meta then settings_val = settings_val | 32768 end

  r.GetSetProjectInfo(proj, "RENDER_SETTINGS", settings_val, true)

  local bounds_val = 1
  if tab.render_source == 0 or tab.render_source == 1 then
    if tab.render_bounds == 1 then bounds_val = 2 else bounds_val = 1 end
  elseif tab.render_source == 2 or tab.render_source == 3 then bounds_val = 3
  elseif tab.render_source == 4 or tab.render_source == 5 then bounds_val = 4 end

  r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", bounds_val, true)

  if tab.render_source == 0 or tab.render_source == 1 then
    r.GetSetProjectInfo(proj, "RENDER_STARTPOS", tab.bounds_start or 0.0, true)
    r.GetSetProjectInfo(proj, "RENDER_ENDPOS", tab.bounds_end or 0.0, true)
  end
  
  -- SR & CH
  local sr_val = 48000
  if tab.sr_idx == 0 then
    sr_val = (p_item and p_item.item) and GetItemSampleRate(p_item.item) or 0
    if sr_val == 0 then sr_val = r.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false) end
  elseif tab.sr_idx == 12 then sr_val = tab.custom_sr
  else sr_val = sr_values[tab.sr_idx] end
  r.GetSetProjectInfo(proj, "RENDER_SRATE", sr_val, true)
  
  local ch_val = 2
  if tab.channels == 0 then
    ch_val = (p_item and p_item.track) and GetTrackChannels(p_item.track) or 2
  else
    local ch_map = {[1]=1, [2]=2, [3]=4, [4]=6, [5]=8}
    ch_val = ch_map[tab.channels] or 2
  end
  r.GetSetProjectInfo(proj, "RENDER_CHANNELS", ch_val, true)
  
  local tail_flag = 0
  if tab.enable_tail then
    if tab.render_source == 4 or tab.render_source == 5 then tail_flag = 16
    elseif tab.render_source == 2 or tab.render_source == 3 then tail_flag = 8
    elseif tab.render_bounds == 0 then tail_flag = 2
    elseif tab.render_bounds == 1 then tail_flag = 4 end
  end
  r.GetSetProjectInfo(proj, "RENDER_TAILFLAG", tail_flag, true)
  r.GetSetProjectInfo(proj, "RENDER_TAILMS", tab.tail_len * 1000, true)
  
  local norm_flag = 0
  if tab.enable_norm then norm_flag = norm_flag | 1 end
  if tab.enable_limit then norm_flag = norm_flag | 64 end
  if tab.enable_fadein then norm_flag = norm_flag | 512 end
  if tab.enable_fadeout then norm_flag = norm_flag | 1024 end

  r.GetSetProjectInfo(proj, "RENDER_NORMALIZE", norm_flag, true)

  local norm_linear = 10 ^ ((tab.norm_val or -24.0) / 20)
  r.GetSetProjectInfo(proj, "RENDER_NORMALIZE_TARGET", norm_linear, true)

  local limit_linear = 10 ^ ((tab.limit_val or 0.0) / 20)
  r.GetSetProjectInfo(proj, "RENDER_BRICKWALL", limit_linear, true)

  r.GetSetProjectInfo(proj, "RENDER_FADEIN", math.max(0, tab.fadein_len or 0), true)
  r.GetSetProjectInfo(proj, "RENDER_FADEOUT", math.max(0, tab.fadeout_len or 0), true)
  r.GetSetProjectInfo(proj, "RENDER_FADEINSHAPE", tab.fadein_shape or 0, true)
  r.GetSetProjectInfo(proj, "RENDER_FADEOUTSHAPE", tab.fadeout_shape or 0, true)
  
  r.GetSetProjectInfo(proj, "RENDER_ADDTOPROJ", tab.add_to_proj and 1 or 0, true)
  r.GetSetProjectInfo(proj, "RENDER_AUTOCLOSE", tab.auto_close and 1 or 0, true)

  local fmt_str = GetRenderFormatString(tab)
  r.GetSetProjectInfo_String(proj, "RENDER_FORMAT", fmt_str, true)
end

local function GetProjectRegions()
  local regions = {}
  local i = 0

  while true do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers(i)
    if retval == 0 then break end

    if isrgn then
      table.insert(regions, {
        index = markrgnindexnumber,
        start_pos = pos,
        end_pos = rgnend,
        name = (name ~= "" and name) or ("Region " .. tostring(markrgnindexnumber))
      })
    end

    i = i + 1
  end

  return regions
end

local function GetTimeSelectionRegions()
  local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local regions = {}

  if ts_end <= ts_start then return 0, regions, ts_start, ts_end end

  for _, region in ipairs(GetProjectRegions()) do
    if region.start_pos < ts_end and region.end_pos > ts_start then
      table.insert(regions, region.name)
    end
  end

  return #regions, regions, ts_start, ts_end
end

local function GetMatrixRegions()
  local regions = {}
  local master_tr = r.GetMasterTrack(0)

  for _, region in ipairs(GetProjectRegions()) do
    local master_mix_selected = false

    if r.EnumRegionRenderMatrix then
      local rendertrack = 0
      while true do
        local matrix_track = r.EnumRegionRenderMatrix(0, region.index, rendertrack)
        if not matrix_track then break end
        if matrix_track == master_tr then
          master_mix_selected = true
          break
        end
        rendertrack = rendertrack + 1
      end
    elseif r.GetSetRegionRenderMatrix then
      master_mix_selected = r.GetSetRegionRenderMatrix(0, region.index, master_tr, -1) > 0
    end

    if master_mix_selected then
      table.insert(regions, region.name)
    end
  end

  return #regions, regions
end

local function GetAllMatrixTracks()
  local tracks = {r.GetMasterTrack(0)}
  for i = 0, r.CountTracks(0) - 1 do
    tracks[#tracks + 1] = r.GetTrack(0, i)
  end
  return tracks
end

local function ClearAllRegionRenderMatrix()
  if not r.SetRegionRenderMatrix then return false end

  local tracks = GetAllMatrixTracks()
  for _, region in ipairs(GetProjectRegions()) do
    for _, track in ipairs(tracks) do
      r.SetRegionRenderMatrix(0, region.index, track, -1)
    end
  end

  return true
end

local function SetMatrixFromTimeSelection()
  if not r.SetRegionRenderMatrix then return false, 0 end

  local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts_end <= ts_start then return false, 0 end

  local master_tr = r.GetMasterTrack(0)
  local overlapping = {}

  for _, region in ipairs(GetProjectRegions()) do
    if region.start_pos < ts_end and region.end_pos > ts_start then
      overlapping[#overlapping + 1] = region
    end
  end

  r.TrackList_AdjustWindows(false)
  if not ClearAllRegionRenderMatrix() then
    r.TrackList_AdjustWindows(true)
    return false, 0
  end

  for _, region in ipairs(overlapping) do
    r.SetRegionRenderMatrix(0, region.index, master_tr, 1)
  end

  r.TrackList_AdjustWindows(true)
  r.UpdateArrange()
  return true, #overlapping
end

local function CaptureRegionRenderMatrix()
  local snapshot = {}
  if not r.EnumRegionRenderMatrix then return snapshot end

  for _, region in ipairs(GetProjectRegions()) do
    local selected_tracks = {}
    local rendertrack = 0

    while true do
      local matrix_track = r.EnumRegionRenderMatrix(0, region.index, rendertrack)
      if not matrix_track then break end
      selected_tracks[#selected_tracks + 1] = matrix_track
      rendertrack = rendertrack + 1
    end

    snapshot[region.index] = selected_tracks
  end

  return snapshot
end

local function RestoreRegionRenderMatrix(snapshot)
  if not snapshot or not r.SetRegionRenderMatrix then return end

  r.TrackList_AdjustWindows(false)
  ClearAllRegionRenderMatrix()
  for region_index, tracks in pairs(snapshot) do
    for _, track in ipairs(tracks) do
      if r.ValidatePtr(track, "MediaTrack*") then
        r.SetRegionRenderMatrix(0, region_index, track, 1)
      end
    end
  end

  r.TrackList_AdjustWindows(true)
  r.UpdateArrange()
end

local function ApplyTimeSelectionMatrix()
  local snapshot = CaptureRegionRenderMatrix()
  local success, count = SetMatrixFromTimeSelection()
  if not success then return nil, count end
  return snapshot, count
end

local function ParseWildcards(tab, pattern, sel_track, sel_item, sel_region, file_num)
  local out = pattern
  if not out or out == "" then return "" end

  local p_name = r.GetProjectName(0, "")
  p_name = p_name == "" and "Untitled" or p_name:gsub("%.RPP", "")
  
  local track_name = "NoTrack"
  if sel_track then _, track_name = r.GetTrackName(sel_track) end
  
  local item_name = "NoItem"
  if sel_item then
    local take = r.GetActiveTake(sel_item)
    if take then _, item_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false) end
  end
  
  local region_name = sel_region or "NoRegion"
  
  local sr_val = 48000
  if tab.sr_idx == 0 then
    sr_val = sel_item and GetItemSampleRate(sel_item) or 0
    if sr_val == 0 then sr_val = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) end
  elseif tab.sr_idx == 12 then sr_val = tab.custom_sr
  else sr_val = sr_values[tab.sr_idx] end
  local sr_k = tostring(sr_val/1000) .. "k"
  
  local ch_val = 2
  if tab.channels == 0 then
    ch_val = sel_track and GetTrackChannels(sel_track) or 2
  else
    local ch_map = {[1]=1, [2]=2, [3]=4, [4]=6, [5]=8}
    ch_val = ch_map[tab.channels] or 2
  end
  local ch_str = tostring(math.floor(ch_val))

  out = out:gsub("%$project", p_name)
  out = out:gsub("%$track", track_name)
  out = out:gsub("%$region", region_name)
  out = out:gsub("%$item", item_name)
  out = out:gsub("%$sampleratek", sr_k)
  out = out:gsub("%$channels", ch_str)
  
  local fnum_str = string.format("%02d", file_num or 1)
  out = out:gsub("%$filenumber%[%d+%]", fnum_str)
  out = out:gsub("%$uniqueid%[[%wN]+%]", "ID" .. tostring(math.random(1000, 9999)))
  
  out = out:gsub("%$datetime", os.date("%Y-%m-%d %H_%M_%S"))
  out = out:gsub("%$date", os.date("%Y-%m-%d"))
  out = out:gsub("%$time", os.date("%H_%M_%S"))
  out = out:gsub("%$year2", os.date("%y"))
  out = out:gsub("%$year", os.date("%Y"))
  out = out:gsub("%$monthname", os.date("%B"))
  out = out:gsub("%$month", os.date("%m"))
  out = out:gsub("%$dayname", os.date("%A"))
  out = out:gsub("%$day", os.date("%d"))
  out = out:gsub("%$hour12", os.date("%I"))
  out = out:gsub("%$hour", os.date("%H"))
  out = out:gsub("%$ampm", os.date("%p"))
  out = out:gsub("%$minute", os.date("%M"))
  out = out:gsub("%$second", os.date("%S"))
  out = out:gsub("%$localtime", os.date("%p %I:%M, %B %d %Y"))
  
  return out
end

local function GetFilteredRenderItems()
  local count = r.CountSelectedMediaItems(0)
  if count == 0 then return {} end
  
  local sel_items = {}
  local folder_items = {}
  
  for i = 0, count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local track = r.GetMediaItem_Track(item)
    table.insert(sel_items, {item = item, track = track})
    
    if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      table.insert(folder_items, {item = item, track = track, start_pos = pos, end_pos = pos + len})
    end
  end
  
  if #folder_items == 0 then return sel_items end
  
  local filtered_items = {}
  for _, s_item in ipairs(sel_items) do
    local is_child_of_selected_folder = false
    
    for _, f_item in ipairs(folder_items) do
      if s_item.item ~= f_item.item then
        local parent = r.GetParentTrack(s_item.track)
        local is_child = false
        while parent do
          if parent == f_item.track then
            is_child = true
            break
          end
          parent = r.GetParentTrack(parent)
        end
        
        if is_child then
          local pos = r.GetMediaItemInfo_Value(s_item.item, "D_POSITION")
          local len = r.GetMediaItemInfo_Value(s_item.item, "D_LENGTH")
          if pos < f_item.end_pos and (pos + len) > f_item.start_pos then
            is_child_of_selected_folder = true
            break
          end
        end
      end
    end
    
    if not is_child_of_selected_folder then table.insert(filtered_items, s_item) end
  end
  return filtered_items
end

local function GetDisplaySR(tab, item)
  if tab.sr_idx == 0 then
    local sr = item and GetItemSampleRate(item) or 0
    if sr == 0 then sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) end
    return string.format("%d (Auto)", math.floor(sr))
  elseif tab.sr_idx == 12 then return tostring(tab.custom_sr)
  else return tostring(sr_values[tab.sr_idx]) end
end

local function GetDisplayCH(tab, track)
  if tab.channels == 0 then
    local ch = track and GetTrackChannels(track) or 2
    return string.format("%dch (Auto)", math.floor(ch))
  else
    local ch_map = {"Mono", "Stereo", "4ch", "6ch", "8ch"}
    return ch_map[tab.channels] or "Stereo"
  end
end

local function GeneratePreviewList(tab)
  if not tab then tab = tabs[active_tab_idx] or tabs[1] end

  local previews = {}
  local num = 1
  local items_to_process = {}
  
  if tab.render_source == 4 or tab.render_source == 5 then
    if tab.render_source == 4 then
      items_to_process = GetFilteredRenderItems() 
    else
      local count = r.CountSelectedMediaItems(0)
      for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        table.insert(items_to_process, {item = item, track = r.GetMediaItem_Track(item)})
      end
    end
  elseif tab.render_source == 1 then
    local count = r.CountSelectedTracks(0)
    for i = 0, count - 1 do table.insert(items_to_process, {track = r.GetSelectedTrack(0, i)}) end
  elseif tab.render_source == 2 then
    local count, regions = GetMatrixRegions()
    for _, r_name in ipairs(regions) do table.insert(items_to_process, {region = r_name}) end
  elseif tab.render_source == 3 then
    local count, regions = GetTimeSelectionRegions()
    for _, r_name in ipairs(regions) do table.insert(items_to_process, {region = r_name}) end
  else
    table.insert(items_to_process, {track = r.GetSelectedTrack(0,0), item = r.GetSelectedMediaItem(0,0)})
  end
  
  if #items_to_process == 0 then return {}, {} end
  
  for _, p_item in ipairs(items_to_process) do
    local fname = ParseWildcards(tab, tab.file_pattern, p_item.track, p_item.item, p_item.region, num) .. GetRenderFormatExtension(tab)
    table.insert(previews, {
      name = fname, 
      sr = GetDisplaySR(tab, p_item.item), 
      ch = GetDisplayCH(tab, p_item.track)
    })
    num = num + 1
  end
  
  return previews, items_to_process
end

local function Main()
  r.ImGui_PushFont(ctx, font, 14)
  r.ImGui_SetNextWindowSize(ctx, 960, 700, r.ImGui_Cond_FirstUseEver())
  r.ImGui_SetNextWindowSizeConstraints(ctx, 880, 640, 3840, 2160)
  
  local style_pop_count, color_pop_count = ApplyTheme(ctx)
  
  local visible, open_flag = r.ImGui_Begin(ctx, 'JKK_Renderer', open, r.ImGui_WindowFlags_NoCollapse())
  open = open_flag

  -- ESC 키 입력 시 스크립트 닫기
  if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
    open = false
  end

  if visible then
    local is_focused = r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0)
    local is_any_item_active = r.ImGui_IsAnyItemActive(ctx)

    -- =======================================================
    -- GLOBAL KEYBOARD SHORTCUTS
    -- =======================================================
    if is_focused and not is_any_item_active then
      -- 1. Space: Play / Pause transport in REAPER
      if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space(), false) then
        r.Main_OnCommand(40044, 0) -- Transport: Play/pause
      end

      -- 2. Ctrl+Z / Cmd+Z: Trigger REAPER Undo
      local ctrl_down = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) or 
                        r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl()) or 
                        r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftSuper()) or 
                        r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightSuper())
      if ctrl_down and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Z(), false) then
        r.Main_OnCommand(40029, 0) -- Edit: Undo
      end
    end

    if r.ImGui_BeginTabBar(ctx, "RenderTabBar", r.ImGui_TabBarFlags_Reorderable()) then
      local tab_to_delete = nil
      for idx, t_data in ipairs(tabs) do
        local is_selected = r.ImGui_BeginTabItem(ctx, t_data.name .. "##tab_" .. tostring(idx))
        if is_selected then
          active_tab_idx = idx
          r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginPopupContextItem(ctx, "tab_ctx_" .. tostring(idx)) then
          if r.ImGui_MenuItem(ctx, "Rename Tab") then
            rename_tab_target = idx
            rename_input_buf = t_data.name
            r.ImGui_OpenPopup(ctx, "RenameTabModal")
          end
          if r.ImGui_MenuItem(ctx, "Duplicate Tab") then
            local dup = CreateDefaultTabState(t_data.name .. " (Copy)")
            for k, v in pairs(t_data) do if k ~= "name" then dup[k] = v end end
            table.insert(tabs, dup)
            SaveAllExtState()
          end
          if #tabs > 1 and r.ImGui_MenuItem(ctx, "Delete Tab") then tab_to_delete = idx end
          r.ImGui_EndPopup(ctx)
        end
      end
      if r.ImGui_TabItemButton(ctx, "+", r.ImGui_TabItemFlags_Trailing()) then
        table.insert(tabs, CreateDefaultTabState("Render " .. tostring(#tabs + 1)))
        SaveAllExtState()
      end
      if tab_to_delete then
        table.remove(tabs, tab_to_delete)
        if active_tab_idx > #tabs then active_tab_idx = #tabs end
        SaveAllExtState()
      end
      r.ImGui_EndTabBar(ctx)
    end
    
    if r.ImGui_BeginPopupModal(ctx, "RenameTabModal", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
      r.ImGui_Text(ctx, "Enter new tab name:")
      _, rename_input_buf = r.ImGui_InputText(ctx, "##rename_buf", rename_input_buf)
      if r.ImGui_Button(ctx, "OK", 80, 0) then
        if rename_tab_target and tabs[rename_tab_target] and rename_input_buf ~= "" then
          tabs[rename_tab_target].name = rename_input_buf
          SaveAllExtState()
        end
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel", 80, 0) then r.ImGui_CloseCurrentPopup(ctx) end
      r.ImGui_EndPopup(ctx)
    end

    local tab = tabs[active_tab_idx] or tabs[1]
    local previews, items_to_process = GeneratePreviewList(tab)
    local can_render = (#previews > 0)
    
    local enter_pressed = (r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter()))
    local trigger_enter_render = tab.enter_to_render and enter_pressed and is_focused and can_render and not is_any_item_active

    r.ImGui_Spacing(ctx)

    if r.ImGui_BeginTable(ctx, "LayoutTable_v4", 2, r.ImGui_TableFlags_BordersInnerV() | r.ImGui_TableFlags_Resizable()) then
      r.ImGui_TableSetupColumn(ctx, "Left", r.ImGui_TableColumnFlags_WidthFixed(), 320)
      r.ImGui_TableSetupColumn(ctx, "Right", r.ImGui_TableColumnFlags_WidthStretch())
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableSetColumnIndex(ctx, 0)
      
      -- =======================================================
      -- LEFT PANE
      -- =======================================================
      r.ImGui_TextColored(ctx, 0xE3DB8EFF, "Source & Bounds")
      r.ImGui_Spacing(ctx)

      r.ImGui_SetNextItemWidth(ctx, 180)
      _, tab.render_source = r.ImGui_Combo(ctx, '##src', tab.render_source, src_list, 15)
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Source")

      if tab.render_source == 0 or tab.render_source == 1 then
        r.ImGui_SetNextItemWidth(ctx, 180)
        _, tab.render_bounds = r.ImGui_Combo(ctx, '##bnd', tab.render_bounds, bnd_list)
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Bounds")
        
        if tab.render_bounds == 1 then
          local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
          tab.bounds_start = ts_start
          tab.bounds_end = ts_end
        else
          tab.bounds_start = 0.0
          tab.bounds_end = r.GetProjectLength(0)
        end
        local len = math.max(0, tab.bounds_end - tab.bounds_start)
        local range_str = string.format(" Range: %.2fs ~ %.2fs (%.2fs)", tab.bounds_start, tab.bounds_end, len)
        r.ImGui_TextColored(ctx, 0x808080FF, range_str)
      elseif tab.render_source == 2 then
        local rgn_count = GetMatrixRegions()
        if r.ImGui_Button(ctx, "Region Matrix (" .. tostring(rgn_count) .. ")##matrix_btn", 130) then
          r.Main_OnCommand(41888, 0)
        end
        r.ImGui_SameLine(ctx)
        local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        local has_time_selection = ts_end > ts_start
        if not has_time_selection then r.ImGui_BeginDisabled(ctx) end
        PushAccentButtonStyle(ctx)
        if r.ImGui_Button(ctx, "Set##matrix_set_btn", 42) then
          r.Undo_BeginBlock()
          SetMatrixFromTimeSelection()
          r.Undo_EndBlock("Set Region Render Matrix from Time Selection", -1)
        end
        PopAccentButtonStyle(ctx)
        if not has_time_selection then r.ImGui_EndDisabled(ctx) end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Clear all Region Matrix assignments and assign overlapping regions to Master mix.")
        end
      elseif tab.render_source == 3 then
        local rgn_count, _, ts_start, ts_end = GetTimeSelectionRegions()
        local range_text
        if ts_end > ts_start then
          range_text = string.format(" %d regions in Time Selection (%.2fs - %.2fs)", rgn_count, ts_start, ts_end)
        else
          range_text = "No Time Selection"
        end
        r.ImGui_TextColored(ctx, 0x808080FF, range_text)
      else
        r.ImGui_BeginDisabled(ctx)
        r.ImGui_SetNextItemWidth(ctx, 180)
        r.ImGui_Combo(ctx, '##bnd_dis', 0, " N/A\0")
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Bounds")
        r.ImGui_EndDisabled(ctx)
      end
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)

      -- [Format Settings Section]
      r.ImGui_TextColored(ctx, 0xE3DB8EFF, "Format Settings")
      r.ImGui_Spacing(ctx)

      local allow_ch_auto = (tab.render_source == 1 or tab.render_source == 4 or tab.render_source == 5)
      local allow_sr_auto = (tab.render_source == 4 or tab.render_source == 5)
      
      if not allow_ch_auto and tab.channels == 0 then tab.channels = 2 end
      if not allow_sr_auto and tab.sr_idx == 0 then tab.sr_idx = 7 end

      r.ImGui_SetNextItemWidth(ctx, 180)
      local ch_names = {[1]=" Mono", [2]=" Stereo", [3]=" 4ch", [4]=" 6ch", [5]=" 8ch"}
      local cur_ch_text = (tab.channels == 0) and " Auto (Follow Source)" or (ch_names[tab.channels] or " Stereo")
      
      if r.ImGui_BeginCombo(ctx, '##ch', cur_ch_text) then
        for i = 1, 5 do
          if r.ImGui_Selectable(ctx, ch_names[i], tab.channels == i) then tab.channels = i end
        end
        if allow_ch_auto then
          r.ImGui_Separator(ctx)
          if r.ImGui_Selectable(ctx, " Auto (Follow Source)", tab.channels == 0) then tab.channels = 0 end
        end
        r.ImGui_EndCombo(ctx)
      end
      if r.ImGui_IsItemHovered(ctx) and tab.channels == 0 then
        r.ImGui_SetTooltip(ctx, "Automatically uses the channel count from the source track.")
      end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Channels")
      
      r.ImGui_SetNextItemWidth(ctx, 180)
      local cur_sr_text = " 48000"
      if tab.sr_idx == 0 then cur_sr_text = " Auto (Follow Source)"
      elseif tab.sr_idx == 12 then cur_sr_text = " Custom"
      else cur_sr_text = " " .. tostring(sr_values[tab.sr_idx]) end
      
      local combo_flags = r.ImGui_ComboFlags_HeightLargest and r.ImGui_ComboFlags_HeightLargest() or 0
      if r.ImGui_BeginCombo(ctx, '##sr', cur_sr_text, combo_flags) then
        for i = 1, 11 do
          if r.ImGui_Selectable(ctx, " " .. tostring(sr_values[i]), tab.sr_idx == i) then tab.sr_idx = i end
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, " Custom", tab.sr_idx == 12) then tab.sr_idx = 12 end
        if allow_sr_auto then
          r.ImGui_Separator(ctx)
          if r.ImGui_Selectable(ctx, " Auto (Follow Source)", tab.sr_idx == 0) then tab.sr_idx = 0 end
        end
        r.ImGui_EndCombo(ctx)
      end
      if r.ImGui_IsItemHovered(ctx) and tab.sr_idx == 0 then
        r.ImGui_SetTooltip(ctx, "Automatically uses the sample rate of the selected media item.\nFalls back to Project Sample Rate if none found.")
      end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Rate")
      
      if tab.sr_idx == 12 then
        r.ImGui_SetNextItemWidth(ctx, 180)
        _, tab.custom_sr = r.ImGui_InputInt(ctx, '##csr', tab.custom_sr)
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Custom")
      end
      
      r.ImGui_SetNextItemWidth(ctx, 180)
      local fmt_changed, new_fmt = r.ImGui_Combo(ctx, '##fmt', tab.format_idx, format_list)
      if fmt_changed then
        tab.format_idx = new_fmt
      end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Format")
      
      r.ImGui_SetNextItemWidth(ctx, 180)
      if tab.format_idx == 0 then
        local wav_bits = " 8-bit PCM\0 16-bit PCM\0 24-bit PCM\0 32-bit PCM\0 32-bit Float\0 64-bit Float\0"
        _, tab.bit_depth_idx = r.ImGui_Combo(ctx, '##bit', tab.bit_depth_idx, wav_bits)
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Bit depth")
      elseif tab.format_idx == 1 then
        local aiff_bits = " 8-bit PCM\0 16-bit PCM\0 24-bit PCM\0 32-bit PCM\0"
        if tab.bit_depth_idx > 3 then tab.bit_depth_idx = 2 end
        _, tab.bit_depth_idx = r.ImGui_Combo(ctx, '##bit', tab.bit_depth_idx, aiff_bits)
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Bit depth")
      elseif tab.format_idx == 2 then
        local flac_bits = " 16-bit\0 24-bit\0 32-bit\0"
        if tab.bit_depth_idx > 2 then tab.bit_depth_idx = 1 end
        _, tab.bit_depth_idx = r.ImGui_Combo(ctx, '##bit', tab.bit_depth_idx, flac_bits)
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Bit depth")
      elseif tab.format_idx == 3 then
        r.ImGui_BeginDisabled(ctx)
        r.ImGui_Combo(ctx, '##bit_dis', 0, " 320 kbps CBR\0")
        r.ImGui_EndDisabled(ctx)
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Bitrate")
      elseif tab.format_idx == 4 then
        _, tab.opus_bitrate = r.ImGui_SliderInt(ctx, '##opus_br', math.floor(tab.opus_bitrate or 256), 6, 512, "%d kbps")
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Bitrate")
      elseif tab.format_idx == 5 then
        _, tab.vorbis_quality = r.ImGui_SliderDouble(ctx, '##vorbis_q', tab.vorbis_quality or 0.80, 0.0, 1.0, "%.2f VBR")
        r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Quality")
      elseif tab.format_idx == 6 then
        r.ImGui_SetNextItemWidth(ctx, 160)
        _, tab.vid_size_idx = r.ImGui_Combo(ctx, '##vid_size', tab.vid_size_idx, vid_size_list)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 80)
        _, tab.vid_fps_idx = r.ImGui_Combo(ctx, '##vid_fps', tab.vid_fps_idx, vid_fps_list)
      end
      
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)
      
      -- [Post Processing Section]
      r.ImGui_TextColored(ctx, 0xE3DB8EFF, "Post Processing")
      r.ImGui_Spacing(ctx)

      local chk_t_changed, new_t_chk = r.ImGui_Checkbox(ctx, "##t_chk", tab.enable_tail)
      if chk_t_changed then tab.enable_tail = new_t_chk end
      
      r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 160)
      local tail_changed, new_tail_len = r.ImGui_DragDouble(ctx, '##t_val', tab.tail_len, 0.1, 0.0, 10.0, "%.3f sec")
      if tail_changed then tab.tail_len = new_tail_len; tab.enable_tail = true end
      if r.ImGui_IsItemClicked(ctx, 1) then tab.tail_len = 1.000; tab.enable_tail = true end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Tail")
      
      local chk_fi_changed, new_fi_chk = r.ImGui_Checkbox(ctx, "##fi_chk", tab.enable_fadein)
      if chk_fi_changed then tab.enable_fadein = new_fi_chk end
      
      r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 128)
      local fi_changed, new_fi_len = r.ImGui_DragDouble(ctx, '##fi_val', tab.fadein_len, 0.1, 0.0, 10.0, "%.3f sec")
      if fi_changed then tab.fadein_len = new_fi_len; tab.enable_fadein = true end
      if r.ImGui_IsItemClicked(ctx, 1) then tab.fadein_len = 0.000; tab.enable_fadein = true end
      r.ImGui_SameLine(ctx)
      
      local fi_clicked, fi_rclicked = DrawFadeCurveButton(ctx, "fsh_in", tab.fadein_shape, false)
      if fi_clicked then tab.fadein_shape = (tab.fadein_shape + 1) % 7; tab.enable_fadein = true end
      if fi_rclicked then r.ImGui_OpenPopup(ctx, "fi_shape_popup") end
      local new_fi_shape = DrawFadeCurveSelectorPopup(ctx, "fi_shape_popup", tab.fadein_shape, false)
      if new_fi_shape then tab.fadein_shape = new_fi_shape; tab.enable_fadein = true end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Fade in")
      
      local chk_fo_changed, new_fo_chk = r.ImGui_Checkbox(ctx, "##fo_chk", tab.enable_fadeout)
      if chk_fo_changed then tab.enable_fadeout = new_fo_chk end
      
      r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 128)
      local fo_changed, new_fo_len = r.ImGui_DragDouble(ctx, '##fo_val', tab.fadeout_len, 0.1, 0.0, 10.0, "%.3f sec")
      if fo_changed then tab.fadeout_len = new_fo_len; tab.enable_fadeout = true end
      if r.ImGui_IsItemClicked(ctx, 1) then tab.fadeout_len = 0.000; tab.enable_fadeout = true end
      r.ImGui_SameLine(ctx)
      
      local fo_clicked, fo_rclicked = DrawFadeCurveButton(ctx, "fsh_out", tab.fadeout_shape, true)
      if fo_clicked then tab.fadeout_shape = (tab.fadeout_shape + 1) % 7; tab.enable_fadeout = true end
      if fo_rclicked then r.ImGui_OpenPopup(ctx, "fo_shape_popup") end
      local new_fo_shape = DrawFadeCurveSelectorPopup(ctx, "fo_shape_popup", tab.fadeout_shape, true)
      if new_fo_shape then tab.fadeout_shape = new_fo_shape; tab.enable_fadeout = true end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Fade out")
      
      r.ImGui_Spacing(ctx)
      r.ImGui_Spacing(ctx)
      
      local chk_n_changed, new_n_chk = r.ImGui_Checkbox(ctx, "##n_chk", tab.enable_norm)
      if chk_n_changed then tab.enable_norm = new_n_chk end
      r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 160)
      local n_changed, new_n_val = r.ImGui_DragDouble(ctx, '##n_val', tab.norm_val, 0.5, -30.0, 0.0, "%.1f LUFS-I")
      if n_changed then tab.norm_val = new_n_val; tab.enable_norm = true end
      if r.ImGui_IsItemClicked(ctx, 1) then tab.norm_val = -24.0; tab.enable_norm = true end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Normalize")
      
      local chk_l_changed, new_l_chk = r.ImGui_Checkbox(ctx, "##l_chk", tab.enable_limit)
      if chk_l_changed then tab.enable_limit = new_l_chk end
      r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 160)
      local l_changed, new_l_val = r.ImGui_DragDouble(ctx, '##l_val', tab.limit_val, 0.1, -10.0, 0.0, "%.1f dB Peak")
      if l_changed then tab.limit_val = new_l_val; tab.enable_limit = true end
      if r.ImGui_IsItemClicked(ctx, 1) then tab.limit_val = 0.0; tab.enable_limit = true end
      r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, " Limit")
      
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)
      
      -- [File Settings Section]
      r.ImGui_TextColored(ctx, 0xE3DB8EFF, "File Settings")
      r.ImGui_Spacing(ctx)

      if tab.render_source == 1 or tab.render_source == 4 or tab.render_source == 5 then
        _, tab.via_master = r.ImGui_Checkbox(ctx, ' Render via master', tab.via_master)
      else
        r.ImGui_BeginDisabled(ctx)
        r.ImGui_Checkbox(ctx, ' Render via master', false)
        r.ImGui_EndDisabled(ctx)
      end

      if tab.render_source == 4 or tab.render_source == 5 then
        _, tab.embed_take_marker = r.ImGui_Checkbox(ctx, ' Embed take marker', tab.embed_take_marker)
      else
        r.ImGui_BeginDisabled(ctx)
        r.ImGui_Checkbox(ctx, ' Embed take marker', false)
        r.ImGui_EndDisabled(ctx)
      end
      
      _, tab.preserve_meta = r.ImGui_Checkbox(ctx, ' Preserve source metadata', tab.preserve_meta)
      
      _, tab.embed_meta = r.ImGui_Checkbox(ctx, ' Embed metadata', tab.embed_meta)
      r.ImGui_SameLine(ctx)
      PushAccentButtonStyle(ctx)
      if r.ImGui_Button(ctx, "Edit", 40, 20) then
        r.Main_OnCommand(42397, 0)
      end
      PopAccentButtonStyle(ctx)
      
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)
      
      -- [Output Actions Section]
      r.ImGui_TextColored(ctx, 0xE3DB8EFF, "Output Actions")
      r.ImGui_Spacing(ctx)

      _, tab.add_to_proj = r.ImGui_Checkbox(ctx, ' Add to project', tab.add_to_proj)
      _, tab.add_to_queue = r.ImGui_Checkbox(ctx, ' Add to render queue', tab.add_to_queue)
      
      -- 요구사항 2: Enter to render 우측에 Open 버튼 (Action: 40929) 추가
      _, tab.enter_to_render = r.ImGui_Checkbox(ctx, ' Enter to render', tab.enter_to_render)
      r.ImGui_SameLine(ctx)
      PushAccentButtonStyle(ctx)
      if r.ImGui_Button(ctx, "Open##queue_open", 40, 20) then
        r.Main_OnCommand(40929, 0) -- File: Render queue...
      end
      PopAccentButtonStyle(ctx)
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Open REAPER Render Queue Window (40929)")
      end

      _, tab.auto_close = r.ImGui_Checkbox(ctx, ' Auto-Close when finished', tab.auto_close)
      _, tab.open_folder = r.ImGui_Checkbox(ctx, ' Open folder after render', tab.open_folder)
      
      -- Render Button Section
      local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
      local btn_h = 50
      if avail_h > btn_h then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + avail_h - btn_h) end
      
      if not can_render then r.ImGui_BeginDisabled(ctx) end
      
      -- 메인 Render 버튼 너비 계산 (우측 서브버튼 공간 확보)
      local sub_btn_w = 55
      local main_btn_w = math.max(120, avail_w - sub_btn_w - 18)

      r.ImGui_PushFont(ctx, font_btn, 23)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x24866FFF)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2A9A80FF)
      local render_btn_txt = tab.add_to_queue and "Add to Queue" or "Render"
      
      -- 메인 Render 버튼
      if r.ImGui_Button(ctx, render_btn_txt, main_btn_w, btn_h) or trigger_enter_render then
        
        local need_sequential = (tab.channels == 0 or tab.sr_idx == 0) and (#items_to_process > 1) and (tab.render_source == 1 or tab.render_source == 4 or tab.render_source == 5)

        local init_sel_items, init_sel_tracks = {}, {}
        for i = 0, r.CountSelectedMediaItems(0) - 1 do table.insert(init_sel_items, r.GetSelectedMediaItem(0, i)) end
        for i = 0, r.CountSelectedTracks(0) - 1 do table.insert(init_sel_tracks, r.GetSelectedTrack(0, i)) end

        local matrix_snapshot = nil
        if tab.render_source == 3 then
          matrix_snapshot = ApplyTimeSelectionMatrix()
        end

        if need_sequential then
          for _, p_item in ipairs(items_to_process) do
            r.Main_OnCommand(40289, 0)
            r.Main_OnCommand(40297, 0)
            if p_item.item then r.SetMediaItemSelected(p_item.item, true) end
            if p_item.track then r.SetTrackSelected(p_item.track, true) end
            
            ApplyRenderSettingsToProject(tab, p_item)
            if tab.add_to_queue then r.Main_OnCommand(41207, 0) else r.Main_OnCommand(41824, 0) end
          end
        else
          if tab.render_source == 4 then
            r.Main_OnCommand(40289, 0) 
            for _, f_item in ipairs(items_to_process) do
              if f_item.item then r.SetMediaItemSelected(f_item.item, true) end
            end
            r.UpdateArrange()
          end
          
          ApplyRenderSettingsToProject(tab, items_to_process[1])
          if tab.add_to_queue then r.Main_OnCommand(41207, 0) else r.Main_OnCommand(41824, 0) end
        end

        if matrix_snapshot then
          RestoreRegionRenderMatrix(matrix_snapshot)
        end

        r.Main_OnCommand(40289, 0) 
        r.Main_OnCommand(40297, 0) 
        for _, item in ipairs(init_sel_items) do if r.ValidatePtr(item, "MediaItem*") then r.SetMediaItemSelected(item, true) end end
        for _, track in ipairs(init_sel_tracks) do if r.ValidatePtr(track, "MediaTrack*") then r.SetTrackSelected(track, true) end end
        r.UpdateArrange()

        if tab.open_folder then
          local rv, proj_fn = r.EnumProjects(-1)
          local proj_dir = ''
          if proj_fn ~= '' then proj_dir = proj_fn:match('(.+)[/\\]') or ''
          else proj_dir = r.GetProjectPath("") end
          
          local render_path = tab.file_directory
          if render_path == '' or render_path:match("^%s*$") then render_path = proj_dir end
          
          if not render_path:match('^%a:[/\\]') and not render_path:match('^/') and not render_path:match('^\\\\') then
            render_path = proj_dir .. '/' .. render_path
          end
          
          if r.CF_ShellExecute then
            r.CF_ShellExecute(render_path)
          else
            local os_name = r.GetOS()
            if os_name:match("Win") then os.execute('explorer "' .. render_path:gsub('/', '\\') .. '"')
            else os.execute('open "' .. render_path .. '"') end
          end
        end

        if tab.auto_close then open = false end
      end
      
      r.ImGui_PopStyleColor(ctx, 2)
      r.ImGui_PopFont(ctx)

      -- 요구사항 1: Render 버튼 우측 서브버튼 (Open Origin Render - Action: 40015 & 스크립트 종료)
      r.ImGui_SameLine(ctx)
      PushAccentButtonStyle(ctx)
      if r.ImGui_Button(ctx, "Orig.\nRender##orig_render", sub_btn_w, btn_h) then
        r.Main_OnCommand(40015, 0) -- File: Render project to disk...
        open = false               -- 스크립트 종료
      end
      PopAccentButtonStyle(ctx)
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Open REAPER's original render dialog (40015) and exit script.")
      end

      if not can_render then r.ImGui_EndDisabled(ctx) end
      
      -- =======================================================
      -- RIGHT PANE
      -- =======================================================
      r.ImGui_TableSetColumnIndex(ctx, 1)

      -- 1. Directory
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Indent(ctx, 16)
      r.ImGui_Text(ctx, "Directory:")
      r.ImGui_SameLine(ctx, 90)
      r.ImGui_SetNextItemWidth(ctx, -131)
      _, tab.file_directory = r.ImGui_InputText(ctx, '##dir', tab.file_directory)
      
      r.ImGui_SameLine(ctx)
      PushAccentButtonStyle(ctx)
      if r.ImGui_Button(ctx, 'Browse...', 80) then
        if r.JS_Dialog_BrowseForFolder then
          local ret, folder = r.JS_Dialog_BrowseForFolder("Output Directory", tab.file_directory)
          if ret == 1 and folder ~= "" then tab.file_directory = folder end
        end
      end
      PopAccentButtonStyle(ctx)
      
      r.ImGui_SameLine(ctx)
      PushAccentButtonStyle(ctx)
      if r.ImGui_Button(ctx, '★##fav_btn', 35) then r.ImGui_OpenPopup(ctx, 'fav_popup') end
      PopAccentButtonStyle(ctx)
      r.ImGui_Unindent(ctx, 16)
      
      local open_add_fav_modal = false
      if r.ImGui_BeginPopup(ctx, 'fav_popup') then
        if r.ImGui_MenuItem(ctx, "+ Add Current Directory to Favorites...") then
          fav_name_buf = tab.file_directory:match("([^\\/]+)$") or "My Favorite"
          open_add_fav_modal = true
        end
        if #favorites > 0 then
          r.ImGui_Separator(ctx)
          local del_idx = nil
          for idx, fav in ipairs(favorites) do
            local display_str = string.format("%s (%s)", fav.name, SmartShortenPath(ctx, fav.path, 220))
            if r.ImGui_MenuItem(ctx, display_str) then tab.file_directory = fav.path end
            if r.ImGui_BeginPopupContextItem(ctx, "fav_ctx_" .. tostring(idx)) then
              if r.ImGui_MenuItem(ctx, "Delete Favorite") then del_idx = idx end
              r.ImGui_EndPopup(ctx)
            end
          end
          if del_idx then table.remove(favorites, del_idx); SaveAllExtState() end
        end
        r.ImGui_EndPopup(ctx)
      end

      if open_add_fav_modal then r.ImGui_OpenPopup(ctx, "AddFavoriteModal") end

      if r.ImGui_BeginPopupModal(ctx, "AddFavoriteModal", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "Favorite Name:")
        _, fav_name_buf = r.ImGui_InputText(ctx, "##fav_name", fav_name_buf)
        r.ImGui_TextColored(ctx, 0x808080FF, "Path: " .. SmartShortenPath(ctx, tab.file_directory, 300))
        r.ImGui_Spacing(ctx)
        
        if r.ImGui_Button(ctx, "Save", 80, 0) then
          if fav_name_buf ~= "" then table.insert(favorites, { name = fav_name_buf, path = tab.file_directory }); SaveAllExtState() end
          r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel", 80, 0) then r.ImGui_CloseCurrentPopup(ctx) end
        r.ImGui_EndPopup(ctx)
      end

      -- 2. File name
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Indent(ctx, 16)
      r.ImGui_Text(ctx, "File name:")
      r.ImGui_SameLine(ctx, 90)
      r.ImGui_SetNextItemWidth(ctx, -131)
      _, tab.file_pattern = r.ImGui_InputText(ctx, '##fn', tab.file_pattern)
      r.ImGui_SameLine(ctx)
      PushAccentButtonStyle(ctx)
      if r.ImGui_Button(ctx, 'Wildcards', 123) then r.ImGui_OpenPopup(ctx, 'w_popup') end
      PopAccentButtonStyle(ctx)
      r.ImGui_Unindent(ctx, 16)
      
      if r.ImGui_BeginPopup(ctx, 'w_popup') then
        if r.ImGui_MenuItem(ctx, "Project Name ($project)") then tab.file_pattern = tab.file_pattern .. "$project" end
        if r.ImGui_MenuItem(ctx, "Selected Track Name ($track)") then tab.file_pattern = tab.file_pattern .. "$track" end
        if r.ImGui_MenuItem(ctx, "Selected Region Name ($region)") then tab.file_pattern = tab.file_pattern .. "$region" end
        if r.ImGui_MenuItem(ctx, "Selected Item ($item)") then tab.file_pattern = tab.file_pattern .. "$item" end
        if r.ImGui_MenuItem(ctx, "Files Number ($filenumber[01])") then tab.file_pattern = tab.file_pattern .. "$filenumber[01]" end
        if r.ImGui_BeginMenu(ctx, "Format") then
          if r.ImGui_MenuItem(ctx, "Sample Rate ($sampleratek)") then tab.file_pattern = tab.file_pattern .. "$sampleratek" end
          if r.ImGui_MenuItem(ctx, "Channels ($channels)") then tab.file_pattern = tab.file_pattern .. "$channels" end
          r.ImGui_EndMenu(ctx)
        end
        if r.ImGui_BeginMenu(ctx, "Time & Date") then
          if r.ImGui_MenuItem(ctx, "yyyy-mm-dd ($date)") then tab.file_pattern = tab.file_pattern .. "$date" end
          if r.ImGui_MenuItem(ctx, "hh_mm_ss ($time)") then tab.file_pattern = tab.file_pattern .. "$time" end
          if r.ImGui_MenuItem(ctx, "yyyy-mm-dd hh_mm_ss ($datetime)") then tab.file_pattern = tab.file_pattern .. "$datetime" end
          if r.ImGui_MenuItem(ctx, "yyyy ($year)") then tab.file_pattern = tab.file_pattern .. "$year" end
          if r.ImGui_MenuItem(ctx, "yy ($year2)") then tab.file_pattern = tab.file_pattern .. "$year2" end
          if r.ImGui_MenuItem(ctx, "mm ($month)") then tab.file_pattern = tab.file_pattern .. "$month" end
          if r.ImGui_MenuItem(ctx, "Month Name English ($monthname)") then tab.file_pattern = tab.file_pattern .. "$monthname" end
          if r.ImGui_MenuItem(ctx, "dd ($day)") then tab.file_pattern = tab.file_pattern .. "$day" end
          if r.ImGui_MenuItem(ctx, "Day Name English ($dayname)") then tab.file_pattern = tab.file_pattern .. "$dayname" end
          if r.ImGui_MenuItem(ctx, "hh 24-hour format ($hour)") then tab.file_pattern = tab.file_pattern .. "$hour" end
          if r.ImGui_MenuItem(ctx, "hh 12-hour format ($hour12)") then tab.file_pattern = tab.file_pattern .. "$hour12" end
          if r.ImGui_MenuItem(ctx, "AM or PM ($ampm)") then tab.file_pattern = tab.file_pattern .. "$ampm" end
          if r.ImGui_MenuItem(ctx, "mm ($minute)") then tab.file_pattern = tab.file_pattern .. "$minute" end
          if r.ImGui_MenuItem(ctx, "ss ($second)") then tab.file_pattern = tab.file_pattern .. "$second" end
          if r.ImGui_MenuItem(ctx, "Daytime, Monthname... ($localtime)") then tab.file_pattern = tab.file_pattern .. "$localtime" end
          r.ImGui_EndMenu(ctx)
        end
        if r.ImGui_MenuItem(ctx, "Unique ID ($uniqueid[N])") then tab.file_pattern = tab.file_pattern .. "$uniqueid[N]" end
        r.ImGui_EndPopup(ctx)
      end
      
      r.ImGui_Spacing(ctx)

      -- PREVIEW WINDOWS
      local child_flags = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 0
      
      local box_h1 = 56
      if r.ImGui_BeginChild(ctx, "dir_box", 0, box_h1, child_flags) then
        local box_w, _ = r.ImGui_GetContentRegionAvail(ctx)
        local is_empty = (tab.file_directory == "" or tab.file_directory:match("^%s*$"))
        local dir_title = is_empty and "Target Directory (project default render path):" or "Target Directory:"
        local full_dir = is_empty and (r.GetProjectPath("") .. "\\Rendered (Default)") or tab.file_directory
        local display_dir = SmartShortenPath(ctx, full_dir, box_w - 40)
        
        local text_h = r.ImGui_GetTextLineHeight(ctx)
        local item_spacing_y = 4 
        local content_h = text_h * 2 + item_spacing_y
        r.ImGui_SetCursorPosY(ctx, (box_h1 - content_h) / 2)
        
        r.ImGui_SetCursorPosX(ctx, 16)
        r.ImGui_TextColored(ctx, 0x808080FF, dir_title)
        
        r.ImGui_SetCursorPosX(ctx, 16)
        r.ImGui_TextColored(ctx, 0xEDEDEDFF, display_dir)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, full_dir) end
        
        r.ImGui_EndChild(ctx)
      end
      
      r.ImGui_Spacing(ctx)
      
      if r.ImGui_BeginChild(ctx, "preview_box", 0, 0, child_flags) then
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 6)
        r.ImGui_SetCursorPosX(ctx, 16)
        
        local render_title_map = {
          [0] = "Master Mix to Render:", [1] = "Stems to Render (" .. tostring(#previews) .. "):",
          [2] = "Matrix Regions to Render (" .. tostring(#previews) .. "):",
          [3] = "Time Selection Regions to Render (" .. tostring(#previews) .. "):",
          [4] = "Items to Render (" .. tostring(#previews) .. "):",
          [5] = "Items to Render Separately (" .. tostring(#previews) .. "):"
        }
        local box_title = render_title_map[tab.render_source] or ("Items to Render (" .. tostring(#previews) .. "):")
        r.ImGui_TextColored(ctx, 0x808080FF, box_title)
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 4)
        
        if #previews == 0 then
          local empty_msg_map = {
            [0] = " (Master mix ready)", [1] = " (No tracks selected)", [2] = " (No Matrix regions selected)",
            [3] = " (No regions overlap the Time Selection)", [4] = " (No items selected)", [5] = " (No items selected)"
          }
          local empty_msg = empty_msg_map[tab.render_source] or " (No items selected)"
          r.ImGui_SetCursorPosX(ctx, 16)
          r.ImGui_TextColored(ctx, 0x666666FF, empty_msg)
        else
          r.ImGui_Indent(ctx, 16)
          local table_flags = r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_ScrollY()
          if r.ImGui_BeginTable(ctx, "PreviewTable", 3, table_flags) then
            r.ImGui_TableSetupColumn(ctx, "File Name", r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, "Sample Rate", r.ImGui_TableColumnFlags_WidthFixed(), 85)
            r.ImGui_TableSetupColumn(ctx, "Channels", r.ImGui_TableColumnFlags_WidthFixed(), 85)
            
            for i, p in ipairs(previews) do
              r.ImGui_TableNextRow(ctx)
              r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, p.name)
              r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, p.sr)
              r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, p.ch)
            end
            r.ImGui_EndTable(ctx)
          end
          r.ImGui_Unindent(ctx, 16)
        end

        r.ImGui_EndChild(ctx)
      end

      r.ImGui_EndTable(ctx)
    end
    r.ImGui_End(ctx)
  end
  
  r.ImGui_PopStyleVar(ctx, style_pop_count)
  r.ImGui_PopStyleColor(ctx, color_pop_count)
  r.ImGui_PopFont(ctx)

  if open then r.defer(Main)
  else if r.ImGui_DestroyContext then r.ImGui_DestroyContext(ctx) end end
end

r.defer(Main)