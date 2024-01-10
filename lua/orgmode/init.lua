_G.orgmode = _G.orgmode or {}
local ts_revision = '081179c52b3e8175af62b9b91dc099d010c38770'
local setup_ts_grammar_used = false
local instance = nil

---@class Org
---@field initialized boolean
---@field files Files
---@field agenda Agenda
---@field capture Capture
---@field clock Clock
---@field notifications Notifications
local Org = {}

function Org:new()
  local data = { initialized = false }
  setmetatable(data, self)
  self.__index = self
  data:setup_autocmds()
  return data
end

function Org:init()
  if self.initialized then
    return
  end
  require('orgmode.colors.custom_highlighter').setup()
  require('orgmode.events').init()
  self.files = require('orgmode.parser.files').new()
  self.agenda = require('orgmode.agenda'):new()
  self.capture = require('orgmode.capture'):new()
  self.org_mappings = require('orgmode.org.mappings'):new({
    capture = self.capture,
    agenda = self.agenda,
  })
  self.clock = require('orgmode.clock'):new()
  require('orgmode.org.autocompletion').register()
  self.statusline_debounced = require('orgmode.utils').debounce('statusline', self.clock.get_statusline, 300)
  self.initialized = true
end

---@param file? string
function Org:reload(file)
  self:init()
  return self.files.reload(file)
end

function Org:setup_autocmds()
  local org_augroup = vim.api.nvim_create_augroup('orgmode_nvim', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = { '*.org', '*.org_archive' },
    group = org_augroup,
    callback = function(event)
      require('orgmode').reload(vim.fn.fnamemodify(event.file, ':p'))
    end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'org',
    group = org_augroup,
    callback = function()
      require('orgmode').reload(vim.fn.expand('<afile>:p'))
    end,
  })
end

--- @param revision string?
local function setup_ts_grammar(revision)
  setup_ts_grammar_used = true
  local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
  parser_config.org = {
    install_info = {
      url = 'https://github.com/milisims/tree-sitter-org',
      revision = revision or ts_revision,
      files = { 'src/parser.c', 'src/scanner.cc' },
    },
    filetype = 'org',
  }
end

local function check_ts_grammar()
  vim.defer_fn(function()
    if setup_ts_grammar_used then
      return
    end
    local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
    if parser_config and parser_config.org and parser_config.org.install_info.revision then
      if parser_config.org.install_info.revision ~= ts_revision then
        require('orgmode.utils').echo_error({
          'You are using outdated version of tree-sitter grammar for Orgmode.',
          'To use latest version, replace current grammar installation with "require(\'orgmode\').setup_ts_grammar()" and run :TSUpdate org.',
          'More info in setup section of readme: https://github.com/nvim-orgmode/orgmode#setup',
        })
      end
    else
      require('orgmode.utils').echo_error({
        'Cannot detect parser revision.',
        "Please check your org grammar's install info.",
        'Maybe you forgot to call "require(\'orgmode\').setup_ts_grammar()" before setup.',
      })
    end
  end, 200)
end

---@param opts? table
---@return Org
local function setup(opts)
  opts = opts or {}
  instance = Org:new()
  check_ts_grammar()
  local config = require('orgmode.config'):extend(opts)
  config:setup_ts_predicates()
  vim.defer_fn(function()
    if config.notifications.enabled and #vim.api.nvim_list_uis() > 0 then
      require('orgmode.parser.files').load(vim.schedule_wrap(function()
        instance.notifications = require('orgmode.notifications'):new():start_timer()
      end))
    end
    config:setup_mappings('global')
  end, 1)
  return instance
end

---@param file? string
---@return Org|nil
local function reload(file)
  if not instance then
    return
  end
  return instance:reload(file)
end

---@param cmd string
---@param opts string
local function set_dot_repeat(cmd, opts)
  local repeat_action = { string.format("'%s'", cmd) }
  if opts then
    table.insert(repeat_action, string.format("'%s'", opts))
  end
  vim.cmd(
    string.format(
      [[silent! call repeat#set("\<cmd>lua require('orgmode').action(%s)\<CR>")]],
      table.concat(repeat_action, ',')
    )
  )
end

---@param cmd string
---@param opts? any
local function action(cmd, opts)
  local parts = vim.split(cmd, '.', true)
  if not instance or #parts < 2 then
    return
  end
  instance:init()
  local item = nil
  for i = 1, #parts - 1 do
    local part = parts[i]
    if not item then
      item = instance[part]
    else
      item = item[part]
    end
  end
  if item and item[parts[#parts]] then
    local method = item[parts[#parts]]
    local success, result = pcall(method, item, opts)
    if not success then
      if result.message then
        return require('orgmode.utils').echo_error(result.message)
      end
      if type(result) == 'string' then
        return require('orgmode.utils').echo_error(result)
      end
    end
    set_dot_repeat(cmd, opts)
    return result
  end
end

local function cron(opts)
  local config = require('orgmode.config'):extend(opts or {})
  if not config.notifications.cron_enabled then
    return vim.cmd([[qa!]])
  end
  require('orgmode.parser.files').load(vim.schedule_wrap(function()
    instance.notifications = require('orgmode.notifications'):new():cron()
  end))
end

local function get_instance()
  if instance then
    return instance
  else
    error('Orgmode not correctly instanciated!')
  end
end

function _G.orgmode.statusline()
  if not instance or not instance.initialized then
    return ''
  end
  return instance.statusline_debounced() or ''
end

return {
  setup_ts_grammar = setup_ts_grammar,
  setup = setup,
  reload = reload,
  action = action,
  cron = cron,
  instance = get_instance,
}
