# ESO API stubs (drop-in, untracked)

`.luarc.json` adds this folder to `workspace.library`, so anything here becomes
full type information / autocomplete in Neovim (lua-language-server) without
appearing in the addon or in git.

For **full** API type stubs (not just the curated globals list in `.luarc.json`),
drop a LuaCATS / EmmyLua-annotated ESO API export here, e.g.:

- the official `ESOUIDocumentation` Lua that ZeniMax publishes per patch on the
  ESOUI forums, or
- any community LuaCATS ESO-API annotation set.

Put the `.lua` annotation files directly in this folder (or a subfolder) and
restart the language server. Until then, the globals list in `.luarc.json`
keeps the warnings quiet.

This folder is gitignored except for this README.
