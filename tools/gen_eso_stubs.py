#!/usr/bin/env python3
"""Generate a LuaCATS stub of the ESO global API from ESOUIDocumentation.txt.

The ESO engine injects its constants, events and native functions into the Lua
VM at runtime, so neither addon code nor the decompiled esoui Lua *declares*
them -- the language server therefore reports them as undefined globals. This
parses the official API documentation and emits a `---@meta` definition file
declaring every global with best-effort types, which lua-language-server loads
via workspace.library.

Usage:
    python3 tools/gen_eso_stubs.py \
        stubs/esoui/ESOUIDocumentation.txt stubs/eso_api.lua
"""

import re
import sys

LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
    "true", "until", "while",
}

TYPE_MAP = {
    "bool": "boolean", "luaindex": "integer", "integer": "integer",
    "number": "number", "string": "string", "table": "table",
    "function": "function", "object": "table", "type": "any",
    "types": "any", "nilable": "any", "userdata": "userdata", "void": "nil",
}

ARG_RE = re.compile(r"\*([^*]+)\*\s*_([A-Za-z0-9 ]+)_")
FUNC_RE = re.compile(r"^\*\s+([A-Za-z]\w*)\((.*)\)\s*$")
RETURNS_RE = re.compile(r"^\*\*\s+_Returns:_\s*(.*)$")
CONST_RE = re.compile(r"^\*\s+([A-Z][A-Z0-9_]*)\s*$")
EVENT_RE = re.compile(r"^\*\s+(EVENT_[A-Z0-9_]+)")


def lua_type(raw):
    # Enum references in the docs look like *[Bag|#Bag]*; the corresponding
    # constants are declared as plain integers, so map any enum/bracketed
    # reference to `integer` and anything unrecognized to `any`. This keeps the
    # signature useful for hover without producing false type-mismatch errors.
    raw = raw.strip()
    bracketed = any(c in raw for c in "[|#")
    t = raw.strip("*").strip().lstrip("[").rstrip("]")
    t = t.split(":", 1)[0]  # drop :nilable and friends
    if "|" in t:
        t = t.split("|", 1)[0]
    t = t.lstrip("#").strip()
    if t in TYPE_MAP:
        return TYPE_MAP[t]
    if bracketed:
        return "integer"
    return t if (re.fullmatch(r"\w+", t) and t in TYPE_MAP) else "any"


def sanitize(name, used):
    name = name.strip().replace(" ", "_")
    if not re.fullmatch(r"[A-Za-z_]\w*", name):
        name = "arg"
    if name in LUA_KEYWORDS:
        name += "_"
    base, n = name, 1
    while name in used:
        name, n = f"{base}{n}", n + 1
    used.add(name)
    return name


def parse_args(inside):
    args, used, variadic = [], set(), False
    for rawtype, rawname in ARG_RE.findall(inside):
        if rawname.strip() == "arguments":
            variadic = True
            continue
        args.append((sanitize(rawname, used), lua_type(rawtype)))
    return args, variadic


def main(doc_path, out_path):
    lines = open(doc_path, encoding="utf-8", errors="replace").read().splitlines()

    # Split into h2 sections.
    headers = [(i, l[3:].strip()) for i, l in enumerate(lines) if l.startswith("h2.")]
    sections = {}
    for idx, (i, name) in enumerate(headers):
        end = headers[idx + 1][0] if idx + 1 < len(headers) else len(lines)
        sections[name] = lines[i + 1:end]

    constants, functions, seen_fn = [], [], set()

    def collect_constants(section, regex):
        for l in sections.get(section, []):
            m = regex.match(l)
            if m:
                constants.append(m.group(1))

    collect_constants("Global Variables", CONST_RE)
    collect_constants("Events", EVENT_RE)

    for section in ("VM Functions", "Game API"):
        body = sections.get(section, [])
        for i, l in enumerate(body):
            m = FUNC_RE.match(l)
            if not m:
                continue
            fname = m.group(1)
            if fname in seen_fn:
                continue
            seen_fn.add(fname)
            args, variadic = parse_args(m.group(2))
            rets = []
            if i + 1 < len(body):
                rm = RETURNS_RE.match(body[i + 1])
                if rm:
                    rets = [(sanitize(n, set()), lua_type(t)) for t, n in ARG_RE.findall(rm.group(1))]
            functions.append((fname, args, variadic, rets))

    out = ["---@meta",
           "-- AUTO-GENERATED from ESOUIDocumentation.txt. Do not edit by hand.",
           "-- Regenerate with: python3 tools/gen_eso_stubs.py", ""]

    for c in dict.fromkeys(constants):  # dedupe, keep order
        out.append(f"{c} = 0")
    out.append("")

    for fname, args, variadic, rets in functions:
        # All params are emitted optional: the ESO docs under-mark optional and
        # overloaded parameters, so requiring them would flag valid calls.
        for aname, atype in args:
            out.append(f"---@param {aname}? {atype}")
        if variadic:
            out.append("---@vararg any")
        for rname, rtype in rets:
            out.append(f"---@return {rtype} {rname}")
        params = [a for a, _ in args] + (["..."] if variadic else [])
        out.append(f"function {fname}({', '.join(params)}) end")
        out.append("")

    open(out_path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"wrote {out_path}: {len(set(constants))} constants, {len(functions)} functions")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
