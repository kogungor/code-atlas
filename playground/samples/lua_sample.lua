local M = {}

local function format_name(name)
  return string.upper(name)
end

local function greet(name)
  print("hello " .. format_name(name))
end

function M.run()
  greet("atlas")
end

return M
