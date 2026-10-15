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

open Acta_vis
open Cbmc_driver
open Options_acta

let try_read ic =
  try Some (input_line ic) with End_of_file -> None

let append_harness_to_source source_fname harness_buff out_fname =
  let source_chan = open_in source_fname in
  let out_chan = open_out out_fname in
  let rec copy_source () =
    match try_read source_chan with
    | None -> ()
    | Some line ->
        output_string out_chan line;
        output_char out_chan '\n';
        copy_source ()
  in
  copy_source ();
  output_char out_chan '\n';
  Buffer.output_buffer out_chan harness_buff;
  close_in source_chan;
  close_out out_chan

let get_source_file () =
  match Kernel.Files.get () with
  | [] ->
      Self.abort "No source file found"
  | head :: tail ->
      if tail <> [] then
        Self.feedback "More than one source file given, only the first one is used";
      Filepath.to_string head

let render_harness harness_func =
  let harness_buff = Buffer.create 2048 in
  let fmt = Format.formatter_of_buffer harness_buff in
  Format.pp_set_margin fmt max_int;
  let printer = new cbmc_print fmt in
  printer#print_harness harness_func;
  Format.pp_print_flush fmt ();
  harness_buff

let run () =
  if Enabled.get () then
    try
      let translator = new acsl2cbmc in
      let { harness_functions } = translator#translate (Ast.get ()) in
      let target = Kernel.MainFunction.get_function_name () in
      let harness_func =
        match List.find_opt (fun hf -> hf.called_func = target) harness_functions with
        | Some hf -> hf
        | None ->
            Self.abort
              "No ACSL contract found for the selected entry function '%s'"
              target
      in
      let harness_buff = render_harness harness_func in
      let source_fname = get_source_file () in
      let output_fname = OutputFile.get () in
      append_harness_to_source source_fname harness_buff output_fname;
      Self.result "Generated CBMC harness source: %s" output_fname;
      if Run_cbmc.get () then begin
        let cbmc_out = CbmcOutputFile.get () in
        let exit_code =
          run_cbmc
            (CbmcPath.get ())
            (CbmcOptions.get ())
            harness_func.name
            output_fname
            cbmc_out
        in
        Self.result "CBMC finished with exit code %d, output stored in %s"
          exit_code
          cbmc_out
      end
    with Sys_error _ as exc ->
      Self.abort "I/O error during AcTa execution: %s" (Printexc.to_string exc)

let () = Boot.Main.extend run
