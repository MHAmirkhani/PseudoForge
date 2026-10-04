#!/usr/bin/env bash
# Apply PseudoForge patches to an OPIUM 4.1.0 source tree.
# Idempotent: running on an already-patched tree exits 0 without changes.
# See README.md in this directory.

set -euo pipefail

src=${1:?usage: apply.sh <opium-src-dir>}
[ -e "$src/src/main/opium.c" ] || {
    echo "apply.sh: not an OPIUM source tree: $src" >&2
    exit 1
}

python3 - "$src" <<'PY'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
sout = root / "src" / "output"
if not sout.is_dir():
    print("apply.sh: no src/output directory", file=sys.stderr)
    sys.exit(1)

WRITERS = {
    "do_fhi.c", "do_ncpp.c", "do_cpmd.c",
    "do_casino.c", "do_champ.c", "do_siesta.c",
}
INCLUDE_FIX = {"do_fhi.c", "do_ncpp.c"}

sprintf_re = re.compile(
    r'(sprintf\s*\(\s*filename\s*,\s*'
    r'"%s\.(?:pot|psi)\.ps\.l=%d"\s*,\s*param->name\s*,\s*)'
    r'i(\s*\)\s*;)'
)

nrelsproj_re = re.compile(
    r'(?<![\w.])nrelsproj\s*\(\s*param\s*,\s*logfile\s*\)\s*;'
)

decl_old = 'void nrelsproj(param_t *param, char *);'
decl_new = (
    'void nrelsproj(param_t *param, char *);\n'
    'void nrelorbnl(param_t *param, int, char *);\n'
    'void relorbnl(param_t *param, int, char *);'
)

# Insert `int config=-1;` just before the first `nrelsproj(...)` call.
def inject_config(text):
    if re.search(r'\bint\s+config\s*=\s*-1\s*;', text):
        return text
    m = nrelsproj_re.search(text)
    if not m:
        return text
    return text[:m.start()] + 'int config=-1;\n  ' + text[m.start():]

FRl_BRANCH = (
    'if ((!strcmp(param->reltype, "nrl")) || (!strcmp(param->reltype, "srl"))) {\n'
    '    nrelorbnl(param,config,logfile);\n'
    '    nrelsproj(param,logfile);\n'
    '  } else {\n'
    '    relorbnl(param,config,logfile);\n'
    '  }'
)

def frl_block(var):
    return (
        f'    if (!strcmp(param->reltype, "frl")) {{\n'
        f'      sprintf(filename, "%s.{var}.ps.l=%d%c", param->name, aorb_.lo[i],\n'
        f"              (adat_.so[i] > 0) ? '+' : '-');\n"
        f'    }} else {{\n'
        f'      sprintf(filename, "%s.{var}.ps.l=%d", param->name, aorb_.lo[i]);\n'
        f'    }}'
    )

touched = []
for name in sorted(WRITERS):
    p = sout / name
    if not p.is_file():
        continue
    text = p.read_text()
    original = text

    # 1. Declare the frl helpers.
    if 'void relorbnl(param_t *param' not in text:
        text = text.replace(decl_old, decl_new, 1)

    # 2. Add the config variable.
    text = inject_config(text)

    # 3. Wrap the bare nrelsproj() call in the frl/scalar branch.
    if 'nrelorbnl(param,config,logfile)' not in text:
        text = nrelsproj_re.sub(FRl_BRANCH, text, count=1)

    # 4. Fix the loop index in the scratch filenames.
    text = sprintf_re.sub(r'\1aorb_.lo[i]\2', text)

    # 5. Wrap the sprintf in the frl sign branch.
    if "adat_.so[i]" not in text:
        for var in ("pot", "psi"):
            old = f'    sprintf(filename, "%s.{var}.ps.l=%d", param->name,aorb_.lo[i]);'
            if old in text:
                text = text.replace(old, frl_block(var), 1)

    if text != original:
        p.write_text(text)
        touched.append(name)

# 6. Add the missing common_blocks.h includes.
for name in sorted(INCLUDE_FIX):
    p = sout / name
    if not p.is_file():
        continue
    text = p.read_text()
    if '#include "common_blocks.h"' in text:
        continue
    text, n = re.subn(
        r'(#include\s+"cdim\.h"[^\n]*\n)',
        r'\1#include "common_blocks.h"\n',
        text, count=1,
    )
    if n:
        p.write_text(text)
        touched.append(name + " (include)")

if touched:
    print("opium-patch: applied to " + ", ".join(touched))
else:
    print("opium-patch: already applied, nothing to do")
PY
