<div align="center">

# code-atlas

Neovim code-intelligence for call graphs, architecture checks, and risk-focused code health.

![Neovim](https://img.shields.io/badge/neovim-%3E%3D0.10-57A143?logo=neovim&logoColor=white)
![Languages](https://img.shields.io/badge/languages-lua%20python%20ts/js%20go%20rust-3b82f6)
![License](https://img.shields.io/badge/license-MIT-22c55e)

</div>

`code-atlas` combines Tree-sitter parsing, project indexing, and git-aware analysis to answer questions like:

- What does this function call?
- Who calls this function?
- Which modules/files depend on this part of the code?
- What might break if I change or remove this function?

## Screenshot

![code-atlas risk map report](doc/assets/risk-map.png)

## Quick Start (60s)

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/checkout_flow.lua
```

Then run in Neovim:

```vim
:CodeAtlasIndex
:CodeAtlasProjectGraph
:CodeAtlasRiskMap top=10
```

## Main Features

- Local call graph under cursor (`:CodeAtlas`)
- Interactive tree UI (expand/collapse + jump to definition)
- Project-wide call graph and reverse call graph
- Module graph and package graph
- File import graph and reverse import graph
- Dead code report (zero incoming callers)
- Impact analysis report (direct + transitive callers)
- Architecture dependency report with layer violation checks
- Code evolution report (timeline + churn hotspots)
- Interactive graph viewer (focus/filter/search + zoom/pan-like controls)
- Hot path detection (critical symbols and call chains)
- Complexity analysis (SCC/cycles, density, structural score)
- Risk map report (combined architecture/hot-path/complexity/churn signals)
- Snapshot exports for advanced reports (`json` / `jsonl`)
- Optional Telescope picker integration (`:CodeAtlasPick`)

## Requirements

- Neovim `>= 0.10`
- Tree-sitter parsers for target languages (Lua/Python/TS/JS/Go/Rust)
- Optional: `telescope.nvim` for picker workflow

## Installation

Local development with `lazy.nvim`:

```lua
{
  dir = "/Users/kog/Desktop/dev/code-atlas",
  name = "code-atlas",
  config = function()
    require("code-atlas").setup({
      depth_limit = 2,
      ui = {
        mode = "tree",
      },
    })
  end,
}
```

## Commands

- `:CodeAtlas` local graph for function under cursor
- `:CodeAtlasPick` pick function with Telescope (optional)
- `:CodeAtlasIndex` build project function index
- `:CodeAtlasIndexRefresh` refresh project index
- `:CodeAtlasProjectGraph` project call graph (callees)
- `:CodeAtlasProjectReverseGraph` reverse project call graph (callers)
- `:CodeAtlasLSPGraph` LSP call hierarchy graph (callees)
- `:CodeAtlasLSPReverseGraph` LSP call hierarchy reverse graph (callers)
- `:CodeAtlasLSPDebug` inspect attached LSP clients and last hierarchy run
- `:CodeAtlasModuleGraph` module dependency graph
- `:CodeAtlasPackageGraph` package dependency graph
- `:CodeAtlasImportGraph` file import graph
- `:CodeAtlasImportReverseGraph` reverse import graph (dependents)
- `:CodeAtlasDeadCode` dead function report
- `:CodeAtlasImpact` impact analysis for function under cursor
- `:CodeAtlasExport [format] [path] [incoming|outgoing] [depth=N] [layout=hierarchical|force]` export project graph for symbol under cursor
- `:CodeAtlasKnowledge [path|path=...] [format=json|jsonl] [include_tests=bool] [include_imports=bool] [include_types=bool] [include_external=bool]` build unified knowledge graph summary and optional snapshot
- `:CodeAtlasArchitecture [include_tests=bool] [unknown_policy=allow|deny] [max_examples=N] [path=...] [format=json] [pretty=bool]` build architecture layer/domain report, dependency-rule violations, and optional JSON snapshot
- `:CodeAtlasEvolution [limit=N] [hotspot_limit=N] [include_merges=bool] [since=...] [path=...] [out=...] [format=json|jsonl] [pretty=bool] [timeout_ms=N]` build git-based code evolution timeline and churn hotspots with optional snapshot export
- `:CodeAtlasViewer [incoming|outgoing] [depth=N] [dynamic_only=bool] [kind=all|function|method] [filter=path_prefix] [search=query]` open advanced interactive project graph viewer
- `:CodeAtlasHotPath [incoming|outgoing] [top=N] [max_depth=N] [path_depth=N] [path_count=N] [include_tests=bool] [include_churn=bool] [churn_limit=N] [churn_since=...] [churn_weight=N]` rank central functions and critical call chains with optional git-churn weighting
- `:CodeAtlasComplexity [top=N] [scc_limit=N] [include_tests=bool] [path=...] [format=json|jsonl] [pretty=bool]` compute SCC/cycle complexity, cluster metrics, and optional snapshot export
- `:CodeAtlasRiskMap [top=N] [include_tests=bool] [include_churn=bool] [churn_limit=N] [churn_since=...] [churn_weight=N] [baseline_path=...] [path=...] [format=json|jsonl] [pretty=bool]` build combined risk map from architecture/hot-path/complexity/churn signals with severity and optional trend comparison
- `:CodeAtlasUI tree|ascii` switch UI mode

## Main Configuration

```lua
require("code-atlas").setup({
  depth_limit = 2,
  lsp = {
    enabled = true,
    timeout_ms = 1200,
    prefer_call_hierarchy = false,
    include_external = false,
  },
  resolution = {
    poly_score_window = 25,      -- score gap from best to keep alt targets
    poly_min_confidence = "medium", -- low|medium|high
    max_poly_targets = 3,        -- cap alternatives per callsite
  },
  layout = {
    algorithm = "hierarchical", -- "hierarchical" | "force"
  },
  ui = {
    mode = "tree",     -- "tree" | "ascii"
    border = "rounded", -- floating window border style
    max_width = 0.8,     -- max window width ratio
    max_height = 0.8,    -- max window height ratio
  },
  architecture = {
    include_tests = false,
    unknown_layer_policy = "allow", -- "allow" | "deny"
    max_violation_examples = 3,
    export_format = "json",
    export_pretty = true,
    layer_by_top_dir = { tests = "test" },
    layer_by_path_prefix = {},
    layer_by_module_prefix = {},
    domain_by_top_dir = {},
    domain_by_path_prefix = {},
    domain_path_segment = 2,
    rules = {},
    rules_mode = "merge", -- "merge" | "replace"
    severity_thresholds = { critical = 90, high = 70, medium = 55 },
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
    node_kind = "all", -- "all" | "function" | "method"
    filter_path_prefix = nil,
    search_query = nil,
  },
  hot_path = {
    top_n = 10,
    max_depth = 4,
    path_depth = 5,
    path_count = 5,
    include_tests = false,
    include_churn = true,
    churn_limit = 60,
    churn_since = nil,
    churn_timeout_ms = 5000,
    direction = "outgoing",
    weight_in = 2.2,
    weight_out = 1.6,
    weight_balance = 2.4,
    weight_reach = 1.1,
    weight_churn = 0.15,
  },
  complexity = {
    top_n = 15,
    scc_limit = 10,
    include_tests = false,
    cycle_weight = 12,
    degree_weight = 1.0,
    bridge_weight = 1.5,
    scc_size_weight = 0.7,
    severity_thresholds = { critical = 70, high = 45, medium = 25 },
    suggestion_scc_size = 6,
    suggestion_density = 0.35,
    suggestion_top_bridge = 6,
    export_format = "json",
    export_pretty = true,
  },
  risk_map = {
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
    severity_thresholds = { critical = 2.2, high = 1.4, medium = 0.8 },
    baseline_path = nil,
    export_format = "json",
    export_pretty = true,
  },
})
```

## Limitations (Current)

- Cross-file and type-aware resolution are heuristic (not full semantic analysis)
- Dynamic dispatch/polymorphism support is best-effort and confidence-based
- LSP features depend on attached server capabilities and project setup
- Architecture, hot-path, complexity, and risk scores are heuristic and require per-repo tuning
- Language/query coverage is best-effort and may vary by parser availability
- Very large repositories may require stricter caps/caching for optimal performance
- For detailed limitations and caveats, see `doc/code-atlas.txt`

## Help Docs

- Vim help file: `doc/code-atlas.txt`
- Contributing guide: `CONTRIBUTING.md`
- Release process: `RELEASE.md`
- After install, generate helptags for this plugin doc directory:

```vim
:helptags {path-to-code-atlas}/doc
```

- Then open help with:

```vim
:help code-atlas
```

## Playground

- Quick run:

```bash
./playground/run.sh
```

- Rich sample scenario:

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/checkout_flow.lua
```
