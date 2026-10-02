local AgendaItem = require('orgmode.agenda.agenda_item')
local AgendaType = require('orgmode.agenda.types.agenda')
local Date = require('orgmode.objects.date')
local OrgFiles = require('orgmode.files')

-- The agenda shows 2024-03-20 to 2024-04-09, so today is never one of its days.
-- One headline per kind of date. Add a row for every new way a date can show up in the agenda.
local cases = {
  { headline = 'TODO Plain date before the agenda', date = '<2024-03-01 Fri>' },
  { headline = 'TODO Plain date', date = '<2024-03-22 Fri>' },
  { headline = 'TODO Date with time', date = '<2024-03-26 Tue 10:00>' },
  { headline = 'TODO Weekly repeater', date = 'SCHEDULED: <2024-02-21 Wed +1w>' },
  { headline = 'TODO Daily repeater with time', date = '<2024-03-10 Sun 10:00 +1d>' },
  { headline = 'TODO Range', date = '<2024-03-28 Thu>--<2024-04-02 Tue>' },
  { headline = 'TODO Deadline', date = 'DEADLINE: <2024-03-24 Sun>' },
  { headline = 'TODO Deadline with warning period', date = 'DEADLINE: <2024-03-30 Sat -5d>' },
  { headline = 'TODO Scheduled', date = 'SCHEDULED: <2024-03-21 Thu>' },
  { headline = 'TODO Scheduled with delay', date = 'SCHEDULED: <2024-03-27 Wed -2d>' },
  { headline = 'DONE Done scheduled', date = 'SCHEDULED: <2024-04-03 Wed>' },
}

---What the agenda shows on the day
---@param agenda_day OrgAgendaDay
local function shown_labels(agenda_day)
  local items = vim.tbl_filter(function(item)
    return getmetatable(item) == AgendaItem
  end, agenda_day.agenda_items)
  table.sort(items, function(a, b)
    return a.index < b.index
  end)
  return vim.tbl_map(function(item)
    return item.label
  end, items)
end

---What the agenda would show on the day if it checked every date against it
---@param files OrgFiles
---@param day OrgDate
local function expected_labels(files, day)
  local result = {}
  for _, orgfile in ipairs(files:all()) do
    for _, headline in ipairs(orgfile:get_opened_headlines()) do
      for _, headline_date in ipairs(headline:get_valid_dates_for_agenda()) do
        local item = AgendaItem:new(headline_date, headline, day)
        if item.is_valid then
          table.insert(result, item.label)
        end
      end
    end
  end
  return result
end

describe('Agenda days', function()
  local filename

  after_each(function()
    if filename then
      vim.fn.delete(filename)
      filename = nil
    end
  end)

  for _, case in ipairs(cases) do
    it(case.headline .. ' shows on the same days as checking every date against each day', function()
      filename = vim.fn.tempname() .. '.org'
      vim.fn.writefile({ '* ' .. case.headline, '  ' .. case.date }, filename)
      local files = OrgFiles:new({ paths = { filename } })
      files:load_sync(true)

      local view = AgendaType:new({ ---@diagnostic disable-line: missing-fields
        files = files,
        from = Date.from_string('2024-03-20 Wed'),
        span = 21,
        start_on_weekday = false,
      })

      local agenda_days = view:_get_agenda_days()
      assert.are.same(21, #agenda_days)
      local mismatched_days = {}
      for _, agenda_day in ipairs(agenda_days) do
        local expected = expected_labels(files, agenda_day.day)
        local shown = shown_labels(agenda_day)
        if not vim.deep_equal(expected, shown) then
          table.insert(mismatched_days, { day = agenda_day.day:to_string(), expected = expected, shown = shown })
        end
      end
      assert.are.same({}, mismatched_days)
    end)
  end
end)
