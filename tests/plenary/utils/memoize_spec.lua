local Memoize = require('orgmode.utils.memoize')
local OrgFile = require('orgmode.files.file')

describe('Memoize', function()
  ---@return OrgFile
  local new_file = function(content, filename)
    content = content or {}
    filename = filename or vim.fn.tempname() .. '.org'
    return OrgFile:new({ filename = filename, lines = content })
  end

  ---Number of per-node buckets held for a file. Bookkeeping keys are not
  ---buckets.
  ---@param file OrgFile
  local function buckets(file)
    local count = 0
    for key in pairs(file.memoize_cache or {}) do
      if not tostring(key):match('^__') then
        count = count + 1
      end
    end
    return count
  end

  local function collect()
    collectgarbage('collect')
    collectgarbage('collect')
  end

  it('does not keep a file alive once nothing else references it', function()
    local weak = setmetatable({}, { __mode = 'v' })

    do
      local file = new_file({ '* Headline 1', '  body' })
      weak.file = file
      file:get_headlines()
      assert.is_not_nil(weak.file)
    end

    collect()

    assert.is_nil(weak.file)
  end)

  it('does not accumulate buckets when the tree is replaced', function()
    local file = new_file({ '* Headline 1', '  body' })
    file:get_headlines()

    local baseline = buckets(file)

    -- Rewrite the body five times. The headline count never changes, so the
    -- number of live buckets must not change either.
    -- Dropping the parser forces a fresh tree on each round, which is what an
    -- edit in a loaded buffer does; without it the parser is reused and the
    -- node ids stay identical.
    for i = 1, 5 do
      file.parser = nil
      file:_update_lines({ '* Headline 1', '  body ' .. i })
      file:get_headlines()
    end

    assert.are.same(baseline, buckets(file))
  end)

  it('keeps results of different methods apart', function()
    local file = new_file({ '#+PROPERTY: header-args :results output', '* Headline 1' })
    -- Parse first, so both calls use the same bucket
    file:parse()

    -- `get_directive` with the argument `properties` and `get_directive_properties`
    -- without arguments must not share a cache entry
    assert.are.same('table', type(file:get_directive_properties()))
    assert.is_nil(file:get_directive('properties'))
  end)

  it('keeps results of different arguments apart', function()
    local Joiner = {}
    local memoize = Memoize:new(Joiner, function(self)
      return self.file, 'joiner'
    end)
    memoize('join')
    function Joiner:join(...)
      return table.concat({ ... }, '+')
    end
    local joiner = setmetatable({ file = new_file() }, Joiner)

    assert.are.same('a_b', joiner:join('a_b'))
    assert.are.same('a+b', joiner:join('a', 'b'))
  end)
end)
