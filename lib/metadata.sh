# shellcheck shell=bash
# ---------------------------------------------------------------------------
# metadata.sh -- where each library lives, what it is licensed under, and how
# to cite it.
#
# Three rules govern this file:
#
#   1. Nothing here is invented.  MD_VERIFIED says which of three things is
#      true, and they are printed differently because they mean different
#      things to the person about to write a bibliography:
#
#        yes         the authors ask for this citation, in their distribution
#                    or on their publication page.
#        no-request  the authors ask for nothing -- checked, not assumed --
#                    and the reference shown is the one their *own*
#                    documentation gives for the method. It is labelled as
#                    such, because presenting it as a request would put words
#                    in the authors' mouths.
#        no          not established. It prints "Unverified -- check the
#                    source" with a TODO naming what to check, so you go and
#                    look rather than paste something wrong into a paper.
#
#   2. A DOI is only recorded when it belongs to the paper named beside it.
#      DOIs are resolvable, so a wrong one is worse than no one: it sends a
#      reader somewhere confidently incorrect.
#
#   3. Licences are recorded as the distribution states them.  Where a
#      distribution is unclear or mixes sources, the field says so instead of
#      picking the most convenient reading.
#
# You are still responsible for what goes in your bibliography.  PseudoForge gives
# you the reference the authors asked for; it cannot know what your journal
# wants, and it is not a substitute for checking.
# ---------------------------------------------------------------------------

declare -gA MD_INDEX_URL MD_OFFICIAL_URL MD_MIRROR_PATH MD_LICENSE MD_LICENSE_URL \
            MD_CITATION MD_DOI MD_DATA_DOI MD_VERIFIED MD_ALSO_CITE MD_NOTE \
            MD_CITE_SOURCE MD_CITE_TODO

# Default mirror, overridable in ~/.pseudoforgerc.
: "${MIRROR_URL:=https://pseudo.amirkhani.me/library/}"

pf_metadata_load() {
    [ -n "${MD_LICENSE[psl-high]:-}" ] && return 0

    # ---- PSlibrary ---------------------------------------------------------
    local psl_cite="A. Dal Corso, \"Pseudopotentials periodic table: From H to Pu\", Computational Materials Science 95, 337-350 (2014)."
    local psl_doi="10.1016/j.commatsci.2014.07.043"
    local id
    for id in psl-high psl-low psl-031 psl-alt psl-tot; do
        MD_OFFICIAL_URL[$id]="https://pseudopotentials.quantum-espresso.org/upf_files/"
        MD_MIRROR_PATH[$id]="pslibrary"
        MD_LICENSE[$id]="GPL-2.0-or-later"
        MD_LICENSE_URL[$id]="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
        MD_CITATION[$id]=$psl_cite
        MD_DOI[$id]=$psl_doi
        MD_VERIFIED[$id]=yes
        MD_ALSO_CITE[$id]="quantum-espresso"
        MD_NOTE[$id]="Generated here with ld1.x from recipes byte-identical to PSlibrary's own inputs."
    done
    MD_NOTE[psl-031]="The 0.1-0.3.1 recipes, kept for reproducing older published work."


    # ---- PseudoForge itself ------------------------------------------------
    #
    # A DOI is not minted yet.  Rather than leave a placeholder that could be
    # pasted into a paper as if it resolved, the citation carries the project
    # URL and says so.  When the DOI exists, set MD_DOI[pseudoforge] and flip
    # MD_VERIFIED to yes -- nothing else needs to change.
    MD_OFFICIAL_URL[pseudoforge]="https://github.com/MHAmirkhani/pseudoforge"
    MD_MIRROR_PATH[pseudoforge]=""
    MD_LICENSE[pseudoforge]="GPL-2.0-or-later"
    MD_LICENSE_URL[pseudoforge]="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
    MD_CITATION[pseudoforge]="M. H. Amirkhani, \"PseudoForge: a multi-engine pseudopotential generator and validator\", version $PSEUDOFORGE_VERSION (2026). https://github.com/MHAmirkhani/pseudoforge"
    MD_DOI[pseudoforge]=""
    MD_VERIFIED[pseudoforge]=yes
    MD_ALSO_CITE[pseudoforge]=""
    MD_NOTE[pseudoforge]="Cite PseudoForge for the tooling, and the pseudopotential library for the physics. A DOI is not yet minted; check https://github.com/MHAmirkhani/pseudoforge for one before submitting."

    # ---- Quantum ESPRESSO (the code, cited alongside anything ld1.x made) ---
    MD_OFFICIAL_URL[quantum-espresso]="https://www.quantum-espresso.org/"
    MD_MIRROR_PATH[quantum-espresso]=""
    MD_LICENSE[quantum-espresso]="GPL-2.0-or-later"
    MD_LICENSE_URL[quantum-espresso]="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
    MD_CITATION[quantum-espresso]="P. Giannozzi et al., \"QUANTUM ESPRESSO: a modular and open-source software project for quantum simulations of materials\", J. Phys.: Condens. Matter 21, 395502 (2009); and P. Giannozzi et al., \"Advanced capabilities for materials modelling with Quantum ESPRESSO\", J. Phys.: Condens. Matter 29, 465901 (2017)."
    MD_DOI[quantum-espresso]="10.1088/0953-8984/21/39/395502"
    MD_VERIFIED[quantum-espresso]=yes
    MD_ALSO_CITE[quantum-espresso]=""
    MD_NOTE[quantum-espresso]="Cite the code itself when you used ld1.x or pw.x, in addition to the pseudopotential library."

    # ---- SG15 ONCV ---------------------------------------------------------
    MD_OFFICIAL_URL[sg15]="http://www.quantum-simulation.org/potentials/sg15_oncv/"
    MD_INDEX_URL[sg15]="http://www.quantum-simulation.org/potentials/sg15_oncv/upf/"
    MD_MIRROR_PATH[sg15]="sg15"
    MD_LICENSE[sg15]="Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0, stated on the distribution page)"
    MD_LICENSE_URL[sg15]="https://creativecommons.org/licenses/by-sa/4.0/"
    MD_CITATION[sg15]="M. Schlipf and F. Gygi, \"Optimization algorithm for the generation of ONCV pseudopotentials\", Computer Physics Communications 196, 36-44 (2015)."
    MD_DOI[sg15]="10.1016/j.cpc.2015.05.011"
    MD_VERIFIED[sg15]=yes
    MD_ALSO_CITE[sg15]="oncvpsp"
    MD_NOTE[sg15]="Individual files are served from the upf/ directory, and a full tarball is offered as well. SG15 publishes PBE only -- there is no PBEsol or LDA set -- and marks fully-relativistic files with _FR."

    # ---- PseudoDojo --------------------------------------------------------
    MD_OFFICIAL_URL[pseudodojo]="http://www.pseudo-dojo.org/"
    MD_MIRROR_PATH[pseudodojo]="pseudodojo"
    MD_LICENSE[pseudodojo]="see the PseudoDojo site; tables carry their own terms"
    MD_LICENSE_URL[pseudodojo]="http://www.pseudo-dojo.org/"
    MD_CITATION[pseudodojo]="M. J. van Setten, M. Giantomassi, E. Bousquet, M. J. Verstraete, D. R. Hamann, X. Gonze and G.-M. Rignanese, \"The PseudoDojo: Training and grading a 85 element optimized norm-conserving pseudopotential table\", Computer Physics Communications 226, 39-54 (2018)."
    MD_DOI[pseudodojo]="10.1016/j.cpc.2018.01.012"
    MD_VERIFIED[pseudodojo]=yes
    MD_ALSO_CITE[pseudodojo]="oncvpsp"
    MD_NOTE[pseudodojo]="Publishes its ONCVPSP input files alongside the tables; pass them to --params for a real local reproduction."

    # ---- GBRV --------------------------------------------------------------
    MD_OFFICIAL_URL[gbrv]="https://www.physics.rutgers.edu/gbrv/"
    MD_MIRROR_PATH[gbrv]="gbrv"
    MD_LICENSE[gbrv]="see the GBRV distribution"
    MD_LICENSE_URL[gbrv]="https://www.physics.rutgers.edu/gbrv/"
    MD_CITATION[gbrv]="K. F. Garrity, J. W. Bennett, K. M. Rabe and D. Vanderbilt, \"Pseudopotentials for high-throughput DFT calculations\", Computational Materials Science 81, 446-452 (2014)."
    MD_DOI[gbrv]="10.1016/j.commatsci.2013.08.053"
    MD_VERIFIED[gbrv]=yes
    MD_ALSO_CITE[gbrv]="vanderbilt"
    MD_NOTE[gbrv]="Converged at 40 Ry wavefunction / 200 Ry charge-density cutoff for essentially the whole set."

    # ---- SSSP --------------------------------------------------------------
    MD_OFFICIAL_URL[sssp]="https://www.materialscloud.org/discover/sssp/"
    MD_MIRROR_PATH[sssp]="sssp"
    MD_LICENSE[sssp]="per element: the licence of whichever library SSSP selected"
    MD_LICENSE_URL[sssp]="https://www.materialscloud.org/discover/sssp/"
    MD_CITATION[sssp]="G. Prandini, A. Marrazzo, I. E. Castelli, N. Mounet and N. Marzari, \"Precision and efficiency in solid-state pseudopotential calculations\", npj Computational Materials 4, 72 (2018)."
    MD_DOI[sssp]="10.1038/s41524-018-0127-2"
    MD_DATA_DOI[sssp]="10.24435/materialscloud:f3-ym"
    MD_VERIFIED[sssp]=yes
    MD_ALSO_CITE[sssp]=""
    MD_NOTE[sssp]="A curated *selection*, not a generator: also cite the source library of every element you actually used."

    # ---- Vanderbilt ultrasoft ---------------------------------------------
    MD_OFFICIAL_URL[vanderbilt]="https://www.physics.rutgers.edu/~dhv/uspp/"
    MD_MIRROR_PATH[vanderbilt]="vanderbilt"
    MD_LICENSE[vanderbilt]="GPL-2.0-or-later"
    MD_LICENSE_URL[vanderbilt]="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
    MD_CITATION[vanderbilt]="D. Vanderbilt, \"Soft self-consistent pseudopotentials in a generalized eigenvalue formalism\", Physical Review B 41, 7892(R) (1990)."
    MD_DOI[vanderbilt]="10.1103/PhysRevB.41.7892"
    MD_VERIFIED[vanderbilt]=yes
    MD_ALSO_CITE[vanderbilt]=""
    MD_NOTE[vanderbilt]="The paper defines the ultrasoft formalism; the uspp code implements it."

    MD_OFFICIAL_URL[qe-legacy]="https://pseudopotentials.quantum-espresso.org/upf_files"
    MD_MIRROR_PATH[qe-legacy]="qe-legacy"
    MD_LICENSE[qe-legacy]="GPL-2.0-or-later"
    MD_LICENSE_URL[qe-legacy]="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
    MD_CITATION[qe-legacy]=""
    MD_DOI[qe-legacy]=""
    MD_VERIFIED[qe-legacy]=no
    MD_ALSO_CITE[qe-legacy]="quantum-espresso"
    MD_NOTE[qe-legacy]="Contributed by many authors over many years; credit the original author named in each file's header rather than the table as a whole."

    MD_OFFICIAL_URL[gipaw]="https://raw.githubusercontent.com/dceresoli/gipaw-pseudopotentials/main/pseudos"
    MD_INDEX_URL[gipaw]="https://github.com/dceresoli/gipaw-pseudopotentials/tree/main/pseudos"
    MD_MIRROR_PATH[gipaw]="gipaw"
    MD_LICENSE[gipaw]="see the repository"
    MD_LICENSE_URL[gipaw]="https://github.com/dceresoli/gipaw-pseudopotentials"
    MD_CITATION[gipaw]=""
    MD_DOI[gipaw]=""
    MD_VERIFIED[gipaw]=no
    MD_ALSO_CITE[gipaw]="quantum-espresso"
    MD_NOTE[gipaw]="This entry used to say the published files could not be regenerated because they carry no embedded input. That was true of the qe-gipaw repository it pointed at, and wrong about the library: Ceresoli publishes the ld1.x decks separately, in gipaw-pseudopotentials, and PseudoForge now ships and runs those 17 decks. No paper is attached to the pseudopotentials themselves, so there is no citation to give here -- credit the repository and cite Quantum ESPRESSO for ld1.x."

    # ---- HGH ---------------------------------------------------------------
    MD_OFFICIAL_URL[hgh]="https://www.cp2k.org/static/potentials/"
    MD_MIRROR_PATH[hgh]="hgh"
    MD_LICENSE[hgh]="published parameter tables; no separate software licence"
    MD_LICENSE_URL[hgh]=""
    MD_CITATION[hgh]="C. Hartwigsen, S. Goedecker and J. Hutter, \"Relativistic separable dual-space Gaussian pseudopotentials from H to Rn\", Physical Review B 58, 3641 (1998)."
    MD_DOI[hgh]="10.1103/PhysRevB.58.3641"
    MD_VERIFIED[hgh]=yes
    MD_ALSO_CITE[hgh]="cp2k-gth"
    MD_NOTE[hgh]="Analytic fit coefficients. This note used to add that there was therefore nothing for an atomic code to reproduce -- which confused the form of the result with the absence of a generator. CP2K publishes both the fitting code and the per-element inputs, and PseudoForge drives them; see the cp2k-gth entry."

    # ---- GTH ---------------------------------------------------------------
    # Every DOI below was read off the paper, not recalled.  The 1996 paper is
    # cited from the arXiv preprint the user supplied, whose identifiers are on
    # its own first page; the journal-of-record reference is given alongside.
    MD_OFFICIAL_URL[cp2k-gth]="https://github.com/cp2k/cp2k-data/tree/master/potentials"
    MD_INDEX_URL[cp2k-gth]="https://github.com/cp2k/cp2k-data/tree/master/potentials/GTH_rev"
    MD_MIRROR_PATH[cp2k-gth]="cp2k-gth"
    MD_LICENSE[cp2k-gth]="GPL-2.0-or-later (the cp2k-data repository)"
    MD_LICENSE_URL[cp2k-gth]="https://github.com/cp2k/cp2k-data"
    MD_CITATION[cp2k-gth]="S. Goedecker, M. Teter and J. Hutter, \"Separable dual-space Gaussian pseudopotentials\", Physical Review B 54, 1703 (1996); arXiv:mtrl-th/9512004."
    MD_DOI[cp2k-gth]="10.1103/PhysRevB.54.1703"
    MD_VERIFIED[cp2k-gth]=yes
    MD_ALSO_CITE[cp2k-gth]="hgh gth-krack"
    MD_NOTE[cp2k-gth]="Cite all three papers when using a GGA set: Goedecker/Teter/Hutter for the form, Hartwigsen/Goedecker/Hutter for the relativistic tables to Rn, and Krack for the gradient-corrected parametrisations (BLYP, BP, PBE) that most GGA entries here come from."

    MD_OFFICIAL_URL[gth-krack]="https://github.com/cp2k/cp2k-data/tree/master/potentials/Goedecker"
    MD_MIRROR_PATH[gth-krack]="cp2k-gth"
    MD_LICENSE[gth-krack]="published parameter tables"
    MD_LICENSE_URL[gth-krack]=""
    MD_CITATION[gth-krack]="M. Krack, \"Pseudopotentials for H to Kr optimized for gradient-corrected exchange-correlation functionals\", Theoretical Chemistry Accounts 114, 145 (2005)."
    MD_DOI[gth-krack]="10.1007/s00214-005-0655-y"
    MD_VERIFIED[gth-krack]=yes
    MD_ALSO_CITE[gth-krack]=""
    MD_NOTE[gth-krack]="The source of the BLYP, BP and PBE GTH parameter sets for H to Kr."

    # ---- fhi98PP -----------------------------------------------------------
    MD_OFFICIAL_URL[fhi]="https://th.fhi-berlin.mpg.de/th/fhi98md/fhi98PP/"
    MD_MIRROR_PATH[fhi]="fhi"
    MD_LICENSE[fhi]="see the licence inside the fhi98PP distribution"
    MD_LICENSE_URL[fhi]="https://th.fhi-berlin.mpg.de/th/fhi98md/fhi98PP/"
    MD_CITATION[fhi]="M. Fuchs and M. Scheffler, \"Ab initio pseudopotentials for electronic structure calculations of poly-atomic systems using density-functional theory\", Computer Physics Communications 119, 67-98 (1999)."
    MD_DOI[fhi]="10.1016/S0010-4655(98)00201-X"
    MD_VERIFIED[fhi]=yes
    MD_ALSO_CITE[fhi]=""
    MD_NOTE[fhi]="Writes .cpi/.fhi; Quantum ESPRESSO 7.x cannot convert those to UPF (see docs/reference/engines.md)."

    # ---- the generator codes themselves ------------------------------------
    MD_OFFICIAL_URL[oncvpsp]="https://github.com/oncvpsp/oncvpsp"
    MD_MIRROR_PATH[oncvpsp]=""
    MD_LICENSE[oncvpsp]="GPL-3.0"
    MD_LICENSE_URL[oncvpsp]="https://www.gnu.org/licenses/gpl-3.0.html"
    MD_CITATION[oncvpsp]="D. R. Hamann, \"Optimized norm-conserving Vanderbilt pseudopotentials\", Physical Review B 88, 085117 (2013); erratum Physical Review B 95, 239906(E) (2017)."
    MD_DOI[oncvpsp]="10.1103/PhysRevB.88.085117"
    MD_VERIFIED[oncvpsp]=yes
    MD_ALSO_CITE[oncvpsp]=""
    MD_NOTE[oncvpsp]="ONCVPSP prints this request in its own output; cite it for anything the code produced."

    MD_OFFICIAL_URL[uspp]="https://www.physics.rutgers.edu/~dhv/uspp/"
    MD_MIRROR_PATH[uspp]=""
    MD_LICENSE[uspp]="GPL-2.0-or-later"
    MD_LICENSE_URL[uspp]="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
    MD_CITATION[uspp]=${MD_CITATION[vanderbilt]}
    MD_DOI[uspp]=${MD_DOI[vanderbilt]}
    MD_VERIFIED[uspp]=yes
    MD_ALSO_CITE[uspp]=""
    MD_NOTE[uspp]="The uspp code; cite the Vanderbilt formalism paper."

    MD_OFFICIAL_URL[fhi98pp]=${MD_OFFICIAL_URL[fhi]}
    MD_MIRROR_PATH[fhi98pp]=""
    MD_LICENSE[fhi98pp]=${MD_LICENSE[fhi]}
    MD_LICENSE_URL[fhi98pp]=${MD_LICENSE_URL[fhi]}
    MD_CITATION[fhi98pp]=${MD_CITATION[fhi]}
    MD_DOI[fhi98pp]=${MD_DOI[fhi]}
    MD_VERIFIED[fhi98pp]=yes
    MD_ALSO_CITE[fhi98pp]=""
    MD_NOTE[fhi98pp]=${MD_NOTE[fhi]}

    MD_OFFICIAL_URL[ld1]=${MD_OFFICIAL_URL[quantum-espresso]}
    MD_MIRROR_PATH[ld1]=""
    MD_LICENSE[ld1]=${MD_LICENSE[quantum-espresso]}
    MD_LICENSE_URL[ld1]=${MD_LICENSE_URL[quantum-espresso]}
    MD_CITATION[ld1]=${MD_CITATION[quantum-espresso]}
    MD_DOI[ld1]=${MD_DOI[quantum-espresso]}
    MD_VERIFIED[ld1]=yes
    MD_ALSO_CITE[ld1]=""
    MD_NOTE[ld1]=${MD_NOTE[quantum-espresso]}

    # ---- the five engines whose citation had to be looked up -----------------
    #
    # Two of them document what their authors want cited; three do not, and are
    # recorded as unverified with a *named* thing to go and check. A TODO that
    # names a file is a checklist item; a bare "Unverified" is a mystery, and
    # mysteries do not get resolved.
    #
    # MD_CITE_SOURCE says where a citation was taken from, so the claim can be
    # rechecked without repeating the search.

    # APE -- the authors state it, under a heading of exactly this name.
    MD_OFFICIAL_URL[ape]="https://gitlab.com/ape/ape"
    MD_CITATION[ape]="M. J. T. Oliveira and F. Nogueira, \"Generating relativistic pseudo-potentials with explicit incorporation of semi-core states using APE, the Atomic Pseudo-potentials Engine\", Computer Physics Communications 178, 524 (2008)."
    MD_DOI[ape]="10.1016/j.cpc.2007.11.003"
    MD_VERIFIED[ape]=yes
    MD_CITE_SOURCE[ape]="the \"How to cite APE\" section of README.md in the APE source tree"
    MD_ALSO_CITE[ape]=""
    MD_LICENSE[ape]="GPL-2.0-or-later"

    # GTH -- the engine id is the cp2k-gth reference under another name, the
    # same aliasing ld1 uses for quantum-espresso. Nothing new was needed: the
    # citation was already here, verified, under the profile id; only the
    # engine id had no entry, so `pseudoforge citation` fell through to
    # "Unverified" for a reference the codebase already had.
    #
    # Confirmed against the "Please cite:" block carried in every GTH data
    # file under cp2k-data/potentials/Goedecker/, which names the same three
    # papers cp2k-gth already cross-references.
    MD_OFFICIAL_URL[gth]=${MD_OFFICIAL_URL[cp2k-gth]}
    MD_CITATION[gth]=${MD_CITATION[cp2k-gth]}
    MD_DOI[gth]=${MD_DOI[cp2k-gth]}
    MD_VERIFIED[gth]=yes
    MD_CITE_SOURCE[gth]="the \"Please cite:\" block in every GTH data file under cp2k-data/potentials/Goedecker/"
    MD_ALSO_CITE[gth]=${MD_ALSO_CITE[cp2k-gth]}
    MD_NOTE[gth]=${MD_NOTE[cp2k-gth]}
    MD_LICENSE[gth]="GPL-2.0-or-later"

    # AtomPAW -- no citation request anywhere: not in the distribution
    # (README, README.md, AUTHORS), not on Holzwarth's page, not on ABINIT's
    # AtomPAW page, which hosts it now. ABINIT's page lists this paper first
    # under "References"; it is the code's own paper. Checked 2026-09-27.
    MD_OFFICIAL_URL[atompaw]="https://github.com/atompaw/atompaw"
    MD_VERIFIED[atompaw]=no-request
    MD_CITATION[atompaw]="A. R. Tackett, N. A. W. Holzwarth and G. E. Matthews, \"A Projector Augmented Wave (PAW) code for electronic structure calculations, Part I: atompaw for generating atom-centered functions\", Computer Physics Communications 135, 329-347 (2001)."
    MD_DOI[atompaw]="10.1016/S0010-4655(00)00244-7"
    MD_CITE_SOURCE[atompaw]="the distribution, https://users.wfu.edu/natalie/papers/pwpaw/man.html, and ABINIT's AtomPAW page, which lists it as reference [1]"
    MD_LICENSE[atompaw]="GPL-3.0"

    # ADPACK -- no citation request anywhere: not in the tarball (source/ and
    # work/ only), not in the ADPACK 2.2 user's manual, read in full including
    # section 14 and the bibliography. The manual attributes ADPACK's own
    # contribution -- "generation of pseudo-atomic orbitals under a
    # confinement potential" -- to its reference [15], which is these two
    # papers. Both DOIs resolved to the titles below. Checked 2026-09-27.
    #
    # The old URL, openmx-square.org/adpack/adpack.html, now returns 404.
    MD_OFFICIAL_URL[adpack]="https://www.openmx-square.org/adpack_man2.2/"
    MD_VERIFIED[adpack]=no-request
    MD_CITATION[adpack]="T. Ozaki, \"Variationally optimized atomic orbitals for large-scale electronic structures\", Physical Review B 67, 155108 (2003)."
    MD_DOI[adpack]="10.1103/PhysRevB.67.155108"
    MD_CITE_SOURCE[adpack]="the ADPACK 2.2 user's manual (2011-09-28), sections 1 and 14 and reference [15]"
    # Reference [15] names two papers. One DOI per entry, because md_doi_url
    # turns the field into a link and two DOIs in one field made one broken
    # link. The second paper is its own entry, linked the way cp2k-gth links
    # Krack.
    MD_ALSO_CITE[adpack]="adpack-kino"
    MD_OFFICIAL_URL[adpack-kino]=${MD_OFFICIAL_URL[adpack]}
    MD_VERIFIED[adpack-kino]=no-request
    MD_CITATION[adpack-kino]="T. Ozaki and H. Kino, \"Numerical atomic basis orbitals from H to Kr\", Physical Review B 69, 195113 (2004)."
    MD_DOI[adpack-kino]="10.1103/PhysRevB.69.195113"
    MD_CITE_SOURCE[adpack-kino]=${MD_CITE_SOURCE[adpack]}
    MD_LICENSE[adpack-kino]="GPL-2.0-or-later"
    MD_LICENSE[adpack]="GPL-2.0-or-later"

    # OPIUM -- no citation request anywhere, and no paper for the software
    # itself: not in the distribution, not on opium.sourceforge.net, not on
    # its "Scientific references" page, which lists the methods it
    # implements. PseudoForge's OPIUM decks select the `opt` scheme in their
    # [Pseudo] section, which that page attributes to this paper. The DOI
    # resolved to this title. Checked 2026-09-27.
    #
    # If a deck is changed to kerker or tm, this is no longer the right
    # reference -- the scientific-references page lists those too.
    MD_OFFICIAL_URL[opium]="https://opium.sourceforge.net/"
    MD_VERIFIED[opium]=no-request
    MD_CITATION[opium]="A. M. Rappe, K. M. Rabe, E. Kaxiras and J. D. Joannopoulos, \"Optimized pseudopotentials\", Physical Review B 41, 1227 (1990)."
    MD_DOI[opium]="10.1103/PhysRevB.41.1227"
    MD_CITE_SOURCE[opium]="the distribution and https://opium.sourceforge.net/sci.html, reference [2], for the opt scheme our decks use"
    MD_LICENSE[opium]="GPL-2.0"


    # ---- profiles PseudoForge knows of but has no verified citation for --------
    #
    # These are real distributions, but PseudoForge does not have a citation it can
    # stand behind.  Rather than guess at authors, journal or DOI, they are
    # marked unverified and print with the project URL so you can check.
    for id in wentzcovitch dacapo pseudoforge-auto; do
        MD_OFFICIAL_URL[$id]=""
        MD_MIRROR_PATH[$id]="$id"
        MD_LICENSE[$id]="unknown -- check the distribution"
        MD_LICENSE_URL[$id]=""
        MD_CITATION[$id]=""
        MD_DOI[$id]=""
        MD_VERIFIED[$id]=no
        MD_ALSO_CITE[$id]=""
        MD_NOTE[$id]=""
    done
    MD_OFFICIAL_URL[wentzcovitch]="https://www.materialscloud.org/discover/sssp/"
    MD_NOTE[wentzcovitch]="Distributed through SSSP; PseudoForge has no separate citation for this set."
    MD_OFFICIAL_URL[dacapo]="https://wiki.fysik.dtu.dk/dacapo/"
    MD_NOTE[dacapo]="Legacy Dacapo/CAMPOS set; superseded in practice by GBRV and PSlibrary."
    MD_LICENSE[pseudoforge-auto]="the licence of whichever recipe it was adapted from"
    MD_NOTE[pseudoforge-auto]="Not a published library: PseudoForge's own construction. There is nothing to cite but the engine that ran and the recipe it was adapted from -- both are recorded in the UPF header and the run manifest."
    MD_VERIFIED[pseudoforge-auto]=no
}

# ---------------------------------------------------------------------------
# Accessors.  Every one tolerates an unknown key, because profiles can be added
# by dropping a file into data/profiles without touching this table.
# ---------------------------------------------------------------------------
md_known()    { pf_metadata_load; [ -n "${MD_VERIFIED[$1]:-}" ]; }
md_license()  { pf_metadata_load; printf '%s\n' "${MD_LICENSE[$1]:-unknown -- check the distribution}"; }
md_doi()      { pf_metadata_load; printf '%s\n' "${MD_DOI[$1]:-}"; }
md_official() { pf_metadata_load; printf '%s\n' "${MD_OFFICIAL_URL[$1]:-}"; }

md_doi_url() {
    local doi; doi=$(md_doi "$1")
    [ -n "$doi" ] && printf 'https://doi.org/%s\n' "$doi"
}

# The one-line reference, or an honest admission that there is not one.
md_citation() {
    pf_metadata_load
    local id=$1 cite doi out
    cite=${MD_CITATION[$id]:-}
    doi=${MD_DOI[$id]:-}

    # The authors ask for nothing; say so, then give the reference their own
    # documentation uses for the method. Checked before the "no" branch: a
    # no-request entry has a citation and must not print as unverified.
    if [ "${MD_VERIFIED[$id]:-no}" = no-request ] && [ -n "$cite" ]; then
        out="No citation request from the authors (checked: ${MD_CITE_SOURCE[$id]:-their distribution}). Method reference from their own documentation: $cite"
        [ -n "$doi" ] && out="$out DOI: $doi"
        printf '%s\n' "$out"
        return 0
    fi

    if [ "${MD_VERIFIED[$id]:-no}" != yes ] || [ -z "$cite" ]; then
        # A bare "Unverified" is a mystery; a TODO that names a file or a
        # page is a checklist item, and checklist items get done.
        local url=${MD_OFFICIAL_URL[$id]:-} todo=${MD_CITE_TODO[$id]:-}
        if [ -n "$todo" ]; then
            printf 'Unverified -- check the source. TODO: %s\n' "$todo"
        else
            printf 'Unverified -- check the source%s\n' "${url:+: $url}"
        fi
        return 0
    fi

    out=$cite
    [ -n "$doi" ] && out="$out DOI: $doi"
    # Additional references are not appended here: md_citation_set expands
    # MD_ALSO_CITE into separate entries, and doing both printed GTH second
    # and third papers twice over.
    # Where it was taken from, so the claim can be rechecked without
    # repeating the search through somebody else's source tree.
    [ -n "${MD_CITE_SOURCE[$id]:-}" ] && out="$out [from ${MD_CITE_SOURCE[$id]}]"
    printf '%s\n' "$out"
}

# Some engine ids are the same reference under another name: citing ld1.x means
# citing Quantum ESPRESSO, and citing the uspp code means citing the Vanderbilt
# paper.  Normalise before de-duplicating, or the same work appears twice in one
# reference list.
md_canon_id() {
    case $1 in
        ld1)     printf 'quantum-espresso\n' ;;
        uspp)    printf 'vanderbilt\n' ;;
        fhi98pp) printf 'fhi\n' ;;
        *)       printf '%s\n' "$1" ;;
    esac
}

# Everything that should be credited for one run: the library, whatever it says
# to also cite, and the engine that did the work.
md_citation_set() {
    local prof=$1 engine=${2:-}
    pf_metadata_load
    # PseudoForge last: the physics belongs to the library, the tooling to us.
    local -a ids=("$prof")
    local extra
    for extra in ${MD_ALSO_CITE[$prof]:-}; do ids+=("$extra"); done
    [ -n "$engine" ] && ids+=("$(md_canon_id "$engine")")
    ids+=(pseudoforge)
    # de-duplicate, preserving order
    local seen="" id c
    for id in "${ids[@]}"; do
        c=$(md_canon_id "$id")
        case " $seen " in *" $c "*) continue ;; esac
        md_known "$c" || continue
        seen="$seen $c"
        printf '%s\n' "$id"
    done
}

# ---------------------------------------------------------------------------
# md_citation_text <profile> <engine> -- the contents of CITATION.txt.
# ---------------------------------------------------------------------------
md_citation_text() {
    local prof=$1 engine=${2:-} id n=0
    pf_metadata_load
    pf_profiles_load

    printf 'Please cite the following for the pseudopotentials in this directory.\n'
    printf '\n'
    printf 'Generated by PseudoForge %s on %s\n' "$PSEUDOFORGE_VERSION" "$(date '+%Y-%m-%d')"
    printf 'Library : %s\n' "${PROF_LABEL[$prof]:-$prof}"
    [ -n "$engine" ] && printf 'Engine  : %s\n' "${ENG_LABEL[$engine]:-$engine}"
    printf '\n'
    printf -- '-------------------------------------------------------------------------\n\n'

    while read -r id; do
        [ -n "$id" ] || continue
        n=$((n + 1))
        printf '[%d] %s\n' "$n" "$(md_citation "$id")"
        local url; url=$(md_doi_url "$id")
        [ -n "$url" ] && printf '    %s\n' "$url"
        printf '\n'
    done < <(md_citation_set "$prof" "$engine")

    if [ "$n" = 0 ]; then
        printf 'PseudoForge has no verified citation for this selection.\n'
        printf 'Check the distribution you obtained these files from.\n\n'
    fi

    printf -- '-------------------------------------------------------------------------\n'
    printf '\n'
    # This used to say every reference above was "the one the libraries' own
    # authors ask for". Three engines -- ADPACK, AtomPAW, OPIUM -- ask for
    # nothing, and each entry now says which kind it is, so the footer states
    # only what is true of all of them.
    printf 'Each entry says what it is.  Where the authors ask for a citation, it is the\n'
    printf 'one they ask for; where they ask for none, the entry says so and gives the\n'
    printf 'reference their own documentation uses for the method.\n'
    printf '\n'
    printf 'They are reproduced for convenience and are not a substitute for checking:\n'
    printf 'your journal may want a different format, and a distribution may have moved on.\n'
    [ -n "${MD_NOTE[$prof]:-}" ] && printf '\nNote: %s\n' "${MD_NOTE[$prof]}"
}

# ---------------------------------------------------------------------------
# md_license_text <profile> <engine> -- the contents of LICENSE.txt.
#
# This states the terms the *pseudopotentials* come under, which is not the
# same as PseudoForge's own licence, and says so.
# ---------------------------------------------------------------------------
md_license_text() {
    local prof=$1 engine=${2:-} id
    pf_metadata_load
    pf_profiles_load

    printf 'Licence terms for the pseudopotentials in this directory\n'
    printf '=======================================================\n\n'
    printf 'These files were produced with PseudoForge, but PseudoForge does not own them and\n'
    printf 'its own licence does not apply to them.  The terms below are those of the\n'
    printf 'library and the generator that produced the data.\n\n'

    for id in "$prof" $engine; do
        md_known "$id" || continue
        printf -- '-------------------------------------------------------------------------\n'
        printf '%s\n\n' "${PROF_LABEL[$id]:-${ENG_LABEL[$id]:-$id}}"
        printf '  Licence : %s\n' "$(md_license "$id")"
        [ -n "${MD_LICENSE_URL[$id]:-}" ] && printf '  Terms   : %s\n' "${MD_LICENSE_URL[$id]}"
        [ -n "${MD_OFFICIAL_URL[$id]:-}" ] && printf '  Source  : %s\n' "${MD_OFFICIAL_URL[$id]}"
        printf '\n'
    done

    printf -- '-------------------------------------------------------------------------\n\n'
    printf 'Where a licence is recorded as unknown, PseudoForge did not have a statement it\n'
    printf 'could stand behind.  Check the distribution before redistributing anything.\n'
}

# ---------------------------------------------------------------------------
# md_write_attribution <dir> <profile> <engine>
#   Drop CITATION.txt and LICENSE.txt beside the .UPF files.
# ---------------------------------------------------------------------------
md_write_attribution() {
    local dir=$1 prof=$2 engine=${3:-}
    [ -d "$dir" ] || return 1
    md_citation_text "$prof" "$engine" > "$dir/CITATION.txt" || return 1
    md_license_text  "$prof" "$engine" > "$dir/LICENSE.txt"  || return 1
    return 0
}
