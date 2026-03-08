local M = {}

local function resolve_language(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local map = {
    javascriptreact = "javascript",
    typescriptreact = "typescript",
  }
  return map[filetype] or filetype
end

local function node_text(node, bufnr)
  if not node then
    return nil
  end
  return vim.treesitter.get_node_text(node, bufnr)
end

local function node_contains(node, row, col)
  if not node then
    return false
  end
  local sr, sc, er, ec = node:range()
  if row < sr or row > er then
    return false
  end
  if row == sr and col < sc then
    return false
  end
  if row == er and col >= ec then
    return false
  end
  return true
end

local function node_size(node)
  local sr, sc, er, ec = node:range()
  return (er - sr) * 10000 + (ec - sc)
end

local function parser_root(bufnr, lang)
  local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not parser_ok or not parser then
    return nil, "tree-sitter parser unavailable for language: " .. lang
  end

  local trees = parser:parse()
  local tree = trees and trees[1]
  if not tree then
    return nil, "failed to parse buffer"
  end

  return tree:root(), nil
end

local function capture_node(value)
  if not value then
    return nil
  end
  if type(value) == "table" then
    return value[#value]
  end
  return value
end

local function query_for_lang(lang)
  local names = { "code_atlas", "code-atlas" }

  for _, name in ipairs(names) do
    local ok, result = pcall(vim.treesitter.query.get, lang, name)
    if ok and result then
      return result
    end
  end

  return nil
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

local function function_from_query(bufnr, lang, root, row, col)
  local query = query_for_lang(lang)

  if not query then
    return nil
  end

  local best = nil

  for _, matches in query:iter_matches(root, bufnr, 0, -1) do
    local outer
    local name

    for id, value in pairs(matches) do
      local node = capture_node(value)
      local capture = query.captures[id]
      if capture == "function.outer" then
        outer = node
      elseif capture == "function.name" then
        name = node_text(node, bufnr)
      end
    end

    if outer and node_contains(outer, row, col) then
      local candidate = {
        name = name or "<anonymous>",
        node_type = outer:type(),
        range = { outer:range() },
        lang = lang,
      }

      if not best or node_size(outer) < node_size(best._node) then
        candidate._node = outer
        best = candidate
      end
    end
  end

  return best
end

local function collect_functions(bufnr, lang, root)
  local query = query_for_lang(lang)
  if not query then
    return {}
  end

  local result = {}

  for _, matches in query:iter_matches(root, bufnr, 0, -1) do
    local outer
    local name

    for id, value in pairs(matches) do
      local node = capture_node(value)
      local capture = query.captures[id]

      if capture == "function.outer" then
        outer = node
      elseif capture == "function.name" then
        name = node_text(node, bufnr)
      end
    end

    if outer then
      result[#result + 1] = {
        name = normalize_symbol_name(name) or "<anonymous>",
        node_type = outer:type(),
        range = { outer:range() },
        lang = lang,
        _node = outer,
      }
    end
  end

  return result
end

local function function_from_cursor_node(bufnr, row, col, lang)
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })
  if not node then
    return nil
  end

  local known_types = {
    function_definition = true,
    function_declaration = true,
    method_definition = true,
    method_declaration = true,
    function_item = true,
    closure_expression = true,
  }

  while node do
    if known_types[node:type()] then
      return {
        name = "<anonymous>",
        node_type = node:type(),
        range = { node:range() },
        lang = lang,
        _node = node,
      }
    end
    node = node:parent()
  end

  return nil
end

local function resolve_current_function(bufnr, row, col, lang, root)
  local from_query = function_from_query(bufnr, lang, root, row, col)
  if from_query then
    return from_query, nil
  end

  local from_fallback = function_from_cursor_node(bufnr, row, col, lang)
  if from_fallback then
    return from_fallback, nil
  end

  return nil, "no function found under cursor"
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

local function normalize_call_name(text)
  return normalize_symbol_name(text)
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

local function call_types_for_language(lang)
  local per_lang = {
    lua = { function_call = true },
    python = { call = true },
    typescript = { call_expression = true, new_expression = true },
    javascript = { call_expression = true, new_expression = true },
    go = { call_expression = true },
    rust = { call_expression = true, macro_invocation = true },
  }

  local defaults = {
    call_expression = true,
    function_call = true,
    call = true,
  }

  return per_lang[lang] or defaults
end

local function extract_calls_from_function(bufnr, lang, function_node)
  local wanted_types = call_types_for_language(lang)
  local calls = {}

  iter_descendants(function_node, function(node)
    if node == function_node then
      return
    end

    if not wanted_types[node:type()] then
      return
    end

    local target = call_target_node(node)
    local name = normalize_call_name(node_text(target, bufnr)) or "<unknown>"
    local sr, sc, er, ec = node:range()

    calls[#calls + 1] = {
      name = name,
      node_type = node:type(),
      range = { sr, sc, er, ec },
    }
  end)

  return calls
end

function M.get_current_function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local lang = resolve_language(bufnr)
  local root, parse_err = parser_root(bufnr, lang)
  if not root then
    return nil, parse_err
  end

  local func, err = resolve_current_function(bufnr, row, col, lang, root)
  if not func then
    return nil, err
  end

  func._node = nil
  return func, nil
end

function M.list_local_functions(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lang = resolve_language(bufnr)
  local root, parse_err = parser_root(bufnr, lang)
  if not root then
    return nil, parse_err
  end

  local functions = collect_functions(bufnr, lang, root)
  for _, item in ipairs(functions) do
    item._node = nil
  end

  return functions, nil
end

function M.get_local_calls(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local lang = resolve_language(bufnr)
  local root, parse_err = parser_root(bufnr, lang)

  if not root then
    return nil, parse_err
  end

  local func, err = resolve_current_function(bufnr, row, col, lang, root)
  if not func then
    return nil, err
  end

  if not func._node then
    return {}, nil
  end

  local calls = extract_calls_from_function(bufnr, lang, func._node)
  return calls, nil
end

function M.find_local_function_definition(bufnr, call_name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lang = resolve_language(bufnr)
  local root, parse_err = parser_root(bufnr, lang)
  if not root then
    return nil, parse_err
  end

  local functions = collect_functions(bufnr, lang, root)
  for _, item in ipairs(functions) do
    if names_match(call_name, item.name) then
      item._node = nil
      return item, nil
    end
  end

  return nil, "definition not found"
end

function M.get_local_calls_for_function(bufnr, function_name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lang = resolve_language(bufnr)
  local root, parse_err = parser_root(bufnr, lang)
  if not root then
    return nil, parse_err
  end

  local functions = collect_functions(bufnr, lang, root)
  for _, item in ipairs(functions) do
    if names_match(function_name, item.name) then
      if not item._node then
        return {}, nil
      end
      return extract_calls_from_function(bufnr, lang, item._node), nil
    end
  end

  return nil, "function not found"
end

return M
