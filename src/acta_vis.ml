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

open Cil_types
open Cil_datatype

module VarinfoSet = Cil_datatype.Varinfo.Set

let to_c_type (lt : logic_type) : logic_type =
  match lt with
  | Linteger -> Ctype (Cil.int32_t ())
  | _ -> lt

module HarnessPrinter = struct
  open Printer

  let unsupported what =
    Kernel.fatal ~current:true "AcTa does not support %s in harness generation yet" what

  let with_print_cil_as_is f arg =
    let module PrintAsIs = Kernel.PrintAsIs in
    let old, default = PrintAsIs.get (), not (PrintAsIs.is_set ()) in
    PrintAsIs.on ();
    let r = f arg in
    if default then PrintAsIs.clear () else PrintAsIs.set old;
    r

  module type FunctionNameProvider = sig
    val name : string
  end

  module Make (Name : FunctionNameProvider) : PrinterExtension =
  functor (X : PrinterClass) ->
  struct
    class printer : Printer.extensible_printer =
      object (self)
        inherit X.printer as super

        val context_func_name = Name.name
        val mutable let_var_defs = Logic_var.Hashtbl.create 10
        val mutable in_old_context = false

        method private add_let_var_def b =
          Logic_var.Hashtbl.replace let_var_defs b.l_var_info b.l_body

        method private result_string (fname : string) =
          fname ^ "_result"

        method private is_old_like_label = function
          | BuiltinLabel Old
          | BuiltinLabel Pre ->
              true
          | _ ->
              false

        method private with_old_context_term f arg =
          let old_state = in_old_context in
          in_old_context <- true;
          try
            let result = f arg in
            in_old_context <- old_state;
            result
          with exn ->
            in_old_context <- old_state;
            raise exn

        method private with_old_context_predicate f arg =
          let old_state = in_old_context in
          in_old_context <- true;
          try
            let result = f arg in
            in_old_context <- old_state;
            result
          with exn ->
            in_old_context <- old_state;
            raise exn

        method! logic_constant fmt = function
          | Boolean false -> Format.fprintf fmt "%d" 0
          | Boolean true -> Format.fprintf fmt "%d" 1
          | lc -> super#logic_constant fmt lc

        method! logic_var fmt lv =
          match lv.lv_origin with
          | Some vi when in_old_context ->
              Format.fprintf fmt "%s_old" vi.vorig_name
          | Some vi ->
              Format.fprintf fmt "%s" vi.vorig_name
          | None -> super#logic_var fmt lv

        method! quantifiers _fmt _qfs =
          ()

        method! term_offset fmt = function
          | TModel (mi, _) ->
              unsupported (Format.asprintf "model field access '%s'" mi.mi_name)
          | toff -> super#term_offset fmt toff

        method! term_lval fmt (tlh, toff) =
          match tlh with
          | TResult typ ->
              if in_old_context then
                unsupported "\\old(\\result)"
              else
                let tlh' =
                  TVar
                    (Cil_const.make_logic_var_kind
                       (self#result_string context_func_name)
                       LVC
                       (Ctype typ))
                in
                super#term_lval fmt (tlh', toff)
          | TVar lv ->
              (match Logic_var.Hashtbl.find_opt let_var_defs lv with
               | Some (LBterm t) -> self#term fmt t
               | Some (LBpred p) -> self#predicate fmt p
               | Some _ -> unsupported "non-term let bindings"
               | None -> super#term_lval fmt (tlh, toff))
          | _ -> super#term_lval fmt (tlh, toff)

        method! term_node fmt t =
          match t.term_node with
          | TConst _
          | TLval _
          | TSizeOf _
          | TSizeOfE _
          | TAlignOf _
          | TAlignOfE _
          | TUnOp _
          | TBinOp _
          | TCast _
          | TAddrOf _
          | TStartOf _
          | Tif _
          | Tnull ->
              super#term_node fmt t
          | Tat (inner, label) ->
              if self#is_old_like_label label then
                self#with_old_context_term (self#term fmt) inner
              else
                self#term fmt inner
          | Tlet (def, body) ->
              self#add_let_var_def def;
              self#term fmt body
          | TDataCons _
          | Tapp _
          | Tlambda _
          | Tbase_addr _
          | Toffset _
          | Tblock_length _
          | TUpdate _
          | Ttypeof _
          | Ttype _
          | Tempty_set
          | Tunion _
          | Tinter _
          | Tcomprehension _
          | Trange _ ->
              unsupported "advanced ACSL terms"
          | _ ->
              unsupported "advanced ACSL terms"

        method private pred_bin_op fmt p1 p2 op_string =
          Format.fprintf fmt "%a %s %a" self#predicate p1 op_string self#predicate p2

        method! predicate_node fmt = function
          | Ptrue ->
              super#predicate_node fmt (Prel (Rneq, Cil.lone (), Cil.lzero ()))
          | Pfalse ->
              super#predicate_node fmt (Prel (Rneq, Cil.lzero (), Cil.lzero ()))
          | ((Pnot _ | Pand _ | Por _ | Prel _ | Pif _) as pn) ->
              super#predicate_node fmt pn
          | Pxor (p1, p2) ->
              self#pred_bin_op fmt p1 p2 "!="
          | Pimplies (p1, p2) ->
              let rewritten = Por (Logic_const.pnot p1, p2) in
              super#predicate_node fmt rewritten
          | Piff (p1, p2) ->
              self#pred_bin_op fmt p1 p2 "=="
          | Pat (inner, label) ->
              if self#is_old_like_label label then
                self#with_old_context_predicate (self#predicate fmt) inner
              else
                self#predicate fmt inner
          | Pforall _
          | Pexists _ ->
              unsupported "quantifiers"
          | Plet (binding, p) ->
              self#add_let_var_def binding;
              self#predicate fmt p
          | Pvalid _
          | Pvalid_read _
          | Pinitialized _
          | Pdangling _
          | Pallocable _
          | Pfreeable _
          | Pfresh _
          | Pseparated _
          | Papp _
          | Pobject_pointer _
          | Pvalid_function _ ->
              unsupported "advanced ACSL predicates"
      end
  end
end

type harness_func = {
  name : string;
  called_func : string;
  assumes : identified_predicate list;
  asserts : identified_predicate list;
  params : varinfo list;
  old_vars : varinfo list;
  return_type : typ;
}

type src_data = {
  harness_functions : harness_func list;
}

let is_old_like_label = function
  | BuiltinLabel Old
  | BuiltinLabel Pre ->
      true
  | _ ->
      false

let add_old_var_from_logic_var acc lv =
  match lv.lv_origin with
  | Some vi -> VarinfoSet.add vi acc
  | None -> acc

let rec old_vars_in_term
    (acc : VarinfoSet.t)
    (in_old : bool)
    (term : term) : VarinfoSet.t =
  match term.term_node with
  | TConst _
  | TSizeOf _
  | TSizeOfStr _
  | TAlignOf _
  | Tnull
  | Ttype _ ->
      acc
  | TLval lval
  | TAddrOf lval
  | TStartOf lval ->
      old_vars_in_term_lval acc in_old lval
  | TSizeOfE t
  | TAlignOfE t
  | TUnOp (_, t)
  | TCast (_, _, t)
  | Tbase_addr (_, t)
  | Toffset (_, t)
  | Tblock_length (_, t)
  | Ttypeof t ->
      old_vars_in_term acc in_old t
  | TBinOp (_, t1, t2)
  | TUpdate (t1, _, t2) ->
      old_vars_in_term (old_vars_in_term acc in_old t1) in_old t2
  | Tif (p, t1, t2) ->
      old_vars_in_term
        (old_vars_in_term (old_vars_in_term acc in_old p) in_old t1)
        in_old
        t2
  | Tat (inner, label) ->
      old_vars_in_term acc (in_old || is_old_like_label label) inner
  | Tapp (_, _, terms)
  | TDataCons (_, terms)
  | Tunion terms
  | Tinter terms ->
      List.fold_left (fun set t -> old_vars_in_term set in_old t) acc terms
  | Tlet (binding, body) ->
      let acc' =
        match binding.l_body with
        | LBterm t -> old_vars_in_term acc in_old t
        | _ -> acc
      in
      old_vars_in_term acc' in_old body
  | Tlambda (_, body) ->
      old_vars_in_term acc in_old body
  | Trange (t1, t2) ->
      let acc' =
        match t1 with
        | Some t -> old_vars_in_term acc in_old t
        | None -> acc
      in
      (match t2 with
       | Some t -> old_vars_in_term acc' in_old t
       | None -> acc')
  | Tempty_set
  | Tcomprehension _ ->
      acc

and old_vars_in_term_lval
    (acc : VarinfoSet.t)
    (in_old : bool)
    ((host, offset) : term_lval) : VarinfoSet.t =
  let acc' =
    match host with
    | TVar lv when in_old -> add_old_var_from_logic_var acc lv
    | TVar _ -> acc
    | TMem t -> old_vars_in_term acc in_old t
    | TResult _ -> acc
  in
  old_vars_in_term_offset acc' in_old offset

and old_vars_in_term_offset
    (acc : VarinfoSet.t)
    (in_old : bool)
    (offset : term_offset) : VarinfoSet.t =
  match offset with
  | TNoOffset -> acc
  | TField (_, offset)
  | TModel (_, offset) ->
      old_vars_in_term_offset acc in_old offset
  | TIndex (term, offset) ->
      old_vars_in_term_offset (old_vars_in_term acc in_old term) in_old offset

and old_vars_in_predicate
    (acc : VarinfoSet.t)
    (in_old : bool)
    (pred : predicate) : VarinfoSet.t =
  match pred.pred_content with
  | Ptrue
  | Pfalse ->
      acc
  | Papp (_, _, terms)
  | Pseparated terms ->
      List.fold_left (fun set t -> old_vars_in_term set in_old t) acc terms
  | Pvalid (_, t)
  | Pvalid_read (_, t)
  | Pinitialized (_, t)
  | Pdangling (_, t)
  | Pallocable (_, t)
  | Pfreeable (_, t)
  | Pobject_pointer (_, t)
  | Pvalid_function t ->
      old_vars_in_term acc in_old t
  | Pfresh (_, _, t1, t2)
  | Prel (_, t1, t2) ->
      old_vars_in_term (old_vars_in_term acc in_old t1) in_old t2
  | Pand (p1, p2)
  | Por (p1, p2)
  | Pxor (p1, p2)
  | Pimplies (p1, p2)
  | Piff (p1, p2) ->
      old_vars_in_predicate (old_vars_in_predicate acc in_old p1) in_old p2
  | Pnot p ->
      old_vars_in_predicate acc in_old p
  | Pif (p, p1, p2) ->
      old_vars_in_predicate
        (old_vars_in_predicate (old_vars_in_term acc in_old p) in_old p1)
        in_old
        p2
  | Pat (inner, label) ->
      old_vars_in_predicate acc (in_old || is_old_like_label label) inner
  | Plet (binding, p) ->
      let acc' =
        match binding.l_body with
        | LBterm t -> old_vars_in_term acc in_old t
        | LBpred pred -> old_vars_in_predicate acc in_old pred
        | _ -> acc
      in
      old_vars_in_predicate acc' in_old p
  | Pforall (_, p)
  | Pexists (_, p) ->
      old_vars_in_predicate acc in_old p

let make_harness_func fdec behavs =
  let is_default_behavior b = Cil.is_default_behavior b in
  let assumes, asserts =
    match behavs with
    | [b] ->
        (b.b_requires, List.map snd b.b_post_cond)
    | _ ->
        let named_behaviors = List.filter (fun b -> not (is_default_behavior b)) behavs in
        if named_behaviors <> [] then
          Kernel.fatal ~current:true
            "AcTa does not support multiple or named behaviors in harness generation yet";
        let default_behaviors = List.filter is_default_behavior behavs in
        let requires = List.concat_map (fun b -> b.b_requires) default_behaviors in
        let posts = List.concat_map (fun b -> List.map snd b.b_post_cond) default_behaviors in
        (requires, posts)
  in
  let old_vars =
    List.fold_left
      (fun set ip -> old_vars_in_predicate set false ip.ip_content.tp_statement)
      VarinfoSet.empty
      asserts
    |> VarinfoSet.elements
  in
  let return_type =
    match fdec.svar.vtype.tnode with
    | TFun (ret, _, _) -> ret
    | _ -> fdec.svar.vtype
  in
  {
    name = Format.sprintf "acta_harness_%s" fdec.svar.vorig_name;
    called_func = fdec.svar.vorig_name;
    assumes;
    asserts;
    params = fdec.sformals;
    old_vars;
    return_type;
  }

let get_type_decl_string typ =
  Format.asprintf "%a" Printer.pp_typ typ

let get_var_decl_string vi =
  Printf.sprintf "%s %s" (get_type_decl_string vi.vtype) vi.vname

class acsl2cbmc =
  object (self)
    inherit Visitor.frama_c_inplace

    val mutable curr_func = None
    val mutable hf_list = []

    method translate file =
      ignore
        (Visitor.visitFramacFileSameGlobals
           (self :> Visitor.frama_c_inplace)
           file);
      { harness_functions = List.rev hf_list }

    method! vglob_aux = function
      | GFun (f, _) ->
          curr_func <- Some f;
          Cil.DoChildren
      | _ -> Cil.SkipChildren

    method! vfunc _ =
      Cil.SkipChildren

    method! vspec s =
      if s.spec_behavior <> [] then (
        match curr_func with
        | Some f -> hf_list <- make_harness_func f s.spec_behavior :: hf_list
        | None -> ()
      );
      Cil.SkipChildren
  end

class cbmc_print out =
  object (self)
    method private result_string fname =
      fname ^ "_result"

    method private print_newline =
      Format.fprintf out "@,"

    method private print_header =
      Format.fprintf out "void __CPROVER_assume(_Bool);@,";
      Format.fprintf out "void __CPROVER_assert(_Bool, const char *);@,@,"

    method private print_param_decls hf =
      match hf.params with
      | [] -> ()
      | params ->
          Format.fprintf out "// Harness parameters are left symbolic for CBMC.@,";
          List.iter
            (fun vi -> Format.fprintf out "%s;@," (get_var_decl_string vi))
            params

    method private print_require_assumes hf =
      match hf.assumes with
      | [] -> ()
      | assumes ->
          Format.fprintf out "// requires -> __CPROVER_assume@,";
          List.iter
            (fun ip ->
              Format.fprintf out "__CPROVER_assume(%a);@,"
                Printer.pp_predicate_node
                ip.ip_content.tp_statement.pred_content)
            assumes

    method private print_old_snapshots hf =
      match hf.old_vars with
      | [] -> ()
      | vars ->
          Format.fprintf out "// Pre-state snapshots used by ensures.@,";
          List.iter
            (fun vi ->
              Format.fprintf out "%s %s_old = %s;@,"
                (get_type_decl_string vi.vtype)
                vi.vname
                vi.vname)
            vars

    method private print_function_call hf =
      let params = String.concat ", " (List.map (fun vi -> vi.vname) hf.params) in
      match hf.return_type.tnode with
      | TVoid ->
          Format.fprintf out "%s(%s);@,@," hf.called_func params
      | _ ->
          Format.fprintf out "%s %s = %s(%s);@,@,"
            (get_type_decl_string hf.return_type)
            (self#result_string hf.called_func)
            hf.called_func
            params

    method private print_ensure_asserts hf =
      match hf.asserts with
      | [] -> ()
      | asserts ->
          Format.fprintf out "// ensures -> __CPROVER_assert@,";
          List.iter
            (fun ip ->
              Format.fprintf out "__CPROVER_assert(%a, \"ensures\");@,"
                Printer.pp_predicate_node
                ip.ip_content.tp_statement.pred_content)
            asserts

    method print_harness hf =
      let old_printer = Printer.current_printer () in
      let new_printer =
        (module HarnessPrinter.Make (struct
          let name = hf.called_func
        end) : Printer.PrinterExtension)
      in
      let print_body hf =
        self#print_header;
        Format.fprintf out "@[<v>void %s(void)@,@[<v 2>{@," hf.name;
        self#print_param_decls hf;
        self#print_newline;
        self#print_require_assumes hf;
        self#print_newline;
        self#print_old_snapshots hf;
        self#print_newline;
        self#print_function_call hf;
        self#print_ensure_asserts hf;
        Format.fprintf out "@]@,}@,@]"
      in
      try
        Printer.update_printer new_printer;
        (HarnessPrinter.with_print_cil_as_is
           (Kernel.Unicode.without_unicode print_body))
          hf;
        Printer.set_printer old_printer
      with exn ->
        Printer.set_printer old_printer;
        raise exn
  end
