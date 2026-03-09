local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasIndex") ~= 2 then
  error("feature9 smoke failed: :CodeAtlasIndex command is not registered")
end

local code_atlas = require("code-atlas")
local index, err = code_atlas.build_project_index({ root = root })
if not index then
  error("feature9 smoke failed: " .. tostring(err))
end

if index.symbol_count < 10 then
  error("feature9 smoke failed: expected at least 10 symbols, got " .. tostring(index.symbol_count))
end

if not index.by_name["checkout"] and not index.by_name["M.checkout"] then
  error("feature9 smoke failed: expected checkout function in index")
end

if not index.by_name["run"] and not index.by_name["M.run"] then
  error("feature9 smoke failed: expected run function in index")
end

local refreshed, refresh_err = code_atlas.refresh_project_index()
if not refreshed then
  error("feature9 smoke failed: refresh failed: " .. tostring(refresh_err))
end

if refreshed.symbol_count ~= index.symbol_count then
  error(
    "feature9 smoke failed: symbol count changed unexpectedly after refresh ("
      .. tostring(index.symbol_count)
      .. " -> "
      .. tostring(refreshed.symbol_count)
      .. ")"
  )
end

vim.notify("feature9 smoke passed", vim.log.levels.INFO)
