local OrgFiles = require('orgmode.files')

---@param fixtures table<string, string[]>
---@return OrgFiles, string
local function build(fixtures)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  for name, content in pairs(fixtures) do
    vim.fn.writefile(content, dir .. '/' .. name)
  end
  local files = OrgFiles:new({ paths = dir .. '/*' })
  files:load_sync(true, 10000)
  return files, dir
end

---@param files OrgFiles
---@param basename string
---@return OrgFile
local function file_named(files, basename)
  for _, file in ipairs(files:all()) do
    if vim.fn.fnamemodify(file.filename, ':t') == basename then
      return file
    end
  end
  error('fixture not found: ' .. basename)
end

local closed = {
  '* TODO Closed',
  '  :LOGBOOK:',
  '  CLOCK: [2026-09-08 Tue 09:15]--[2026-09-08 Tue 10:30] =>  1:15',
  '  :END:',
}

local plain = {
  '* TODO Plain',
  '  Nothing to see here.',
}

local running = {
  '* TODO Running',
  '  :LOGBOOK:',
  '  CLOCK: [2026-09-08 Tue 11:00]',
  '  :END:',
}

describe('OrgFiles get_clocked_headline', function()
  it('should find the headline with the running clock', function()
    local files = build({ ['a_closed.org'] = closed, ['b_plain.org'] = plain, ['c_running.org'] = running })
    local headline = files:get_clocked_headline()
    assert.is.Not.Nil(headline)
    assert.are.same('Running', headline:get_title())
    assert.is_true(headline:is_clocked_in())
  end)

  it('should not parse files that cannot hold a running clock', function()
    local files = build({ ['a_closed.org'] = closed, ['b_plain.org'] = plain, ['c_running.org'] = running })
    files:get_clocked_headline()
    assert.is.Nil(file_named(files, 'a_closed.org').root)
    assert.is.Nil(file_named(files, 'b_plain.org').root)
    assert.is.Not.Nil(file_named(files, 'c_running.org').root)
  end)

  it('should return nil when every clock is closed', function()
    local files = build({ ['a_closed.org'] = closed, ['b_plain.org'] = plain })
    assert.is.Nil(files:get_clocked_headline())
  end)

  it('should ignore a running clock in an archive file', function()
    local files = build({ ['a_archived.org_archive'] = running })
    assert.is.Nil(files:get_clocked_headline())
  end)
end)
