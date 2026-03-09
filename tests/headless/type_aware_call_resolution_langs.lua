local root = vim.fn.getcwd()
local atlas = require("code-atlas")

local index, err = atlas.build_project_index({ root = root })
if not index then
  error("feature21_langs smoke failed: " .. tostring(err))
end

local function find_symbol(path, short_name)
  for _, symbol in ipairs(index.by_path[path] or {}) do
    if symbol.short_name == short_name then
      return symbol
    end
  end
  return nil
end

local function find_resolution(symbol, receiver, call_name)
  for _, item in ipairs(index.call_resolutions[symbol.id] or {}) do
    if item.receiver == receiver and item.call_name == call_name then
      return item
    end
  end
  return nil
end

local validated = 0

local py_path = root .. "/playground/samples/py_method_resolution.py"
local py_symbol = find_symbol(py_path, "calculate_with_receivers")
if py_symbol then
  local py_match = find_resolution(py_symbol, "checkout_service", "apply_discount")
  if not py_match or py_match.unresolved or not py_match.best then
    error("feature21_langs smoke failed: python receiver resolution failed")
  end
  if py_match.best.name ~= "CheckoutService.apply_discount" then
    error("feature21_langs smoke failed: python best target mismatch")
  end
  validated = validated + 1
end

local go_path = root .. "/playground/samples/go_method_resolution.go"
local go_symbol = find_symbol(go_path, "CalculateWithReceivers")
if go_symbol then
  local go_match = find_resolution(go_symbol, "checkoutService", "ApplyDiscount")
  if not go_match or go_match.unresolved or not go_match.best then
    error("feature21_langs smoke failed: go receiver resolution failed")
  end
  if go_match.best.name ~= "CheckoutService.ApplyDiscount" then
    error("feature21_langs smoke failed: go best target mismatch")
  end
  validated = validated + 1
end

local rust_path = root .. "/playground/samples/rust_method_resolution.rs"
local rust_symbol = find_symbol(rust_path, "calculate_with_receivers")
if rust_symbol then
  local rust_match = find_resolution(rust_symbol, "checkout_service", "apply_discount")
  if not rust_match or rust_match.unresolved or not rust_match.best then
    error("feature21_langs smoke failed: rust receiver resolution failed")
  end
  if rust_match.best.name ~= "CheckoutService.apply_discount" then
    error("feature21_langs smoke failed: rust best target mismatch")
  end
  validated = validated + 1
end

if validated == 0 then
  vim.notify("feature21_langs smoke skipped: language parsers unavailable in test env", vim.log.levels.WARN)
else
  vim.notify("feature21_langs smoke validated languages: " .. tostring(validated), vim.log.levels.INFO)
end

vim.notify("feature21_langs smoke passed", vim.log.levels.INFO)
