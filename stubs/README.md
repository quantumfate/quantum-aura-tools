# ESO API stubs (drop-in, untracked)

`.luarc.json` adds this folder to `workspace.library`, so anything here becomes
type information / autocomplete in Neovim (lua-language-server) without appearing
in the addon or in git. Everything in `stubs/` is gitignored except this README.

## esoui decompiled source (recommended)

Clone the official decompiled ESO UI source here — it defines every `ZO_*`
object and every `EVENT_*` / `CT_*` / anchor / `SI_*` constant, so the language
server resolves them for real:

```sh
git clone --depth 1 https://github.com/esoui/esoui.git stubs/esoui
```

Refresh it each patch with `git -C stubs/esoui pull`.

It also ships `stubs/esoui/ESOUIDocumentation.txt` — the reference for the
engine-native functions (`GetUnitBuffInfo`, `GetGameTimeSeconds`, the
`EVENT_MANAGER` methods, …). Those are implemented in C, so they are *not* in the
Lua source; the curated `diagnostics.globals` list in `.luarc.json` keeps them
quiet. (A future improvement: generate LuaCATS annotations from that doc for full
signatures.)

## Anything else

Drop any other LuaCATS / EmmyLua `.lua` annotation files directly in this folder
and restart the language server.
