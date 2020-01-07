open Pacomb
open Lex
open Pos
open Grammar
(* this example illustrates various features:
   - extensible grammars
   - dependant sequences to deal with priorities (necessary for extensibility
   - error reporting


Here is an example of accepted input:

x ++ y priority 6 left associative = (x+y)/2
-- x priority 1 = x - 1
++ x priority 1 = x + 1
a = 2
b(x) = sin(x) + cos(x)
c = a ++ b(a)
c + 5
*)

(* type of expressions *)
type expr =
  | Cst of float
  | Idt of string * expr array

(* and the values inthe environment *)
type func =
  | Def of (expr*string array)
  | Op0 of float
  | Op1 of (float -> float)
  | Op2 of (float -> float -> float)
  | Op3 of (float -> float -> float -> float)

(* The initial environment *)
let init_env =[(("^",2)  , (Op2 ( ** )))
              ;(("*",2)  , (Op2 ( *. )))
              ;(("/",2)  , (Op2 ( /. )))
              ;(("+",2)  , (Op2 ( +. )))
              ;(("-",2)  , (Op2 ( -. )))
              ;(("-",1)  , (Op1 (fun x -> -. x)))
              ;(("+",1)  , (Op1 (fun x -> x)))
              ;(("e",0)  , (Op0 (exp 1.0)))
              ;(("exp",1), (Op1 (exp )))
              ;(("log",1), (Op1 (log )))
              ;(("pi",0) , (Op0 (acos(-1.0))))
              ;(("cos",1), (Op1 (cos )))
              ;(("sin",1), (Op1 (sin )))
              ;(("tan",1), (Op1 (tan )))
              ]

let env =
  let e = Hashtbl.create 32 in
  List.iter (fun (k,d) -> Hashtbl.add e k d) init_env;
  e

exception Unbound of string * int

(* and the evaluation function *)
let rec eval env = function
  | Cst x -> x
  | Idt(id,args) ->
     try
       let args = Array.map (eval env) args in
       let f = Hashtbl.find env (id,Array.length args) in
       match f with
       | Def(f,params) ->
          let add i id = Hashtbl.add env (id,0) (Op0 args.(i)) in
          let remove _ id = Hashtbl.remove env (id,0) in
          Array.iteri add params;
          (try
            let r = eval env f in
            Array.iteri remove params; r
          with
            e -> Array.iteri remove params; raise e)
       | Op0(x) -> x
       | Op1(f) -> f args.(0)
       | Op2(f) -> f args.(0) args.(1)
       | Op3(f) -> f args.(0) args.(1) args.(2)

     with Not_found -> raise (Unbound (id, Array.length args))

(* parser for identifier, notice the error construct to report error messages,
   using regular expressions *)
let%parser ident = (id::RE("[a-zA-Z][a-zA-Z0-9_]*")) => id
                 ; ERROR("ident")

(* tables giving the syntax class of each symbol *)
type assoc = RightAssoc | LeftAssoc | NonAssoc

let cs = Charset.(from_string "-&~^+=*/\\$!:")

let infix_tbl =
  let t = Word_list.create ~cs () in
  Word_list.add_ascii t "^" ("^", 2.0, RightAssoc);
  Word_list.add_ascii t "*" ("*", 4.0, LeftAssoc);
  Word_list.add_ascii t "/" ("/", 4.0, LeftAssoc);
  Word_list.add_ascii t "+" ("+", 6.0, LeftAssoc);
  Word_list.add_ascii t "-" ("-", 6.0, LeftAssoc);
  t

let prefix_tbl =
  let t = Word_list.create ~cs () in
  Word_list.add_ascii t "+" ("+", 5.0);
  Word_list.add_ascii t "-" ("-", 5.0);
  t

(* parser for symbols, it uses Lex.give_up to reject some rule from the action
   code. *)
let%parser op =
  (c::RE("[-&~^+=*/\\$!:]+\\(_[a-zA-Z0-9_]+\\)?"))
    => (if c = "=" then give_up ~msg:"= not valid as op bin" (); c)
; (ERROR "symbol")

(* parser for infix symbol parametrized with the maximum and minimum
   priority. It returns the actual priority, minum eps for left and non
   associative symbols *)

let eps = 1e-10

let%parser infix pmin pmax =
  ((c,p,a)::Word_list.word infix_tbl) =>
        let good = match a with
          | NonAssoc   -> pmin < p && p < pmax
          | LeftAssoc  -> pmin <= p && p < pmax
          | RightAssoc -> pmin < p && p <= pmax
        in
        if not good then give_up ();
        let p = match a with
          | RightAssoc -> p
          | _          -> p -. 1e-10
        in
        (p,c)

(* parser for prefix symbol *)
let%parser prefix pmax =
  ((c,p)::Word_list.word prefix_tbl) =>
        let good = p <= pmax in
        if not good then give_up ();
        (p,c)

(* some keywords *)
let%parser opening = '(' => (); ERROR "closing parenthesis"
let%parser closing = ')' => (); ERROR "closing parenthesis"
let%parser comma   = ',' => (); ERROR "comma"

(* parser for expressions, using dependant sequence.  when writing
   (p,x)>:grammar in a rule, p can be used in the rest of the rule while x can
   only be used in the rest of the grammar.

   Like infix and prefix, expression are parametrized with a priority (here a
   maximum and we use the priorities returned by the parsing of expressions,
   infix and prefix to deal with priority of whats coming next.
 *)
let%parser rec
 expr pmax = ((pe,e1)>:expr pmax) ((pop,b)>:infix pe pmax)
               ((__,e2)::expr pop)            =>  (pop, Idt(b,[|e1;e2|]))
            ; ((pop,b)>:prefix pmax)
               ((__,e1)::expr pop)            =>  (pop, Idt(b,[|e1|]))
            ; (x::FLOAT)                      => (0.0,Cst x)
            ; opening (e::expr_top) closing   => (0.0,e)
            ; (id::ident) (args::args)        => (0.0, Idt(id,args))

(* the ppx extension has syntactic sugar for option and sequences.
   ~+ [comma] grammar denotes non empty lists with separator. *)
and args =
    ()                                        => [||]
  ; opening (l:: ~+ [comma] expr_top) closing => Array.of_list l

and expr_top = ((__,e)::expr 1000.0)          => e

(* here we define the keywords for parsing symbol definitions *)
let%parser assoc = "none"   => NonAssoc
                 ; "left"   => LeftAssoc
                 ; "right"  => RightAssoc
                 ; ERROR("assoc: none | left | right")

let%parser priority = (x::FLOAT) => x
                    ; ERROR("float")

let%parser eq = '=' => () ; ERROR("=")
let%parser priority_kwd = "priority" => (); ERROR("priority keyword")
let%parser assoc_kwd = "associative" => (); ERROR("associative keyword")

(* list of parameters for definition of functions *)
let%parser params =
    ()                                     => [||]
  ; opening (l:: ~+ [comma] ident) closing => Array.of_list l

(* toplevel commands *)
let%parser cmd =
    (e::expr_top) EOF
      => (Printf.printf "%f\n%!" (eval env e))
  ; (id::ident) (params::params) eq (e::expr_top) EOF
      => Hashtbl.add env (id,Array.length params) (Def(e,params))
  ; (id::op) (a1::ident)
       priority_kwd (p::priority)
       eq (e::expr_top) EOF
      => (let params = [|a1|] in
         Hashtbl.add env (id,Array.length params) (Def(e,params));
         Word_list.add_ascii prefix_tbl id (id,p))
  ; (a1::ident) (id::op) (a2::ident)
       priority_kwd (p::priority)
       (a::assoc) assoc_kwd
       eq (e::expr_top) EOF
      => (let params = [|a1;a2|] in
         Hashtbl.add env (id,Array.length params) (Def(e,params));
         Word_list.add_ascii infix_tbl id (id,p,a))

(* blanks *)
let blank = Blank.from_charset (Charset.singleton ' ')

(* main loop *)
let _ =
  try
    while true do
      let f () =
        try
          Printf.printf "=> %!";
          let line = input_line stdin in
          parse_string cmd blank line
        with Unbound(s,n) ->
          Printf.eprintf "unbound %s with arity %d\n%!" s n
      in handle_exception ~error:(fun _ -> ()) f ()
    done
  with
    End_of_file -> ()
