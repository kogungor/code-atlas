# code-atlas

`code-atlas` is a Neovim code-intelligence plugin for exploring function relationships.
It combines Tree-sitter parsing with project indexing to answer questions like:

- What does this function call?
- Who calls this function?
- Which modules/files depend on this part of the code?
- What might break if I change or remove this function?

## Main Features

- Local call graph under cursor (`:CodeAtlas`)
- Interactive tree UI (expand/collapse + jump to definition)
- Project-wide call graph and reverse call graph
- Module graph and package graph
- File import graph and reverse import graph
- Dead code report (zero incoming callers)
- Impact analysis report (direct + transitive callers)
- Architecture dependency report with layer violation checks
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
})
```

## Limitations (Current)

- Cross-file resolution is heuristic name matching (not full type-aware resolution yet)
- Dynamic dispatch/polymorphism is not fully modeled
- LSP call hierarchy support depends on attached server capabilities
- LSP graph defaults to project-local symbols; set `lsp.include_external=true` to include library nodes
- Type-aware call resolution is partial (receiver-aware for TS/JS method calls)
- Receiver-aware heuristics now also include Python/Go/Rust patterns (best-effort)
- Project graph now shows mixed-source resolution preview (`index`, `lsp`, `mixed(index+lsp)`) with confidence labels when available
- Project graph now annotates polymorphic/dynamic call edges and alternative targets
- Architecture report now includes severity scoring (`critical/high/medium/low`) for rule violations
- Layer/domain inference is heuristic by default, but can be overridden via `architecture.*_prefix` and `architecture.*_top_dir`
- Evolution report uses git churn heuristics and current index mapping for symbol/edge touch estimation
- Interactive viewer adds focus/filter/search, node-kind filtering, search highlighting, and zoom/pan-style navigation over project graph data
- Hot path detection combines centrality/reach with optional git churn weighting to rank risk-heavy critical chains
- Language coverage is best-effort and parser/query dependent
- Large projects may need further performance guardrails/caching improvements

## Help Docs

- Vim help file: `doc/code-atlas.txt`
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
