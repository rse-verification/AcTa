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
      (Filename.quote cbmc_path) (Filename.quote harness_name) cbmc_opts
      (Filename.quote source_fname) (Filename.quote output_fname)
  in
  Sys.command cmd_str

(* Keep stdout as JSON and stderr separate; no shell interprets report-mode arguments. *)
let run_cbmc_json cbmc_path arguments output_fname =
  let stdout = Unix.openfile output_fname [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
  Fun.protect ~finally:(fun () -> Unix.close stdout) (fun () ->
    let stderr = Unix.openfile (output_fname ^ ".stderr.log")
        [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
    Fun.protect ~finally:(fun () -> Unix.close stderr) (fun () ->
      let pid = Unix.create_process cbmc_path
          (Array.of_list (cbmc_path :: arguments)) Unix.stdin stdout stderr in
      let rec wait () =
        try snd (Unix.waitpid [] pid)
        with Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
      in
      match wait () with
      | Unix.WEXITED code -> code
      | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 128))
