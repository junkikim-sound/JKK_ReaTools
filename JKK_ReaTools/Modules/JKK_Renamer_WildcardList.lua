--========================================================
-- @title JKK_Renamer Wildcard List Module
-- @author Junki Kim
-- @noindex
--========================================================

return {
    { insert = "$project", name = "Project Name", desc = "Project Name" },
    { insert = "$track", name = "Track Name", desc = "Selected Track Name" },
    { insert = "$region", name = "Region Name", desc = "Selected Region Name" },
    { insert = "$item", name = "Item Name", desc = "Selected Item Name" },
    { insert = "$filenumber[01]", name = "Files Number", desc = "Sequential Numbering" },
    { insert = "$sampleratek", name = "Sample Rate", desc = "Format: 48k" },
    { insert = "$channels", name = "Channels", desc = "Format: 2" },
    { insert = "$date", name = "Date", desc = "yyyy-mm-dd" },
    { insert = "$time", name = "Time", desc = "hh_mm_ss" },
    { insert = "$datetime", name = "Date & Time", desc = "yyyy-mm-dd hh_mm_ss" },
    { insert = "$year", name = "Year", desc = "yyyy" },
    { insert = "$year2", name = "Year2", desc = "yy" },
    { insert = "$month", name = "Month", desc = "mm" },
    { insert = "$monthname", name = "Month Name", desc = "Month Name English" },
    { insert = "$day", name = "Day", desc = "dd" },
    { insert = "$dayname", name = "Day Name", desc = "Day Name English" },
    { insert = "$hour", name = "Hour", desc = "hh 24-hour format" },
    { insert = "$hour12", name = "Hour12", desc = "hh 12-hour format" },
    { insert = "$ampm", name = "AM/PM", desc = "AM or PM" },
    { insert = "$minute", name = "Minute", desc = "mm" },
    { insert = "$second", name = "Second", desc = "ss" },
    { insert = "$localtime", name = "Local Time", desc = "Daytime, Monthname..." },
    { insert = "$uniqueid[N]", name = "Unique ID", desc = "Unique ID string" }
}