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

local function table_keys_sorted(map)
  local keys = {}
  for key, _ in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    if #a == #b then
      return a < b
    end
    return #a > #b
  end)
  return keys
end

local function first_prefix_value(value, map)
  for _, key in ipairs(table_keys_sorted(map)) do
    if starts_with(value, tostring(key)) then
      return map[key]
    end
  end
  return nil
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

  local explicit_path_layer = first_prefix_value(rel, opts.layer_by_path_prefix or {})
  if explicit_path_layer then
    return tostring(explicit_path_layer)
  end

  local explicit_module_layer = first_prefix_value(module_id, opts.layer_by_module_prefix or {})
  if explicit_module_layer then
    return tostring(explicit_module_layer)
  end

  local top = rel:match("^([^/]+)/")
  if top and (opts.layer_by_top_dir or {})[top] then
    return opts.layer_by_top_dir[top]
  end

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

  local layer_tokens = vim.tbl_deep_extend("force", {
    interface = { "ui", "view", "views", "controller", "controllers", "handler", "handlers", "api", "cli", "window", "render" },
    application = { "app", "application", "service", "services", "usecase", "usecases", "workflow", "orchestrator" },
    domain = { "domain", "model", "models", "entity", "entities", "core", "graph", "analysis", "knowledge" },
    infrastructure = { "infra", "infrastructure", "repo", "repository", "gateway", "adapter", "adapters", "storage", "db", "client", "lsp" },
  }, opts.layer_tokens or {})

  if has_any(layer_tokens.interface) then
    return "interface"
  end
  if has_any(layer_tokens.application) then
    return "application"
  end
  if has_any(layer_tokens.domain) then
    return "domain"
  end
  if has_any(layer_tokens.infrastructure) then
    return "infrastructure"
  end

  return "core"
end

local function infer_domain(symbol, opts)
  local rel = tostring(symbol.relpath or symbol.path or ""):lower()

  local explicit_path_domain = first_prefix_value(rel, opts.domain_by_path_prefix or {})
  if explicit_path_domain then
    return tostring(explicit_path_domain)
  end

  local first = rel:match("^([^/]+)/")
  if first and first ~= "" and (opts.domain_by_top_dir or {})[first] then
    return tostring((opts.domain_by_top_dir or {})[first])
  end

  local seg_index = tonumber(opts.domain_path_segment) or 2
  if seg_index < 1 then
    seg_index = 1
  end
  local segments = {}
  for segment in rel:gmatch("[^/]+") do
    segments[#segments + 1] = segment
  end
  local by_index = segments[seg_index]
  if by_index and by_index ~= "" then
    return by_index
  end
  if segments[1] and segments[1] ~= "" then
    return segments[1]
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

local function normalize_arch_rules(custom_rules, mode)
  local rules
  if tostring(mode or "merge") == "replace" then
    rules = vim.deepcopy(custom_rules or {})
  else
    rules = vim.tbl_deep_extend("force", default_arch_rules(), custom_rules or {})
  end
  for source_layer, allowed in pairs(rules) do
    local normalized = {}
    for target_layer, enabled in pairs(allowed or {}) do
      if enabled == true then
        normalized[tostring(target_layer)] = true
      end
    end
    rules[source_layer] = normalized
  end
  return rules
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

local function violation_severity(edge_count, source_layer, target_layer, opts)
  local levels = vim.tbl_deep_extend("force", {
    interface = 5,
    application = 4,
    core = 4,
    domain = 3,
    shared = 3,
    infrastructure = 2,
    test = 1,
  }, opts.layer_levels or {})
  local source_level = tonumber(levels[source_layer]) or 3
  local target_level = tonumber(levels[target_layer]) or 3
  local gap = math.abs(source_level - target_level)
  local direction_penalty = 0
  if source_level > target_level then
    direction_penalty = 12
  end

  local score = 35 + (gap * 14) + math.min(25, tonumber(edge_count) or 0) * 2 + direction_penalty
  local thresholds = vim.tbl_deep_extend("force", {
    critical = 90,
    high = 70,
    medium = 55,
  }, opts.severity_thresholds or {})

  local severity = "low"
  if score >= (tonumber(thresholds.critical) or 90) then
    severity = "critical"
  elseif score >= (tonumber(thresholds.high) or 70) then
    severity = "high"
  elseif score >= (tonumber(thresholds.medium) or 55) then
    severity = "medium"
  end

  return severity, score
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
    layer_by_path_prefix = {},
    layer_by_module_prefix = {},
    domain_by_top_dir = {},
    domain_by_path_prefix = {},
    domain_path_segment = 2,
    layer_tokens = {},
    layer_levels = {},
    severity_thresholds = {
      critical = 90,
      high = 70,
      medium = 55,
    },
    rules = {},
    rules_mode = "merge",
  }, opts or {})

  opts.rules = normalize_arch_rules(opts.rules, opts.rules_mode)

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
      local domain = infer_domain(symbol, opts)
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
  local severity_counts = {
    critical = 0,
    high = 0,
    medium = 0,
    low = 0,
  }
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
        local item = violations[#violations]
        item.severity, item.severity_score = violation_severity(item.count, item.source_layer, item.target_layer, opts)
        severity_counts[item.severity] = (severity_counts[item.severity] or 0) + 1
      end
    end
  end

  table.sort(violations, function(a, b)
    if a.severity_score == b.severity_score then
      if a.count == b.count then
        if a.source_group_id == b.source_group_id then
          return a.target_group_id < b.target_group_id
        end
        return a.source_group_id < b.source_group_id
      end
      return a.count > b.count
    end
    return a.severity_score > b.severity_score
  end)

  local layer_keys = {}
  for key, _ in pairs(layer_counts) do
    layer_keys[#layer_keys + 1] = key
  end
  table.sort(layer_keys)

  local normalized_rules = {}
  for _, source in ipairs(table_keys_sorted(opts.rules)) do
    normalized_rules[source] = {}
    for _, target in ipairs(table_keys_sorted(opts.rules[source])) do
      normalized_rules[source][target] = opts.rules[source][target]
    end
  end

  local normalized_path_layers = {}
  for _, key in ipairs(table_keys_sorted(opts.layer_by_path_prefix)) do
    normalized_path_layers[key] = opts.layer_by_path_prefix[key]
  end
  local normalized_module_layers = {}
  for _, key in ipairs(table_keys_sorted(opts.layer_by_module_prefix)) do
    normalized_module_layers[key] = opts.layer_by_module_prefix[key]
  end
  local normalized_domain_paths = {}
  for _, key in ipairs(table_keys_sorted(opts.domain_by_path_prefix)) do
    normalized_domain_paths[key] = opts.domain_by_path_prefix[key]
  end

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
    layer_order = layer_keys,
    dependency_count = dependency_count,
    violation_count = #violations,
    severity_counts = severity_counts,
    violations = violations,
    options = {
      include_tests = to_bool(opts.include_tests, false),
      unknown_layer_policy = opts.unknown_layer_policy,
      max_violation_examples = opts.max_violation_examples,
      domain_path_segment = opts.domain_path_segment,
      layer_by_top_dir = opts.layer_by_top_dir,
      layer_by_path_prefix = normalized_path_layers,
      layer_by_module_prefix = normalized_module_layers,
      domain_by_top_dir = opts.domain_by_top_dir,
      domain_by_path_prefix = normalized_domain_paths,
      rules = normalized_rules,
      rules_mode = opts.rules_mode,
      severity_thresholds = opts.severity_thresholds,
      layer_levels = opts.layer_levels,
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

function M.code_evolution_report(index, opts)
  if not index then
    return nil, "project index unavailable"
  end

  opts = vim.tbl_deep_extend("force", {
    limit = 30,
    hotspot_limit = 10,
    include_merges = false,
    since = nil,
    path = nil,
    timeout_ms = 5000,
  }, opts or {})

  local git = require("code-atlas.git")
  local repo_root, root_err = git.repo_root(index.root or vim.fn.getcwd())
  if not repo_root then
    return nil, root_err
  end

  local commits, history_err = git.history_with_stats(repo_root, {
    limit = opts.limit,
    include_merges = opts.include_merges,
    since = opts.since,
    path = opts.path,
    timeout_ms = opts.timeout_ms,
  })
  if not commits then
    return nil, history_err
  end

  local symbols_by_relpath = {}
  for _, symbol in ipairs(index.symbols or {}) do
    local rel = symbol.relpath or symbol.path
    symbols_by_relpath[rel] = symbols_by_relpath[rel] or {}
    symbols_by_relpath[rel][#symbols_by_relpath[rel] + 1] = symbol
  end

  local symbol_touches = {}
  local symbol_churn = {}
  local file_hotspots = {}
  local timeline = {}
  local total_insertions = 0
  local total_deletions = 0

  for _, commit in ipairs(commits or {}) do
    local changed_files = {}
    local changed_set = {}
    local commit_churn = 0

    for _, file in ipairs(commit.files or {}) do
      local rel = tostring(file.path)
      changed_files[#changed_files + 1] = rel
      changed_set[rel] = true

      local churn = (tonumber(file.added) or 0) + (tonumber(file.deleted) or 0)
      commit_churn = commit_churn + churn
      total_insertions = total_insertions + (tonumber(file.added) or 0)
      total_deletions = total_deletions + (tonumber(file.deleted) or 0)

      file_hotspots[rel] = file_hotspots[rel] or { path = rel, churn = 0, touches = 0 }
      file_hotspots[rel].churn = file_hotspots[rel].churn + churn
      file_hotspots[rel].touches = file_hotspots[rel].touches + 1
    end

    table.sort(changed_files)

    local touched_symbol_ids = {}
    local touched_symbol_set = {}
    for rel, _ in pairs(changed_set) do
      for _, symbol in ipairs(symbols_by_relpath[rel] or {}) do
        if not touched_symbol_set[symbol.id] then
          touched_symbol_set[symbol.id] = true
          touched_symbol_ids[#touched_symbol_ids + 1] = symbol.id

          symbol_touches[symbol.id] = (symbol_touches[symbol.id] or 0) + 1
          symbol_churn[symbol.id] = (symbol_churn[symbol.id] or 0) + commit_churn
        end
      end
    end

    local touched_edges = {}
    for _, symbol_id in ipairs(touched_symbol_ids) do
      for _, target_id in ipairs((index.outgoing or {})[symbol_id] or {}) do
        touched_edges[string.format("%s>%s", symbol_id, target_id)] = true
      end
      for _, source_id in ipairs((index.incoming or {})[symbol_id] or {}) do
        touched_edges[string.format("%s>%s", source_id, symbol_id)] = true
      end
    end

    local edge_count = 0
    for _, _ in pairs(touched_edges) do
      edge_count = edge_count + 1
    end

    timeline[#timeline + 1] = {
      hash = commit.hash,
      short_hash = tostring(commit.hash):sub(1, 8),
      date = commit.date,
      author = commit.author,
      subject = commit.subject,
      files_count = commit.files_count,
      insertions = commit.insertions,
      deletions = commit.deletions,
      churn = commit_churn,
      touched_symbols = #touched_symbol_ids,
      touched_edges = edge_count,
      changed_files = changed_files,
    }
  end

  table.sort(timeline, function(a, b)
    return tostring(a.date) < tostring(b.date)
  end)

  local files = {}
  for _, item in pairs(file_hotspots) do
    files[#files + 1] = item
  end
  table.sort(files, function(a, b)
    if a.churn == b.churn then
      if a.touches == b.touches then
        return a.path < b.path
      end
      return a.touches > b.touches
    end
    return a.churn > b.churn
  end)

  local symbols = {}
  for symbol_id, touches in pairs(symbol_touches) do
    local symbol = (index.by_id or {})[symbol_id]
    if symbol then
      symbols[#symbols + 1] = {
        id = symbol_id,
        name = symbol.name,
        path = symbol.path,
        relpath = symbol.relpath,
        range = symbol.range,
        touches = touches,
        churn = symbol_churn[symbol_id] or 0,
      }
    end
  end
  table.sort(symbols, function(a, b)
    if a.touches == b.touches then
      if a.churn == b.churn then
        return tostring(a.name) < tostring(b.name)
      end
      return a.churn > b.churn
    end
    return a.touches > b.touches
  end)

  local function take_first(items)
    local out = {}
    local cap = math.max(1, tonumber(opts.hotspot_limit) or 10)
    for i = 1, math.min(cap, #items) do
      out[#out + 1] = items[i]
    end
    return out
  end

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    root = repo_root,
    commits_count = #commits,
    timeline = timeline,
    totals = {
      insertions = total_insertions,
      deletions = total_deletions,
      churn = total_insertions + total_deletions,
    },
    hotspots = {
      files = take_first(files),
      symbols = take_first(symbols),
    },
    options = {
      limit = opts.limit,
      hotspot_limit = opts.hotspot_limit,
      include_merges = opts.include_merges,
      since = opts.since,
      path = opts.path,
    },
  }, nil
end

function M.write_evolution_report(path, report, opts)
  if not path or path == "" then
    return nil, "report path is required"
  end
  if not report then
    return nil, "evolution report is required"
  end

  opts = opts or {}
  local format = tostring(opts.format or "json"):lower()
  if format ~= "json" and format ~= "jsonl" then
    return nil, "unsupported format"
  end

  local dir = vim.fs.dirname(path)
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end

  local payload = vim.deepcopy(report)
  local pretty = to_bool(opts.pretty, true)
  local lines = {}

  if format == "jsonl" then
    lines[#lines + 1] = vim.json.encode(payload)
  else
    local encoded = vim.json.encode(payload)
    if pretty then
      local ok, decoded = pcall(vim.json.decode, encoded)
      if ok then
        encoded = vim.json.encode(decoded)
      end
    end
    for line in (encoded .. "\n"):gmatch("([^\n]*)\n") do
      lines[#lines + 1] = line
    end
  end

  vim.fn.writefile(lines, path)
  local bytes = #table.concat(lines, "\n")

  return {
    path = path,
    bytes = bytes,
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
