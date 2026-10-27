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

Use Frama-C 33 in the active opam switch. AcTa must be built and loaded with
the same Frama-C installation.

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

## Verification report

Consumers such as [AutoDeduct](https://github.com/rse-verification/auto-deduct)
can ask AcTa to generate the harness, run CBMC, and write a versioned JSON
report in one invocation:

```sh
frama-c -acta -main compute input.c \
  -acta-run-cbmc -acta-out harness.c \
  -acta-report acta-report.json -acta-cbmc-out cbmc.json \
  -acta-cbmc-unwind 10 -acta-cbmc-args '["--trace", "-I", "include directory"]'
```

Report mode invokes CBMC with an argument vector, keeps JSON stdout separate
from `cbmc.json.stderr.log`, and enables unwinding assertions. Extra arguments
use a JSON string array so spaces and punctuation remain literal. Do not combine
`-acta-cbmc-opts` with `-acta-report`; that option retains the legacy shell-based
interface for standalone use.

Allowed extra arguments are `--trace`, `--bounds-check`, `--pointer-check`,
`--pointer-overflow-check`, `--signed-overflow-check`, `--unsigned-overflow-check`,
`--div-by-zero-check`, `--float-overflow-check`, `--nan-check`, `--slice-formula`,
`--sat-preprocessor`, `--no-sat-preprocessor`, and attached `-D`/`-U` definitions.
`-I`, `--object-bits`, `--verbosity`, and `--unwindset` each take the next argument
as their value. Options that retarget the harness, select properties, disable
assertions, bypass full unwinding, or add source files are rejected.

The JSON object has `schema_version: 1` and these fields:

| Field | Meaning |
| --- | --- |
| `status` | `passed`, `failed`, or `error` |
| `entry_point`, `harness_function`, `harness_file` | Verification target |
| `unwind` | Requested positive loop bound |
| `cbmc_output_file`, `cbmc_exit_code` | Raw CBMC evidence and exit code; exit is null if CBMC did not run |
| `properties`, `proved`, `failed_properties` | Property counts and unsuccessful property identifiers |
| `error` | Failure explanation, or null on success |

`passed` requires CBMC exit zero, one JSON success status, a nonempty property
list containing an entry `ensures` assertion, and every property successful.
Counterexamples, incomplete unwinding, missing or malformed evidence, and
unknown property results fail verification. AcTa exits nonzero on verification
failure, including through the legacy `-acta-run-cbmc` interface. When execution
reaches the plugin, report mode also writes an `error` report for generation or
execution errors; Frama-C errors before the plugin runs may leave no report.
Consumers should clear old reports before each invocation, check the process
exit status, and validate the report version and requested target.
The harness, report, CBMC output and stderr paths must be distinct and separate
from the input files; AcTa rejects collisions before cleaning or writing them.

## Regression Tests

The regression runner requires Frama-C, CBMC and Python 3 on `PATH`.

Run the AcTa regression suite with:

```sh
dune runtest
```

Or invoke the runner directly:

```sh
bash tests/run_regression_tests.sh _build/default/src/Acta.cmxs
```

The harness cases under `tests/basic/` mirror Saida's oracle-based style:

- `tests/basic/*.c`: input programs.
- `tests/basic/oracle/*.out.c`: expected generated harness output.
- `tests/basic/oracle/*.cbmc.result`: expected CBMC result markers.

`tests/report/report_tests.py` checks the JSON report interface and failure
handling with real CBMC and deliberately malformed output.

## Layout

- `src/options_acta.ml`: plugin registration and command-line options.
- `src/acta_vis.ml`: AST traversal and ACSL-to-harness translation.
- `src/cbmc_driver.ml`: CBMC process invocation.
- `src/main.ml`: orchestration for generation and execution.
