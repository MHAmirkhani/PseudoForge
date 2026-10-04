# Tutorials

Seven worked examples, in order. Each one starts from an empty directory, shows
the command, shows **the output that command actually produced**, and explains
why each choice was made rather than a different one.

Every transcript on these pages was captured from a real run. Where something
failed, or produced a warning, or came back with no data, that is shown too —
a tutorial that only demonstrates the happy path teaches you nothing about the
day it does not happen.

| # | Element | What it teaches |
|---|---|---|
| [1](01-carbon.md) | Carbon | The shape of a run. Norm-conserving, PBE, one element. Why the transferability column can be empty. |
| [2](02-silicon.md) | Silicon | Ultrasoft, PBEsol, and reading a transferability grade properly. |
| [3](03-iron.md) | Iron | PAW, semicore states, and what "spn" means in a file name. |
| [4](04-copper.md) | Copper | A core hole for XPS/XAS, and watching the auto-fix engine work. |
| [5](05-gold.md) | Gold | Fully relativistic with ONCVPSP, and a ghost-state warning that is not a failure. |
| [6](06-scan.md) | Silicon, r2SCAN | Meta-GGA generated for real, a refusal that protects you, and why the output is not UPF. |
| [7](07-batch.md) | 29 transition metals | Parallelism, resume, failure isolation, and reading a batch report. |

## Before you start

You need a working installation and `ld1.x`. Tutorials 5 and 6 additionally
need ONCVPSP and AtomPAW:

```bash
pseudoforge doctor
pseudoforge engines build oncvpsp atompaw
```

Each tutorial writes into its own directory under wherever you run it, and
none of them touches anything outside that directory or `~/.pseudoforge`.

## The convention used here

Commands are shown as you would type them:

```bash
pseudoforge generate -e C -t nc -p psl-high -x pbe -o ./c-nc
```

Output is shown as it came back, with terminal colour removed:

```text
OK    C  ->  C.pbe-nc.UPF  (1s)
```

Where the wizard is easier than the flags, both are given. They are the same
run: the wizard's review screen prints the command line, and
`pseudoforge recipe load` prints it for a saved recipe.
