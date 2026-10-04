# Elements and selectors

`-e/--elements` accepts symbols, names, atomic numbers, ranges and named
selectors. Comma- or space-separated; several `-e` on one line accumulate.

```bash
pseudoforge generate -e Si,Ge,Sn -t paw -p psl-high -x pbe -o ./out
pseudoforge generate -e 1-18 -t paw -p psl-high -x pbe -j 8 -o ./out
pseudoforge generate -e transition-metals,!Tc -t paw -p psl-high -x pbe -o ./out
```

## Forms

| Form | Example | Matches |
|---|---|---|
| symbol | `Fe` | iron |
| name | `iron` | iron |
| atomic number | `26` | iron |
| **Z range** | `1-18` | hydrogen through argon, inclusive |
| everything | `all` | every element in the table |
| block | `block:d` | the d block |
| series | `series:transition` | by series |
| period | `period:4` | row 4 |
| group | `group:16` | column 16 |
| exclusion | `!Fe` | removes it, applied after every include |

## Named selectors

| Selector | Contents |
|---|---|
| `all` | every element in the table |
| `lanthanides` | the lanthanide series |
| `actinides` | the actinide series |
| `transition-metals`, `transition` | the transition series |
| `rare-earths` | the lanthanides plus Sc and Y |
| `main-group` | the s and p blocks |
| `magnetic` | Cr, Mn, Fe, Co, Ni, Gd |
| `semiconductors` | Si, Ge, C, B, N, P, As, Ga, In, Al, Zn, O, S, Se, Te, Cd, Sb |

`magnetic` and `semiconductors` are convenience lists, not definitions of the
words. They are what the table says, and they are there because they are
convenient starting points, not because the boundary is principled.

## Exclusions

Applied **after** every include, regardless of order:

```bash
pseudoforge generate -e all,!lanthanides,!actinides -t paw -p psl-high -x pbe -o ./out
pseudoforge generate -e period:6,!Pm -t paw -p psl-high -x pbe -o ./out
```

## Ranges are by atomic number

`1-18` works. `H-Ar` does **not** — a range is numeric:

```text
WARN  unknown element or selector: H-Ar
ERROR element selection ' H-Ar' matched nothing
```

An unrecognised selector produces a warning and is skipped; if nothing at all
matched, the run stops rather than silently generating an empty set.

## Check before you run

The expansion is echoed before anything is generated:

```text
INFO  elements   29: Sc Ti V Cr Mn Fe Co Ni Cu Zn Y Zr Nb Mo Tc Ru Rh Pd Ag Cd Hf Ta W Re Os Ir Pt Au Hg
```

which is the moment to notice a selector matched more, or less, than you meant.
To see it without running anything:

```bash
pseudoforge generate -e transition-metals -t paw -p psl-high -x pbe --dry-run
```

## Coverage is a separate question

A selector expands against the **periodic table**, not against what a library
covers. An element with no recipe in the chosen profile and family is reported
as skipped, with the reason:

```bash
pseudoforge list profiles      # coverage per profile
pseudoforge list recipes Fe    # every recipe any profile has for one element
```

## The table itself

`data/elements/table.tsv` — symbol, name, Z, period, group, block, series, mass
and ground-state configuration. Its provenance is recorded in
[Data provenance](data-provenance.md).
