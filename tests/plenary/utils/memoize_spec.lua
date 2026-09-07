local OrgFile = require('orgmode.files.file')

describe('Memoize', function()
  ---@return OrgFile
  local load_file_sync = function(content, filename)
    content = content or {}
    filename = filename or vim.fn.tempname() .. '.org'
    vim.fn.writefile(content, filename)
    return OrgFile.load(filename):wait()
  end

  local function collect()
    collectgarbage('collect')
    collectgarbage('collect')
  end

  it('does not keep a file alive once nothing else references it', function()
    local weak = setmetatable({}, { __mode = 'v' })

    do
      local file = load_file_sync({ '* Headline 1', '  body' })
      weak.file = file
      file:get_headlines()
      assert.is_not_nil(weak.file)
    end

    collect()

    assert.is_nil(weak.file)
  end)
end)
