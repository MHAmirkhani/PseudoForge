# Reference-constrained Si demonstration

See `docs/how-to/reference-design.md` for the full protocol and its limitations.
Run from the repository root:

```sh
python3 examples/design-si/make_reference.py --pw /path/to/pw.x -o ./si-reference
./pseudoforge design si-reference/protocol.json --plan -o ./si-plan
./pseudoforge design si-reference/protocol.json --pw /path/to/pw.x -o ./si-design
```

The script measures forces and stress with the existing Si ONCV UPF fixture at
80 and 100 Ry. It checks cutoff changes before recording the 100 Ry result as
a reference. The k mesh is small and fixed; this is an execution demonstration
against a pseudopotential reference, not an all-electron accuracy benchmark.
No precomputed physical results are fabricated or embedded in the protocol.
