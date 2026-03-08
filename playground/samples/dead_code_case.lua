local M = {}

local function beta()
  return 42
end

local function alpha()
  return beta()
end

local function orphan()
  return "unused"
end

function M.run()
  return alpha()
end

return M
