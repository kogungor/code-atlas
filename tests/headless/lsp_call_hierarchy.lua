local root = vim.fn.getcwd()
local sample = root .. "/playground/samples/checkout_flow.lua"

if vim.fn.exists(":CodeAtlasLSPGraph") ~= 2 then
  error("feature20 smoke failed: :CodeAtlasLSPGraph command is not registered")
end

if vim.fn.exists(":CodeAtlasLSPReverseGraph") ~= 2 then
  error("feature20 smoke failed: :CodeAtlasLSPReverseGraph command is not registered")
end

if vim.fn.exists(":CodeAtlasLSPDebug") ~= 2 then
  error("feature20 smoke failed: :CodeAtlasLSPDebug command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
  lsp = {
    enabled = true,
    timeout_ms = 1000,
    prefer_call_hierarchy = false,
  },
})

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local anchor_line = vim.fn.search("^local function apply_discount_rules", "nw")
if anchor_line == 0 then
  error("feature20 smoke failed: could not locate apply_discount_rules")
end
vim.api.nvim_win_set_cursor(0, { anchor_line, 2 })

local uri = vim.uri_from_fname(vim.fs.normalize(sample))
local external_uri = vim.uri_from_fname(vim.fs.normalize(vim.env.HOME .. "/.cache/code-atlas-external.ts"))
local function item(name, line)
  return {
    name = name,
    uri = uri,
    range = {
      start = { line = line, character = 0 },
      ["end"] = { line = line + 1, character = 0 },
    },
    selectionRange = {
      start = { line = line, character = 0 },
      ["end"] = { line = line, character = #name },
    },
  }
end

local function external_item(name, line)
  return {
    name = name,
    uri = external_uri,
    range = {
      start = { line = line, character = 0 },
      ["end"] = { line = line + 1, character = 0 },
    },
    selectionRange = {
      start = { line = line, character = 0 },
      ["end"] = { line = line, character = #name },
    },
  }
end

local original_get_clients = vim.lsp.get_clients
local original_buf_request_sync = vim.lsp.buf_request_sync

vim.lsp.get_clients = function(_)
  return {
    {
      id = 1000,
      offset_encoding = "utf-16",
      supports_method = function(_, method)
        return method == "textDocument/prepareCallHierarchy"
          or method == "callHierarchy/outgoingCalls"
          or method == "callHierarchy/incomingCalls"
      end,
    },
    {
      id = 999,
      offset_encoding = "utf-16",
      supports_method = function(_, method)
        return method == "textDocument/prepareCallHierarchy"
          or method == "callHierarchy/outgoingCalls"
          or method == "callHierarchy/incomingCalls"
      end,
    },
  }
end

vim.lsp.buf_request_sync = function(_, method, params, _)
  if method == "textDocument/prepareCallHierarchy" then
    return {
      [1000] = {
        result = {},
      },
      [999] = {
        result = {
          item("apply_discount_rules", 28),
        },
      },
    }
  end

  if method == "callHierarchy/outgoingCalls" then
    local name = params.item and params.item.name
    if name == "apply_discount_rules" then
      return {
        [1000] = {
          result = {
            { to = item("bad_noise", 5) },
          },
        },
        [999] = {
          result = {
            { to = item("normalize_coupon", 16) },
            { to = item("customer_has_coupon", 20) },
            { to = external_item("external_helper", 10) },
          },
        },
      }
    end
    if name == "customer_has_coupon" then
      return {
        [1000] = {
          result = {},
        },
        [999] = {
          result = {
            { to = item("is_vip_customer", 24) },
          },
        },
      }
    end
    return { [999] = { result = {} } }
  end

  if method == "callHierarchy/incomingCalls" then
    local name = params.item and params.item.name
    if name == "apply_discount_rules" then
      return {
        [1000] = {
          result = {
            { from = item("bad_noise", 9) },
          },
        },
        [999] = {
          result = {
            { from = item("calculate_total", 50) },
          },
        },
      }
    end
    if name == "calculate_total" then
      return {
        [1000] = {
          result = {},
        },
        [999] = {
          result = {
            { from = item("M.checkout", 80) },
          },
        },
      }
    end
    return { [999] = { result = {} } }
  end

  return { [999] = { result = {} } }
end

atlas.run_lsp_call_graph("outgoing")

local window = require("code-atlas.window")
local state = window.get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature20 smoke failed: lsp outgoing graph window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("mode: callees", 1, true) then
  error("feature20 smoke failed: outgoing mode header missing")
end
if not text:find("backend: lsp_call_hierarchy", 1, true) then
  error("feature20 smoke failed: outgoing backend header missing")
end
if not text:find("lsp_client_id: 999", 1, true) then
  error("feature20 smoke failed: outgoing lsp client id header missing")
end
if not text:find("external_filtered: true", 1, true) then
  error("feature20 smoke failed: outgoing external filter header missing")
end
if not text:find("normalize_coupon", 1, true) then
  error("feature20 smoke failed: outgoing lsp child missing")
end
if not text:find("is_vip_customer", 1, true) then
  error("feature20 smoke failed: outgoing transitive lsp child missing")
end
if text:find("bad_noise", 1, true) then
  error("feature20 smoke failed: outgoing graph should ignore non-selected client noise")
end
if text:find("external_helper", 1, true) then
  error("feature20 smoke failed: outgoing graph should filter external symbols by default")
end

atlas.run_lsp_call_graph("incoming")

local state2 = window.get_state()
local text2 = table.concat(vim.api.nvim_buf_get_lines(state2.buf, 0, -1, false), "\n")
if not text2:find("mode: callers", 1, true) then
  error("feature20 smoke failed: incoming mode header missing")
end
if not text2:find("calculate_total", 1, true) then
  error("feature20 smoke failed: incoming lsp caller missing")
end
if text2:find("bad_noise", 1, true) then
  error("feature20 smoke failed: incoming graph should ignore non-selected client noise")
end

atlas.show_lsp_debug()
local state_debug = window.get_state()
local debug_text = table.concat(vim.api.nvim_buf_get_lines(state_debug.buf, 0, -1, false), "\n")
if not debug_text:find("code%-atlas lsp debug") then
  error("feature20 smoke failed: debug report was not rendered")
end
if not debug_text:find("selected_client_id: 999", 1, true) then
  error("feature20 smoke failed: debug report missing selected client id")
end

atlas.setup({
  depth_limit = 2,
  lsp = {
    enabled = true,
    timeout_ms = 1000,
    prefer_call_hierarchy = true,
  },
})
atlas.build_project_index({ root = root })

vim.lsp.get_clients = function(_)
  return {}
end

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local checkout_line = vim.fn.search("^function M\\.checkout", "nw")
if checkout_line == 0 then
  error("feature20 smoke failed: could not locate M.checkout")
end
vim.api.nvim_win_set_cursor(0, { checkout_line, 2 })
atlas.run_project_call_graph()

local state3 = window.get_state()
local text3 = table.concat(vim.api.nvim_buf_get_lines(state3.buf, 0, -1, false), "\n")
if not text3:find("code%-atlas project graph") then
  error("feature20 smoke failed: project graph fallback was not rendered")
end

vim.lsp.get_clients = original_get_clients
vim.lsp.buf_request_sync = original_buf_request_sync

vim.notify("feature20 smoke passed", vim.log.levels.INFO)
