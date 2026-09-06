local Template = require('orgmode.capture.template')
local config = require('orgmode.config')
local org = require('orgmode')

---@param lines string[]
---@return string
local function create_destination(lines)
  local destination = vim.fn.tempname() .. '.org'
  vim.fn.writefile(lines, destination)
  -- Look the file up once so the buffer cache records a miss for it
  org.files:get(destination)
  return destination
end

---@param destination string
---@return number previous window
local function open_capture(destination)
  local previous_win = vim.api.nvim_get_current_win()
  org.capture:open_template(Template:new({ template = '* %?', target = destination }))
  vim.wait(1000, function()
    return vim.b.org_capture == true
  end)
  assert.is.True(vim.b.org_capture)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '* captured' })
  return previous_win
end

describe('Capture :w', function()
  after_each(function()
    config:extend({ win_split_mode = 'horizontal' })
    vim.cmd('silent! %bwipeout!')
  end)

  it('refiles into a destination that has no buffer', function()
    local destination = create_destination({ '* existing' })
    open_capture(destination)

    vim.cmd('write')

    assert.are.same({ '* existing', '* captured' }, vim.fn.readfile(destination))
    assert.are.same(destination, vim.api.nvim_buf_get_name(0))
    assert.are.same('org', vim.bo.filetype)
    assert.is.Nil(vim.b.org_capture)
  end)

  it('treats a second :w in the destination as a plain write', function()
    local destination = create_destination({ '* existing' })
    open_capture(destination)
    vim.cmd('write')

    vim.cmd('write')

    assert.are.same({ '* existing', '* captured' }, vim.fn.readfile(destination))
  end)

  it(':wq closes the window and returns to the previous one', function()
    local destination = create_destination({ '* existing' })
    local previous_win = open_capture(destination)
    local windows = #vim.api.nvim_list_wins()

    vim.cmd('wq')

    assert.are.same({ '* existing', '* captured' }, vim.fn.readfile(destination))
    assert.are.same(windows - 1, #vim.api.nvim_list_wins())
    assert.are.same(previous_win, vim.api.nvim_get_current_win())
  end)

  it('shows the destination inside a floating capture window', function()
    config:extend({ win_split_mode = 'float' })
    local destination = create_destination({ '* existing' })
    local previous_win = open_capture(destination)
    assert.are_not.same('', vim.api.nvim_win_get_config(0).relative)

    vim.cmd('write')

    assert.are.same({ '* existing', '* captured' }, vim.fn.readfile(destination))
    assert.are.same(destination, vim.api.nvim_buf_get_name(0))
    assert.are.same('org', vim.bo.filetype)
    assert.are_not.same('', vim.api.nvim_win_get_config(0).relative)

    vim.cmd('quit')

    assert.are.same(previous_win, vim.api.nvim_get_current_win())
  end)
end)
