open Pp

let solution_file = "/workspace/Solution.v"
let ocaml_compiler = "ocamlc"
let driver_file = "driver.ml"

let format_msg =
  let re = Str.regexp_string "\n" in
  Str.global_replace re "<:LF:>" 

let display tag msg =
  Feedback.msg_notice (str (Printf.sprintf "\n<%s::>%s\n" tag (format_msg msg)))

let stop_on_failure_flag = ref true

type group = {
  tag : string;
  start_time : float
}

let stop_on_failure v = stop_on_failure_flag := v <> 0

let mk_group tag t = { tag = tag; start_time = t }

let group_stack = Summary.ref ~name:"open_groups" ([] : group list)

let rec end_group tag =
  let e = Unix.gettimeofday() in
  match !group_stack with 
  | [] -> CErrors.user_err (str "No open groups")
  | {tag = "IT"} :: g :: gs when tag <> "IT" ->
    end_group "IT"; end_group tag
  | g :: gs ->
    if g.tag <> tag then CErrors.user_err (str "Ending incorrect group");
    group_stack := gs;
    display "COMPLETEDIN" (Printf.sprintf "%.2f" ((e -. g.start_time) *. 1000.))

let begin_group tag name =
  let t = Unix.gettimeofday() in
  let () =
    match !group_stack with
    | {tag = "IT"} :: _ when tag = "IT" -> end_group "IT"
    | _ -> () in
  group_stack := mk_group tag t :: !group_stack;
  display tag name

let rec end_all_groups () =
  match !group_stack with
  | [] -> ()
  | {tag = tag} :: gs -> end_group tag; end_all_groups ()

let passed = display "PASSED"

let failed msg = 
  display "FAILED" msg;
  if !stop_on_failure_flag then begin
    end_all_groups ();
    CErrors.user_err (str msg)
  end

let locate r =
  try
    let gr = Smartlocate.locate_global_with_alias r in
    (gr, Globnames.printable_constr_of_global gr)
  with Not_found -> CErrors.user_err (str "Not found: " ++ Libnames.pr_qualid r)
  
let test_type ?(msg = "Type Test") r c_ty =
  let env = Global.env() in
  let sigma = Evd.from_env env in
  let tm = EConstr.of_constr (snd (locate r)) in
  let sigma, expected_ty = Constrintern.interp_constr_evars env sigma c_ty in
  let actual_ty = Retyping.get_type_of ~lax:true env sigma tm in
  match Reductionops.infer_conv env sigma actual_ty expected_ty with
  | Some _ -> passed msg
  | None ->
    let p_actual = Printer.pr_econstr_env env sigma actual_ty in
    let p_expected = Printer.pr_econstr_env env sigma expected_ty in
    failed (Printf.sprintf "%s\nActual type = %s\nExpected type = %s"
              msg (string_of_ppcmds p_actual) (string_of_ppcmds p_expected))
    (* CErrors.user_err (str "Incorrect Type: " ++ Printer.pr_econstr_env env sigma tm) *)

(* Based on the PrintAssumptions code from vernac/vernacentries.ml *)
let assumptions r =
  try
    let gr = Smartlocate.locate_global_with_alias r in
    let cstr = Globnames.printable_constr_of_global gr in
    let st = Conv_oracle.get_transp_state (Environ.oracle (Global.env())) in
    Assumptions.assumptions st gr cstr
  with Not_found -> CErrors.user_err (str "Not found: " ++ Libnames.pr_qualid r)

let locate_constant r =
  try
    let gr = Smartlocate.locate_global_with_alias r in
    match gr with
    | Globnames.ConstRef cst -> cst
    | _ -> CErrors.user_err (str "A constant is expected: " ++ Printer.pr_global gr)
  with Not_found -> CErrors.user_err (str "Not found: " ++ Libnames.pr_qualid r)

let pr_axiom env sigma ax ty =
  match ax with
  | Printer.Constant kn -> 
    Printer.pr_constant env kn ++ str " : " ++ Printer.pr_ltype_env env sigma ty
  | _ -> str "? : "  ++ Printer.pr_ltype_env env sigma ty

let test_axioms ?(msg = "Axiom Test") c_ref ax_refs = 
  let env = Global.env() in
  let sigma = Evd.from_env env in
  let ax_csts = List.map locate_constant ax_refs in
  let ax_objs = List.map (fun c -> Printer.Axiom (Printer.Constant c, [])) ax_csts in
  let ax_set = Printer.ContextObjectSet.of_list ax_objs in
  let assums = assumptions c_ref in
  let iter t ty axioms =
    match t with
    | Printer.Axiom (ax, _) ->
      if Printer.ContextObjectSet.mem t ax_set then axioms
      else begin
        let p_axiom = pr_axiom env sigma ax ty in
        string_of_ppcmds p_axiom :: axioms
      end
    | _ -> axioms
  in
  let axioms = Printer.ContextObjectMap.fold_left iter assums [] in
  match axioms with
  | [] -> passed msg
  | _ -> failed (Printf.sprintf "%s\nProhibited Axioms: %s" msg (String.concat "\n" axioms))

(** Tests that the file size is less than a given number *)
let test_file_size ?(fname = solution_file) size =
  try
    let stats = Unix.stat fname in
    if stats.Unix.st_size < size then
      passed (Format.sprintf "Size %d < %d" stats.Unix.st_size size)
    else begin
      let msg = Format.sprintf "Size %d >= %d" stats.Unix.st_size size in 
      failed msg
    end
  with Unix.Unix_error _ -> CErrors.user_err (str ("Bad file name: " ^ fname))

(** Tests that the file's content matches a given regular expression *)
let test_file_regex ?(fname = solution_file) match_flag regex =
  let re = Str.regexp regex in
  let ic = open_in fname in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  let () = close_in ic in
  let matched = try ignore (Str.search_forward re s 0); true
                with Not_found -> false in
  if matched = match_flag then
    passed "OK"
  else
    failed "Bad match"

let run_system_command ?(err_msg = "Failed") args =
  let cmd = String.concat " " args in
  Printf.printf "Running: %s" cmd;
  match Unix.system (cmd ^ " 2>&1") with
  | Unix.WEXITED 0 -> true
  | _ -> (failed err_msg; false)

let write_file fname str =
  let oc = open_out fname in
  Printf.fprintf oc "%s" str;
  close_out oc

(** Compiles and runs the given OCaml source files *)
let compile_and_run files ?(options = "") driver_code =
  write_file driver_file driver_code;
  if run_system_command ~err_msg:"Compilation failed" ([ocaml_compiler; options] @ files @ [driver_file]) then begin
    passed "OK";
    if run_system_command ["./a.out"] then passed "OK"
  end
