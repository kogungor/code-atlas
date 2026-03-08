local M = {}

M.defaults = {
  depth_limit = 2,
  lsp = {
    enabled = true,
    timeout_ms = 1200,
    prefer_call_hierarchy = false,
    include_external = false,
  },
  resolution = {
    poly_score_window = 25,
    poly_min_confidence = "medium",
    max_poly_targets = 3,
  },
  layout = {
    algorithm = "hierarchical",
    spacing_x = 220,
    spacing_y = 90,
    force_iterations = 24,
  },
  ui = {
    border = "rounded",
    max_width = 0.8,
    max_height = 0.8,
    mode = "tree",
  },
  architecture = {
    include_tests = false,
    unknown_layer_policy = "allow",
    max_violation_examples = 3,
    export_format = "json",
    export_pretty = true,
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
    rules = {},
    rules_mode = "merge",
    severity_thresholds = {
      critical = 90,
      high = 70,
      medium = 55,
    },
  },
  evolution = {
    limit = 30,
    hotspot_limit = 10,
    include_merges = false,
    since = nil,
    path = nil,
    timeout_ms = 5000,
    export_format = "json",
    export_pretty = true,
  },
  viewer = {
    depth_limit = 3,
    direction = "outgoing",
    dynamic_only = false,
    node_kind = "all",
    filter_path_prefix = nil,
    search_query = nil,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

function M.get()
  return M.options
end

return M
