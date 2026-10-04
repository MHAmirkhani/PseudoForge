# 5. Gold, fully relativistic

Everything so far used `ld1.x` and PSlibrary. Gold changes both: a different
engine, a different library, and the first time relativity is a decision rather
than a default.

You will also meet a warning that looks like a failure and is not, which is
worth knowing before you meet it on your own work at midnight.

## Why gold is different

Gold is element 79. Its 1s electrons move fast enough that relativistic mass
increase contracts the s shells measurably, which cascades: contracted s shells
screen the nucleus better, so the d shells expand, and the 5d–6s gap narrows
until it lands in the visible. That is why gold is yellow and silver is not.

Scalar-relativistic treatment captures the contraction. It does **not** capture
spin–orbit splitting, which for gold's 5d shell is over 1 eV. If you are doing
anything with band topology, Rashba splitting, magnetic anisotropy or optical
response in a heavy element, you need the full treatment.

## What we are asking for

```bash
pseudoforge generate -e Au -t nc -p sg15 -x pbe -r full --engine oncvpsp -o ./05-gold
```

`-r full`
: **Fully relativistic.** Solves the Dirac equation and produces j-dependent
  projectors — separate channels for p₁⸝₂ and p₃⸝₂, d₃⸝₂ and d₅⸝₂. This is what
  `lspinorb = .true.` in `pw.x` needs. It roughly doubles the projector count.

`-p sg15 --engine oncvpsp`
: **SG15, generated with ONCVPSP.** SG15 is Schlipf and Gygi's optimised
  norm-conserving table, built with Hamann's ONCVPSP code. It is a good choice
  for heavy elements: ONCV pseudopotentials are unusually soft *for
  norm-conserving*, which matters when the alternative for gold is a very hard
  potential. Norm-conserving is also what you want if the calculation after
  this one is GW or BSE.

    The engine is stated explicitly here, but it would have been chosen anyway:
    `sg15` implies `oncvpsp`, because that is the code the library was built
    with. Asking for SG15 from `ld1.x` would be asking for a different thing
    wearing SG15's name.

## What happens

```text
== PseudoForge 1.3.0 ==
INFO  profile    SG15 ONCV (Schlipf-Gygi)  [generated]
INFO  family     NC   functional PBE   Full-relativistic (with spin-orbit)
INFO  elements   1: Au
INFO  project    ./05-gold

== Generating ==
INFO  generating 1 element(s) with 4 parallel job(s)
OK    Au  ->  Au.rel-pbe-oncv.UPF  (6s)

== Transferability tests (oncvpsp's own test configurations) ==
```

Two things to notice immediately.

**`Full-relativistic (with spin-orbit)`** — the run echoes back what it
understood, so a typo in `-r` does not quietly give you a scalar
pseudopotential.

**`rel-pbe` in the file name** — `Au.rel-pbe-oncv.UPF`. The `rel-` prefix is
the convention for a fully relativistic set, and it means you cannot mix this
file up with the scalar one in a `pseudo_dir`.

**The transferability heading changed.** Silicon said
`Transferability tests (ld1.x, iswitch=2)`. This says
`(oncvpsp's own test configurations)`. Different engine, different measurement —
see below.

## The warning

```text
 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 Au   Au.rel-pbe-oncv.UPF                ok        library     no-data    -            positive-energy ghost above ~39.13 Ry (informational; common in published tables)
```

A **ghost state** is a spurious bound state introduced by the separable
Kleinman–Bylander form — an eigenvalue the real atom does not have. A ghost
below or near the valence energies is fatal: it will appear in your band
structure as a band that should not exist.

This one is at **+39 Ry**, far above any energy a valence electron occupies,
and PseudoForge labels it `informational` rather than a failure for that
reason. Positive-energy ghosts well above the valence region are common in
published norm-conserving tables, including SG15's own distributed files. It is
recorded rather than hidden, and it is not treated as an error.

!!! tip "How to decide for yourself"
    Plot the log derivatives and look:

    ```bash
    pseudoforge plot ./05-gold
    ```

    A ghost shows as a pole in the pseudo curve that has no counterpart in the
    all-electron curve. Judge it by *where* it is: inside the range your
    valence states occupy, it matters; tens of Ry above, it does not. See
    [Validate a pseudopotential](../how-to/validate.md).

`TRANSFER no-data` here for the same reason as copper: SG15 is a library
PseudoForge reproduces from the authors' own inputs, and the authors' inputs do
not carry the kind of unfitted-configuration test deck PSlibrary ships.
ONCVPSP's own configuration tests ran — that is the heading — but they do not
produce a number on the same scale, and inventing one would be worse than an
empty column.

## The input, and where it came from

```bash
head -14 ./05-gold/inputs/Au*
```

```text
# ATOM AND REFERENCE CONFIGURATION
# atsym, z, nc, nv, iexc   psfile
    Au   79    10   4   4   upf
#
# n, l, f  (nc+nv lines)
1 0 2
2 0 2
2 1 6
3 0 2
3 1 6
3 2 10
4 0 2
4 1 6
4 2 10
```

This is ONCVPSP's own input format, not `ld1.x`'s — a different engine means a
different deck, and PseudoForge writes whichever the engine reads. `nc 10` and
`nv 4` are the core and valence shell counts: ten frozen shells, four in the
valence.

`iexc 4` is the exchange-correlation selector. ONCVPSP's built-in codes are
small integers; when PseudoForge needs a functional outside that set it uses
ONCVPSP's libxc encoding instead, which is a negative number of the form
−(X×1000 + C). That only works if your ONCVPSP was built against libxc —
`pseudoforge engines show oncvpsp` says whether yours was.

## What the provenance recorded

```text
engine.id=oncvpsp
engine.label=ONCVPSP (Hamann)
engine.version=4.0.1
engine.build=9c0080741f21
engine.binary=~/.pseudoforge/engines/bin/oncvpsp.x
engine.upstream=https://github.com/oncvpsp/oncvpsp
profile=sg15
family=nc
functional=PBE
functional.requested=pbe
relativity=full
```

`engine.build` is a hash of the built binary. Two people with ONCVPSP 4.0.1 can
still have different binaries — different compiler, different libxc, a patch
applied — and if their results differ this is the line that says so.

## Using it

```text
ATOMIC_SPECIES
  Au  196.96657  Au.rel-pbe-oncv.UPF
```

and in `&system`:

```text
  noncolin    = .true.
  lspinorb    = .true.
```

Spin–orbit requires a non-collinear calculation, which is roughly four times
the cost of the scalar one. Using a `rel-` pseudopotential without
`lspinorb = .true.` is not an error — it will run, and use the j-averaged
potential — but you have paid for the splitting and thrown it away.

Norm-conserving gold is hard. Expect `ecutwfc` in the 60–80 Ry region, with
`ecutrho` at the 4× default.

---

Next: [Meta-GGA with AtomPAW](06-scan.md) — where PseudoForge refuses to do
what you asked, for a good reason.
