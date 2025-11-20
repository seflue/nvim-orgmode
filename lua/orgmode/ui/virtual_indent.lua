local tree_utils = require('orgmode.utils.treesitter')
---@class OrgVirtualIndent
---@field private _ns_id number extmarks namespace id
---@field private _bufnr integer Buffer VirtualIndent is attached to
---@field private _attached boolean Whether or not VirtualIndent is attached for its buffer
---@field private _bufnrs table<integer, OrgVirtualIndent> Buffers with VirtualIndent attached
local VirtualIndent = {
  _ns_id = vim.api.nvim_create_namespace('orgmode.ui.indent'),
  _bufnrs = {},
}
VirtualIndent.__index = VirtualIndent

--- Creates a new instance of VirtualIndent for a given buffer or returns the existing instance if
--- one exists
---@param bufnr? integer Buffer to use for VirtualIndent when attached
---@return OrgVirtualIndent
function VirtualIndent:new(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if self._bufnrs[bufnr] then
    return self._bufnrs[bufnr]
  end
  local this = setmetatable({
    _bufnr = bufnr,
    _attached = false,
  }, self)
  self._bufnrs[bufnr] = this
  return this
end

function VirtualIndent.toggle_buffer_indent_mode(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local instance = VirtualIndent:new(bufnr)
  local message = ''
  if vim.b[bufnr].org_indent_mode then
    message = 'disabled'
    instance:detach()
  else
    message = 'enabled'
    instance:attach()
  end
  require('orgmode.utils').echo_info('Org-Indent mode ' .. message .. ' in current buffer')
end

--- Deletes all extmarks in the indent namespace within the given line range
--- Uses nvim_buf_clear_namespace for efficient batch deletion
---@param start_line number 0-indexed start line (inclusive)
---@param end_line number 0-indexed end line (inclusive)
function VirtualIndent:_delete_old_extmarks(start_line, end_line)
  -- Clear all extmarks in the namespace within the range
  -- Note: clear_namespace uses end-exclusive range, so we add 1 to end_line
  pcall(vim.api.nvim_buf_clear_namespace, self._bufnr, self._ns_id, start_line, end_line + 1)
end

function VirtualIndent:_get_indent_size(line, tree_has_errors)
  -- If tree has errors, we can't rely on treesitter to get the correct indentation
  -- Fallback to searching closest headline by checking each previous line
  if tree_has_errors then
    local linenr = line
    while linenr > 0 do
      -- We offset `linenr` by 1 because it's 0-indexed and `getline` is 1-indexed
      local _, level = vim.fn.getline(linenr + 1):find('^%*+')
      if level then
        -- If the current line is a headline we should return no virtual indentation, otherwise
        -- return virtual indentation
        return (linenr == line and 0 or level + 1)
      end
      linenr = linenr - 1
    end
  end

  local headline = tree_utils.closest_headline_node({ line + 1, 1 })

  if headline then
    local headline_line = headline:start()

    if headline_line ~= line then
      local _, level = headline:field('stars')[1]:end_()
      return level + 1
    end
  end

  return 0
end

--- Optimized version that uses cached headline information to avoid redundant treesitter queries
--- Falls back to original implementation when cached data is not available
---@param line number 0-indexed line number
---@param tree_has_errors boolean whether the treesitter parse tree has errors
---@param cached_headline table|nil pre-queried headline node
---@param cached_indent number|nil pre-calculated indent level
---@return number indent size for the line
function VirtualIndent:_get_indent_size_cached(line, tree_has_errors, cached_headline, cached_indent)
  -- If no cached data available, fallback to original implementation
  if not cached_headline or cached_indent == nil then
    return self:_get_indent_size(line, tree_has_errors)
  end

  -- If tree has errors, fallback to the original implementation
  if tree_has_errors then
    return self:_get_indent_size(line, tree_has_errors)
  end

  -- Fast check: is current line a headline? (avoids treesitter query)
  -- Headlines always have indent 0
  local current_line_text = vim.api.nvim_buf_get_lines(self._bufnr, line, line + 1, false)[1]
  if current_line_text and current_line_text:match('^%*+%s') then
    return 0
  end

  -- Use cached headline information
  local headline_line = cached_headline:start()
  if headline_line ~= line then
    return cached_indent
  end

  return 0
end

---@param start_line number start line number to set the indentation, 0-based inclusive
---@param end_line number end line number to set the indentation, 0-based inclusive
---@param ignore_ts? boolean whether or not to skip the treesitter start & end lookup
function VirtualIndent:set_indent(start_line, end_line, ignore_ts)
  ignore_ts = ignore_ts or false

  -- Query headline once for the entire range
  local headline = tree_utils.closest_headline_node({ start_line + 1, 1 })
  local cached_indent = nil

  if headline and not ignore_ts then
    -- Pre-calculate indent level BEFORE modifying start_line
    local headline_line = headline:start()
    local _, level = headline:field('stars')[1]:end_()
    cached_indent = level + 1

    -- Adjust range to parent boundaries
    local parent = headline:parent()
    if parent then
      start_line = math.min(parent:start(), start_line)
      end_line = math.max(parent:end_(), end_line)
    end
  end

  if start_line > 0 then
    start_line = start_line - 1
  end

  local node_at_cursor = tree_utils.get_node()
  local tree_has_errors = false
  if node_at_cursor then
    tree_has_errors = node_at_cursor:tree():root():has_error()
  end

  self:_delete_old_extmarks(start_line, end_line)

  for line = start_line, end_line do
    -- Use cached version to avoid redundant treesitter queries
    local indent = self:_get_indent_size_cached(line, tree_has_errors, headline, cached_indent)

    if indent > 0 then
      -- NOTE: `ephemeral = true` is not implemented for `inline` virt_text_pos :(
      pcall(vim.api.nvim_buf_set_extmark, self._bufnr, self._ns_id, line, 0, {
        virt_text = { { string.rep(' ', indent), 'OrgIndent' } },
        virt_text_pos = 'inline',
        right_gravity = false,
        priority = 110,
      })
    end
  end
end

--- Enables virtual indentation in registered buffer
function VirtualIndent:attach()
  if self._attached then
    return
  end
  self:set_indent(0, vim.api.nvim_buf_line_count(self._bufnr) - 1, true)

  vim.api.nvim_buf_attach(self._bufnr, false, {
    on_lines = function(_, _, _, start_line, _, end_line)
      if not self._attached then
        return true
      end

      vim.schedule(function()
        self:set_indent(start_line, end_line)
      end)
    end,
    on_reload = function()
      self:set_indent(0, vim.api.nvim_buf_line_count(self._bufnr) - 1, true)
    end,
    on_detach = function(_, bufnr)
      self:detach()
      self._bufnrs[bufnr] = nil
    end,
  })
  self._attached = true
  vim.b[self._bufnr].org_indent_mode = true
end

function VirtualIndent:detach()
  if not self._attached then
    return
  end
  self:_delete_old_extmarks(0, vim.api.nvim_buf_line_count(self._bufnr) - 1)
  self._attached = false
  vim.b[self._bufnr].org_indent_mode = false
end

return VirtualIndent
