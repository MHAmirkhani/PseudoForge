# Plot the diagnostics

```bash
pseudoforge generate -e Si -t paw -p psl-high -x pbe --plot -o ./out
pseudoforge plot ./out                 # or later, on a finished project
```

Two plots per element land in `out/plots/`.

## Log derivatives

The standard diagnostic. The logarithmic derivative of the wavefunction,
evaluated just outside the core, as a function of energy — for the
all-electron atom and for the pseudo atom.

**The two curves should lie on top of each other.** Where they separate, the
pseudopotential scatters differently from the real atom at that energy, and any
state at that energy will be wrong.

The poles are real: each channel has one where it crosses a bound state. A pole
in the pseudo curve with **no counterpart** in the all-electron curve is a
ghost state.

```text
Si -- log derivatives at r = 2.10 bohr
```

The radius is chosen outside the largest matching radius in the recipe — from
the deck's own card block, plus 0.3 bohr. Sampling inside the matching region
would show the pseudisation rather than the scattering the plot is for.
Override with `--plot-rlderiv`.

The y-axis is clipped to the bulk of the data, so the poles run off the top and
bottom of the frame rather than flattening every curve into a straight line.
That is how these plots are normally shown.

## Radial wavefunctions

All-electron and pseudo, per orbital. They must **agree outside the matching
radius** and be **smooth and nodeless inside it**. A pseudo curve that does not
rejoin its all-electron partner is a pseudopotential that does not describe the
atom you think it does.

The x-axis is cut to where the last curve stops being distinguishable from
zero; the radial grid itself runs to about 100 bohr, almost all of it flat.

## Backends

gnuplot if it is on `PATH`, otherwise matplotlib via `python3`, otherwise
nothing:

```text
WARN  no plotting backend: install gnuplot, or python3 with matplotlib
INFO    nothing else about this run is affected; the data is in ./out/tests
```

and **exit 0**. A machine without a plotting program has not produced bad
pseudopotentials. The plot *data* is still written, so you can copy the project
elsewhere and plot it there:

```bash
pseudoforge plot ./out                 # on a machine that has a backend
```

```bash
pseudoforge doctor | grep -A1 plotting
```

tells you which backend was found. Note that "python3 exists" is not
"matplotlib is installed" — the probe imports it rather than trusting the
interpreter.

## `--plot` does not change the physics

Log derivatives require five extra keywords in the `ld1.x` deck. They go into
the **validation** deck, which runs *after* the pseudopotential has been
written, so they cannot affect it — and the generation deck is left exactly as
the recipe database holds it.

Measured on Si, Fe and O with and without `--plot`: the UPFs, the
transferability verdicts and the generation decks are bit-identical. The only
difference is the five keywords in the validation deck.

## Band structures and densities of state

**PseudoForge does not compute either.** Generating a pseudopotential does not
involve a crystal, and producing a band structure would mean inventing a
structure, a k-path and a cutoff on your behalf and labelling the result as
yours.

If you have run `pw.x` and `bands.x` or `dos.x` yourself, point at the output:

```bash
pseudoforge plot ./out --plot-bands ./si.bands.dat --plot-dos ./si.dos
```

With no such file, `--plot` says which command would produce one:

```text
INFO    bands: no band-structure data. PseudoForge does not compute one -- run
        pw.x with calculation='bands' and bands.x, then point --plot-bands at
        its output
```

and if you point at a file that is not there, it says *that* instead:

```text
INFO    bands: no such file: ./si.bands.dat
```

## Options

| Flag | Effect |
|---|---|
| `--plot` | draw after the run |
| `--plot-dir D` | write plots to `D` instead of `<project>/plots` |
| `--plot-format png\|svg` | output format |
| `--plot-rlderiv R` | log-derivative radius, in bohr |
| `--plot-bands FILE` | plot a `bands.x` output |
| `--plot-dos FILE` | plot a `dos.x` output |
