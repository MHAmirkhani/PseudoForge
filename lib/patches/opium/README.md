# PseudoForge patches for OPIUM 4.1.0

These patches are applied by `lib/build.sh::build_opium` between extracting
(or locating) the OPIUM source tree and running `configure`/`make`.  They
are local: the upstream tree is not modified on disk in any persistent way,
and re-running the build applies them idempotently.  A file already using
the correct `aorb_.lo[i]` form is left alone, so once upstream merges the
equivalent fix the script becomes a no-op.

The full patch is also kept as `0001-dshell-writers.patch`, produced against
the release tarball, for anyone who wants to apply it by hand or read it in
unified-diff form.

## 0001 — six writers segfault on elements with a gap in their l-shells

### Symptom

Six of OPIUM's ten output writers abort with SIGSEGV on any element whose
valence configuration has a gap in its angular-momentum shells — the common
case being the 3d and 5d transition metals, which have s and d electrons but
no valence p.  Si and the s/p elements are unaffected because their shells
happen to be contiguous.

Example: `opium fe.param fe.log all ke rpt upf fhi` segfaults on Fe but
succeeds on Si.  The same crash reproduces with ncpp, cpmd, casino, champ,
siesta.

Affected writers:

| writer | file |
|---|---|
| FHI / ABINIT | `src/output/do_fhi.c` |
| NCPP | `src/output/do_ncpp.c` |
| CPMD | `src/output/do_cpmd.c` |
| CASINO | `src/output/do_casino.c` |
| CHAMP | `src/output/do_champ.c` |
| SIESTA | `src/output/do_siesta.c` |

The other four writers (UPF, recpot, Teter, QSO) already use the correct
form and are unaffected.

### Cause 1 — loop index used as angular momentum

Each writer reads its radial data from binary scratch files whose names
embed the angular momentum:

    <name>.pot.ps.l=<l>
    <name>.psi.ps.l=<l>

The loop that reads them uses the loop index `i` where the real angular
momentum belongs:

    for (i = 0; i < param->nll; i++) {
        sprintf(filename, "%s.pot.ps.l=%d", param->name, i);   /* wrong */
        fp = fopen(filename, "rb");
        fread(rvcore[i], sizeof(double), param->ngrid, fp);    /* fp == NULL */
    }

For Fe the shell list is {s, d}.  The loop wants l = 0, 1, 2 but `do_nl.c`
writes scratch files only for the shells that actually exist, so
`fe.pot.ps.l=1` is never created, `fopen` returns NULL, and
`fread(NULL, ...)` segfaults.

The four correct writers use `aorb_.lo[i]`:

    sprintf(filename, "%s.pot.ps.l=%d", param->name, aorb_.lo[i]);

### Cause 2 — no fully-relativistic branch

The same six writers call `nrelsproj(param, logfile)` unconditionally at
the top of the function.  In fully-relativistic mode (`[Relativity] frl`)
that leaves `aorb_.lo[]` and `adat_.so[]` unpopulated, so the corrected
filename above would still be garbage.  `do_qeupf.c` and `do_teter.c`
already branch on the relativity mode:

    if ((!strcmp(param->reltype, "nrl")) || (!strcmp(param->reltype, "srl"))) {
        nrelorbnl(param,config,logfile);
        nrelsproj(param,logfile);
    } else {
        relorbnl(param,config,logfile);
    }

In `frl` mode the scratch files also carry a spin-orbit sign suffix
(`fe.pot.ps.l=2+`, `fe.pot.ps.l=2-`), which only the two writers above
build correctly.

### Fix

For each of the six writers:

1. Declare `void nrelorbnl(param_t *, int, char *);` and
   `void relorbnl(param_t *, int, char *);` next to the existing
   `nrelsproj` declaration.
2. Insert `int config=-1;` and replace the bare `nrelsproj` call with the
   `nrl/srl else frl` branch above.
3. Use `aorb_.lo[i]` instead of `i` in the scratch-file name, and add the
   `+`/`-` suffix in `frl` mode, matching the pattern in `do_qeupf.c`.
4. For `do_fhi.c` and `do_ncpp.c` only, add
   `#include "common_blocks.h"` — the other four already include it.

### Verified

| Element | Mode | Before | After |
|---|---|---|---|
| Fe, Cu, Zn, Au | srl | UPF only; others crash | all ten formats write |
| Fe, Cu, Zn, Au | frl | UPF + Teter only | UPF + Teter (unchanged) |
| Si, Na, Mg, Al, Cl, Ca, Ga | srl | all ten | all ten (unchanged) |

In `frl` mode OPIUM's own writers refuse the eight non-UPF formats with
their own error messages ("the fhi format does not support fully
relativistic psps", etc.).  That is a limit of the formats, not of this
patch, and it is unchanged.

### Upstream

Reported as rappegroup/opium#1 and fixed in rappegroup/opium#2.
