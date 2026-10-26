(*
 * Copyright 2026 Scania CV AB
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * SPDX-License-Identifier: GPL-2.0+
 *)

module Self = Plugin.Register
  (struct
    let name = "AcTa"
    let shortname = "acta"
    let help = "Generate a CBMC harness from an ACSL entry contract"
  end)

module OutputFile = Self.String
  (struct
    let option_name = "-acta-out"
    let default = "acta.out.c"
    let arg_name = "output_file"
    let help =
      "Name of the generated C file containing the original source plus the CBMC harness."
  end)

module CbmcPath = Self.String
  (struct
    let option_name = "-acta-cbmc-path"
    let default = "cbmc"
    let arg_name = "cbmc_path"
    let help = "Path to the CBMC executable."
  end)

module CbmcOptions = Self.String
  (struct
    let option_name = "-acta-cbmc-opts"
    let default = ""
    let arg_name = "cbmc_opts"
    let help = "Extra command-line options passed to CBMC."
  end)

module CbmcOutputFile = Self.String
  (struct
    let option_name = "-acta-cbmc-out"
    let default = "acta.cbmc.out"
    let arg_name = "cbmc_output_file"
    let help = "File used to store CBMC stdout/stderr when -acta-run-cbmc is enabled."
  end)

module Enabled = Self.False
  (struct
    let option_name = "-acta"
    let help = "Enable AcTa harness generation."
  end)

module ReportFile = Self.String
  (struct
    let option_name = "-acta-report"
    let default = ""
    let arg_name = "report_file"
    let help = "Write a versioned JSON verification report (requires -acta-run-cbmc)."
  end)

module CbmcArguments = Self.String
  (struct
    let option_name = "-acta-cbmc-args"
    let default = "[]"
    let arg_name = "json_array"
    let help = "Additional CBMC arguments as a JSON array of strings, for -acta-report."
  end)

module CbmcUnwind = Self.Int
  (struct
    let option_name = "-acta-cbmc-unwind"
    let default = 10
    let arg_name = "bound"
    let help = "Positive loop bound for -acta-report; unwinding assertions remain enabled."
  end)

module Run_cbmc = Self.False
  (struct
    let option_name = "-acta-run-cbmc"
    let help = "Run CBMC on the generated harness file."
  end)
