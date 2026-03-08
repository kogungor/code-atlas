local M = {
  state = {
    index = nil,
    root = nil,
    autocmd_ready = false,
  },
}

local unpack_fn = table.unpack or unpack

local function normalize_path(path)
  return vim.fs.normalize(path)
end

local function relative_path(root, path)
  local prefix = root
  if prefix:sub(-1) ~= "/" then
    prefix = prefix .. "/"
  end
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

local function strip_extension(path)
  return (path:gsub("%.[^.]+$", ""))
end

local function module_id_from_relpath(relpath)
  local base = strip_extension(relpath)
  return base:gsub("/", ".")
end

local function dirname(path)
  return vim.fs.dirname(path)
end

local function package_id_from_relpath(relpath)
  local first = relpath:match("^([^/]+)/")
  return first or "(root)"
end

local function language_for_path(path)
  local ext = path:match("%.([^.]+)$")
  if not ext then
    return nil
  end

  local map = {
    lua = "lua",
    py = "python",
    js = "javascript",
    jsx = "javascript",
    ts = "typescript",
    tsx = "typescript",
    go = "go",
    rs = "rust",
  }

  return map[ext]
end

local function query_for_language(lang)
  local names = { "code_atlas", "code-atlas" }
  for _, name in ipairs(names) do
    local ok, query = pcall(vim.treesitter.query.get, lang, name)
    if ok and query then
      return query
    end
  end
  return nil
end

local function call_types_for_language(lang)
  local per_lang = {
    lua = { function_call = true },
    python = { call = true },
    typescript = { call_expression = true, new_expression = true },
    javascript = { call_expression = true, new_expression = true },
    go = { call_expression = true },
    rust = { call_expression = true, macro_invocation = true },
  }

  return per_lang[lang] or {
    call_expression = true,
    function_call = true,
    call = true,
  }
end

local function capture_node(value)
  if type(value) == "table" then
    return value[#value]
  end
  return value
end

local function normalize_symbol_name(name)
  if not name then
    return nil
  end
  local cleaned = name:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if cleaned == "" then
    return nil
  end
  return cleaned
end

local function names_match(call_name, def_name)
  local left = normalize_symbol_name(call_name)
  local right = normalize_symbol_name(def_name)
  if not left or not right then
    return false
  end

  if left == right then
    return true
  end

  if right:sub(-(#left + 1)) == "." .. left or right:sub(-(#left + 1)) == ":" .. left then
    return true
  end

  if left:sub(-(#right + 1)) == "." .. right or left:sub(-(#right + 1)) == ":" .. right then
    return true
  end

  return false
end

local function node_text(node, bufnr)
  if not node then
    return nil
  end
  return normalize_symbol_name(vim.treesitter.get_node_text(node, bufnr))
end

local function file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return lines
end

local function add_unique(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return
    end
  end
  list[#list + 1] = value
end

local function relative_join(base_relpath, part)
  local base_dir = dirname(base_relpath)
  return normalize_path(base_dir .. "/" .. part)
end

local function lua_module_candidates(module_name)
  local slash = module_name:gsub("%.", "/")
  return {
    slash .. ".lua",
    slash .. "/init.lua",
  }
end

local function relative_import_candidates(base_relpath, import_path)
  local path = relative_join(base_relpath, import_path)
  return {
    path,
    path .. ".lua",
    path .. ".ts",
    path .. ".tsx",
    path .. ".js",
    path .. ".jsx",
    path .. ".py",
    path .. ".go",
    path .. ".rs",
    path .. "/init.lua",
    path .. "/index.ts",
    path .. "/index.js",
    path .. "/__init__.py",
    path .. "/mod.rs",
  }
end

local function parse_import_tokens(lines, lang)
  local tokens = {}

  for _, line in ipairs(lines or {}) do
    if lang == "lua" then
      for mod in line:gmatch("require%s*%(%s*[\"']([^\"']+)[\"']%s*%)") do
        add_unique(tokens, mod)
      end
      for mod in line:gmatch("require%s+[\"']([^\"']+)[\"']") do
        add_unique(tokens, mod)
      end
    elseif lang == "python" then
      local from_mod = line:match("^%s*from%s+([%w_%.]+)%s+import%s+")
      if from_mod then
        add_unique(tokens, from_mod)
      end
      local import_mod = line:match("^%s*import%s+([%w_%.]+)")
      if import_mod then
        add_unique(tokens, import_mod)
      end
    elseif lang == "typescript" or lang == "javascript" then
      local from_path = line:match("from%s+[\"']([^\"']+)[\"']")
      if from_path then
        add_unique(tokens, from_path)
      end
      local req_path = line:match("require%s*%(%s*[\"']([^\"']+)[\"']%s*%)")
      if req_path then
        add_unique(tokens, req_path)
      end
      local direct = line:match("^%s*import%s+[\"']([^\"']+)[\"']")
      if direct then
        add_unique(tokens, direct)
      end
    elseif lang == "go" then
      local single = line:match("^%s*import%s+[\"']([^\"']+)[\"']")
      if single then
        add_unique(tokens, single)
      end
      for mod in line:gmatch("[\"']([^\"']+)[\"']") do
        add_unique(tokens, mod)
      end
    elseif lang == "rust" then
      local use_mod = line:match("^%s*use%s+([^;]+)")
      if use_mod then
        add_unique(tokens, use_mod)
      end
      local mod_decl = line:match("^%s*mod%s+([%w_]+)")
      if mod_decl then
        add_unique(tokens, mod_decl)
      end
    end
  end

  return tokens
end

local function resolve_import_token(base_relpath, token, lang, file_set)
  local candidates = {}

  if token:sub(1, 1) == "." then
    candidates = relative_import_candidates(base_relpath, token)
  elseif lang == "lua" then
    candidates = lua_module_candidates(token)
  elseif lang == "python" then
    local slash = token:gsub("%.", "/")
    candidates = {
      slash .. ".py",
      slash .. "/__init__.py",
    }
  end

  for _, rel in ipairs(candidates) do
    local normalized = normalize_path(rel)
    if file_set[normalized] then
      return normalized
    end
  end

  return nil
end

local function extract_import_edges(path, relpath, lang, file_set)
  local lines = file_lines(path)
  local tokens = parse_import_tokens(lines, lang)
  local imports = {}

  for _, token in ipairs(tokens) do
    local resolved = resolve_import_token(relpath, token, lang, file_set)
    if resolved then
      add_unique(imports, resolved)
    end
  end

  return imports
end

local function iter_descendants(node, fn)
  if not node then
    return
  end
  fn(node)
  for child in node:iter_children() do
    iter_descendants(child, fn)
  end
end

local function call_target_node(call_node)
  local fields = { "name", "function", "value", "method" }
  for _, field in ipairs(fields) do
    local got = call_node:field(field)
    if got and got[1] then
      return got[1]
    end
  end

  for child in call_node:iter_children() do
    if child:named() then
      return child
    end
  end

  return nil
end

local function extract_calls_from_node(bufnr, lang, function_node)
  local calls = {}
  local wanted = call_types_for_language(lang)

  iter_descendants(function_node, function(node)
    if node == function_node then
      return
    end
    if not wanted[node:type()] then
      return
    end

    local target = call_target_node(node)
    local call_name = node_text(target, bufnr)
    if call_name then
      calls[#calls + 1] = call_name
    end
  end)

  return calls
end

local function dedupe(items)
  local seen = {}
  local out = {}
  for _, item in ipairs(items) do
    if not seen[item] then
      seen[item] = true
      out[#out + 1] = item
    end
  end
  return out
end

local function dedupe_ids(items)
  return dedupe(items)
end

local function extract_functions(path, lang)
  local query = query_for_language(lang)
  if not query then
    return {}
  end

  local lines = file_lines(path)
  if not lines then
    return {}
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", lang, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local parser_ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not parser_ok or not parser then
    vim.api.nvim_buf_delete(buf, { force = true })
    return {}
  end

  local trees = parser:parse()
  local tree = trees and trees[1]
  if not tree then
    vim.api.nvim_buf_delete(buf, { force = true })
    return {}
  end

  local root = tree:root()
  local symbols = {}

  for _, matches in query:iter_matches(root, buf, 0, -1) do
    local outer
    local name

    for id, value in pairs(matches) do
      local node = capture_node(value)
      local capture = query.captures[id]
      if capture == "function.outer" then
        outer = node
      elseif capture == "function.name" then
        name = node_text(node, buf)
      end
    end

    if outer then
      local sr, sc, er, ec = outer:range()
      local symbol_name = name or "<anonymous>"
      local calls = dedupe(extract_calls_from_node(buf, lang, outer))

      symbols[#symbols + 1] = {
        id = string.format("%s:%d:%d:%s", path, sr + 1, sc + 1, symbol_name),
        name = symbol_name,
        symbol_kind = "Function",
        node_type = outer:type(),
        lang = lang,
        path = path,
        relpath = path,
        range = { sr, sc, er, ec },
        calls = calls,
      }
    end
  end

  vim.api.nvim_buf_delete(buf, { force = true })
  return symbols
end

local function project_files(root)
  local pattern = root .. "/**/*"
  local paths = vim.fn.glob(pattern, true, true)
  local out = {}

  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 0 then
      local normalized = normalize_path(path)
      if language_for_path(normalized) then
        out[#out + 1] = normalized
      end
    end
  end

  table.sort(out)
  return out
end

local function build_maps(symbols)
  local by_name = {}
  local by_path = {}
  local by_id = {}

  for _, symbol in ipairs(symbols) do
    by_name[symbol.name] = by_name[symbol.name] or {}
    by_name[symbol.name][#by_name[symbol.name] + 1] = symbol

    by_path[symbol.path] = by_path[symbol.path] or {}
    by_path[symbol.path][#by_path[symbol.path] + 1] = symbol

    by_id[symbol.id] = symbol
  end

  return by_name, by_path, by_id
end

local function build_dependency_graph(symbols, outgoing, level)
  local nodes = {}
  local out = {}
  local incoming = {}
  local symbol_by_id = {}

  for _, symbol in ipairs(symbols) do
    symbol_by_id[symbol.id] = symbol
  end

  local function id_for_symbol(symbol)
    if level == "package" then
      return symbol.package_id
    end
    return symbol.module_id
  end

  for _, symbol in ipairs(symbols) do
    local source_id = id_for_symbol(symbol)
    if source_id then
      nodes[source_id] = nodes[source_id] or {
        id = source_id,
        label = source_id,
        target = {
          path = symbol.path,
          row = symbol.range[1],
          col = symbol.range[2],
        },
      }

      out[source_id] = out[source_id] or {}
      incoming[source_id] = incoming[source_id] or {}

      for _, target_symbol_id in ipairs(outgoing[symbol.id] or {}) do
        local target_symbol = symbol_by_id[target_symbol_id]

        if target_symbol then
          local target_id = id_for_symbol(target_symbol)
          if target_id then
            out[source_id][#out[source_id] + 1] = target_id
            incoming[target_id] = incoming[target_id] or {}
            incoming[target_id][#incoming[target_id] + 1] = source_id
          end
        end
      end
    end
  end

  local edge_count = 0
  for id, ids in pairs(out) do
    out[id] = dedupe_ids(ids)
    edge_count = edge_count + #out[id]
  end

  for id, ids in pairs(incoming) do
    incoming[id] = dedupe_ids(ids)
  end

  return {
    level = level,
    nodes = nodes,
    outgoing = out,
    incoming = incoming,
    edge_count = edge_count,
    node_count = vim.tbl_count(nodes),
  }
end

local function call_resolution_candidates(source_symbol, call_name, by_name)
  local candidates = {}

  for def_name, defs in pairs(by_name) do
    if names_match(call_name, def_name) then
      for _, def in ipairs(defs) do
        if def.id ~= source_symbol.id then
          local score = 0
          local reasons = {}

          if call_name == def_name then
            score = score + 100
            reasons[#reasons + 1] = "exact"
          else
            score = score + 60
            reasons[#reasons + 1] = "suffix"
          end

          if source_symbol.path == def.path then
            score = score + 30
            reasons[#reasons + 1] = "same_file"
          else
            score = score + 10
            reasons[#reasons + 1] = "cross_file"
          end

          if def.name == "<anonymous>" then
            score = score - 50
            reasons[#reasons + 1] = "anonymous_penalty"
          end

          candidates[#candidates + 1] = {
            id = def.id,
            name = def.name,
            path = def.path,
            score = score,
            reasons = reasons,
          }
        end
      end
    end
  end

  table.sort(candidates, function(a, b)
    if a.score == b.score then
      if a.path == b.path then
        return a.name < b.name
      end
      return a.path < b.path
    end
    return a.score > b.score
  end)

  return candidates
end

local function resolve_outgoing(symbol, by_name)
  local ids = {}
  local resolutions = {}

  for _, call_name in ipairs(symbol.calls or {}) do
    local candidates = call_resolution_candidates(symbol, call_name, by_name)
    local best = candidates[1]

    resolutions[#resolutions + 1] = {
      call = call_name,
      unresolved = best == nil,
      candidates = candidates,
      best = best,
    }

    if best then
      ids[#ids + 1] = best.id
    end
  end

  return dedupe(ids), resolutions
end

local function build_edges(symbols, by_name)
  local outgoing = {}
  local incoming = {}
  local call_resolutions = {}
  local unresolved_count = 0

  for _, symbol in ipairs(symbols) do
    local out, resolutions = resolve_outgoing(symbol, by_name)
    outgoing[symbol.id] = out
    incoming[symbol.id] = incoming[symbol.id] or {}
    call_resolutions[symbol.id] = resolutions

    for _, item in ipairs(resolutions) do
      if item.unresolved then
        unresolved_count = unresolved_count + 1
      end
    end

    for _, target_id in ipairs(out) do
      incoming[target_id] = incoming[target_id] or {}
      incoming[target_id][#incoming[target_id] + 1] = symbol.id
    end
  end

  for id, ins in pairs(incoming) do
    incoming[id] = dedupe(ins)
  end

  return outgoing, incoming, call_resolutions, unresolved_count
end

local function build_import_graph(root, files)
  local nodes = {}
  local outgoing = {}
  local incoming = {}
  local file_set = {}

  for _, abs_path in ipairs(files) do
    local rel = relative_path(root, abs_path)
    file_set[rel] = abs_path
  end

  for rel, abs_path in pairs(file_set) do
    local lang = language_for_path(abs_path)
    nodes[rel] = {
      id = rel,
      label = rel,
      target = {
        path = abs_path,
        row = 0,
        col = 0,
      },
    }

    local deps = extract_import_edges(abs_path, rel, lang, file_set)
    outgoing[rel] = deps
    incoming[rel] = incoming[rel] or {}

    for _, dep in ipairs(deps) do
      incoming[dep] = incoming[dep] or {}
      incoming[dep][#incoming[dep] + 1] = rel
    end
  end

  local edge_count = 0
  for id, deps in pairs(outgoing) do
    outgoing[id] = dedupe_ids(deps)
    edge_count = edge_count + #outgoing[id]
  end
  for id, deps in pairs(incoming) do
    incoming[id] = dedupe_ids(deps)
  end

  return {
    nodes = nodes,
    outgoing = outgoing,
    incoming = incoming,
    node_count = vim.tbl_count(nodes),
    edge_count = edge_count,
  }
end

local function build_index(root)
  local symbols = {}
  local files = project_files(root)

  for _, path in ipairs(files) do
    local lang = language_for_path(path)
    local found = extract_functions(path, lang)
    for _, symbol in ipairs(found) do
      symbol.relpath = relative_path(root, symbol.path)
      symbol.module_id = module_id_from_relpath(symbol.relpath)
      symbol.package_id = package_id_from_relpath(symbol.relpath)
      symbols[#symbols + 1] = symbol
    end
  end

  local by_name, by_path, by_id = build_maps(symbols)
  local outgoing, incoming, call_resolutions, unresolved_count = build_edges(symbols, by_name)
  local module_graph = build_dependency_graph(symbols, outgoing, "module")
  local package_graph = build_dependency_graph(symbols, outgoing, "package")

  local import_graph = build_import_graph(root, files)

  return {
    root = root,
    generated_at = os.time(),
    files_indexed = #files,
    symbol_count = #symbols,
    symbols = symbols,
    by_name = by_name,
    by_path = by_path,
    by_id = by_id,
    outgoing = outgoing,
    incoming = incoming,
    call_resolutions = call_resolutions,
    unresolved_count = unresolved_count,
    module_graph = module_graph,
    package_graph = package_graph,
    import_graph = import_graph,
  }
end

local function ensure_autocmd()
  if M.state.autocmd_ready then
    return
  end

  local group = vim.api.nvim_create_augroup("CodeAtlasProjectIndex", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      if not M.state.index then
        return
      end

      local file = normalize_path(args.file)
      if file == "" or not language_for_path(file) then
        return
      end

      if not file:find(M.state.root, 1, true) then
        return
      end

      M.refresh({ silent = true })
    end,
  })

  M.state.autocmd_ready = true
end

function M.find_symbol_at(index, path, row, col)
  if not index then
    return nil
  end

  local list = index.by_path[path] or {}
  local best = nil

  for _, symbol in ipairs(list) do
    local sr, sc, er, ec = unpack_fn(symbol.range)
    local inside = true

    if row < sr or row > er then
      inside = false
    elseif row == sr and col < sc then
      inside = false
    elseif row == er and col >= ec then
      inside = false
    end

    if inside then
      if not best then
        best = symbol
      else
        local bsr, bsc, ber, bec = unpack_fn(best.range)
        local current_size = (er - sr) * 10000 + (ec - sc)
        local best_size = (ber - bsr) * 10000 + (bec - bsc)
        if current_size < best_size then
          best = symbol
        end
      end
    end
  end

  return best
end

function M.build(opts)
  opts = opts or {}
  local root = normalize_path(opts.root or vim.fn.getcwd())

  local index = build_index(root)
  M.state.index = index
  M.state.root = root
  ensure_autocmd()

  return index, nil
end

function M.refresh(opts)
  opts = opts or {}
  if not M.state.root then
    return M.build(opts)
  end

  local index = build_index(M.state.root)
  M.state.index = index

  if not opts.silent then
    vim.notify(
      string.format("code-atlas: project index refreshed (%d symbols)", index.symbol_count),
      vim.log.levels.INFO
    )
  end

  return index, nil
end

function M.get()
  return M.state.index
end

function M.module_graph(index)
  index = index or M.state.index
  if not index then
    return nil
  end
  return index.module_graph
end

function M.package_graph(index)
  index = index or M.state.index
  if not index then
    return nil
  end
  return index.package_graph
end

function M.import_graph(index)
  index = index or M.state.index
  if not index then
    return nil
  end
  return index.import_graph
end

return M
