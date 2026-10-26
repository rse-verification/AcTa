#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plugin_path="${1:-_build/default/src/Acta.cmxs}"

if [[ "$plugin_path" != /* ]]; then
  plugin_path="$PWD/$plugin_path"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

run_harness_case() {
  local case_name="$1"
  local entry_fn="$2"
  local input="$repo_root/tests/basic/${case_name}.c"
  local expected="$repo_root/tests/basic/oracle/${case_name}.out.c"
  local actual="$tmpdir/${case_name}.out.c"

  frama-c \
    -no-autoload-plugins \
    -load-module "$plugin_path" \
    -acta \
    -main "$entry_fn" \
    "$input" \
    -acta-out "$actual" \
    >/dev/null 2>&1

  diff -u "$expected" "$actual"
}

run_cbmc_case() {
  local case_name="$1"
  local harness_name="$2"
  local generated="$tmpdir/${case_name}.out.c"
  local expected_result="$repo_root/tests/basic/oracle/${case_name}.cbmc.result"
  local actual_log="$tmpdir/${case_name}.cbmc.log"

  cbmc --function "$harness_name" "$generated" >"$actual_log" 2>&1
  grep -F -f "$expected_result" "$actual_log" >/dev/null
}

run_harness_case simple main
run_harness_case func_arguments start
run_harness_case implies func
run_harness_case old_predicate main
run_cbmc_case implies acta_harness_func
python3 "$repo_root/tests/report_tests.py" "$plugin_path"

printf 'AcTa regression tests passed.\n'
