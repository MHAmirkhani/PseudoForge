# Independent molecular force pilot

The reference uses all electrons in PySCF, with PBE, the one-electron
spin-free X2C Hamiltonian and neutral closed-shell geometries. The protocol
uses displaced silane for training and displaced silanone as the other
molecular family. These are exploratory geometries, with no claim about
equilibrium or the broader chemical domain. See the [PySCF scalar
relativistic methods](https://pyscf.org/user/scf.html).

Install PySCF in a separate Python environment. Supply scalar-PBE H and O UPFs
with known provenance. Those two operators stay fixed across all Si candidates.
For example, generate them with `pseudoforge generate --engine oncvpsp -p sg15`
and the corresponding element, native PBE functional and scalar relativity.

```bash
python examples/design-forces/make_protocol.py --h-upf /path/to/H.UPF \
  --o-upf /path/to/O.UPF -o molecular-inputs
pseudoforge design molecular-inputs/protocol.json --plan -o molecular-plan
pseudoforge design molecular-inputs/protocol.json --pw /path/to/pw.x -o molecular-run
```

The generator records the basis hashes, PySCF version, coordinates and
analytic gradients. It cross-checks density fitting against a direct
calculation in the triple-zeta basis. The larger calculations use the
`def2-universal-jkfit` auxiliary basis for the Coulomb term. Basis changes,
grid changes, the finite-difference force component and the net force from
translation must each fit within a quarter of the chosen force tolerance.
A source fingerprint in each protocol reference identifies the all-electron
report. Compare the recorded numerical checks before interpreting agreement.
When the triple-to-quadruple-zeta change exceeds that gate, the generator
adds a five-zeta rung and repeats the grid and finite-difference checks.
`--refine-reference` extends a previously saved reference using the same
PySCF version and basis hashes.

QE uses an isolated-cell correction and a separate wavefunction/density-cutoff
ladder. Use `--reuse-reference molecular-inputs/force-reference.json`
with a larger `--cell-bohr` and compare forces across the two cells before
reporting a converged result. Keep the same H and O files. The test measures
transferability of the Si candidate **in the presence of those fixed
operators**. SF-X2C-1e and the scalar terms used in the pseudopotential
construction can have a residual model difference. The protocol uses only
forces and makes no cross-composition comparison of total energies.
