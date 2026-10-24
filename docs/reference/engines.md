# Engines

PseudoForge does not implement pseudopotential generation. It drives nine codes
that do, each written by the people who developed the method it implements, and
each carrying its own licence and citation.

The table is generated from the engine registry in `lib/engines.sh`, so it
cannot drift from what the code actually knows about.

<!-- generated:begin -->
<!-- Do not edit between these markers: tools/gen_reference.sh writes them. -->

| Engine | Families | Writes UPF directly | Licence | Upstream |
|---|---|---|---|---|
| [ADPACK (Ozaki)](engines/adpack.md) | NC | no | GPL-2.0-or-later | [source](http://www.openmx-square.org/adpack/adpack.html) |
| [APE (Atomic Pseudopotential Engine)](engines/ape.md) | NC | yes | GPL-2.0-or-later | [source](https://gitlab.com/ape/ape) |
| [AtomPAW (Holzwarth)](engines/atompaw.md) | PAW | yes | GPL-3.0 | [source](https://github.com/atompaw/atompaw) |
| [fhi98PP (Fuchs/Scheffler)](engines/fhi98pp.md) | NC | no | see the licence inside the distribution | [source](https://th.fhi-berlin.mpg.de/th/fhi98md/fhi98PP/) |
| [GTH (Goedecker/Hartwigsen, CP2K)](engines/gth.md) | NC | no | GPL-2.0-or-later | [source](https://github.com/cp2k/cp2k-data) |
| [Quantum ESPRESSO ld1.x](engines/ld1.md) | NC US PAW | yes | GPL-2.0-or-later | [source](https://gitlab.com/QEF/q-e) |
| [ONCVPSP (Hamann)](engines/oncvpsp.md) | NC | yes | GPL-3.0 | [source](https://github.com/oncvpsp/oncvpsp) |
| [OPIUM (Rappe group)](engines/opium.md) | NC | yes | GPL-2.0 | [source](https://github.com/rappegroup/opium) |
| [USPP (Vanderbilt)](engines/uspp.md) | US | no | GPL-2.0-or-later | [source](https://www.physics.rutgers.edu/~dhv/uspp/) |

<!-- generated:end -->

---

## Choosing between them

The short version, with the reasoning in [Choose an
engine](../how-to/choose-an-engine.md):

| If you want | Use |
|---|---|
| PAW or ultrasoft, reproducing PSlibrary | [`ld1`](engines/ld1.md) |
| Hard, accurate norm-conserving; SG15 or PseudoDojo | [`oncvpsp`](engines/oncvpsp.md) |
| A meta-GGA PAW dataset generated self-consistently | [`atompaw`](engines/atompaw.md) |
| Ultrasoft in Vanderbilt's own code | [`uspp`](engines/uspp.md) |
| Many output formats from one generation | [`opium`](engines/opium.md) |
| Analytic GTH/HGH coefficients for CP2K | [`gth`](engines/gth.md) |
| Norm-conserving with a wide functional range via libxc | [`ape`](engines/ape.md) — [no GGA for open-d metals](engines/ape.md#known-limitation-d-shell-elements) |
| OpenMX `.vps` files | [`adpack`](engines/adpack.md) |
| The FHI98 method specifically | [`fhi98pp`](engines/fhi98pp.md) |

## Installing them

PseudoForge can build all nine engines; eight build automatically from bundled source archives into `~/.pseudoforge/engines`, while `ld1.x` comes from Quantum ESPRESSO and is installed on first use (or on demand).

```bash
pseudoforge engines list          # what is present, what is missing
pseudoforge engines build all     # fetch, patch and build eight engines
pseudoforge engines build ape     # or just one
pseudoforge engines show ape      # version, build id, binary path
```

### Source archives

The repository bundles or caches source archives under `engines-src/`, verified against `engines-src/MANIFEST.txt`:

| Archive | SHA256 | Size | Engine / Library |
|---|---|---|---|
| `adpack2.2.tar.gz` | `c2eb8f451fdb67375a02013eb3111fdb192df5e0c5d63f0d01eeaa10bbfa494d` | 337 KB | ADPACK |
| `ape.tar.gz` | `29d1980b0150f61142abc8eca6848f9ae186d9c3d215774f56d47c5bacf18339` | 2.1 MB | APE |
| `atompaw.tar.gz` | `06507a0eea25213830ae2d9298abd127b130632e8b604c41040a2c5965c595c8` | 29.1 MB | AtomPAW |
| `cp2k-data.tar.gz` | `c63cfb61d7915b3ade462f411a7f519682b460a055b85bcfd86e0de625992528` | 9.3 MB | GTH |
| `fhi98PP.zip` | `e65b3cd7e6defcf1083eec01dc13ab790898d347f3bce5b701cd3523b0ebff47` | 2.2 MB | fhi98PP |
| `gsl-2.7.1.tar.gz` | `cd7a951ac9d990ed7d6738ad98084b27c6b9c2f88b2962252c3fdaa14bd9910d` | 25.7 MB | GSL (supporting library) |
| `libxc-7.1.2.tar.gz` | `9248009bb98862277017de99287e5f9d7cf5b237cc7b6c113b229c83c142a08f` | 27.7 MB | libxc (supporting library) |
| `oncvpsp-master.zip` | `89978fbdb0cf457fe4e25038b21c3692d855f58ec1d61a87264a553a0cfdacdb` | 5.5 MB | ONCVPSP |
| `opium-4.1.0.tar.gz` | `d256d0cf0eca8a945b2558fabeb43e3f97e1687381ab52876640150aaf6145ce` | 1.6 MB | OPIUM |
| `uspp-734-3.tgz` | `32f595e73e6d1b71fbfed1d090e5c077a873105de850f81efecc19d695cef5a4` | 258 KB | USPP |

`pseudoforge doctor` reports the same thing with a fix command for each
missing item. See [Installation](../getting-started/installation.md).

## What "writes UPF directly" means

An engine that writes UPF produces a file Quantum ESPRESSO can read without any
conversion step. An engine that does not writes its own native format, and
PseudoForge converts it — which means a conversion appears in the provenance,
and that conversion may be `exact` or `lossy`. It is never silent.

The engines that do not write UPF are USPP, fhi98PP, GTH and ADPACK. For GTH
and ADPACK the conversion to UPF is **refused**, not merely absent: see
[Formats and conversions](formats.md) for why, and use those engines' output
with the codes that read it natively.

## Versions and build ids

Every engine's version and a hash of the build are recorded in the provenance
of anything it generates:

```text
engine.id=oncvpsp
engine.label=ONCVPSP (Hamann)
engine.version=4.0.1
engine.build=7de3694ef3fd
engine.binary=~/.pseudoforge/engines/bin/oncvpsp.x
engine.upstream=https://github.com/oncvpsp/oncvpsp
```

Where a version cannot be determined it is recorded as `unrecorded` rather than
guessed. See [Provenance](../architecture/provenance.md).

## Citing them

```bash
pseudoforge citation --all        # every library and every engine
pseudoforge citation psl-high     # one library
```

Each generated project directory also gets a `CITATION.txt` and a
`LICENSE.txt` in `pseudos/`, so the attribution travels with the files rather
than staying with the command that made them.
