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

let run_cbmc cbmc_path cbmc_opts harness_name source_fname output_fname =
  let cmd_str =
    Format.asprintf "%s --function %s %s %s > %s 2>&1"
      cbmc_path harness_name cbmc_opts source_fname output_fname
  in
  Sys.command cmd_str
