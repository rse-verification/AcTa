(* Copyright 2026 Scania CV AB; SPDX-License-Identifier: GPL-2.0+ *)
(* AcTa owns CBMC invocation and interpretation; consumers import this report. *)

open Yojson.Basic.Util

let report ~entry ~harness ~source ~output ~unwind ~status ~exit_code
    ~properties ~proved ~failed ~error =
  `Assoc [
    "schema_version", `Int 1; "status", `String status;
    "entry_point", `String entry; "harness_function", `String harness;
    "harness_file", `String source; "cbmc_output_file", `String output;
    "unwind", `Int unwind; "cbmc_exit_code", exit_code;
    "properties", `Int properties; "proved", `Int proved;
    "failed_properties", `List (List.map (fun name -> `String name) failed);
    "error", error;
  ]

let write path value =
  let channel = open_out path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    Yojson.Basic.pretty_to_channel channel value;
    output_char channel '\n')

let error ?(exit_code = `Null) ~entry ~harness ~source ~output ~unwind message =
  report ~entry ~harness ~source ~output ~unwind ~status:"error"
    ~exit_code ~properties:0 ~proved:0 ~failed:[] ~error:(`String message)

let flags = [
  "--trace"; "--bounds-check"; "--pointer-check"; "--pointer-overflow-check";
  "--signed-overflow-check"; "--unsigned-overflow-check"; "--div-by-zero-check";
  "--float-overflow-check"; "--nan-check"; "--slice-formula";
  "--sat-preprocessor"; "--no-sat-preprocessor";
]

let arguments text =
  let values = Yojson.Basic.from_string text |> to_list |> List.map to_string in
  let rec validate = function
    | [] -> ()
    | ("--object-bits" | "--verbosity" | "--unwindset" | "-I" as option) :: rest ->
        (match rest with
         | value :: tail when value <> "" && value.[0] <> '-' -> validate tail
         | _ -> invalid_arg (option ^ " requires a value"))
    | value :: tail when List.mem value flags ||
        (String.length value > 2 &&
         (String.starts_with ~prefix:"-D" value || String.starts_with ~prefix:"-U" value)) ->
        validate tail
    | value :: _ -> invalid_arg ("unsupported CBMC argument in report mode: " ^ value)
  in
  validate values;
  values

let evidence path harness =
  let records = Yojson.Basic.from_file path |> to_list in
  let statuses = List.filter_map (fun record ->
    match member "cProverStatus" record with `Null -> None | value -> Some (to_string value)) records in
  let groups = List.filter_map (fun record ->
    match member "result" record with `Null -> None | value -> Some (to_list value)) records in
  let status = match statuses with
    | [status] when groups <> [] -> status
    | _ -> invalid_arg "CBMC did not report one verification status and a property list"
  in
  let properties = List.concat groups in
  if properties = [] then invalid_arg "CBMC reported no properties";
  let details = List.map (fun property ->
    to_string (member "property" property), to_string (member "status" property)) properties in
  if not (List.exists (fun property ->
    member "description" property = `String "ensures" &&
    String.starts_with ~prefix:(harness ^ ".assertion.") (to_string (member "property" property))) properties)
  then invalid_arg "CBMC reported no entry ensures assertion";
  status, List.length properties,
  List.filter_map (fun (name, status) -> if status = "SUCCESS" then None else Some name) details

let run ~cbmc ~extra ~entry ~harness ~source ~output ~unwind =
  if unwind <= 0 then invalid_arg "CBMC loop bound must be greater than zero";
  let argv = ["--function"; harness; "--json-ui"; "--unwinding-assertions";
              "--unwind"; string_of_int unwind] @ arguments extra @ [source] in
  let exit_code = Cbmc_driver.run_cbmc_json cbmc argv output in
  try
    let status, properties, failed = evidence output harness in
    let proved = properties - List.length failed in
    let passed = exit_code = 0 && status = "success" && failed = [] in
    let message = if passed then `Null else `String
        (Printf.sprintf "CBMC proved %d/%d properties; status=%s, exit=%d"
           proved properties status exit_code) in
    report ~entry ~harness ~source ~output ~unwind
      ~status:(if passed then "passed" else "failed") ~exit_code:(`Int exit_code)
      ~properties ~proved ~failed ~error:message
  with (Yojson.Json_error _ | Type_error _ | Invalid_argument _ | Sys_error _) as exc ->
    error ~exit_code:(`Int exit_code) ~entry ~harness ~source ~output ~unwind
      (Printexc.to_string exc)
