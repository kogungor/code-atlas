local M = {}

local function starts_with(text, prefix)
  return text:sub(1, #prefix) == prefix
end

local function is_test_symbol(symbol)
  local rel = symbol.relpath or symbol.path or ""
  local lower = rel:lower()
  if lower:find("/test", 1, true) or lower:find("spec", 1, true) then
    return true
  end
  if lower:find("_test%.", 1) then
    return true
  end
  if starts_with(symbol.name:lower(), "test") then
    return true
  end
  return false
end

local function is_entrypoint_name(name)
  local n = name:lower()
  return n == "main" or n == "init" or n == "setup" or n == "run" or n == "m.run"
end

local function should_ignore(symbol, opts)
  if opts.ignore_tests and is_test_symbol(symbol) then
    return true
  end

  if opts.ignore_entrypoints and is_entrypoint_name(symbol.name) then
    return true
  end

  for _, prefix in ipairs(opts.ignore_path_prefixes or {}) do
    local rel = symbol.relpath or ""
    if starts_with(rel, prefix) then
      return true
    end
  end

  return false
end

function M.detect_dead_code(index, opts)
  if not index then
    return nil, "project index unavailable"
  end

  opts = vim.tbl_deep_extend("force", {
    ignore_tests = true,
    ignore_entrypoints = true,
    ignore_path_prefixes = {
      "tests/",
      "playground/",
    },
  }, opts or {})

  local dead = {}

  for _, symbol in ipairs(index.symbols or {}) do
    if not should_ignore(symbol, opts) then
      local incoming = index.incoming[symbol.id] or {}
      if #incoming == 0 then
        dead[#dead + 1] = symbol
      end
    end
  end

  table.sort(dead, function(a, b)
    if a.relpath == b.relpath then
      return a.name < b.name
    end
    return (a.relpath or a.path) < (b.relpath or b.path)
  end)

  return {
    dead = dead,
    total_symbols = #(index.symbols or {}),
    dead_count = #dead,
    options = opts,
  }, nil
end

local function symbol_label(symbol)
  return string.format("%s - %s", symbol.name, symbol.relpath or symbol.path)
end

local function set_add(list, seen, value)
  if not seen[value] then
    seen[value] = true
    list[#list + 1] = value
  end
end

function M.impact_for_symbol(index, root_symbol_id, opts)
  if not index then
    return nil, "project index unavailable"
  end

  opts = vim.tbl_deep_extend("force", {
    max_depth = 8,
    include_tests = true,
  }, opts or {})

  local root = index.by_id[root_symbol_id]
  if not root then
    return nil, "root symbol not found"
  end

  local direct = {}
  local direct_seen = {}
  for _, caller_id in ipairs(index.incoming[root_symbol_id] or {}) do
    set_add(direct, direct_seen, caller_id)
  end

  local impacted = {}
  local impacted_seen = {}
  local queue = {
    { id = root_symbol_id, depth = 0 },
  }

  while #queue > 0 do
    local current = table.remove(queue, 1)
    if current.depth < opts.max_depth then
      for _, caller_id in ipairs(index.incoming[current.id] or {}) do
        if not impacted_seen[caller_id] then
          impacted_seen[caller_id] = true
          impacted[#impacted + 1] = caller_id
          queue[#queue + 1] = {
            id = caller_id,
            depth = current.depth + 1,
          }
        end
      end
    end
  end

  local impacted_symbols = {}
  local impacted_modules = {}
  local impacted_packages = {}
  local impacted_tests = {}
  local module_seen = {}
  local package_seen = {}

  for _, id in ipairs(impacted) do
    local symbol = index.by_id[id]
    if symbol then
      impacted_symbols[#impacted_symbols + 1] = symbol

      if symbol.module_id then
        set_add(impacted_modules, module_seen, symbol.module_id)
      end
      if symbol.package_id then
        set_add(impacted_packages, package_seen, symbol.package_id)
      end

      if opts.include_tests and is_test_symbol(symbol) then
        impacted_tests[#impacted_tests + 1] = symbol
      end
    end
  end

  table.sort(impacted_symbols, function(a, b)
    if a.relpath == b.relpath then
      return a.name < b.name
    end
    return (a.relpath or a.path) < (b.relpath or b.path)
  end)
  table.sort(impacted_modules)
  table.sort(impacted_packages)
  table.sort(impacted_tests, function(a, b)
    return symbol_label(a) < symbol_label(b)
  end)

  local direct_symbols = {}
  for _, id in ipairs(direct) do
    local symbol = index.by_id[id]
    if symbol then
      direct_symbols[#direct_symbols + 1] = symbol
    end
  end
  table.sort(direct_symbols, function(a, b)
    return symbol_label(a) < symbol_label(b)
  end)

  return {
    root = root,
    direct_callers = direct_symbols,
    impacted_symbols = impacted_symbols,
    impacted_modules = impacted_modules,
    impacted_packages = impacted_packages,
    impacted_tests = impacted_tests,
    max_depth = opts.max_depth,
  }, nil
end

return M
