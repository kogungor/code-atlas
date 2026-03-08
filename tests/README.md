# Tests

This directory contains lightweight headless checks that can run without extra dependencies.

Run the current smoke test:

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature2.lua" +qall
```

Run local call detection smoke test (Feature 3):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature3.lua" +qall
```

Run floating ASCII graph smoke test (Feature 4):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature4.lua" +qall
```

Run graph node navigation smoke test (Feature 5):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature5.lua" +qall
```

Run node expansion smoke test (Feature 6):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature6.lua" +qall
```

Run depth limit smoke test (Feature 7):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature7.lua" +qall
```

Run function-selection graph smoke test (Feature 8):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature8.lua" +qall
```

Run project index smoke test (Feature 9):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature9.lua" +qall
```

Run project call graph smoke test (Feature 10):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature10.lua" +qall
```

Run reverse project call graph smoke test (Feature 11):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature11.lua" +qall
```

Run cross-file resolution smoke test (Feature 12):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature12.lua" +qall
```

Run module dependency graph smoke test (Feature 13):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature13.lua" +qall
```

Run import graph smoke test (Feature 14):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature14.lua" +qall
```

Run dead code detection smoke test (Feature 15):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature15.lua" +qall
```

Run impact analysis smoke test (Feature 16):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature16.lua" +qall
```

Run interactive tree UI smoke test (Feature 17):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature17.lua" +qall
```

Run graph export smoke test (Feature 18):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature18.lua" +qall
```

Run graph layout metadata smoke test (Feature 19):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature19.lua" +qall
```

Run LSP call hierarchy smoke test (Feature 20):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature20.lua" +qall
```

Run type-aware call resolution smoke test (Feature 21):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature21.lua" +qall
```

Run multi-language receiver disambiguation smoke test:

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature21_langs.lua" +qall
```

Run polymorphism detection smoke test (Feature 22):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/feature22.lua" +qall
```

As features grow, add one file per feature in `tests/headless/` and keep each check fast.
