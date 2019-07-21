open Asttypes
open Parsetree
open Ast_mapper
open Ast_helper
open Longident
open Location

let grmod s = Exp.ident (Location.mknoloc (Ldot(Lident "Grammar",s)))
let lxmod s = Exp.ident (Location.mknoloc (Ldot(Lident "Lex",s)))
let rgmod s = Exp.ident (Location.mknoloc (Ldot(Lident "Regexp",s)))

let unit_ = Exp.construct (Location.mknoloc (Lident "()")) None

let app f x = Exp.apply f [(Nolabel, x)]
let app2 f x y = Exp.apply f [(Nolabel, x);(Nolabel, y)]

let has_ident id e =
  let found = ref false in
  let mapper =
    { default_mapper with
      expr = (fun mapper exp ->
        match exp.pexp_desc with
        | Pexp_ident { txt = (Lident id'); _} when id' = id ->
           found := true; exp
        | _ -> default_mapper.expr mapper exp)
    }
  in
  let _ = mapper.expr mapper e in
  !found

let exp_to_grammar ?name_param exp =
  let lexify exp =
    match exp.pexp_desc with
    | Pexp_constant (Pconst_char _) ->
       app (grmod "term") (app2 (lxmod "char") exp unit_)
    | Pexp_constant (Pconst_string _) ->
       app (grmod "term") (app2 (lxmod "string") exp unit_)
    | Pexp_construct({txt = Lident "INT"; _}, None) ->
       app (grmod "term") (app (lxmod "int") unit_)
    | Pexp_construct({txt = Lident "FLOAT"; _}, None) ->
       app (grmod "term") (app (lxmod "float") unit_)
    | Pexp_construct({txt = Lident "RE"; _}, Some s) ->
       app (grmod "term") (app (lxmod "regexp")
                             (app (rgmod "from_string") s))
    | Pexp_apply({ pexp_desc = Pexp_ident { txt = Lident("="|"<"|">"|"<="|">="); _ }; _}, _) ->
       app (grmod "test") exp
    | _ -> exp
  in
  let item e =  match e.pexp_desc with
    | Pexp_construct
      ( { txt = Lident "::"; _}
      , Some({pexp_desc =
                Pexp_tuple
                  [ {pexp_desc = Pexp_ident {txt = Lident name; loc}; _}
                  ; exp ]; _})) ->
       (Some (mkloc name loc),lexify exp)
    | _ ->
       (None, lexify e)
  in
  let items e = match e.pexp_desc with
    | Pexp_apply(e1, args) ->
       let l = e1 :: List.map snd args in
       List.map item l
    | Pexp_construct({txt = Lident "()"; _}, None) ->
       [None, app (grmod "empty") unit_]
    | _ -> [item e]
  in
  let rec rules e = match e.pexp_desc with
    | Pexp_apply
      ( { pexp_desc = Pexp_ident {txt = Lident "=>"; _}; _ }
      , [(Nolabel,rule);(Nolabel,action)]) ->
       let rule = items rule in
       let fn (exp, rule) (name, item) = match name with
         | None    -> (exp, (false, false, false, item) :: rule)
         | Some id ->
            let id_rpos = mkloc (id.txt ^ "_rpos") id.loc in
            let (exp,rpos) =
              if has_ident id_rpos.txt action then
                (Exp.fun_ Nolabel None (Pat.var id_rpos) exp, true)
              else (exp, false)
            in
            let (exp,has_id) =
              if has_ident id.txt action then
                (Exp.fun_ Nolabel None (Pat.var id) exp, true)
              else
                (exp, false)
            in
            let id_lpos = mkloc (id.txt ^ "_lpos") id.loc in
            let (exp,lpos) =
              if has_ident id_lpos.txt action then
                (Exp.fun_ Nolabel None (Pat.var id_lpos) exp, true)
              else
                (exp, false)
            in
            (exp, (lpos,has_id,rpos,item) :: rule)
       in
       let (action, rule) = List.fold_left fn (action, []) rule in
       let rule = List.rev rule in
       let action = app  (grmod "empty") action in
       let fn (lpos,has_id,rpos,item) exp =
         let f = match (lpos,has_id,rpos) with
           | false, false, false -> "seq2"
           | false, true , false -> "seqf"
           | true , false, false -> "seq2_lpos"
           | true , true , false -> "seqf_lpos"
           | false, false, true  -> "seq2_rpos"
           | false, true , true  -> "seqf_rpos"
           | true , false, true  -> "seq2_pos"
           | true , true , true  -> "seqf_pos"
         in
         app2 (grmod f) item exp
       in
       let rule = List.fold_right fn rule action in
       [rule]
    | Pexp_apply
      ( { pexp_desc = Pexp_ident {txt = Lident "<"; _}; _ }
      , [_;_]) when name_param <> None ->
       let rec fn exp = match exp.pexp_desc with
         | Pexp_apply
           ( { pexp_desc = Pexp_ident {txt = Lident "<"; _}; _ }
           , [(Nolabel, x);(Nolabel, y)]) ->
            y :: fn x
         | _ -> [exp]
       in
       let prios = fn e in
       let (name,param) =
         match name_param with None -> assert false
                       | Some x -> x
       in
       let rec gn acc l =
         match l with
         | x::(y::_ as l) ->
            let e =
              app2 (grmod "seq2")
                (app (grmod "test") (app2 (Exp.ident (mknoloc (Lident "=")))
                                     (Exp.ident param) x))
                (app (Exp.ident name) y)
            in gn (e::acc) l
         | [] | [_] -> acc
       in
       gn [] prios
    | Pexp_sequence(e1,e2) ->
       rules e1 @ rules e2
    | _ -> raise Exit
  in
  let fail = app (grmod "fail") unit_ in
  let fn rule exp = app2 (grmod "alt") rule exp in
  try List.fold_right fn (rules exp) fail
  with Exit -> exp

let str_to_grammar str =
  match str with
  | [{pstr_desc = Pstr_eval(e,_); _}] ->
     exp_to_grammar e
  | _              -> Exp.extension
                        (extension_of_error
                           (Location.error ~loc:(List.hd str).pstr_loc "shoud be an expression"))

let str_to_parser items =
  let fn item =
    match item.pstr_desc with
    | Pstr_value(rec_,ls) ->
       let gn vb =
         let name = match vb.pvb_pat.ppat_desc with
           | Ppat_var s -> s
           | _          -> exit 1
         in
         let (param,exp) = match vb.pvb_expr.pexp_desc with
           | Pexp_fun (Nolabel, None, { ppat_desc = Ppat_var param; _ }, exp) ->
             (Some param, exp)
           | _ -> (None, vb.pvb_expr)
         in
         let name_param = match param with
           | None -> None
           | Some p -> Some ( mkloc (Lident name.txt) name.loc
                            , mkloc (Lident p.txt) p.loc)
         in
         let rules = exp_to_grammar ?name_param exp in
         let rules =
           if List.exists (fun (s,_) -> s.txt = "cached") vb.pvb_attributes then
             app (grmod "cache") rules
           else rules
         in
         (name,param,rules)
       in
       let ls = List.map gn ls in
       begin match rec_ with
       | Nonrecursive ->
         let definitions =
           let gn (name, param, rules) =
             if param <> None then exit 1; (* FIXME *)
             Str.value Nonrecursive
               [Vb.mk (Pat.var name) rules]
           in
           List.map gn ls
         in
         definitions
       | Recursive ->
          let set name = "set__grammar__" ^ name.txt in
          let declarations =
            let gn (name, param, _) =
              let vd =
                match param with
                | None ->
                   Vb.mk (Pat.var name)
                     (app (grmod "declare_grammar") (Exp.constant (Const.string name.txt)))
                | Some _ ->
                   Vb.mk (Pat.tuple [Pat.var name; Pat.var (mkloc (set name) name.loc)])
                     (app (grmod "grammar_family") (Exp.constant (Const.string name.txt)))
              in
              Str.value Nonrecursive [vd]
            in
            List.map gn ls
         in
         let definitions =
           let fn (name, param, rules) =
             let exp =
               match param with
               | None ->
                  app2 (grmod "set_grammar")
                    (Exp.ident (Location.mkloc (Lident name.txt) name.loc))
                    rules
               | Some n ->
                  app
                    (Exp.ident (Location.mkloc (Lident (set name)) name.loc))
                    (Exp.fun_ Nolabel None (Pat.var n) rules)
             in
             Str.value Nonrecursive [Vb.mk (Pat.any ()) exp]
           in
           List.map fn ls
         in
         declarations @ definitions
       end
    | _              -> [item]
  in
  let items = List.flatten (List.map fn items) in
  Str.include_ { pincl_mod = Mod.structure items
               ; pincl_loc = Location.none
               ; pincl_attributes = [] }


let test_mapper _argv =
  { default_mapper with
    structure_item = (fun mapper item ->
      match item with
      | { pstr_desc = Pstr_extension (({ txt = "parser"; _ }, PStr str), _); _} ->
         str_to_parser str
      | other -> default_mapper.structure_item mapper other)
  ; expr = (fun mapper exp ->
      match exp with
      | { pexp_desc = Pexp_extension ({ txt = "grammar"; _ }, PStr str); _} ->
         str_to_grammar str
      | other -> default_mapper.expr mapper other)

  }

let () =
  register "ppx_test" test_mapper