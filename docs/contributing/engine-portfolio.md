# Research proposal: allocating a pseudopotential design budget across engines

Status: **proposal, not an implemented optimizer or a demonstrated advantage**.
Literature checked on 18 November 2026. The implemented foundation is the
[nine-engine manual workflow](../how-to/manual-generation.md), its typed
controls, input snapshots and failure reporting. The current `design` command
evaluates a finite grid, a seeded random subset or uniform allocation across
engine/formulation pairs through QE, with optional
cutoff/k-mesh stability checks and declared structural-family splits. The
adaptive portfolio scheduler and CP2K/OpenMX evaluation remain proposed.

## What is already established

The following are precedents, not features we can claim to have invented.
This is a focused literature review, not proof that no related method exists.

| Primary source | Established contribution | Consequence for our claim |
| --- | --- | --- |
| [Schlipf and Gygi, 2015](https://arxiv.org/abs/1502.00995) | Optimizes ONCV input parameters against a material training set | Automatic parameter optimization alone is insufficient novelty |
| [Hansel et al., CPC 2015](https://doi.org/10.1016/j.cpc.2015.06.014), supplied PDF | Multi-objective genetic optimization of AtomPAW cutoff radii and s/p projector energies against atomic log derivatives and material properties | Automated PAW fitting and a cost/accuracy trade-off already exist |
| [García et al., CPC 2018](https://doi.org/10.1016/j.cpc.2018.02.011), supplied PDF | PSML/libPSML describe provenance and share the same NC operator across consumer codes | Interoperability and provenance alone are not new; cross-code agreement requires matching the actual operator |
| [PseudoDojo, 2018](https://arxiv.org/abs/1710.10138) | Trains and grades an optimized 85-element ONCV table | A periodic table, grades and published tests alone are insufficient |
| [Prandini et al., 2018, SSSP](https://www.nature.com/articles/s41524-018-0127-2) | Selects precision/efficiency libraries from tested NC, US and PAW potentials | Selecting among existing files and formulations is already established; adapt native construction parameters and compare against SSSP |
| [Shojaei et al., 2022 preprint](https://arxiv.org/abs/2209.09806) | Evolutionary multi-objective optimization of ONCV softness/accuracy | A Pareto plot or evolutionary radius search alone is insufficient |
| [Schmitz et al., 2025](https://arxiv.org/abs/2509.07785) | Differentiable plane-wave DFT, including learning pseudopotential parameters | Property-driven or gradient-based fitting is not automatically new |
| [Nascimento et al., 2025 preprint / 2026 article](https://arxiv.org/abs/2504.03962) | Controls smearing and k-sampling errors with precision/efficiency protocols | Separate numerical convergence from construction quality and compare the numerical protocol against existing methods |
| [UZH protocol, 2026](https://arxiv.org/abs/2606.11064) | Separates Gaussian-basis and GTH errors using CP2K, same-GTH plane-wave SIRIUS and all-electron SIRIUS; revises parameters | Error decomposition and a constructive validation loop already exist |
| [Yamashita and Shiihara, 2026](https://doi.org/10.2472/jsms.2025.00095) | Bayesian optimization of fractional-charge ADPACK potentials, with atomic and bulk checks | Neither Bayesian search nor fractional nuclear charge alone is a new contribution |
| [Bosoni et al., 2024](https://arxiv.org/abs/2305.17274) | Common workflows verify nine pseudopotential-based approaches against 960 all-electron equations of state | Uniform cross-code interfaces and broad reference verification already exist |
| [APNS project](https://kirk0830.github.io/ABACUS-Pseudopot-Nao-Square/) | Evaluates multiple pseudopotential libraries and associated numerical atomic orbitals in ABACUS | Comparing many published libraries is not itself a new search method |
| [Synthetic molecular benchmark, 2026](https://pmc.ncbi.nlm.nih.gov/articles/PMC13553045/) | 669-molecule all-electron atomization-energy benchmark, multipole-conserving potentials and attribution of elemental pseudization errors | Chemical diversity and elemental error attribution also have direct precedents |

The attached papers have been checked as scientific sources, not instructions
to assert priority or guaranteed acceptance. Force-based targets and PAW
parameter fitting are not assumed new. Algorithm portfolios also predate this
project outside electronic structure: for example
[Yuen and Zhang, GECCO 2013](https://www.cmap.polytechnique.fr/~nikolaus.hansen/proceedings/2013/GECCO/proceedings/p567.pdf)
allocates work among evolutionary algorithms using predicted progress. Our
research question is the physical design problem and its tested benefit,
not inventing portfolio selection in general.

Multi-engine DFT workflow systems also exist: [FlowX's own tutorial](https://flowx.readthedocs.io/en/latest/tutorials/multi_engine.html)
describes common inputs for SIESTA, VASP, QE and GPAW. These are consumer DFT
codes, not the nine atomic generators here. This distinction does not justify
a general claim that PseudoForge invented physics-first or engine-independent
workflows.

## Recommended question

**Under the same total compute budget, can adaptive selection of generator
and its native physical parameters find a usable, cheaper potential more
reliably than optimizing one fixed generator or dividing work uniformly?**

For a specified element, XC/relativity, target material domain and consumer
code, a candidate consists of a generator, a supported representation and
generator-specific parameters. Feasibility requires native construction checks
and independently measured errors in forces, stresses and relative energies.
Minimize downstream simulation cost subject to these constraints, while charging
every construction, failed run and evaluation to the search budget. Report
both best feasible simulation cost at fixed search budgets and compute spent
before the first feasible candidate; these are different objectives.

The potential contribution is a physically constrained experimental design
method over heterogeneous construction families, with an open benchmark that
establishes when the extra choice is useful. We have not established priority
for that contribution or measured its benefit yet.

## Method to implement

1. Build a capability graph from generator, family, XC, relativity, native
   parameters and consumer-readable formats. Each engine owns a separate
   conditional search space with native units and coupled constraints.
2. Start from traceable library inputs and a small balanced initial allocation.
   Use a simple equal-budget random/native search as the first executable
   baseline before adding a learned scheduler.
3. Classify construction failures: malformed or unsupported inputs, SCF/root
   failures, ghost detections, and independent observable failures. A timeout
   is a censored cost observation, not evidence of physical instability.
4. Allocate the next compute block using predicted probability of feasibility
   and expected improvement per measured cost. Specify the acquisition rule
   before evaluation, include exploration and uncertainty calibration, and
   compare it with ordinary cost-aware conditional optimization.
5. Screen cheap atomic diagnostics before expensive material calculations
   only after measuring that the screen does not systematically discard good
   candidates. Native grades are diagnostics, not a common numerical target.
6. Freeze the chosen candidate using training/validation information. Evaluate
   held-out structures once; do not tune until the test set passes.

Nine engines are **not nine fidelity levels**. PAW augmentation, USPP beta
projectors and GTH Gaussian widths do not have interchangeable meanings.
Do not average their potentials or force a shared radius coordinate. Multiple
fidelities, if introduced, should be separately defined and calibrated
measurement levels within a compatible evaluation task.

## Comparability and consumer backends

Begin with an honest QE/UPF subset. Add CP2K or systematic plane-wave GTH
evaluation and OpenMX only with converged basis settings and consistent
independent references. Merely executing every atomic generator does not make
its files comparable in one solver. Do not convert GTH coefficients or
ADPACK files to nominal UPFs without a verified mathematical implementation.

For comparisons across consumer codes, separate basis/numerical error from
pseudopotential error; the UZH protocol is a direct precedent. Match functional,
relativistic treatment, composition, geometry, k sampling and reference
conventions. Use composition-matched energy differences rather than absolute
energies with different core-energy zeros. Document which comparisons are
within-code and which involve a code change.

## Evidence needed before writing a strong claim

- Predefine a diverse pilot (for example Si, O, Na, Ti, Fe, Cu, Sr and a heavy
  element), then expand only after observing whether engines are complementary.
  A target list is not a claim of available all-electron reference coverage.
- Group splits by material family or chemical environment. Include compressed
  cells, displaced structures and compounds with independent references.
  Exclude test structures and their near duplicates from scheduler training.
  Existing all-electron EOS and molecular energy datasets can provide some
  reference observables; they do not automatically supply force/stress data
  or permission to change functional and relativistic conventions.
- Compare the best fixed engine chosen on training data, uniform allocation,
  random search, the existing finite grid, and a conditional cost-aware search
  baseline. Include strong published libraries at comparable accuracy targets.
  An oracle best engine may be shown as an unattainable diagnostic bound.
- Use identical CPU-hour budgets, hardware/thread settings and timeouts; count
  failures, initialization and all fitting/evaluation work. Report downstream
  simulation cost separately from search cost. Archive raw observations.
- Repeat stochastic searches with independent seeds and report uncertainty
  across material groups. Ablate scheduling, coupled constraints, failure
  information and screening. Measure screen false rejections explicitly.
- State the tolerances, reference convergence requirements and practical
  improvement threshold before running the final benchmark. Report negative
  results if one engine dominates or scheduling overhead erases the benefit.

The go/no-go condition is evidence of complementary generators and a robust
equal-budget advantage over strong baselines. Without that, nine adapters and
a polished interface remain software infrastructure rather than demonstrated
optimization novelty. Do not prewrite numerical gains.

## Two narrower alternatives

**Search for a domain boundary.** Find off-equilibrium structures where a
candidate first violates force/stress constraints, then repair the construction
using those failures. The research contribution would need a new search or
calibration method and evidence beyond existing force-based fitting and
transferability tests. Publish an empirical tested domain, not a universal
certificate of correctness.

**Choose a physical intervention.** When a potential fails under pressure or
in oxides, test whether changing semicore partition, projector basis, matching
radii or generator is the least expensive effective intervention. This needs
controlled paired experiments and comparison with existing semicore and UZH
parameter revisions; an automatic retry by itself is not the contribution.

## Publication scope

The [CPC scope](https://shop.elsevier.com/journals/computer-physics-communications/0010-4655)
emphasizes significant computational methods and software for physics. A
reproducible implementation, meaningful physics benchmark, clear advance over
related work, accessible source and honest limitations support a submission.
No feature, test count or journal quartile guarantees acceptance. The proposed
method needs implementation and scientific evidence before it belongs in the
paper as a result.
