# AcTa

AcTa is a Frama-C plugin for generating a CBMC harness from the ACSL
contract of an entry-point function.

This project follows the same overall structure as the sibling `saida`
project:

1. Read the C file and its ACSL annotations through Frama-C.
2. Find the selected entry function, typically via `-main`.
3. Translate the entry contract into a harness for bounded verification.
4. Append the generated harness to the input source file.
5. Optionally run CBMC on the generated file.

## Current scope

The first implementation in this repository is intentionally narrower than
Saida:

- It targets CBMC harness generation, not helper-contract inference.
- It currently supports one entry function with a direct ACSL contract.
- It supports simple `requires` and `ensures` clauses over C-like expressions,
  including `\result` and pre-state snapshots for plain variables used in
  postconditions.
- It does not yet support quantifiers, full memory-state `\old`, or advanced
  ACSL memory predicates in harness generation.

## Build

```sh
dune build
```

To install it as a Frama-C plugin:

```sh
dune build @install && dune install
```

## Usage

Generate a harness-augmented C file:

```sh
frama-c -acta -main foo input.c
```

Useful options:

- `-acta-out <file>`: write the generated source-with-harness to `<file>`.
- `-acta-cbmc-path <path>`: path to the `cbmc` executable.
- `-acta-cbmc-opts "<opts>"`: extra CBMC command-line options.
- `-acta-run-cbmc`: run CBMC after generating the harness.
- `-acta-cbmc-out <file>`: store CBMC output in `<file>`.

## Regression Tests

Run the AcTa regression suite with:

```sh
dune runtest
```

Or invoke the runner directly:

```sh
bash tests/run_regression_tests.sh _build/default/src/Acta.cmxs
```

The current suite is under `tests/basic/` and mirrors Saida's oracle-based
style:

- `tests/basic/*.c`: input programs.
- `tests/basic/oracle/*.out.c`: expected generated harness output.
- `tests/basic/oracle/*.cbmc.result`: expected CBMC result markers.

## Layout

- `src/options_acta.ml`: plugin registration and command-line options.
- `src/acta_vis.ml`: AST traversal and ACSL-to-harness translation.
- `src/cbmc_driver.ml`: CBMC process invocation.
- `src/main.ml`: orchestration for generation and execution.
