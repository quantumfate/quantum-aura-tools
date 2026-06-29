# Quantum's Aura Tools — dev tasks. Run `just` to list recipes.

esoui_dir := "stubs/esoui"
api_doc := "stubs/esoui/ESOUIDocumentation.txt"
api_stub := "stubs/eso_api.lua"

# ESO install paths come from the environment so no local paths are committed.
# Export these in your shell profile (live shown; pts variants also supported):
#   ESO_USER_DIR, ESO_LIVE_ADDONS_DIR, ESO_LIVE_SV_DIR
eso_user := env_var_or_default("ESO_USER_DIR", "")
addons_dir := env_var_or_default("ESO_LIVE_ADDONS_DIR", "")
sv_dir := env_var_or_default("ESO_LIVE_SV_DIR", "")
ddl_sv := sv_dir / "LibDebugLogger.lua"
errors_log := eso_user / "live/Logs/interface.log"

# List available recipes.
default:
    @just --list

# One-shot dev environment setup: fetch esoui + generate the LSP API stubs.
setup: esoui stubs
    @echo ""
    @echo "Dev environment ready. Restart your Lua language server (e.g. :LspRestart)."

# Clone the decompiled esoui source into stubs/ (skips if already present).
esoui:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d "{{esoui_dir}}/.git" ]; then
        echo "esoui already present ({{esoui_dir}}); run 'just update-esoui' to refresh."
    else
        echo "Cloning esoui into {{esoui_dir}} ..."
        git clone --depth 1 https://github.com/esoui/esoui.git "{{esoui_dir}}"
    fi

# Refresh esoui to the latest patch, then regenerate stubs.
update-esoui:
    git -C {{esoui_dir}} pull --ff-only
    @just stubs

# Generate the LuaCATS API stub ({{api_stub}}) from the esoui documentation.
stubs:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{api_doc}}" ]; then
        echo "Missing {{api_doc}} — run 'just esoui' first." >&2
        exit 1
    fi
    python3 tools/gen_eso_stubs.py "{{api_doc}}" "{{api_stub}}"

# Show this addon's LibDebugLogger entries. LEVEL = V/D/I/W/E (default D).
# Reload the game UI (/reloadui) before running so SavedVariables are flushed.
logs level="D":
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "{{sv_dir}}" ] || { echo "Set ESO_LIVE_SV_DIR in your environment." >&2; exit 1; }
    python3 tools/extract_logs.py "{{ddl_sv}}" --tag Quantum --level {{level}}

# Tail ESO's plaintext script-error log (hard Lua errors / stack traces).
errors:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "{{eso_user}}" ] || { echo "Set ESO_USER_DIR in your environment." >&2; exit 1; }
    tail -n 100 "{{errors_log}}"

# Symlink this repo into live AddOns as QuantumAuraTools (run once; safe to re-run).
link:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "{{addons_dir}}" ] || { echo "Set ESO_LIVE_ADDONS_DIR in your environment." >&2; exit 1; }
    target="{{addons_dir}}/QuantumAuraTools"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "Refusing: $target exists and is not a symlink." >&2; exit 1
    fi
    ln -sfn "$(pwd)" "$target"
    echo "Linked $target -> $(pwd)"

# Format all Lua with stylua.
fmt:
    stylua .

# Check formatting and Lua syntax (tracked .lua files only).
check:
    #!/usr/bin/env bash
    set -euo pipefail
    stylua --check .
    git ls-files '*.lua' | while read -r f; do luac -p "$f"; done
    echo "ok"
