local orgmode = require('orgmode')

---@class OrgCapture
local OrgCapture = {}

---@class OrgRefileOpts
---@field filename string
---@field headline string

---@param options OrgRefileOpts
function OrgCapture.refile(options)
  vim.validate({
    options = { options, 'table' },
    filename = { options.filename, 'string' },
    headline = { options.headline, 'string', true },
  })
  options = options or {}
  local org = orgmode.instance()
  org:init()
  local files = org.files
  local file = files:get(options.filename)
  if not file then
    error('Invalid filename provided')
  end
end
