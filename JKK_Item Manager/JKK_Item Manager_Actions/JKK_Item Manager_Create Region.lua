--========================================================
-- @title JKK_Item Manager_Create Region
-- @author Junki Kim
-- @version 1.0.0
-- @changelog: A tool for creating a single region that spans the total time range covered by all selected media items.
--========================================================

local reaper = reaper

local function CreateRegionsFromSelectedItems(base_name)
    if not base_name or base_name:len() == 0 then
        reaper.MB("Region base name cannot be empty.", "Error", 0)
        return
    end
    
    local project = reaper.EnumProjects(-1, 0)
    if not project then 
        reaper.MB("No project is currently open.", "Error", 0)
        return 
    end

    local sel_items = {}
    local item_count = reaper.CountSelectedMediaItems(project)

    if item_count == 0 then
        reaper.MB("Please select one or more media items to create regions.", "Info", 0)
        return
    end

    -- Collect item start/end
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(project, i)
        local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local end_time = start_time + length
        table.insert(sel_items, {start=start_time, end_=end_time})
    end

    -- Sort by start time to handle overlaps correctly
    table.sort(sel_items, function(a, b) return a.start < b.start end)

    local regions_to_create = {}
    local current_start, current_end = -1, -1

    -- Merge overlapping/adjacent item ranges
    for _, item_data in ipairs(sel_items) do
        local s = item_data.start
        local e = item_data.end_
        
        if current_start == -1 then
            current_start = s
            current_end = e
        elseif s <= current_end then
            current_end = math.max(current_end, e)
        else
            table.insert(regions_to_create, {start=current_start, end_=current_end})
            current_start = s
            current_end = e
        end
    end

    -- Add the last collected region
    if current_start ~= -1 then
        table.insert(regions_to_create, {start=current_start, end_=current_end})
    end

    reaper.Undo_BeginBlock()
    
    -- Create Regions
    for i, region_data in ipairs(regions_to_create) do
        local start = region_data.start
        local end_ = region_data.end_
        local n = string.format("%s_%02d", base_name, i)
        reaper.AddProjectMarker(project, 1, start, end_, n, -1)
    end
    
    reaper.Undo_EndBlock(string.format("Create %d Regions from Selected Items", #regions_to_create), -1)
    reaper.UpdateArrange()
end

local success, base_name = reaper.GetUserInputs("Create Regions", 1, "Base Name:", "")

if success then
    CreateRegionsFromSelectedItems(base_name)
end