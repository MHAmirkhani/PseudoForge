id=vanderbilt
label=Vanderbilt ultrasoft (classic)
families=us
provenance=reproducible
generator=uspp (Vanderbilt)
upstream=Vanderbilt USPP library
author=D. Vanderbilt and collaborators
reference=https://www.physics.rutgers.edu/~dhv/uspp/
license=GPL-2.0-or-later
summary=The original ultrasoft pseudopotential library and the `uspp` generation code that GBRV later built on.
notes=The original ultrasoft library and the uspp code behind it. Its per-element decks ship inside the uspp distribution PseudoForge already builds, so no download is needed. Output is converted to UPF through reform.x and QE's upfconv.x.
engine=uspp
available=LDA and PBE ultrasoft, the elements in the uspp Work tree.
# xc_available: Every deck sets exfact 4 and the files declare PW91. This profile declared pz and pbe, and produced PW91 under both names.
xc_available=pw91
rel_available=scalar
families_note=US, the uspp Work tree
formats=uspp van upf xml
