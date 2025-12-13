--========================================================
-- @title JJK_Timeline Manager_Region Creator (from Selected Seperate Items)
-- @author Junki Kim
-- @version 1.0.0
--========================================================

function main()
    local project = reaper.EnumProjects(-1, 0)
    if not project then return end

    local sel_items = {}
    local item_count = reaper.CountSelectedMediaItems(project)

    if item_count == 0 then
        return
    end

    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(project, i)
        local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local end_time = start_time + length
        table.insert(sel_items, {start=start_time, end_=end_time})
    end

    local retval, name_base = reaper.GetUserInputs("Enter Region Name", 1, "Region Name", "New_Region")
    if retval == 0 then
        return
    end

    table.sort(sel_items, function(a, b) return a.start < b.start end)

    local regions_to_create = {}
    local current_start, current_end = -1, -1

    for _, item_data in ipairs(sel_items) do
        local start_time = item_data.start
        local end_time = item_data.end_
        
        if current_start == -1 then
            current_start = start_time
            current_end = end_time
        elseif start_time <= current_end then
            current_end = math.max(current_end, end_time)
        else
            table.insert(regions_to_create, {start=current_start, end_=current_end})
            current_start = start_time
            current_end = end_time
        end
    end

    if current_start ~= -1 then
        table.insert(regions_to_create, {start=current_start, end_=current_end})
    end

    local region_index = 0
    for i, region_data in ipairs(regions_to_create) do
        local start = region_data.start
        local end_ = region_data.end_
        
        local region_num = string.format("_%02d", i)
        local region_name = name_base .. region_num

        reaper.AddProjectMarker(project, 1, start, end_, region_name, 0)
        region_index = region_index + 1
    end

    reaper.UpdateArrange()
end

reaper.defer(main)