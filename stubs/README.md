# ESO API stubs (drop-in, untracked)

`.luarc.json` points `workspace.library` here, so these become type information /
autocomplete in Neovim (lua-language-server) without appearing in the addon or in
git. Everything in `stubs/` is gitignored.

## Why two pieces

ESO's constants, events and native functions are injected into the Lua VM by the
C++ engine. The decompiled Lua only *uses* them, so the language server reports
them as undefined globals. The real definitions live in `ESOUIDocumentation.txt`,
which isn't Lua. So two things are needed:

1. **`esoui/`** — the decompiled UI source, for all `ZO_*` objects/helpers and the
   `ESOUIDocumentation.txt` reference:

   ```sh
   git clone --depth 1 https://github.com/esoui/esoui.git stubs/esoui
   git -C stubs/esoui pull        # refresh each patch
   ```

2. **`eso_api.lua`** — a generated `---@meta` stub that *declares* every engine
   constant, event and native function (with `---@param`/`---@return` types parsed
   from the documentation), so the language server resolves them:

   ```sh
   python3 tools/gen_eso_stubs.py stubs/esoui/ESOUIDocumentation.txt stubs/eso_api.lua
   ```

Regenerate `eso_api.lua` whenever you update `stubs/esoui` to a new patch. Both
files are local-only; the generator (`tools/gen_eso_stubs.py`) is tracked.
