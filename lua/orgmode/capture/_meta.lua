---@meta

---@class OrgProcessRefileOpts
---@field source_headline OrgHeadline
---@field destination_file? OrgFile
---@field destination_headline? OrgHeadline
---@field message? string

---@class OrgProcessCaptureOpts
---@field template OrgCaptureTemplate
---@field capture_window OrgCaptureWindow
---@field source_file OrgFile
---@field source_headline? OrgHeadline
---@field destination_file OrgFile
---@field destination_headline? OrgHeadline
---@field disposition? 'close' | 'show' what happens to the capture window
---@field cursor? integer[] cursor to restore in the destination, "show" only

---@class OrgDatetreeTreeItem
---@field format string - The lua date format to use for the tree item
---@field pattern string - Pattern to match important date parts the date format
---@field order number[] - Order of checking the date parts matched from the pattern

---@class OrgCaptureTemplateDatetreeOpts
---@field date OrgDate
---@field time_prompt? boolean
---@field reversed? boolean
---@field tree? OrgDatetreeTreeItem[]
---@field tree_type? 'day' | 'week' | 'month' | 'custom'

---@alias OrgCaptureTemplateDatetree boolean | OrgCaptureTemplateDatetreeOpts
