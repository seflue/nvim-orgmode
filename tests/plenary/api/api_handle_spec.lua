local helpers = require('tests.plenary.helpers')
local api = require('orgmode.api')
local config = require('orgmode.config')

describe('Api handles', function()
  ---@return OrgApiFile
  local cur_file = function()
    -- Wait for 1ms to ensure that the file is reloaded
    vim.wait(1)
    return api.current()
  end

  it('loads several files by a list of names', function()
    local first = helpers.create_agenda_file({ '* TODO First' })
    local second = helpers.create_agenda_file({ '* TODO Second' })

    local files = api.load({ first.filename, second.filename })
    local names = vim.tbl_map(function(file)
      return file.filename
    end, files)
    table.sort(names)
    local expected = { first.filename, second.filename }
    table.sort(expected)
    assert.are.same(expected, names)
  end)

  it('loads a file by a list of names that holds a symlink to it', function()
    local target = helpers.create_agenda_file({ '* TODO Target' })
    local link = vim.fn.tempname() .. '-link.org'
    vim.uv.fs_symlink(target.filename, link)

    local files = api.load({ link })
    vim.fn.delete(link)

    assert.are.same(
      { target.filename },
      vim.tbl_map(function(file)
        return file.filename
      end, files)
    )
  end)

  it('reloads the same headline after a headline was inserted above', function()
    helpers.create_file({
      '* TODO First',
      '* TODO Second',
    })
    local headline = cur_file().headlines[2]
    assert.are.same('Second', headline.title)

    vim.api.nvim_buf_set_lines(0, 0, 0, false, { '* TODO Inserted' })

    local reloaded = headline:reload()
    assert.are.same('Second', reloaded.title)
  end)

  it('applies a mutator to its own headline after lines were inserted above', function()
    helpers.create_file({
      '* TODO First',
      '* TODO Second',
    })
    local headline = cur_file().headlines[2]

    vim.api.nvim_buf_set_lines(0, 0, 0, false, { '* TODO Inserted' })

    headline:set_tags({ 'moved' }):wait()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.are.same('* TODO Inserted', lines[1])
    assert.are.same('* TODO First', lines[2])
    assert.is.Not.Nil(lines[3]:match('^%* TODO Second%s+:moved:$'))
  end)

  it('applies a second mutator through the same handle', function()
    helpers.create_file({
      '* TODO First',
      '* TODO Second',
    })
    local headline = cur_file().headlines[2]

    headline:set_tags({ 'one' }):wait()
    headline:set_priority('A'):wait()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.are.same('* TODO First', lines[1])
    assert.is.Not.Nil(lines[2]:match('^%* TODO %[#A%] Second%s+:one:$'))
  end)

  it('applies a mutator to every identical headline in a loop over one load', function()
    helpers.create_file({
      '* TODO Same',
      '* TODO Same',
    })

    for _, headline in ipairs(cur_file().headlines) do
      headline:set_priority('A'):wait()
    end

    assert.are.same({ '* TODO [#A] Same', '* TODO [#A] Same' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('keeps sibling handles valid after a mutation through another handle of the same load', function()
    helpers.create_file({
      '* TODO A',
      '* TODO Same',
      '* TODO Same',
    })
    local file = cur_file()

    file.headlines[1]:set_tags({ 'x' }):wait()
    file.headlines[2]:set_tags({ 'y' }):wait()

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.is.Not.Nil(lines[1]:match('^%* TODO A%s+:x:$'))
    assert.is.Not.Nil(lines[2]:match('^%* TODO Same%s+:y:$'))
    assert.are.same('* TODO Same', lines[3])
  end)

  it('updates the handle when its headline is mutated through a child handle parent', function()
    helpers.create_file({
      '* TODO Parent',
      '** TODO Child',
    })
    local parent = cur_file().headlines[1]

    parent:set_tags({ 'one' }):wait()
    parent.headlines[1].parent:set_priority('A'):wait()

    assert.are.same('A', parent.priority)
    assert.are.equal(parent, parent.headlines[1].parent)
  end)

  it('keeps the handle valid when a write hook changes the file on save', function()
    local group = vim.api.nvim_create_augroup('OrgApiHandleWriteHook', { clear = true })
    vim.api.nvim_create_autocmd('BufWritePre', {
      group = group,
      command = [[%s/\s\+$//e]],
    })
    helpers.create_file({
      '* TODO Same',
      'body ',
      '* TODO Same',
    })
    local headline = cur_file().headlines[2]

    local ok, err = pcall(function()
      headline:set_deadline('2026-01-01'):wait()
      headline:set_priority('A'):wait()
    end)
    vim.api.nvim_del_augroup_by_id(group)

    assert(ok, err)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.are.same({ '* TODO Same', 'body' }, { lines[1], lines[2] })
    assert.are.same('* TODO [#A] Same', lines[3])
  end)

  it('refiles its own headline after a headline was inserted above', function()
    local destination = helpers.create_agenda_file({ '* Destination' })
    helpers.create_file({
      '* TODO First',
      '* TODO Second',
    })
    local headline = cur_file().headlines[2]

    vim.api.nvim_buf_set_lines(0, 0, 0, false, { '* TODO Inserted' })
    api.refile({ source = headline, destination = api.load(destination.filename) }):wait()

    assert.are.same({ '* TODO Inserted', '* TODO First' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('creates the link id on its own headline after a headline was inserted above', function()
    helpers.create_file({
      '* TODO First',
      '* TODO Second',
    })
    local headline = cur_file().headlines[2]

    vim.api.nvim_buf_set_lines(0, 0, 0, false, { '* TODO Inserted' })
    local link = nil
    helpers.with_var(config.opts, 'org_id_link_to_org_use_id', true, function()
      link = headline:get_link()
    end)

    local id = link:match('^id:(.+)::%*Second$')
    assert.is.Not.Nil(id)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.are.same({ '* TODO Inserted', '* TODO First', '* TODO Second' }, { lines[1], lines[2], lines[3] })
    assert.is.Not.Nil(lines[5]:match(':ID: ' .. vim.pesc(id) .. '$'))
  end)

  it('returns the same id when id_get_or_create is called twice on a handle', function()
    helpers.create_file({ '* TODO First' })
    local headline = cur_file().headlines[1]

    local first_id = headline:id_get_or_create()
    local second_id = headline:id_get_or_create()

    assert.are.same(first_id, second_id)
    assert.are.same(first_id, cur_file().headlines[1]:get_property('id'))
  end)

  it('clears a removed date on the handle', function()
    helpers.create_file({ '* TODO First' })
    local headline = cur_file().headlines[1]

    headline:set_deadline('2026-01-01'):wait()
    assert.is.Not.Nil(headline.deadline)
    headline:set_deadline(''):wait()
    assert.is.Nil(headline.deadline)
  end)

  it('raises an error instead of guessing between identical headlines after an edit', function()
    helpers.create_file({
      '* TODO Same',
      '* TODO Same',
    })
    local headline = cur_file().headlines[2]

    vim.api.nvim_buf_set_lines(0, 0, 0, false, { '* TODO Inserted' })

    local promise = headline:set_tags({ 'x' })
    assert.has.error(function()
      promise:wait()
    end)
    assert.are.same({ '* TODO Inserted', '* TODO Same', '* TODO Same' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('passes the error to a catch handler when the handle no longer finds its headline', function()
    helpers.create_file({
      '* TODO Same',
      '* TODO Same',
    })
    local headline = cur_file().headlines[2]
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { '* TODO Inserted' })

    local caught = nil
    local ok = pcall(function()
      headline
        :set_tags({ 'x' })
        :catch(function(err)
          caught = err
        end)
        :wait()
    end)

    assert.is.True(ok)
    assert.is.Not.Nil(caught:match('not found'))
    assert.are.same({ '* TODO Inserted', '* TODO Same', '* TODO Same' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('raises an error when the headline with its id was deleted', function()
    helpers.create_file({
      '* TODO Same',
      '  :PROPERTIES:',
      '  :ID: first-id',
      '  :END:',
      '* TODO Same',
      '  :PROPERTIES:',
      '  :ID: second-id',
      '  :END:',
    })
    local headline = cur_file().headlines[1]

    vim.api.nvim_buf_set_lines(0, 0, 4, false, {})

    local promise = headline:set_tags({ 'x' })
    assert.has.error(function()
      promise:wait()
    end)
    assert.are.same(
      { '* TODO Same', '  :PROPERTIES:', '  :ID: second-id', '  :END:' },
      vim.api.nvim_buf_get_lines(0, 0, -1, false)
    )
  end)

  it('raises an error when two headlines share the id of the handle', function()
    helpers.create_file({
      '* TODO First',
      '  :PROPERTIES:',
      '  :ID: same-id',
      '  :END:',
      '* TODO Second',
      '  :PROPERTIES:',
      '  :ID: same-id',
      '  :END:',
    })
    local headline = cur_file().headlines[2]

    local promise = headline:set_tags({ 'x' })
    assert.has.error(function()
      promise:wait()
    end)
    assert.are.same('* TODO First', vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
  end)

  it('raises an error when the handle of one of two identical headlines outlives its headline', function()
    helpers.create_file({
      '* TODO Same',
      '* TODO Same',
    })
    local headline = cur_file().headlines[2]

    vim.api.nvim_buf_set_lines(0, 1, 2, false, {})

    local promise = headline:set_tags({ 'x' })
    assert.has.error(function()
      promise:wait()
    end)
    assert.are.same({ '* TODO Same' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it('acts on its own headline after the file was reordered and opened in a new buffer', function()
    -- The tick a buffer gets when the file is opened again
    local probe = helpers.create_file({ '* TODO Probe' })
    local probe_bufnr = vim.api.nvim_get_current_buf()
    vim.cmd('enew')
    vim.cmd('bwipeout ' .. probe_bufnr)
    vim.cmd('edit ' .. vim.fn.fnameescape(probe.filename))
    local reopen_tick = vim.api.nvim_buf_get_changedtick(0)

    local file = helpers.create_file({ '* TODO First', '* TODO Second' })
    local old_bufnr = vim.api.nvim_get_current_buf()
    while vim.api.nvim_buf_get_changedtick(old_bufnr) < reopen_tick do
      vim.api.nvim_buf_set_lines(old_bufnr, 0, 1, false, { '* TODO First' })
    end
    local old_tick = vim.api.nvim_buf_get_changedtick(old_bufnr)
    local headline = cur_file().headlines[2]

    vim.cmd('enew')
    vim.cmd('bwipeout! ' .. old_bufnr)
    vim.wait(10)
    vim.fn.writefile({ '* TODO Second', '* TODO First' }, file.filename)
    vim.cmd('edit ' .. vim.fn.fnameescape(file.filename))
    assert.are.same(old_tick, vim.api.nvim_buf_get_changedtick(0))

    headline:set_tags({ 'x' }):wait()

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.is.Not.Nil(lines[1]:match('^%* TODO Second%s+:x:$'))
    assert.are.same('* TODO First', lines[2])
  end)

  it('builds handles from the current buffer text when loading a list of files', function()
    local target = helpers.create_agenda_file({
      '* TODO Same',
      '* TODO Same',
    })
    local target_bufnr = vim.fn.bufnr(target.filename)
    vim.api.nvim_buf_set_lines(target_bufnr, 0, 0, false, { '* TODO Inserted' })

    api.load({ target.filename })[1].headlines[3]:set_tags({ 'x' }):wait()

    local lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
    assert.are.same('* TODO Same', lines[2])
    assert.is.Not.Nil(lines[3]:match('^%* TODO Same%s+:x:$'))
  end)

  it('has the id property set once id_get_or_create returns for a file not in the current buffer', function()
    local target = helpers.create_agenda_file({
      '* TODO Target',
    })
    local target_name = target.filename
    helpers.create_file({ '* TODO Other buffer' })

    local headline = api.load(target_name).headlines[1]
    local id = headline:id_get_or_create()

    local on_disk = vim.fn.readfile(target_name)
    assert.is.Not.Nil(table.concat(on_disk, '\n'):find(id, 1, true))
  end)
end)
