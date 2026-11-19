# Design against reference data

`pseudoforge design` searches a finite, explicit set of generation parameters
and selects a candidate that meets physical error limits on training
structures. It then evaluates the locked choice on held-out structures.
This is a reproducible constrained grid search, not a new Bayesian optimizer or
a claim that a potential is accurate outside those structures.

The atomic generators and ordinary generation remain in Bash. This optional
command needs Python 3.10 or newer (standard library only) and a local Quantum
ESPRESSO `pw.x`. The public server does not run these calculations. Its
[design page](https://pseudo.amirkhani.me/design/) prepares protocol files and
reads local reports; [custom generation](https://pseudo.amirkhani.me/customize/)
shows engine-specific controls and builds commands.

## Run the worked Si example

From the repository root, with `ld1`, ONCVPSP and AtomPAW installed:

```bash
python3 examples/design-si/make_reference.py --pw /path/to/pw.x -o ./si-reference
pseudoforge design si-reference/protocol.json --plan -o ./si-plan
pseudoforge design si-reference/protocol.json --pw /path/to/pw.x -o ./si-design
```

The first command computes the reference; it does not contain invented reference
values. It uses the repository's Si PBE ONCV fixture at 80 and 100 Ry and checks
the change in forces and stress before writing the protocol. Both calculations
use the same small 2×2×2 k mesh. This is a demonstration against a
cutoff-checked pseudopotential reference, **not an all-electron verification**.
Increase and converge the k mesh and extend the environments for a research study.

The example compares five candidates from three generators: two ld1 PAW radius
scales, two ONCVPSP NC radius scales, and AtomPAW PAW. Training uses displaced
diamond Si; the test uses a displaced, compressed cell. Change the candidate
list if an engine is unavailable. All candidates use the same functional and
relativity as the reference. Candidate failures are kept in the report.

Output directories must be new or empty. Neither this command nor `optimise`
deletes previous projects. A failing held-out test leaves the training choice
unchanged; the program does not try alternatives until the test set passes.

## Protocol

A protocol is JSON with `schema_version: 1`, `element`, native `xc`, `relativity`,
`candidates`, and `benchmarks`. Unknown and duplicate keys are rejected.
Paths are relative to the protocol file. There must be both `train` and `test`
cases. Identical input templates in both splits are refused. For scientific
benchmarks, give each case a `group` for its structural family or material.
The runner refuses a declared group in both splits and energy anchors from
different groups. Group labels should follow the protocol's physical design.

A candidate describes `id`, `engine`, `family`, `profile`, `ecutwfc`, `ecutrho`,
and `options`. The supported option keys follow the shared physics specification:
`config`, `core_hole`, `zed`, `zval`, `nlcc`, `rcore`, `rho0`, `which_augfun`,
`rmatch_augfun`, `lloc`, `rcloc`, `rcut_scale`, `nc_form`, `beta`, `tr2`, `lsd`,
`gipaw`, `extra_projectors`, `channel_radii`, and `engine_options`.

Boolean flags use JSON booleans. `extra_projectors` and `channel_radii` use lists
of strings, such as `{"channel_radii": ["s:1.7", "p:1.8"]}`.
`engine_options` is also a list, for example `["qcut.s=5.12", "nbas.s=8"]`;
the same typed native catalogue validates it. Other values are
scalars. An optional `grid` maps option keys to lists of alternative values;
their Cartesian product is expanded, up to 256 candidates. A key cannot be in
both `options` and `grid`. Unsupported engine controls are refused by the same
core validation used for ordinary generation. Published ONCVPSP and OPIUM decks
cannot have their configuration rewritten with `--config`; supply a complete
edited native input to ordinary generation, or choose a supported construction.

For a finite-pool random baseline, set the top-level
`"search": {"strategy": "random", "seed": 19, "max_trials": 8}`. The seed
determines the order of distinct candidate IDs in the expanded pool. The report
records that order before generation and a failed attempt counts toward the
trial limit. Limit trials to the available candidate count. This matches
methods by number of trials. A comparison by CPU-hour needs separate resource
accounting.

Every benchmark has an `id`, `split`, local `input` template, `reference` and
`tolerances`. A reference contains:

- `source`: a citation or traceable calculation identifier;
- `kind`: `all-electron`, `converged-pseudopotential`, or `synthetic-test`;
- `xc` and `relativity`, matching the generation specification;
- the required measurements: `forces_Ry_bohr`, `stress_kbar`, or `energy_Ry`.

Force references contain one three-component row per atom. Stress is a 3×3
matrix in kbar. The available constraints are:

| Tolerance key | Error evaluated |
| --- | --- |
| `force_max_Ry_bohr` | Maximum absolute Cartesian component error across atoms |
| `stress_max_kbar` | Maximum absolute component error in the stress tensor |
| `relative_energy_Ry_atom` | Error in an energy difference per atom, relative to `relative_to` |

Absolute total energies from different pseudopotentials do not share an energy
zero. Energy constraints therefore require `relative_to`: another case in the
same split with the same composition and atom count. The reference energy
difference is subtracted from the candidate's energy difference before division
by atom count. Training and test anchors cannot cross splits.

## QE templates and mixtures

This evaluator requires QE-readable UPFs. Native-input preparation supports
all nine generators, but this command does not compare GTH/CP2K or
ADPACK/OpenMX outputs. Additional consumer backends and independent reference
benchmarks are research work; see the
[engine-portfolio research proposal](../contributing/engine-portfolio.md).

Templates must request a single-point `calculation='scf'`, declare matching
`nat`, `ntyp`, `ATOMIC_SPECIES` and `ATOMIC_POSITIONS`, and contain:

```text
{{PSEUDO_DIR}}  {{UPF}}  {{ECUTWFC}}  {{ECUTRHO}}  {{OUTDIR}}  {{PREFIX}}
```

`{{ELEMENT}}` is optional. Request `tprnfor=.true.` for force measurements and
`tstress=.true.` for stress. `input_dft` is refused so it cannot override a
candidate's functional. For fully relativistic calculations, the author must
include the appropriate spinor settings and match the reference treatment.

To study a compound, supply the other elements' UPFs in `fixed_pseudos`, a map
of element symbols to paths. Their species records use `SYMBOL.fixed.UPF`;
the generated species uses `{{UPF}}`. The fixed files are copied and hashed so
every candidate sees the same environment. The protocol author is responsible
for their functional and relativistic consistency with the reference.

## Selection, records and limits

`repeats` defaults to 3. Each repeat uses a fresh scratch directory and one
OpenMP/BLAS thread. The sum of the median times per training case is the cost.
The worst physical error over repeats is divided by each stated tolerance.
A candidate is feasible only when every training constraint is satisfied.
The report includes the nondominated training candidates in cost/error space.
By default (`"selection": "cost"`), selection chooses the feasible candidate
with the lowest training cost. Ties use its worst normalized error and then
its id. With `"selection": "accuracy"`, error comes first and time breaks ties.
Use this mode for matched fixed-cutoff comparisons. A loaded machine can
change wall-time rankings. The report records the host and solver identity.

### Test numerical stability

Add an optional block at the protocol's top level. For example, a candidate
using 60/480 Ry can be checked with three successive increases.

```json
{
  "convergence": {
    "base_k_mesh": [8, 8, 8],
    "tolerance_fraction": 0.1,
    "levels": [
      {"ecutwfc": 80, "ecutrho": 480, "k_mesh": [8, 8, 8]},
      {"ecutwfc": 80, "ecutrho": 640, "k_mesh": [8, 8, 8]},
      {"ecutwfc": 80, "ecutrho": 640, "k_mesh": [12, 12, 12]}
    ]
  }
}
```

In every template, use `K_POINTS automatic` followed by
`{{K_MESH}} 0 0 0`, or the desired three shifts. Every level must increase
at least one setting and keep the others the same or tighter. The evaluator
runs each tighter level once. It compares forces, stress and signed energy
differences with the preceding level and with all base repeats. For each
metric, the maximum drift must fit within the specified fraction of the
benchmark tolerance. The physical reference limits must also pass at every
level. A failed level stays in the report. The selection time objective still
uses the median base-setting simulation time, while the complete generation
and training trial elapsed times are recorded separately. A pass establishes
stability across the declared levels and structures.

Every generation runs with `--no-autofix`; the search must evaluate the requested
parameters. A bound ghost detected by ONCVPSP is refused even with optional
tests off. Engine-specific atomic grades are retained as diagnostics, never
used as a common cross-engine accuracy score. A force/stress test is not a
complete ghost search or a proof of transferability in other environments.

`report.json` records commands, failed candidates, training measurements,
the locked selection, held-out results, reference kinds, checksums and scope.
`protocol-inputs/protocol.json` and the copied inputs form a portable snapshot.
Generated inputs, UPFs, atomic diagnostics and every QE input/log remain in
the candidate directories. Timeouts terminate the complete solver process group.

`meets_reference_constraints` becomes true only if the selected candidate passes
the held-out cases and the references are not labelled `synthetic-test`.
Exit code 0 means that condition holds, 2 means no verified choice, and 1 means
invalid inputs or an execution setup error. A successful `--plan` returns 0
but performs no physical measurement and leaves the flag false.

This implements the measurement and selection workflow. Establishing a new
scientific advantage requires a broader benchmark, independent reference data,
comparison to published libraries and equal-budget search baselines. This
workflow and a successful example cannot guarantee journal acceptance.
