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

let validate_output_paths inputs outputs =
  let rec canonical path =
    try Unix.realpath path with Unix.Unix_error (Unix.ENOENT, _, _) ->
      Filename.concat (canonical (Filename.dirname path)) (Filename.basename path)
  in
  let same_file left right =
    canonical left = canonical right ||
    try
      let left = Unix.stat left and right = Unix.stat right in
      left.Unix.st_dev = right.Unix.st_dev && left.Unix.st_ino = right.Unix.st_ino
    with Unix.Unix_error (Unix.ENOENT, _, _) -> false
  in
  let rec check = function
    | [] -> ()
    | path :: rest ->
        if List.exists (same_file path) (inputs @ rest) then
          Self.abort "Output paths must be distinct and separate from inputs: %s" path;
        check rest
  in
  check outputs

let run () =
  if Enabled.get () then begin
    let entry = Kernel.MainFunction.get_function_name () in
    let harness = "acta_harness_" ^ entry in
    let source = OutputFile.get () in
    let output = CbmcOutputFile.get () in
    let unwind = CbmcUnwind.get () in
    let report_path = ReportFile.get () in
    let report_written = ref false in
    let save_report value =
      Verification_report.write report_path value;
      report_written := true
    in
    (* Validate before error reporting too, so an invalid report cannot replace an input. *)
    if report_path <> "" then
      validate_output_paths (List.map Filepath.to_string (Kernel.Files.get ()))
        [source; report_path; output; output ^ ".stderr.log"];
    try
      if report_path <> "" then begin
        List.iter (fun path -> if Sys.file_exists path then Sys.remove path)
          [report_path; output; output ^ ".stderr.log"];
        if not (Run_cbmc.get ()) then
          invalid_arg "-acta-report requires -acta-run-cbmc";
        if CbmcOptions.get () <> "" then
          invalid_arg "use -acta-cbmc-args with -acta-report instead of -acta-cbmc-opts"
      end else if CbmcArguments.get () <> "[]" then
        invalid_arg "-acta-cbmc-args requires -acta-report";
      let translator = new acsl2cbmc in
      let { harness_functions } = translator#translate (Ast.get ()) in
      let harness_func =
        match List.find_opt (fun hf -> hf.called_func = entry) harness_functions with
        | Some hf -> hf
        | None ->
            Self.abort
              "No ACSL contract found for the selected entry function '%s'"
              entry
      in
      let harness_buff = render_harness harness_func in
      let source_fname = get_source_file () in
      let output_fname = OutputFile.get () in
      append_harness_to_source source_fname harness_buff output_fname;
      Self.result "Generated CBMC harness source: %s" output_fname;
      if Run_cbmc.get () then begin
        if report_path <> "" then begin
          let result = Verification_report.run ~cbmc:(CbmcPath.get ())
              ~extra:(CbmcArguments.get ()) ~entry ~harness:harness_func.name
              ~source:output_fname ~output ~unwind in
          save_report result;
          if Yojson.Basic.Util.member "status" result <> `String "passed" then
            Self.abort "%s" (Yojson.Basic.Util.member "error" result |> Yojson.Basic.Util.to_string);
          Self.result "Verification passed; report stored in %s" report_path
        end else begin
          let exit_code = run_cbmc (CbmcPath.get ()) (CbmcOptions.get ())
              harness_func.name output_fname output in
          Self.result "CBMC finished with exit code %d, output stored in %s" exit_code output;
          if exit_code <> 0 then Self.abort "CBMC verification failed (exit %d)" exit_code
        end
      end
    with exc ->
      if report_path <> "" && not !report_written then
        save_report (Verification_report.error ~entry ~harness ~source ~output ~unwind
                       (Printexc.to_string exc));
      match exc with
      | Sys_error _ | Unix.Unix_error _ | Invalid_argument _
      | Yojson.Json_error _ | Yojson.Basic.Util.Type_error _ ->
          Self.abort "AcTa execution failed: %s" (Printexc.to_string exc)
      | _ -> raise exc
  end

let () = Boot.Main.extend run
