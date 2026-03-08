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

local function to_bool(value, fallback)
  if value == nil then
    return fallback
  end
  if type(value) == "boolean" then
    return value
  end
  local text = tostring(value):lower()
  if text == "1" or text == "true" or text == "yes" or text == "on" then
    return true
  end
  if text == "0" or text == "false" or text == "no" or text == "off" then
    return false
  end
  return fallback
end

local function split_words(text)
  local out = {}
  for token in tostring(text or ""):gmatch("[%w_%-]+") do
    out[#out + 1] = token:lower()
  end
  return out
end

local function starts_with_any(value, prefixes)
  for _, prefix in ipairs(prefixes or {}) do
    if starts_with(value, prefix) then
      return true
    end
  end
  return false
end

local function infer_layer(symbol, opts)
  local rel = (symbol.relpath or symbol.path or ""):lower()
  local module_id = tostring(symbol.module_id or ""):lower()

  if starts_with_any(rel, { "tests/", "test/", "spec/" }) or module_id:find("%.tests?%.") or module_id:find("%.spec%.") then
    return "test"
  end

  local tokens = split_words(module_id .. " " .. rel)
  local function has_any(candidates)
    local bag = {}
    for _, token in ipairs(tokens) do
      bag[token] = true
    end
    for _, item in ipairs(candidates) do
      if bag[item] then
        return true
      end
    end
    return false
  end

  if has_any({ "ui", "view", "views", "controller", "controllers", "handler", "handlers", "api", "cli", "window", "render" }) then
    return "interface"
  end
  if has_any({ "app", "application", "service", "services", "usecase", "usecases", "workflow", "orchestrator" }) then
    return "application"
  end
  if has_any({ "domain", "model", "models", "entity", "entities", "core", "graph", "analysis", "knowledge" }) then
    return "domain"
  end
  if has_any({ "infra", "infrastructure", "repo", "repository", "gateway", "adapter", "adapters", "storage", "db", "client", "lsp" }) then
    return "infrastructure"
  end

  local top = rel:match("^([^/]+)/")
  if top and (opts.layer_by_top_dir or {})[top] then
    return opts.layer_by_top_dir[top]
  end

  return "core"
end

local function infer_domain(symbol)
  local rel = tostring(symbol.relpath or symbol.path or "")
  local first, second = rel:match("^([^/]+)/([^/]+)/")
  if second and second ~= "" then
    return second
  end
  if first and first ~= "" then
    return first
  end

  local module_id = tostring(symbol.module_id or "")
  local head = module_id:match("^[^%.]+%.([^%.]+)") or module_id:match("^[^%.]+")
  if head and head ~= "" then
    return head
  end

  return "(global)"
end

local function default_arch_rules()
  return {
    interface = { interface = true, application = true, domain = true, shared = true },
    application = { application = true, domain = true, shared = true },
    domain = { domain = true, shared = true },
    infrastructure = { infrastructure = true, domain = true, shared = true },
    shared = { shared = true, domain = true },
    core = { core = true, interface = true, application = true, domain = true, infrastructure = true, shared = true },
    test = { ["*"] = true },
  }
end

local function is_allowed_dependency(rules, source_layer, target_layer, unknown_policy)
  if source_layer == target_layer then
    return true
  end
  local allowed = rules[source_layer]
  if not allowed then
    return unknown_policy == "allow"
  end
  if allowed["*"] then
    return true
  end
  return allowed[target_layer] == true
end

function M.architecture_report(index, opts)
  if not index then
    return nil, "project index unavailable"
  end

  opts = vim.tbl_deep_extend("force", {
    include_tests = false,
    unknown_layer_policy = "allow",
    max_violation_examples = 3,
    layer_by_top_dir = {
      lua = "core",
      tests = "test",
      test = "test",
      spec = "test",
      playground = "application",
    },
    rules = default_arch_rules(),
  }, opts or {})

  local groups = {}
  local layer_counts = {}
  local symbol_group = {}

  local function ensure_group(symbol, layer, domain)
    local group_id = string.format("%s:%s", layer, domain)
    local group = groups[group_id]
    if group then
      return group
    end
    group = {
      id = group_id,
      layer = layer,
      domain = domain,
      label = string.format("[%s] %s", layer, domain),
      symbol_count = 0,
      symbols = {},
      target = {
        path = symbol.path,
        row = symbol.range[1],
        col = symbol.range[2],
      },
    }
    groups[group_id] = group
    layer_counts[layer] = (layer_counts[layer] or 0) + 1
    return group
  end

  for _, symbol in ipairs(index.symbols or {}) do
    local layer = infer_layer(symbol, opts)
    if not (layer == "test" and not to_bool(opts.include_tests, false)) then
      local domain = infer_domain(symbol)
      local group = ensure_group(symbol, layer, domain)
      group.symbol_count = group.symbol_count + 1
      group.symbols[#group.symbols + 1] = symbol.id
      symbol_group[symbol.id] = group.id
    end
  end

  local group_outgoing = {}
  local group_incoming = {}
  local edge_counts = {}

  local function add_group_edge(source_group_id, target_group_id, source_symbol_id, target_symbol_id)
    group_outgoing[source_group_id] = group_outgoing[source_group_id] or {}
    group_incoming[target_group_id] = group_incoming[target_group_id] or {}
    edge_counts[source_group_id] = edge_counts[source_group_id] or {}

    local seen = false
    for _, id in ipairs(group_outgoing[source_group_id]) do
      if id == target_group_id then
        seen = true
        break
      end
    end
    if not seen then
      group_outgoing[source_group_id][#group_outgoing[source_group_id] + 1] = target_group_id
      group_incoming[target_group_id][#group_incoming[target_group_id] + 1] = source_group_id
    end

    local record = edge_counts[source_group_id][target_group_id]
    if not record then
      record = {
        count = 0,
        examples = {},
      }
      edge_counts[source_group_id][target_group_id] = record
    end
    record.count = record.count + 1
    if #record.examples < math.max(1, tonumber(opts.max_violation_examples) or 3) then
      record.examples[#record.examples + 1] = {
        source_symbol_id = source_symbol_id,
        target_symbol_id = target_symbol_id,
      }
    end
  end

  for source_symbol_id, targets in pairs(index.outgoing or {}) do
    local source_group_id = symbol_group[source_symbol_id]
    if source_group_id then
      for _, target_symbol_id in ipairs(targets or {}) do
        local target_group_id = symbol_group[target_symbol_id]
        if target_group_id then
          add_group_edge(source_group_id, target_group_id, source_symbol_id, target_symbol_id)
        end
      end
    end
  end

  for id, ids in pairs(group_outgoing) do
    table.sort(ids)
    local dedupe = {}
    local out = {}
    for _, value in ipairs(ids) do
      if not dedupe[value] then
        dedupe[value] = true
        out[#out + 1] = value
      end
    end
    group_outgoing[id] = out
  end

  for id, ids in pairs(group_incoming) do
    table.sort(ids)
    local dedupe = {}
    local out = {}
    for _, value in ipairs(ids) do
      if not dedupe[value] then
        dedupe[value] = true
        out[#out + 1] = value
      end
    end
    group_incoming[id] = out
  end

  local violations = {}
  for source_group_id, targets in pairs(group_outgoing) do
    local source_group = groups[source_group_id]
    for _, target_group_id in ipairs(targets or {}) do
      local target_group = groups[target_group_id]
      local allowed = is_allowed_dependency(
        opts.rules or default_arch_rules(),
        source_group and source_group.layer,
        target_group and target_group.layer,
        opts.unknown_layer_policy
      )
      if not allowed then
        local edge_meta = (((edge_counts or {})[source_group_id] or {})[target_group_id]) or { count = 0, examples = {} }
        violations[#violations + 1] = {
          source_group_id = source_group_id,
          target_group_id = target_group_id,
          source_layer = source_group and source_group.layer or "unknown",
          target_layer = target_group and target_group.layer or "unknown",
          count = edge_meta.count or 0,
          examples = edge_meta.examples or {},
        }
      end
    end
  end

  table.sort(violations, function(a, b)
    if a.count == b.count then
      if a.source_group_id == b.source_group_id then
        return a.target_group_id < b.target_group_id
      end
      return a.source_group_id < b.source_group_id
    end
    return a.count > b.count
  end)

  local group_ids = {}
  for id, _ in pairs(groups) do
    group_ids[#group_ids + 1] = id
  end
  table.sort(group_ids)

  local dependency_count = 0
  for _, targets in pairs(group_outgoing) do
    dependency_count = dependency_count + #(targets or {})
  end

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    root = index.root,
    group_ids = group_ids,
    groups = groups,
    outgoing = group_outgoing,
    incoming = group_incoming,
    edge_counts = edge_counts,
    layer_counts = layer_counts,
    dependency_count = dependency_count,
    violation_count = #violations,
    violations = violations,
    options = {
      include_tests = to_bool(opts.include_tests, false),
      unknown_layer_policy = opts.unknown_layer_policy,
      rules = opts.rules,
    },
    symbols_by_id = index.by_id,
  }, nil
end

function M.write_architecture_report(path, report, opts)
  if not path or path == "" then
    return nil, "report path is required"
  end
  if not report then
    return nil, "architecture report is required"
  end

  opts = opts or {}
  local format = tostring(opts.format or "json"):lower()
  if format ~= "json" then
    return nil, "unsupported format"
  end

  local dir = vim.fs.dirname(path)
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end

  local payload = vim.deepcopy(report)
  local pretty = to_bool(opts.pretty, true)
  local encoded = vim.json.encode(payload)
  if pretty then
    local ok, decoded = pcall(vim.json.decode, encoded)
    if ok then
      encoded = vim.json.encode(decoded)
    end
  end
  vim.fn.writefile(vim.split(encoded .. "\n", "\n", { plain = true }), path)

  return {
    path = path,
    bytes = #encoded,
    format = format,
  }, nil
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
