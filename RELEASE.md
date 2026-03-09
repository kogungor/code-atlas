# Release Process

This repository uses a two-step promotion model.

## Branches

- `dev`: integration branch (default on GitHub)
- `main`: release branch

## Standard Release Steps

1. Complete feature/bugfix work in `feature/*` or `bugfix/*` branches.
2. Merge reviewed PRs into `dev`.
3. When ready to release, open a PR from `dev` to `main`.
4. Validate before merge:
   - run core headless smoke tests
   - verify command help/docs are up to date
5. Merge `dev -> main` PR.
6. Create release/tag from `main`.

## Suggested Pre-Release Checks

- `tests/headless/current_function_detection.lua`
- `tests/headless/project_call_graph.lua`
- `tests/headless/architecture_graph.lua`
- `tests/headless/code_evolution_graph.lua`
- `tests/headless/interactive_graph_viewer.lua`
- `tests/headless/hot_path_detection.lua`
- `tests/headless/complexity_analysis.lua`
- `tests/headless/risk_map_report.lua`
