# Quantum's Aura Tools — dev tasks. Run `just` to list recipes.

esoui_dir := "stubs/esoui"
api_doc := "stubs/esoui/ESOUIDocumentation.txt"
api_stub := "stubs/eso_api.lua"

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
