(lang dune 3.13)
(using dune_site 0.1)
(name frama-c-acta)

(generate_opam_files true)

(license GPL-2.0-or-later)
(maintainers "Scania")
(authors "The AcTa development team")
(source (github rse-verification/AcTa))
(homepage "https://github.com/rse-verification/AcTa")
(version dev)

(package
 (name frama-c-acta)
 (depends
  (ocaml (>= 4.14))
  (frama-c (and (>= 31) (< 32))))
 (synopsis "CBMC harness generation from ACSL entry contracts")
 (description
  "This plugin for the Frama-C platform reads the ACSL contract of an entry
function and generates a C harness suitable for execution by CBMC."))
