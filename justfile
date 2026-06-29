# Quantum's Aura Tools — dev tasks. Run `just` to list recipes.

esoui_dir := "stubs/esoui"
api_doc := "stubs/esoui/ESOUIDocumentation.txt"
api_stub := "stubs/eso_api.lua"

# ESO install paths come from the environment so no local paths are committed.
# Export these in your shell profile (pts variants supported by `env=pts`):
#   ESO_USER_DIR
#   ESO_LIVE_ADDONS_DIR / ESO_PTS_ADDONS_DIR
#   ESO_LIVE_SV_DIR     / ESO_PTS_SV_DIR
# The `env` recipe argument selects live (default) or pts; paths are read from
# the matching variables inside each recipe.

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

# Show this addon's LibDebugLogger entries. level = V/D/I/W/E (default D),
# env = live (default) or pts. Reload the game UI (/reloadui) first so
# SavedVariables are flushed to disk.
logs level="D" env="live":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{env}}" in
        live) sv="${ESO_LIVE_SV_DIR:-}"; var="ESO_LIVE_SV_DIR";;
        pts)  sv="${ESO_PTS_SV_DIR:-}";  var="ESO_PTS_SV_DIR";;
        *) echo "env must be 'live' or 'pts'" >&2; exit 1;;
    esac
    [ -n "$sv" ] || { echo "Set $var in your environment." >&2; exit 1; }
    python3 tools/extract_logs.py "$sv/LibDebugLogger.lua" --tag Quantum --level {{level}}

# Tail ESO's plaintext script-error log. env = live (default) or pts.
errors env="live":
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "${ESO_USER_DIR:-}" ] || { echo "Set ESO_USER_DIR in your environment." >&2; exit 1; }
    case "{{env}}" in live|pts) ;; *) echo "env must be 'live' or 'pts'" >&2; exit 1;; esac
    tail -n 100 "$ESO_USER_DIR/{{env}}/Logs/interface.log"

# Symlink this project into AddOns as QuantumAuraTools. Works from any cwd. env = live|pts.
link env="live":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{env}}" in
        live) addons="${ESO_LIVE_ADDONS_DIR:-}"; var="ESO_LIVE_ADDONS_DIR";;
        pts)  addons="${ESO_PTS_ADDONS_DIR:-}";  var="ESO_PTS_ADDONS_DIR";;
        *) echo "env must be 'live' or 'pts'" >&2; exit 1;;
    esac
    [ -n "$addons" ] || { echo "Set $var in your environment." >&2; exit 1; }
    source="{{justfile_directory()}}"
    target="$addons/QuantumAuraTools"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "Refusing: $target exists and is not a symlink." >&2; exit 1
    fi
    mkdir -p "$addons"
    ln -sfn "$source" "$target"
    echo "Linked $target -> $source"

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
