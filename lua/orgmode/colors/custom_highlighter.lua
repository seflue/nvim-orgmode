local Date = require('orgmode.objects.date')
local config = require('orgmode.config')
local namespace = vim.api.nvim_create_namespace('org_custom_highlighter')
local HideLeadingStars = nil
local MarkupHighlighter = nil
local valid_bufnrs = {}

---@param bufnr number
---@param first_line number
---@param last_line number
local function apply_highlights(bufnr, first_line, last_line, tick_changed)
  local changed_lines = vim.api.nvim_buf_get_lines(bufnr, first_line, last_line, false)
  HideLeadingStars.apply(namespace, bufnr, changed_lines, first_line, last_line)
  MarkupHighlighter.apply(namespace, bufnr, changed_lines, first_line, last_line, tick_changed)
end

local function is_valid_date(match, _, source, pred)
  if not pred[2] or not pred[3] then
    return false
  end
  local start_node = match[pred[2]]
  local end_node = match[pred[3]]
  if not start_node or not end_node then
    return false
  end
  local start_row, start_col = start_node:start()
  local end_row, end_col = end_node:end_()
  if start_row ~= end_row then
    return false
  end
  local text = vim.api.nvim_buf_get_text(source, start_row, start_col, end_row, end_col, {})
  if not text or not text[1] then
    return false
  end
  local is_valid = text[1]:find(Date.pattern)
  return is_valid ~= nil
end

local function setup()
  local ts_highlights_enabled = config:ts_highlights_enabled()
  if not ts_highlights_enabled then
    return
  end
  require('orgmode.colors.todo_highlighter').add_todo_keyword_highlights()
  HideLeadingStars = require('orgmode.colors.hide_leading_stars')
  MarkupHighlighter = require('orgmode.colors.markup_highlighter')
  vim.treesitter.query.add_predicate('org-is-valid-date?', is_valid_date)

  MarkupHighlighter.setup()

  vim.api.nvim_set_decoration_provider(namespace, {
    on_win = function(_, _, bufnr, topline, botline)
      local changedtick = vim.api.nvim_buf_get_var(bufnr, 'changedtick')
      local tick_changed = not valid_bufnrs[bufnr] or valid_bufnrs[bufnr] ~= changedtick
      if valid_bufnrs[bufnr] then
        valid_bufnrs[bufnr] = changedtick
        return apply_highlights(bufnr, topline, botline, tick_changed)
      end
      local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')
      if ft == 'org' then
        valid_bufnrs[bufnr] = changedtick
        return apply_highlights(bufnr, topline, botline, tick_changed)
      end
    end,
  })
end

return {
  setup = setup,
}
