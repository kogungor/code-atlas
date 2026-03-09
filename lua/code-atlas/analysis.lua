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

local function degree_maps(index)
  local in_degree = {}
  local out_degree = {}
  for _, symbol in ipairs(index.symbols or {}) do
    in_degree[symbol.id] = #((index.incoming or {})[symbol.id] or {})
    out_degree[symbol.id] = #((index.outgoing or {})[symbol.id] or {})
  end
  return in_degree, out_degree
end

local function file_churn_map(root, opts)
  if not to_bool(opts.include_churn, true) then
    return {}, {
      enabled = false,
      commits = 0,
      files = 0,
      total_churn = 0,
    }
  end

  local git_ok, git = pcall(require, "code-atlas.git")
  if not git_ok or not git then
    return {}, {
      enabled = false,
      commits = 0,
      files = 0,
      total_churn = 0,
      error = "git module unavailable",
    }
  end

  local repo_root, root_err = git.repo_root(root or vim.fn.getcwd())
  if not repo_root then
    return {}, {
      enabled = false,
      commits = 0,
      files = 0,
      total_churn = 0,
      error = root_err,
    }
  end

  local commits, history_err = git.history_with_stats(repo_root, {
    limit = math.max(1, math.floor(tonumber(opts.churn_limit) or 60)),
    include_merges = false,
    since = opts.churn_since,
    timeout_ms = opts.churn_timeout_ms,
  })
  if not commits then
    return {}, {
      enabled = false,
      commits = 0,
      files = 0,
      total_churn = 0,
      error = history_err,
    }
  end

  local churn_by_path = {}
  local total = 0
  for _, commit in ipairs(commits or {}) do
    for _, file in ipairs(commit.files or {}) do
      local rel = tostring(file.path)
      local churn = (tonumber(file.added) or 0) + (tonumber(file.deleted) or 0)
      churn_by_path[rel] = (churn_by_path[rel] or 0) + churn
      total = total + churn
    end
  end

  local files = 0
  for _, _ in pairs(churn_by_path) do
    files = files + 1
  end

  return churn_by_path, {
    enabled = true,
    commits = #commits,
    files = files,
    total_churn = total,
  }
end

local function bounded_reach_count(edges, root_id, max_depth)
  local seen = {}
  local queue = {
    { id = root_id, depth = 0 },
  }
  seen[root_id] = true
  local count = 0

  while #queue > 0 do
    local current = table.remove(queue, 1)
    if current.depth < max_depth then
      for _, next_id in ipairs((edges or {})[current.id] or {}) do
        if not seen[next_id] then
          seen[next_id] = true
          count = count + 1
          queue[#queue + 1] = {
            id = next_id,
            depth = current.depth + 1,
          }
        end
      end
    end
  end

  return count
end

local function build_hot_path(index, scores, root_id, opts)
  local edges = opts.direction == "incoming" and (index.incoming or {}) or (index.outgoing or {})
  local path = {}
  local visited = {}
  local current = root_id
  local min_score = math.huge

  for _ = 1, math.max(1, tonumber(opts.path_depth) or 5) do
    if visited[current] then
      break
    end
    visited[current] = true
    path[#path + 1] = current
    min_score = math.min(min_score, tonumber((scores[current] or {}).score) or 0)

    local next_id = nil
    local next_score = -math.huge
    for _, candidate in ipairs(edges[current] or {}) do
      if not visited[candidate] then
        local score = tonumber((scores[candidate] or {}).score) or 0
        if score > next_score then
          next_score = score
          next_id = candidate
        end
      end
    end
    if not next_id then
      break
    end
    current = next_id
  end

  return {
    ids = path,
    bottleneck_score = min_score == math.huge and 0 or min_score,
  }
end

function M.hot_path_report(index, opts)
  if not index then
    return nil, "project index unavailable"
  end

  opts = vim.tbl_deep_extend("force", {
    top_n = 10,
    max_depth = 4,
    path_depth = 5,
    path_count = 5,
    direction = "outgoing",
    include_tests = false,
    weight_in = 2.2,
    weight_out = 1.6,
    weight_balance = 2.4,
    weight_reach = 1.1,
    include_churn = true,
    churn_limit = 60,
    churn_since = nil,
    churn_timeout_ms = 5000,
    weight_churn = 0.15,
  }, opts or {})

  local in_degree, out_degree = degree_maps(index)
  local churn_by_path, churn_meta = file_churn_map(index.root, opts)
  local scores = {}

  for _, symbol in ipairs(index.symbols or {}) do
    if opts.include_tests or not is_test_symbol(symbol) then
      local in_d = tonumber(in_degree[symbol.id]) or 0
      local out_d = tonumber(out_degree[symbol.id]) or 0
      local balance = math.min(in_d, out_d)
      local out_reach = bounded_reach_count(index.outgoing, symbol.id, tonumber(opts.max_depth) or 4)
      local in_reach = bounded_reach_count(index.incoming, symbol.id, tonumber(opts.max_depth) or 4)
      local reach = out_reach + in_reach
      local churn = tonumber(churn_by_path[symbol.relpath or symbol.path]) or 0

      local score = (in_d * opts.weight_in)
        + (out_d * opts.weight_out)
        + (balance * opts.weight_balance)
        + (reach * opts.weight_reach)
        + (churn * opts.weight_churn)

      scores[symbol.id] = {
        symbol = symbol,
        in_degree = in_d,
        out_degree = out_d,
        balance = balance,
        out_reach = out_reach,
        in_reach = in_reach,
        reach = reach,
        churn = churn,
        score = score,
      }
    end
  end

  local ranked = {}
  for _, item in pairs(scores) do
    ranked[#ranked + 1] = item
  end
  table.sort(ranked, function(a, b)
    if a.score == b.score then
      if a.reach == b.reach then
        return symbol_label(a.symbol) < symbol_label(b.symbol)
      end
      return a.reach > b.reach
    end
    return a.score > b.score
  end)

  local top_n = math.max(1, tonumber(opts.top_n) or 10)
  local hotspots = {}
  for i = 1, math.min(top_n, #ranked) do
    local item = ranked[i]
    hotspots[#hotspots + 1] = {
      rank = i,
      symbol = item.symbol,
      score = item.score,
      in_degree = item.in_degree,
      out_degree = item.out_degree,
      balance = item.balance,
      reach = item.reach,
      out_reach = item.out_reach,
      in_reach = item.in_reach,
      churn = item.churn,
      rationale = string.format(
        "fan-in=%d fan-out=%d reach=%d balance=%d churn=%d",
        item.in_degree,
        item.out_degree,
        item.reach,
        item.balance,
        item.churn
      ),
    }
  end

  local hot_paths = {}
  local path_count = math.max(1, tonumber(opts.path_count) or 5)
  for i = 1, math.min(path_count, #hotspots) do
    local start = hotspots[i]
    local chain = build_hot_path(index, scores, start.symbol.id, opts)
    local nodes = {}
    for _, symbol_id in ipairs(chain.ids or {}) do
      local item = scores[symbol_id]
      if item then
        nodes[#nodes + 1] = {
          id = symbol_id,
          name = item.symbol.name,
          path = item.symbol.path,
          relpath = item.symbol.relpath,
          range = item.symbol.range,
          score = item.score,
        }
      end
    end
    hot_paths[#hot_paths + 1] = {
      root_symbol_id = start.symbol.id,
      root_score = start.score,
      bottleneck_score = chain.bottleneck_score,
      nodes = nodes,
    }
  end

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    root = index.root,
    total_symbols = #(index.symbols or {}),
    analyzed_symbols = #ranked,
    direction = opts.direction,
    hotspots = hotspots,
    hot_paths = hot_paths,
    options = {
      top_n = top_n,
      max_depth = opts.max_depth,
      path_depth = opts.path_depth,
      path_count = path_count,
      include_tests = to_bool(opts.include_tests, false),
      direction = opts.direction,
      churn = {
        include = to_bool(opts.include_churn, true),
        limit = opts.churn_limit,
        since = opts.churn_since,
        timeout_ms = opts.churn_timeout_ms,
        weight = opts.weight_churn,
      },
      weights = {
        in_degree = opts.weight_in,
        out_degree = opts.weight_out,
        balance = opts.weight_balance,
        reach = opts.weight_reach,
        churn = opts.weight_churn,
      },
    },
    churn = churn_meta,
  }, nil
end

local function tarjan_scc(nodes, edges)
  local index_id = 0
  local stack = {}
  local on_stack = {}
  local indices = {}
  local low = {}
  local components = {}

  local function strongconnect(v)
    index_id = index_id + 1
    indices[v] = index_id
    low[v] = index_id
    stack[#stack + 1] = v
    on_stack[v] = true

    for _, w in ipairs((edges or {})[v] or {}) do
      if nodes[w] then
        if not indices[w] then
          strongconnect(w)
          low[v] = math.min(low[v], low[w])
        elseif on_stack[w] then
          low[v] = math.min(low[v], indices[w])
        end
      end
    end

    if low[v] == indices[v] then
      local component = {}
      while #stack > 0 do
        local w = table.remove(stack)
        on_stack[w] = false
        component[#component + 1] = w
        if w == v then
          break
        end
      end
      components[#components + 1] = component
    end
  end

  for id, _ in pairs(nodes or {}) do
    if not indices[id] then
      strongconnect(id)
    end
  end

  return components
end

local function complexity_cluster_metrics(index, symbol_ids)
  local module_stats = {}
  local total_edges = 0

  for _, symbol_id in ipairs(symbol_ids) do
    local symbol = (index.by_id or {})[symbol_id]
    if symbol then
      local module_id = symbol.module_id or "(unknown)"
      module_stats[module_id] = module_stats[module_id] or {
        module_id = module_id,
        symbols = 0,
        edges = 0,
      }
      module_stats[module_id].symbols = module_stats[module_id].symbols + 1
    end
  end

  local set = {}
  for _, id in ipairs(symbol_ids) do
    set[id] = true
  end

  for _, symbol_id in ipairs(symbol_ids) do
    local symbol = (index.by_id or {})[symbol_id]
    if symbol then
      local module_id = symbol.module_id or "(unknown)"
      for _, target_id in ipairs((index.outgoing or {})[symbol_id] or {}) do
        if set[target_id] then
          module_stats[module_id].edges = module_stats[module_id].edges + 1
          total_edges = total_edges + 1
        end
      end
    end
  end

  local modules = {}
  for _, item in pairs(module_stats) do
    local n = item.symbols
    local max_edges = math.max(1, n * (n - 1))
    item.density = item.edges / max_edges
    modules[#modules + 1] = item
  end

  table.sort(modules, function(a, b)
    if a.density == b.density then
      return a.symbols > b.symbols
    end
    return a.density > b.density
  end)

  local max_cluster_density = 0
  for _, item in ipairs(modules) do
    max_cluster_density = math.max(max_cluster_density, item.density)
  end

  return {
    module_clusters = modules,
    module_count = #modules,
    max_cluster_density = max_cluster_density,
    total_internal_edges = total_edges,
  }
end

local function classify_severity(score, thresholds)
  if score >= (tonumber(thresholds.critical) or 70) then
    return "critical"
  end
  if score >= (tonumber(thresholds.high) or 45) then
    return "high"
  end
  if score >= (tonumber(thresholds.medium) or 25) then
    return "medium"
  end
  return "low"
end

function M.complexity_report(index, opts)
  if not index then
    return nil, "project index unavailable"
  end

  opts = vim.tbl_deep_extend("force", {
    include_tests = false,
    top_n = 15,
    scc_limit = 10,
    cycle_weight = 12,
    degree_weight = 1.0,
    bridge_weight = 1.5,
    scc_size_weight = 0.7,
    severity_thresholds = {
      critical = 70,
      high = 45,
      medium = 25,
    },
    suggestion_scc_size = 6,
    suggestion_density = 0.35,
    suggestion_top_bridge = 6,
  }, opts or {})

  local nodes = {}
  local symbol_ids = {}
  for _, symbol in ipairs(index.symbols or {}) do
    if opts.include_tests or not is_test_symbol(symbol) then
      nodes[symbol.id] = symbol
      symbol_ids[#symbol_ids + 1] = symbol.id
    end
  end

  local components = tarjan_scc(nodes, index.outgoing or {})
  local scc_by_symbol = {}
  local sccs = {}
  local cyclic_count = 0

  for i, component in ipairs(components) do
    local has_cycle = #component > 1
    if not has_cycle and #component == 1 then
      local only = component[1]
      for _, target in ipairs((index.outgoing or {})[only] or {}) do
        if target == only then
          has_cycle = true
          break
        end
      end
    end

    local edge_count = 0
    local set = {}
    for _, id in ipairs(component) do
      set[id] = true
      scc_by_symbol[id] = i
    end
    for _, id in ipairs(component) do
      for _, target in ipairs((index.outgoing or {})[id] or {}) do
        if set[target] then
          edge_count = edge_count + 1
        end
      end
    end

    local n = #component
    local max_edges = math.max(1, n * (n - 1))
    local density = edge_count / max_edges
    if has_cycle then
      cyclic_count = cyclic_count + n
    end

    sccs[#sccs + 1] = {
      id = i,
      size = n,
      has_cycle = has_cycle,
      edge_count = edge_count,
      density = density,
      symbols = component,
    }
  end

  table.sort(sccs, function(a, b)
    if a.size == b.size then
      if a.density == b.density then
        return a.id < b.id
      end
      return a.density > b.density
    end
    return a.size > b.size
  end)

  local complexity_by_symbol = {}
  for _, symbol_id in ipairs(symbol_ids) do
    local symbol = nodes[symbol_id]
    local in_d = #((index.incoming or {})[symbol_id] or {})
    local out_d = #((index.outgoing or {})[symbol_id] or {})
    local bridge = math.min(in_d, out_d)
    local scc = sccs[scc_by_symbol[symbol_id] or 0]
    local cycle_bonus = (scc and scc.has_cycle) and opts.cycle_weight or 0
    local scc_size = scc and scc.size or 1
    local score = cycle_bonus
      + ((in_d + out_d) * opts.degree_weight)
      + (bridge * opts.bridge_weight)
      + ((scc_size - 1) * opts.scc_size_weight)

    complexity_by_symbol[symbol_id] = {
      symbol = symbol,
      score = score,
      in_degree = in_d,
      out_degree = out_d,
      bridge = bridge,
      scc_id = scc and scc.id or nil,
      scc_size = scc_size,
      in_cycle = (scc and scc.has_cycle) == true,
    }
  end

  local ranked = {}
  for _, item in pairs(complexity_by_symbol) do
    ranked[#ranked + 1] = item
  end
  table.sort(ranked, function(a, b)
    if a.score == b.score then
      return symbol_label(a.symbol) < symbol_label(b.symbol)
    end
    return a.score > b.score
  end)

  local top = {}
  local severity_counts = {
    critical = 0,
    high = 0,
    medium = 0,
    low = 0,
  }
  local top_n = math.max(1, tonumber(opts.top_n) or 15)
  for i = 1, math.min(top_n, #ranked) do
    local item = ranked[i]
    local severity = classify_severity(item.score, opts.severity_thresholds or {})
    severity_counts[severity] = (severity_counts[severity] or 0) + 1
    top[#top + 1] = {
      rank = i,
      symbol = item.symbol,
      score = item.score,
      severity = severity,
      in_degree = item.in_degree,
      out_degree = item.out_degree,
      bridge = item.bridge,
      scc_id = item.scc_id,
      scc_size = item.scc_size,
      in_cycle = item.in_cycle,
      rationale = string.format(
        "deg=%d bridge=%d scc=%d cycle=%s",
        item.in_degree + item.out_degree,
        item.bridge,
        item.scc_size,
        tostring(item.in_cycle)
      ),
    }
  end

  local cluster = complexity_cluster_metrics(index, symbol_ids)
  local cycle_scc_count = 0
  for _, scc in ipairs(sccs) do
    if scc.has_cycle then
      cycle_scc_count = cycle_scc_count + 1
    end
  end

  local scc_limit = math.max(1, tonumber(opts.scc_limit) or 10)
  local top_sccs = {}
  for i = 1, math.min(scc_limit, #sccs) do
    local scc = sccs[i]
    local labels = {}
    for j = 1, math.min(4, #scc.symbols) do
      local symbol = nodes[scc.symbols[j]]
      if symbol then
        labels[#labels + 1] = symbol.name
      end
    end
    top_sccs[#top_sccs + 1] = {
      id = scc.id,
      size = scc.size,
      has_cycle = scc.has_cycle,
      density = scc.density,
      edge_count = scc.edge_count,
      preview = labels,
      symbols = scc.symbols,
    }
  end

  local total_complexity = 0
  for _, item in ipairs(ranked) do
    total_complexity = total_complexity + item.score
  end
  local avg_complexity = #ranked > 0 and (total_complexity / #ranked) or 0
  local structural_score = avg_complexity
    + (cycle_scc_count * 0.8)
    + (cluster.max_cluster_density * 12)
  local overall_severity = classify_severity(structural_score, opts.severity_thresholds or {})

  local suggestions = {}
  if cycle_scc_count > 0 then
    local largest_cycle = 0
    for _, scc in ipairs(sccs) do
      if scc.has_cycle then
        largest_cycle = math.max(largest_cycle, scc.size)
      end
    end
    if largest_cycle >= (tonumber(opts.suggestion_scc_size) or 6) then
      suggestions[#suggestions + 1] = string.format(
        "Large cycle detected (largest SCC size=%d). Consider extracting boundaries/interfaces to break recursive dependencies.",
        largest_cycle
      )
    else
      suggestions[#suggestions + 1] = "Cyclic SCCs exist. Prioritize untangling cycle entry nodes to reduce change amplification."
    end
  end

  if (cluster.max_cluster_density or 0) >= (tonumber(opts.suggestion_density) or 0.35) then
    suggestions[#suggestions + 1] = string.format(
      "High module density detected (max=%.3f). Split dense modules or enforce stricter internal layering.",
      cluster.max_cluster_density
    )
  end

  local bridge_hotspots = 0
  for _, item in ipairs(top) do
    if (item.bridge or 0) >= (tonumber(opts.suggestion_top_bridge) or 6) then
      bridge_hotspots = bridge_hotspots + 1
    end
  end
  if bridge_hotspots > 0 then
    suggestions[#suggestions + 1] = string.format(
      "%d hotspot(s) behave as bridges (high min(in,out)). Add focused regression tests before refactors.",
      bridge_hotspots
    )
  end

  if #suggestions == 0 then
    suggestions[#suggestions + 1] = "Complexity looks manageable at current thresholds. Keep monitoring SCC growth over time."
  end

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    root = index.root,
    total_symbols = #(index.symbols or {}),
    analyzed_symbols = #symbol_ids,
    scc_count = #sccs,
    cycle_scc_count = cycle_scc_count,
    cyclic_symbol_count = cyclic_count,
    structural_complexity_score = structural_score,
    structural_complexity_severity = overall_severity,
    average_symbol_complexity = avg_complexity,
    severity_counts = severity_counts,
    hotspots = top,
    sccs = top_sccs,
    cluster = cluster,
    suggestions = suggestions,
    options = {
      top_n = top_n,
      scc_limit = scc_limit,
      include_tests = to_bool(opts.include_tests, false),
      severity_thresholds = opts.severity_thresholds,
      suggestion_scc_size = opts.suggestion_scc_size,
      suggestion_density = opts.suggestion_density,
      suggestion_top_bridge = opts.suggestion_top_bridge,
      weights = {
        cycle = opts.cycle_weight,
        degree = opts.degree_weight,
        bridge = opts.bridge_weight,
        scc_size = opts.scc_size_weight,
      },
    },
  }, nil
end

function M.write_complexity_report(path, report, opts)
  if not path or path == "" then
    return nil, "report path is required"
  end
  if not report then
    return nil, "complexity report is required"
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
  return {
    path = path,
    bytes = #table.concat(lines, "\n"),
    format = format,
  }, nil
end

function M.risk_map_report(index, opts)
  if not index then
    return nil, "project index unavailable"
  end

  opts = vim.tbl_deep_extend("force", {
    top_n = 20,
    include_tests = false,
    include_churn = true,
    churn_limit = 60,
    churn_since = nil,
    churn_timeout_ms = 5000,
    weight_hot_path = 1.3,
    weight_complexity = 1.1,
    weight_architecture = 1.6,
    weight_churn = 0.35,
    severity_thresholds = {
      critical = 2.2,
      high = 1.4,
      medium = 0.8,
    },
    baseline_path = nil,
    architecture = {
      include_tests = false,
      unknown_layer_policy = "allow",
      max_violation_examples = 8,
    },
  }, opts or {})

  local hot, hot_err = M.hot_path_report(index, {
    top_n = math.max(1, #(index.symbols or {})),
    include_tests = opts.include_tests,
    include_churn = opts.include_churn,
    churn_limit = opts.churn_limit,
    churn_since = opts.churn_since,
    churn_timeout_ms = opts.churn_timeout_ms,
    weight_in = 2.2,
    weight_out = 1.6,
    weight_balance = 2.4,
    weight_reach = 1.1,
    weight_churn = 0.15,
  })
  if not hot then
    return nil, hot_err
  end

  local complexity, complexity_err = M.complexity_report(index, {
    top_n = math.max(1, #(index.symbols or {})),
    include_tests = opts.include_tests,
    scc_limit = 50,
  })
  if not complexity then
    return nil, complexity_err
  end

  local architecture, architecture_err = M.architecture_report(index, opts.architecture)
  if not architecture then
    return nil, architecture_err
  end

  local churn_by_path, churn_meta = file_churn_map(index.root, {
    include_churn = opts.include_churn,
    churn_limit = opts.churn_limit,
    churn_since = opts.churn_since,
    churn_timeout_ms = opts.churn_timeout_ms,
  })

  local hot_map = {}
  local complexity_map = {}
  local architecture_map = {}
  local max_hot = 0
  local max_complexity = 0
  local max_churn = 0

  for _, item in ipairs(hot.hotspots or {}) do
    hot_map[item.symbol.id] = tonumber(item.score) or 0
    max_hot = math.max(max_hot, hot_map[item.symbol.id])
  end
  for _, item in ipairs(complexity.hotspots or {}) do
    complexity_map[item.symbol.id] = tonumber(item.score) or 0
    max_complexity = math.max(max_complexity, complexity_map[item.symbol.id])
  end

  for _, symbol in ipairs(index.symbols or {}) do
    local churn = tonumber(churn_by_path[symbol.relpath or symbol.path]) or 0
    max_churn = math.max(max_churn, churn)
  end

  for _, violation in ipairs(architecture.violations or {}) do
    for _, example in ipairs(violation.examples or {}) do
      architecture_map[example.source_symbol_id] = (architecture_map[example.source_symbol_id] or 0) + 1
      architecture_map[example.target_symbol_id] = (architecture_map[example.target_symbol_id] or 0) + 1
    end
  end

  local by_symbol = {}
  local by_module = {}
  local by_package = {}
  for _, symbol in ipairs(index.symbols or {}) do
    if opts.include_tests or not is_test_symbol(symbol) then
      local hot_score = tonumber(hot_map[symbol.id]) or 0
      local complexity_score = tonumber(complexity_map[symbol.id]) or 0
      local architecture_hits = tonumber(architecture_map[symbol.id]) or 0
      local churn = tonumber(churn_by_path[symbol.relpath or symbol.path]) or 0

      local normalized_hot = max_hot > 0 and (hot_score / max_hot) or 0
      local normalized_complexity = max_complexity > 0 and (complexity_score / max_complexity) or 0
      local normalized_churn = max_churn > 0 and (churn / max_churn) or 0

      local score = (normalized_hot * opts.weight_hot_path)
        + (normalized_complexity * opts.weight_complexity)
        + (architecture_hits * opts.weight_architecture)
        + (normalized_churn * opts.weight_churn)

      local item = {
        symbol = symbol,
        score = score,
        hot_score = hot_score,
        complexity_score = complexity_score,
        architecture_hits = architecture_hits,
        churn = churn,
        rationale = string.format(
          "hot=%.2f complexity=%.2f arch_hits=%d churn=%d",
          normalized_hot,
          normalized_complexity,
          architecture_hits,
          churn
        ),
      }
      by_symbol[#by_symbol + 1] = item

      local module_id = symbol.module_id or "(unknown)"
      by_module[module_id] = by_module[module_id] or { id = module_id, score = 0, count = 0 }
      by_module[module_id].score = by_module[module_id].score + score
      by_module[module_id].count = by_module[module_id].count + 1

      local package_id = symbol.package_id or "(root)"
      by_package[package_id] = by_package[package_id] or { id = package_id, score = 0, count = 0 }
      by_package[package_id].score = by_package[package_id].score + score
      by_package[package_id].count = by_package[package_id].count + 1
    end
  end

  table.sort(by_symbol, function(a, b)
    if a.score == b.score then
      return symbol_label(a.symbol) < symbol_label(b.symbol)
    end
    return a.score > b.score
  end)

  local function ranked_groups(map)
    local out = {}
    for _, item in pairs(map) do
      out[#out + 1] = {
        id = item.id,
        score = item.score,
        count = item.count,
        avg_score = item.count > 0 and (item.score / item.count) or 0,
      }
    end
    table.sort(out, function(a, b)
      if a.avg_score == b.avg_score then
        return a.score > b.score
      end
      return a.avg_score > b.avg_score
    end)
    return out
  end

  local top_n = math.max(1, tonumber(opts.top_n) or 20)
  local top_symbols = {}
  local severity_counts = {
    critical = 0,
    high = 0,
    medium = 0,
    low = 0,
  }
  for i = 1, math.min(top_n, #by_symbol) do
    local item = by_symbol[i]
    local severity = classify_severity(item.score, opts.severity_thresholds or {})
    severity_counts[severity] = (severity_counts[severity] or 0) + 1
    top_symbols[#top_symbols + 1] = {
      rank = i,
      symbol = item.symbol,
      score = item.score,
      severity = severity,
      hot_score = item.hot_score,
      complexity_score = item.complexity_score,
      architecture_hits = item.architecture_hits,
      churn = item.churn,
      rationale = item.rationale,
    }
  end

  local module_rank = ranked_groups(by_module)
  local package_rank = ranked_groups(by_package)

  local function compute_overall_severity(items)
    local max_score = 0
    for _, item in ipairs(items or {}) do
      max_score = math.max(max_score, tonumber(item.score) or 0)
    end
    return classify_severity(max_score, opts.severity_thresholds or {})
  end

  local suggestions = {}
  if tonumber(architecture.violation_count) and tonumber(architecture.violation_count) > 0 then
    suggestions[#suggestions + 1] = string.format(
      "Resolve architecture rule violations first (%d detected) to reduce structural risk spread.",
      tonumber(architecture.violation_count) or 0
    )
  end

  local churn_heavy = 0
  for _, item in ipairs(top_symbols) do
    if tonumber(item.churn or 0) >= 400 then
      churn_heavy = churn_heavy + 1
    end
  end
  if churn_heavy > 0 then
    suggestions[#suggestions + 1] = string.format(
      "%d top hotspot(s) show high churn. Add stricter review and regression checks on these files.",
      churn_heavy
    )
  end

  local arch_heavy = 0
  for _, item in ipairs(top_symbols) do
    if tonumber(item.architecture_hits or 0) > 0 then
      arch_heavy = arch_heavy + 1
    end
  end
  if arch_heavy > 0 then
    suggestions[#suggestions + 1] = string.format(
      "%d top hotspot(s) are linked to architecture violations. Prioritize boundary cleanup before large refactors.",
      arch_heavy
    )
  end

  if #suggestions == 0 then
    suggestions[#suggestions + 1] = "No dominant risk driver detected in top hotspots; keep monitoring trend deltas between snapshots."
  end

  local trend = {
    enabled = false,
    baseline_path = opts.baseline_path,
  }

  if opts.baseline_path and tostring(opts.baseline_path) ~= "" and vim.fn.filereadable(opts.baseline_path) == 1 then
    local baseline_text = table.concat(vim.fn.readfile(opts.baseline_path), "\n")
    local ok, baseline = pcall(vim.json.decode, baseline_text)
    if ok and type(baseline) == "table" then
      trend.enabled = true
      trend.baseline_generated_at = baseline.generated_at

      local current_top = top_symbols
      local previous_top = baseline.risk_hotspots or {}

      local function avg_top(items)
        if not items or #items == 0 then
          return 0
        end
        local sum = 0
        for _, item in ipairs(items) do
          sum = sum + (tonumber(item.score) or 0)
        end
        return sum / #items
      end

      local current_avg = avg_top(current_top)
      local previous_avg = avg_top(previous_top)
      trend.avg_top_score_delta = current_avg - previous_avg

      local current_top1 = tonumber((current_top[1] or {}).score) or 0
      local previous_top1 = tonumber((previous_top[1] or {}).score) or 0
      trend.top1_score_delta = current_top1 - previous_top1

      local previous_ids = {}
      for _, item in ipairs(previous_top) do
        local symbol = item.symbol or {}
        local key = tostring(symbol.id or (symbol.path and (symbol.path .. ":" .. tostring((symbol.range or {})[1])) or ""))
        if key ~= "" then
          previous_ids[key] = true
        end
      end

      local overlap = 0
      for _, item in ipairs(current_top) do
        local symbol = item.symbol or {}
        local key = tostring(symbol.id or (symbol.path and (symbol.path .. ":" .. tostring((symbol.range or {})[1])) or ""))
        if key ~= "" and previous_ids[key] then
          overlap = overlap + 1
        end
      end
      trend.top_overlap_count = overlap
      trend.top_overlap_ratio = (#current_top > 0) and (overlap / #current_top) or 0
    else
      trend.error = "failed to decode baseline snapshot"
    end
  elseif opts.baseline_path and tostring(opts.baseline_path) ~= "" then
    trend.error = "baseline snapshot not found"
  end

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    root = index.root,
    total_symbols = #(index.symbols or {}),
    analyzed_symbols = #by_symbol,
    risk_severity = compute_overall_severity(top_symbols),
    severity_counts = severity_counts,
    risk_hotspots = top_symbols,
    module_risk = module_rank,
    package_risk = package_rank,
    architecture_violation_count = tonumber(architecture.violation_count) or 0,
    churn = churn_meta,
    suggestions = suggestions,
    trend = trend,
    options = {
      top_n = top_n,
      include_tests = to_bool(opts.include_tests, false),
      include_churn = to_bool(opts.include_churn, true),
      churn_limit = opts.churn_limit,
      churn_since = opts.churn_since,
      baseline_path = opts.baseline_path,
      severity_thresholds = opts.severity_thresholds,
      weights = {
        hot_path = opts.weight_hot_path,
        complexity = opts.weight_complexity,
        architecture = opts.weight_architecture,
        churn = opts.weight_churn,
      },
    },
  }, nil
end

function M.write_risk_map_report(path, report, opts)
  if not path or path == "" then
    return nil, "report path is required"
  end
  if not report then
    return nil, "risk map report is required"
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
  return {
    path = path,
    bytes = #table.concat(lines, "\n"),
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
