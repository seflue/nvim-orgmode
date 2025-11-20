local M = {}
local start_time = nil
local events = {}
local instrumented = false

function M.start()
  events = {}
  start_time = vim.loop.hrtime()
  vim.notify('🔬 Detailed profiler started', vim.log.levels.INFO)
end

function M.log_event(name, metadata)
  if not start_time then
    return
  end

  local timestamp = (vim.loop.hrtime() - start_time) / 1e6
  table.insert(events, {
    time = timestamp,
    name = name,
    metadata = metadata or {},
  })
end

function M.stop()
  if not start_time then
    vim.notify('⚠ Profiler not started', vim.log.levels.WARN)
    return
  end

  local file = io.open('/tmp/orgmode_profile.log', 'w')
  if not file then
    vim.notify('❌ Failed to write profile log', vim.log.levels.ERROR)
    return
  end

  file:write('timestamp_ms,event,metadata\n')

  for _, event in ipairs(events) do
    local details = vim.inspect(event.metadata):gsub('\n', ' '):gsub('"', "'")
    file:write(string.format('%.2f,%s,%s\n', event.time, event.name, details))
  end

  file:close()

  -- Quick analysis
  local treesitter_time = 0
  local extmark_time = 0
  local total_events = #events

  for i = 1, #events - 1 do
    local curr = events[i]
    local next_event = events[i + 1]
    local duration = next_event.time - curr.time

    if curr.name:match('treesitter') or curr.name:match('get_indent') then
      treesitter_time = treesitter_time + duration
    elseif curr.name:match('extmark') or curr.name:match('delete') then
      extmark_time = extmark_time + duration
    end
  end

  print('\n' .. string.rep('=', 60))
  print('📊 DETAILED PROFILING SUMMARY')
  print(string.rep('=', 60))
  print(string.format('Total events logged: %d', total_events))
  print(string.format('Treesitter time: %.2f ms', treesitter_time))
  print(string.format('Extmark time: %.2f ms', extmark_time))
  print(string.format('Log file: /tmp/orgmode_profile.log'))
  print(string.rep('=', 60))

  vim.notify('✅ Profile written to /tmp/orgmode_profile.log', vim.log.levels.INFO)
  start_time = nil
end

function M.instrument()
  if instrumented then
    return
  end

  local ok, VirtualIndent = pcall(require, 'orgmode.ui.virtual_indent')
  if not ok then
    vim.notify('⚠ VirtualIndent not loaded', vim.log.levels.WARN)
    return
  end

  local original_set_indent = VirtualIndent.set_indent
  VirtualIndent.set_indent = function(self, start_line, end_line, ignore_ts)
    M.log_event('set_indent_start', { start_line = start_line, end_line = end_line })
    local result = original_set_indent(self, start_line, end_line, ignore_ts)
    M.log_event('set_indent_end', { start_line = start_line, end_line = end_line })
    return result
  end

  local original_get_indent = VirtualIndent._get_indent_size
  VirtualIndent._get_indent_size = function(self, line, tree_has_errors)
    M.log_event('get_indent_start', { line = line, has_errors = tree_has_errors })
    local result = original_get_indent(self, line, tree_has_errors)
    M.log_event('get_indent_end', { line = line, indent = result })
    return result
  end

  local original_delete = VirtualIndent._delete_old_extmarks
  VirtualIndent._delete_old_extmarks = function(self, start_line, end_line)
    M.log_event('delete_extmarks_start', { start_line = start_line, end_line = end_line })
    local result = original_delete(self, start_line, end_line)
    M.log_event('delete_extmarks_end', { start_line = start_line, end_line = end_line })
    return result
  end

  instrumented = true
  vim.notify('🎯 Detailed instrumentation active', vim.log.levels.INFO)
end

function M.toggle()
  if start_time then
    M.stop()
  else
    M.instrument()
    M.start()
  end
end

function M.setup_commands()
  vim.api.nvim_create_user_command('OrgProfileDetailedStart', function()
    M.instrument()
    M.start()
  end, {
    desc = 'Start detailed orgmode performance profiling',
  })

  vim.api.nvim_create_user_command('OrgProfileDetailedStop', function()
    M.stop()
  end, {
    desc = 'Stop detailed profiling and save timeline to /tmp/orgmode_profile.log',
  })

  vim.api.nvim_create_user_command('OrgProfileDetailedToggle', function()
    M.toggle()
  end, {
    desc = 'Toggle detailed orgmode profiling on/off',
  })
end

-- Auto-register commands on module load (matches orgmode pattern)
vim.schedule(function()
  M.setup_commands()
end)

return M
