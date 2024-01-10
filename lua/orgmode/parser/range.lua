---@class Range
---@field start_line number
---@field start_col number
---@field end_line number
---@field end_col number
local Range = {}

---@param data table
function Range:new(data)
  local opts = {}
  opts.start_line = data.start_line
  opts.start_col = data.start_col or 1
  opts.end_line = data.end_line
  opts.end_col = data.end_col or 1
  setmetatable(opts, self)
  self.__index = self
  return opts
end

function Range.from_node(node)
  if not node then
    return Range.from_line(0)
  end
  local start_line, start_col, end_line, end_col = node:range()
  local opts = {
    start_line = start_line + 1,
    start_col = start_col + 1,
    end_line = end_line + 1,
    end_col = end_col,
  }

  if end_col == 0 and start_line ~= end_line then
    opts.end_line = opts.end_line - 1
  end
  return Range:new(opts)
end

---@param lnum number
---@return Range
function Range.from_line(lnum)
  return Range:new({ start_line = lnum, end_line = lnum })
end

---@param lnum number
---@return Range
function Range.for_line_hl(lnum)
  return Range:new({ start_line = lnum, end_line = lnum, end_col = 0 })
end

---@return boolean
function Range:is_same_line()
  return self.start_line == self.end_line
end

---@param line number
---@param col number
---@return boolean
function Range:is_in_range(line, col)
  return self:is_in_line_range(line) and col >= self.start_col and col <= self.end_col
end

function Range:is_in_line_range(line)
  return line >= self.start_line and line <= self.end_line
end

function Range:clone()
  return Range:new({
    start_line = self.start_line,
    end_line = self.end_line,
    start_col = self.start_col,
    end_col = self.end_col,
  })
end

return Range
