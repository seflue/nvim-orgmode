local OrgPosition = require('orgmode.api.position')
local config = require('orgmode.config')
local PriorityState = require('orgmode.objects.priority_state')
local Date = require('orgmode.objects.date')
local Calendar = require('orgmode.objects.calendar')
local Promise = require('orgmode.utils.promise')
local org = require('orgmode')
local Buffers = require('orgmode.state.buffers')

---@class OrgApiHeadline
---@field title string headline title without todo keyword, tags and priority. Ex. `* TODO I am a headline  :SOMETAG:` returns `I am a headline`
---@field line string full headline line
---@field level number headline level (number of asterisks). Example: 1
---@field todo_value? string todo keyword of the headline (Example: TODO, DONE)
---@field todo_type? 'TODO' | 'DONE' | ''
---@field tags string[] List of own tags
---@field deadline OrgDate|nil
---@field scheduled OrgDate|nil
---@field properties table<string, string> Table containing all properties. All keys are lowercased
---@field closed OrgDate|nil
---@field dates OrgDate[] List of all dates that are not "plan" dates
---@field position OrgRange
---@field all_tags string[] List of all tags (own + inherited)
---@field file OrgApiFile
---@field parent OrgApiHeadline|nil
---@field priority string|nil
---@field is_archived boolean headline marked with the `:ARCHIVE:` tag
---@field headlines OrgApiHeadline[]
---@field private _section OrgHeadline
---@field private _file_version number version of the file the handle was built from
---@field private _line_unique boolean no other headline in the file had the same line when the handle was built
local OrgHeadline = {}

---@private
function OrgHeadline:_new(opts)
  local data = {}
  data.file = opts.file
  data.todo_type = opts.todo_type
  data.todo_value = opts.todo_value
  data.title = opts.title
  data.line = opts.line
  data.level = opts.level
  data.category = opts.category
  data.position = opts.position
  data.tags = opts.tags
  data.all_tags = opts.all_tags
  data.priority = opts.priority
  data.deadline = opts.deadline
  data.properties = opts.properties
  data.scheduled = opts.scheduled
  data.closed = opts.closed
  data.dates = opts.dates
  data.is_archived = opts.is_archived
  data.parent = opts.parent
  data.headlines = opts.headlines or {}
  data._section = opts._section
  data._file_version = opts._file_version

  setmetatable(data, self)
  self.__index = self
  return data
end

---@param section OrgHeadline
---@private
function OrgHeadline._build_from_internal_headline(section)
  local todo, _, type = section:get_todo()
  local properties = section:get_own_properties()
  return OrgHeadline:_new({
    title = section:get_title(),
    line = section:get_headline_line_content(),
    level = section:get_level(),
    todo_type = type,
    todo_value = todo,
    all_tags = section:get_tags(),
    tags = section:get_own_tags(),
    ---@diagnostic disable-next-line: invisible
    position = OrgPosition:_build_from_internal_range(section:get_range()),
    properties = properties,
    deadline = section:get_deadline_date(),
    scheduled = section:get_scheduled_date(),
    closed = section:get_closed_date(),
    dates = vim.tbl_filter(function(date)
      return date:is_none()
    end, section:get_all_dates()),
    priority = section:get_priority(),
    is_archived = section:is_archived(),
    _section = section,
    _file_version = section.file.version,
  })
end

--- Return updated version of headline
---@return OrgApiHeadline
function OrgHeadline:reload()
  local file = self.file:reload()
  ---@diagnostic disable-next-line: invisible
  local section = self:_find_section(file._file)
  return file:get_headline_on_line(section:get_range().start_line)
end

--- Set tags on the headline. This replaces all current tags with provided ones
---@param tags string[]
---@return OrgPromise
function OrgHeadline:set_tags(tags)
  return self:_do_action(function()
    local headline = org.files:get_closest_headline()
    headline:set_tags(string.format(':%s:', table.concat(tags, ':')))
  end)
end

--- Increase priority on a headline
---@return OrgPromise
function OrgHeadline:priority_up()
  return self:_do_action(function()
    local headline = org.files:get_closest_headline()
    local current_priority = headline:get_priority()
    local prio_range = config:get_priority_range()
    local start_with_default = config.org_priority_start_cycle_with_default
    local priority_state = PriorityState:new(current_priority, prio_range, start_with_default)
    return headline:set_priority(priority_state:increase())
  end)
end

--- Decrease priority on a headline
---@return OrgPromise
function OrgHeadline:priority_down()
  return self:_do_action(function()
    local headline = org.files:get_closest_headline()
    local current_priority = headline:get_priority()
    local prio_range = config:get_priority_range()
    local start_with_default = config.org_priority_start_cycle_with_default
    local priority_state = PriorityState:new(current_priority, prio_range, start_with_default)
    return headline:set_priority(priority_state:decrease())
  end)
end

--- Set specific priority on a headline. Empty string clears the priority
---@param priority string
---@return OrgPromise
function OrgHeadline:set_priority(priority)
  return self:_do_action(function()
    local headline = org.files:get_closest_headline()
    return headline:set_priority(priority)
  end)
end

--- Set deadline date
---@param date? OrgDate|string|nil If ommited, opens the datepicker. Empty string removes the date. String must follow org date convention (YYYY-MM-DD HH:mm...)
---@return OrgPromise
function OrgHeadline:set_deadline(date)
  return self:_do_action(function()
    local headline = org.files:get_closest_headline()
    local deadline_date = headline:get_deadline_date()
    if not date then
      return Calendar.new({ date = deadline_date or Date.today(), clearable = true, title = 'Set deadline' })
        :open()
        :next(function(new_date, cleared)
          if cleared then
            return headline:remove_deadline_date()
          end
          if not new_date then
            return
          end
          return headline:set_deadline_date(new_date)
        end)
    end

    if type(date) == 'string' then
      if date == '' then
        return headline:remove_deadline_date()
      end
      local date_instance = Date.from_string(date)
      if date_instance then
        return headline:set_deadline_date(date_instance)
      end
      error('Invalid string format for deadline date', 0)
    end

    if Date.is_date_instance(date) then
      return headline:set_deadline_date(date)
    end

    error('Invalid argument to set_deadline', 0)
  end)
end

--- Set scheduled date
---@param date? OrgDate|string|nil If ommited, opens the datepicker. Empty string removes the date. String must follow org date convention (YYYY-MM-DD HH:mm...)
---@return OrgPromise
function OrgHeadline:set_scheduled(date)
  return self:_do_action(function()
    local headline = org.files:get_closest_headline()
    local scheduled_date = headline:get_scheduled_date()
    if not date then
      return Calendar.new({ date = scheduled_date or Date.today(), clearable = true, title = 'Set schedule' })
        :open()
        :next(function(new_date, cleared)
          if cleared then
            return headline:remove_scheduled_date()
          end
          if not new_date then
            return
          end
          return headline:set_scheduled_date(new_date)
        end)
    end

    if type(date) == 'string' then
      if date == '' then
        return headline:remove_scheduled_date()
      end
      local date_instance = Date.from_string(date)
      if date_instance then
        return headline:set_scheduled_date(date_instance)
      end
      error('Invalid string format for schedule date', 0)
    end

    if Date.is_date_instance(date) then
      return headline:set_scheduled_date(date)
    end

    error('Invalid argument to set_scheduled', 0)
  end)
end

--- Set property on a headline. Setting value to nil removes the property
---@param key string
---@param value? string
function OrgHeadline:set_property(key, value)
  return self:_do_action(function()
    local headline = org.files:get_closest_headline()
    return headline:set_property(key, value)
  end)
end

--- Get headline property
---@param key string
---@return string | nil
function OrgHeadline:get_property(key)
  return self.properties[key:lower()]
end

--- Get headline id or create a new one if it doesn't exist
--- @return string
function OrgHeadline:id_get_or_create()
  local id = self:get_property('id')
  if id then
    return id
  end
  local org_id = require('orgmode.org.id').new()
  self:set_property('ID', org_id):wait()
  return org_id
end

--- Find this headline in the current state of the file. Raises an error instead of guessing.
---@param file OrgFile
---@return OrgHeadline
---@private
function OrgHeadline:_find_section(file)
  local sections = file:get_headlines()
  local id = self.properties.id
  if id then
    local by_id = vim.tbl_filter(function(section)
      return section:get_property('id', false) == id
    end, sections)
    if #by_id == 1 then
      return by_id[1]
    end
    error(string.format('Headline "%s" not found in %s', self.line, self.file.filename), 0)
  end

  if file.version == self._file_version then
    return file:get_closest_headline({ self.position.start_line, 0 })
  end

  local same_line = vim.tbl_filter(function(section)
    return section:get_headline_line_content() == self.line
  end, sections)
  if self._line_unique and #same_line == 1 then
    return same_line[1]
  end
  error(string.format('Headline "%s" not found in %s', self.line, self.file.filename), 0)
end

---@param target table
---@param source table
local function replace_fields(target, source)
  for key in pairs(target) do
    target[key] = nil
  end
  for key, value in pairs(source) do
    target[key] = value
  end
end

--- Refresh the file and headline handles of one load in place, matching headlines by index
---@param old_file OrgApiFile
---@param new_file OrgApiFile
local function refresh_handles(old_file, new_file)
  local old_headlines = old_file.headlines
  local old_by_new = {}
  for i, headline in ipairs(new_file.headlines) do
    old_by_new[headline] = old_headlines[i]
  end

  replace_fields(old_file, new_file)
  old_file.headlines = old_headlines
  for i, headline in ipairs(new_file.headlines) do
    local old = old_headlines[i]
    replace_fields(old, headline)
    old.file = old_file
    old.parent = headline.parent and old_by_new[headline.parent]
    old.headlines = vim.tbl_map(function(child)
      return old_by_new[child]
    end, headline.headlines)
  end
end

---@param action function
---@private
function OrgHeadline:_do_action(action)
  local file = org.files:get(self.file.filename)
  local ok, section = pcall(self._find_section, self, file)
  if not ok then
    return Promise.reject(section)
  end
  local start_line = section:get_range().start_line
  local all_handles_valid = true
  for _, headline in ipairs(self.file.headlines) do
    if headline._file_version ~= file.version then
      all_handles_valid = false
    end
  end
  return org.files
    :update_file(self.file.filename, function()
      local view = vim.fn.winsaveview() or {}
      vim.fn.cursor({ start_line, 1 })
      return Promise.resolve(action()):next(function()
        vim.fn.winrestview(view)
      end)
    end)
    :next(function()
      local new_file = self.file:reload()
      local updated = new_file:get_headline_on_line(start_line)
      if not updated then
        error(string.format('Headline "%s" is no longer on line %d', self.line, start_line), 0)
      end
      -- Keeps the handles usable for further actions
      if all_handles_valid and #new_file.headlines == #self.file.headlines then
        refresh_handles(self.file, new_file)
      else
        replace_fields(self, updated)
      end
      return self
    end)
end

--- Get a link destination as string
---
--- Depending if org_id_link_to_org_use_id is set the format is
---
--- id:<uuid>::*title and the id is created if not existing
--- or
--- file:<filepath>::*title
---
--- The result is meant to be used as link_location for OrgApi.insert_link.
--- @return string
function OrgHeadline:get_link()
  local filename = self.file.filename
  local section = self:_find_section(org.files:get(filename))
  local bufnr = Buffers.get_buffer_by_filename(filename)

  if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
    -- do remote edit
    return org.files
      :update_file(filename, function(_)
        return org.links:get_link_to_headline(section)
      end)
      :wait()
  end

  return org.links:get_link_to_headline(section)
end

return OrgHeadline
