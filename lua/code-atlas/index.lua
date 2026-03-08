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

local function receiver_tail(value)
  if not value then
    return nil
  end
  local cleaned = value:gsub("[:%s]+$", "")
  return cleaned:match("([%a_][%w_]*)$")
end

local function parse_call_signature(call_text)
  local raw = normalize_symbol_name(call_text)
  if not raw then
    return nil
  end

  local normalized = raw:gsub("%?%.", ".")
  local dcolon_idx = normalized:match("^.*()::")
  local colon_idx = normalized:match("^.*():")
  local dot_idx = normalized:match("^.*()%.")
  local split_idx = dcolon_idx or colon_idx or dot_idx
  local kind = split_idx and "member" or "function"

  local name = normalized
  local receiver = nil
  if split_idx then
    receiver = normalized:sub(1, split_idx - 1)
    if dcolon_idx and split_idx == dcolon_idx then
      name = normalized:sub(split_idx + 2)
    else
      name = normalized:sub(split_idx + 1)
    end
  end

  name = name:match("^([%a_][%w_]*)") or name
  local tail = receiver_tail(receiver)

  return {
    raw = raw,
    name = name,
    receiver = receiver,
    receiver_tail = tail,
    kind = kind,
  }
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

local function method_container_name(node, bufnr, lang)
  if not node then
    return nil
  end

  if (lang == "typescript" or lang == "javascript") and node:type() == "method_definition" then
    local parent = node:parent()
    while parent do
      local t = parent:type()
      if t == "class_declaration" or t == "class" or t == "class_expression" then
        local names = parent:field("name")
        if names and names[1] then
          return node_text(names[1], bufnr)
        end
        break
      end
      parent = parent:parent()
    end
  end

  if lang == "python" and node:type() == "function_definition" then
    local parent = node:parent()
    while parent do
      if parent:type() == "class_definition" then
        local names = parent:field("name")
        if names and names[1] then
          return node_text(names[1], bufnr)
        end
        local class_text = node_text(parent, bufnr)
        if class_text then
          return class_text:match("class%s+([%a_][%w_]*)")
        end
      end
      parent = parent:parent()
    end
  end

  if lang == "go" and node:type() == "method_declaration" then
    local text = node_text(node, bufnr)
    if text then
      local receiver = text:match("^func%s*%(%s*[%w_]+%s+%*?([%a_][%w_]*)")
      if receiver then
        return receiver
      end
    end
  end

  if lang == "rust" and node:type() == "function_item" then
    local parent = node:parent()
    while parent do
      if parent:type() == "impl_item" then
        local impl_text = node_text(parent, bufnr)
        if impl_text then
          local container = impl_text:match("impl%s+([%a_][%w_]*)")
          if container then
            return container
          end
          local trait_for = impl_text:match("impl%s+.-for%s+([%a_][%w_]*)")
          if trait_for then
            return trait_for
          end
        end
      end
      parent = parent:parent()
    end
  end

  return nil
end

local function extract_receiver_types(bufnr, lang, function_node)
  if lang ~= "typescript" and lang ~= "javascript" and lang ~= "lua" and lang ~= "python" and lang ~= "go" and lang ~= "rust" then
    return {}
  end

  local text = node_text(function_node, bufnr)
  if not text or text == "" then
    return {}
  end

  local out = {}
  for var_name, type_name in text:gmatch("([%a_][%w_]*)%s*:%s*([%a_][%w_]*)") do
    out[var_name] = type_name
  end
  for var_name, class_name in text:gmatch("const%s+([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)") do
    out[var_name] = class_name
  end
  for var_name, class_name in text:gmatch("let%s+([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)") do
    out[var_name] = class_name
  end
  for var_name, class_name in text:gmatch("var%s+([%a_][%w_]*)%s*=%s*new%s+([%a_][%w_]*)") do
    out[var_name] = class_name
  end

  for var_name, class_name in text:gmatch("local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_%.]*)%s*[:.]new%s*%(") do
    out[var_name] = class_name
  end
  for var_name, class_name in text:gmatch("local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_%.]*)%s*%(") do
    if not out[var_name] then
      out[var_name] = class_name
    end
  end

  for var_name, type_name in text:gmatch("([%a_][%w_]*)%s*:%s*([%a_][%w_]*)") do
    if not out[var_name] then
      out[var_name] = type_name
    end
  end
  for var_name, class_name in text:gmatch("([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s*%(") do
    if not out[var_name] then
      out[var_name] = class_name
    end
  end

  for var_name, type_name in text:gmatch("var%s+([%a_][%w_]*)%s+%*?([%a_][%w_]*)") do
    out[var_name] = type_name
  end
  for var_name, type_name in text:gmatch("([%a_][%w_]*)%s*:?=%s*&?([%a_][%w_]*)%s*{") do
    out[var_name] = type_name
  end

  for var_name, type_name in text:gmatch("let%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*)") do
    out[var_name] = type_name
  end
  for var_name, type_name in text:gmatch("let%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*)::") do
    if not out[var_name] then
      out[var_name] = type_name
    end
  end

  if lang == "python" then
    out.self = out.self or "self"
    out.cls = out.cls or "cls"
  end

  return out
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
    local parsed = parse_call_signature(call_name)
    if parsed then
      parsed.row = node:range()
      calls[#calls + 1] = parsed
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

local function dedupe_calls(items)
  local seen = {}
  local out = {}
  for _, item in ipairs(items or {}) do
    local key = item.raw
    if item.receiver then
      key = item.receiver .. "->" .. item.name
    end
    if not seen[key] then
      seen[key] = true
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
      local raw_name = name or "<anonymous>"
      local parsed_name = parse_call_signature(raw_name)
      local short_name = raw_name
      local container = method_container_name(outer, buf, lang)
      if not container and parsed_name and parsed_name.kind == "member" and parsed_name.receiver then
        container = parsed_name.receiver
        short_name = parsed_name.name
      end
      local symbol_name = short_name
      if container and short_name ~= "<anonymous>" then
        symbol_name = container .. "." .. short_name
      end
      local calls = dedupe_calls(extract_calls_from_node(buf, lang, outer))
      local receiver_types = extract_receiver_types(buf, lang, outer)

      symbols[#symbols + 1] = {
        id = string.format("%s:%d:%d:%s", path, sr + 1, sc + 1, symbol_name),
        name = symbol_name,
        short_name = short_name,
        container = container,
        symbol_kind = outer:type() == "method_definition" and "Method" or "Function",
        node_type = outer:type(),
        lang = lang,
        path = path,
        relpath = path,
        range = { sr, sc, er, ec },
        calls = calls,
        receiver_types = receiver_types,
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

  local function add_alias(key, symbol)
    if not key or key == "" then
      return
    end
    by_name[key] = by_name[key] or {}
    by_name[key][#by_name[key] + 1] = symbol
  end

  for _, symbol in ipairs(symbols) do
    add_alias(symbol.name, symbol)
    add_alias(symbol.short_name, symbol)

    by_path[symbol.path] = by_path[symbol.path] or {}
    by_path[symbol.path][#by_path[symbol.path] + 1] = symbol

    by_id[symbol.id] = symbol
  end

  return by_name, by_path, by_id
end

local function confidence_from_score(score)
  if score >= 170 then
    return "high"
  end
  if score >= 110 then
    return "medium"
  end
  return "low"
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

local function call_resolution_candidates(source_symbol, call, by_name)
  local call_name = call.name or call.raw
  local candidates = {}
  local seen = {}
  local receiver = call.receiver_tail
  local receiver_type = nil
  if receiver and source_symbol.receiver_types then
    receiver_type = source_symbol.receiver_types[receiver]
  end

  for def_name, defs in pairs(by_name) do
    if names_match(call_name, def_name) then
      for _, def in ipairs(defs) do
        if def.id ~= source_symbol.id and not seen[def.id] then
          seen[def.id] = true
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

          if call.kind == "member" then
            if def.container then
              score = score + 15
              reasons[#reasons + 1] = "member_target"
            end

            if receiver_type and def.container then
              if receiver_type == def.container then
                score = score + 130
                reasons[#reasons + 1] = "receiver_type_match"
              elseif (receiver_type == "self" or receiver_type == "cls") and source_symbol.container and def.container == source_symbol.container then
                score = score + 120
                reasons[#reasons + 1] = "python_self_container_match"
              else
                score = score - 35
                reasons[#reasons + 1] = "receiver_type_mismatch"
              end
            elseif receiver and def.container and receiver == def.container then
              score = score + 90
              reasons[#reasons + 1] = "receiver_name_match"
            elseif receiver == "this" and source_symbol.container and def.container == source_symbol.container then
              score = score + 110
              reasons[#reasons + 1] = "this_container_match"
            end
          end

          candidates[#candidates + 1] = {
            id = def.id,
            name = def.name,
            path = def.path,
            source = "index",
            score = score,
            confidence = confidence_from_score(score),
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

  for _, call in ipairs(symbol.calls or {}) do
    local call_obj = call
    if type(call_obj) == "string" then
      call_obj = parse_call_signature(call_obj)
    end
    if call_obj then
      local candidates = call_resolution_candidates(symbol, call_obj, by_name)
    local best = candidates[1]

    resolutions[#resolutions + 1] = {
      call = call_obj.raw,
      call_name = call_obj.name,
      receiver = call_obj.receiver,
      receiver_type = call_obj.receiver_tail and (symbol.receiver_types or {})[call_obj.receiver_tail] or nil,
      unresolved = best == nil,
      candidates = candidates,
      best = best,
    }

    if best then
      ids[#ids + 1] = best.id
    end
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

local function sort_candidates(candidates)
  table.sort(candidates, function(a, b)
    if a.score == b.score then
      if a.path == b.path then
        return a.name < b.name
      end
      return a.path < b.path
    end
    return a.score > b.score
  end)
end

local function lsp_index_candidates(index, source_symbol, lsp_candidates)
  local out = {}

  for _, item in ipairs(lsp_candidates or {}) do
    local path = item.path and normalize_path(item.path) or nil
    local matched = false

    for _, symbol in ipairs((path and index.by_path[path]) or {}) do
      if names_match(item.name, symbol.name) or names_match(item.name, symbol.short_name or symbol.name) then
        local score = 165
        local reasons = { "lsp_hierarchy", "index_symbol_match" }
        if source_symbol.path == symbol.path then
          score = score + 20
          reasons[#reasons + 1] = "same_file"
        end

        out[#out + 1] = {
          id = symbol.id,
          name = symbol.name,
          path = symbol.path,
          source = "mixed(index+lsp)",
          score = score,
          confidence = confidence_from_score(score),
          reasons = reasons,
        }
        matched = true
      end
    end

    if not matched and path then
      local score = 140
      local reasons = { "lsp_hierarchy", "external_or_unindexed" }
      if source_symbol.path == path then
        score = score + 10
        reasons[#reasons + 1] = "same_file"
      end

      out[#out + 1] = {
        id = nil,
        name = item.name,
        path = path,
        source = "lsp",
        score = score,
        confidence = confidence_from_score(score),
        reasons = reasons,
      }
    end
  end

  return out
end

function M.merge_lsp_candidates(index, source_symbol_id, lsp_candidates)
  if not index or not source_symbol_id then
    return false
  end

  local source_symbol = index.by_id[source_symbol_id]
  if not source_symbol then
    return false
  end

  local resolutions = index.call_resolutions[source_symbol_id]
  if not resolutions then
    return false
  end

  local lsp_resolved = lsp_index_candidates(index, source_symbol, lsp_candidates)
  if #lsp_resolved == 0 then
    return false
  end

  local merged_any = false
  for _, item in ipairs(resolutions) do
    local call_name = item.call_name or item.call
    local merged = {}
    local seen = {}

    local function add_candidate(candidate)
      local key = tostring(candidate.id) .. "|" .. tostring(candidate.name) .. "|" .. tostring(candidate.path)
      local prev = seen[key]
      if prev then
        local incoming_source = tostring(candidate.source or "")
        local prev_source = tostring(prev.source or "")
        if prev_source == "index" and (incoming_source == "mixed(index+lsp)" or incoming_source == "lsp") then
          prev.source = "mixed(index+lsp)"
          prev.reasons = prev.reasons or {}
          prev.reasons[#prev.reasons + 1] = "lsp_confirmed"
        end
        if (candidate.score or 0) > (prev.score or 0) then
          prev.score = candidate.score
          if incoming_source ~= "" then
            prev.source = candidate.source
          end
          prev.confidence = confidence_from_score(candidate.score or 0)
          prev.reasons = candidate.reasons or prev.reasons
        end
        return
      end

      local clone = vim.deepcopy(candidate)
      clone.confidence = clone.confidence or confidence_from_score(clone.score or 0)
      merged[#merged + 1] = clone
      seen[key] = clone
    end

    for _, candidate in ipairs(item.candidates or {}) do
      add_candidate(candidate)
    end

    for _, candidate in ipairs(lsp_resolved) do
      if call_name and names_match(call_name, candidate.name) then
        add_candidate(candidate)
        merged_any = true
      end
    end

    sort_candidates(merged)
    item.candidates = merged
    item.best = merged[1]
    item.unresolved = item.best == nil or item.best.id == nil or index.by_id[item.best.id] == nil
  end

  if not merged_any then
    return false
  end

  local old_out = index.outgoing[source_symbol_id] or {}
  local new_out = {}
  for _, item in ipairs(resolutions) do
    if item.best and item.best.id and index.by_id[item.best.id] then
      new_out[#new_out + 1] = item.best.id
    end
  end
  new_out = dedupe(new_out)
  index.outgoing[source_symbol_id] = new_out

  local old_set = {}
  for _, id in ipairs(old_out) do
    old_set[id] = true
  end
  local new_set = {}
  for _, id in ipairs(new_out) do
    new_set[id] = true
  end

  for target_id, _ in pairs(old_set) do
    if not new_set[target_id] then
      local ins = index.incoming[target_id] or {}
      local filtered = {}
      for _, id in ipairs(ins) do
        if id ~= source_symbol_id then
          filtered[#filtered + 1] = id
        end
      end
      index.incoming[target_id] = dedupe(filtered)
    end
  end

  for target_id, _ in pairs(new_set) do
    index.incoming[target_id] = index.incoming[target_id] or {}
    index.incoming[target_id][#index.incoming[target_id] + 1] = source_symbol_id
    index.incoming[target_id] = dedupe(index.incoming[target_id])
  end

  local unresolved_count = 0
  for _, entries in pairs(index.call_resolutions or {}) do
    for _, entry in ipairs(entries or {}) do
      if entry.unresolved then
        unresolved_count = unresolved_count + 1
      end
    end
  end
  index.unresolved_count = unresolved_count

  return true
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
