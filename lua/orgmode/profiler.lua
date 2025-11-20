local M = {}

M.timings = {}
M.call_counts = {}
M.enabled = false
M.instrumented = false

function M.wrap(module_name, func_name, func)
  return function(...)
    if not M.enabled then
      return func(...)
    end

    local start = vim.loop.hrtime()
    local result = { func(...) }
    local elapsed = (vim.loop.hrtime() - start) / 1e6

    local key = module_name .. '.' .. func_name
    M.timings[key] = (M.timings[key] or 0) + elapsed
    M.call_counts[key] = (M.call_counts[key] or 0) + 1

    return unpack(result)
  end
end

function M.start()
  M.enabled = true
  M.timings = {}
  M.call_counts = {}
  vim.notify('🔬 Orgmode profiler started', vim.log.levels.INFO)
end

function M.stop()
  M.enabled = false

  local sorted = {}
  for key, time in pairs(M.timings) do
    table.insert(sorted, { key = key, time = time, calls = M.call_counts[key] })
  end
  table.sort(sorted, function(a, b)
    return a.time > b.time
  end)

  print('\n' .. string.rep('=', 80))
  print('📊 ORGMODE PROFILING RESULTS')
  print(string.rep('=', 80))
  print(string.format('%-50s %10s %10s %10s', 'Function', 'Total(ms)', 'Calls', 'Avg(ms)'))
  print(string.rep('-', 80))

  for _, entry in ipairs(sorted) do
    local avg = entry.time / entry.calls
    print(string.format('%-50s %10.2f %10d %10.2f', entry.key, entry.time, entry.calls, avg))
  end

  if #sorted > 0 then
    print('\n' .. string.rep('=', 80))
    print('🔥 TOP 5 BOTTLENECKS')
    print(string.rep('=', 80))
    for i = 1, math.min(5, #sorted) do
      local e = sorted[i]
      print(string.format('%d. %s', i, e.key))
      print(string.format('   Total: %.2f ms | Avg: %.2f ms | Calls: %d', e.time, e.time / e.calls, e.calls))
    end
  end

  print(string.rep('=', 80))
  vim.notify('✅ Profiling stopped. Results printed above.', vim.log.levels.INFO)
end

function M.instrument_virtual_indent()
  local ok, VirtualIndent = pcall(require, 'orgmode.ui.virtual_indent')
  if not ok then
    vim.notify('⚠ VirtualIndent not loaded', vim.log.levels.WARN)
    return
  end

  local original_set_indent = VirtualIndent.set_indent
  VirtualIndent.set_indent = M.wrap('VirtualIndent', 'set_indent', original_set_indent)

  local original_get_indent_size = VirtualIndent._get_indent_size
  VirtualIndent._get_indent_size = M.wrap('VirtualIndent', '_get_indent_size', original_get_indent_size)

  local original_delete_extmarks = VirtualIndent._delete_old_extmarks
  VirtualIndent._delete_old_extmarks = M.wrap('VirtualIndent', '_delete_old_extmarks', original_delete_extmarks)

  vim.notify('✓ VirtualIndent instrumented', vim.log.levels.INFO)
end

function M.instrument_highlighter()
  local ok, highlighter = pcall(require, 'orgmode.colors.highlighter')
  if not ok then
    vim.notify('⚠ Highlighter not loaded', vim.log.levels.WARN)
    return
  end

  if highlighter.reload then
    local original = highlighter.reload
    highlighter.reload = M.wrap('Highlighter', 'reload', original)
  end

  vim.notify('✓ Highlighter instrumented', vim.log.levels.INFO)
end

function M.instrument_tree_utils()
  local ok, tree_utils = pcall(require, 'orgmode.utils.treesitter')
  if not ok then
    vim.notify('⚠ TreeUtils not loaded', vim.log.levels.WARN)
    return
  end

  if tree_utils.closest_headline_node then
    local original = tree_utils.closest_headline_node
    tree_utils.closest_headline_node = M.wrap('TreeUtils', 'closest_headline_node', original)
  end

  vim.notify('✓ TreeUtils instrumented', vim.log.levels.INFO)
end

function M.instrument_all()
  if M.instrumented then
    return
  end
  M.instrument_virtual_indent()
  M.instrument_highlighter()
  M.instrument_tree_utils()
  M.instrumented = true
  vim.notify('🎯 All modules instrumented', vim.log.levels.INFO)
end

function M.toggle()
  if M.enabled then
    M.stop()
  else
    M.instrument_all()
    M.start()
  end
end

function M.setup_commands()
  vim.api.nvim_create_user_command('OrgProfileStart', function()
    M.instrument_all()
    M.start()
  end, {
    desc = 'Start orgmode performance profiling',
  })

  vim.api.nvim_create_user_command('OrgProfileStop', function()
    M.stop()
  end, {
    desc = 'Stop orgmode profiling and show results',
  })

  vim.api.nvim_create_user_command('OrgProfileToggle', function()
    M.toggle()
  end, {
    desc = 'Toggle orgmode profiling on/off',
  })
end

-- Auto-register commands on module load (matches orgmode pattern)
vim.schedule(function()
  M.setup_commands()
end)

return M
