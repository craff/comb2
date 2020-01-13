(* This code is to benchmark extensible grammar ...
   it is not the best code to do a calculator with an extensible grammar *)

open Pacomb

let get_op2 = function
  | "*" -> ( *. )
  | "+" -> ( +. )
  | "/" -> ( /. )
  | "-" -> ( -. )
  | "^" -> ( ** )
  |  _  -> failwith "invalid binary op"

let get_op1 = function
  | "cos" -> cos
  | "sin" -> sin
  | "tan" -> tan
  | "ln"  -> log
  | "exp" -> exp
  |  _  -> failwith "invalid unary op"

(** Bigger float = lower priority, 0.0 is for atomic expresion,
   so all priorities must be positive *)
type prio = float

(** list of all priorities, in decreasing order (lowest priority first). *)
type prios = prio list

(** a parsing rule: a grammar from an environment *)
type 'a rule = env -> 'a Grammar.t

and rules = (float * float rule list) list

(** parsing environment: all rules and all prios sorted in
    decreasing order (lowest priority first). *)
and env = { rules : rules; prios : prios }

let empty_env = { rules = []; prios = [] }

let add_prio p env =
  { env with prios = List.rev (List.sort_uniq compare (p::env.prios)) }

(** get the next priority *)
let next_prio p env =
  let rec fn = function
    | x::(y::_) when x = p -> y
    | x::l                 -> assert (x >= p); fn l
    | _ -> 0.0
  in
  fn env.prios

(** get the priority nearest to p . For associativity,
    we will use [p - epsilon] to get the priority below p,
    and get_prio ill fetch the priority below p *)
let get_prio p env =
  let rec fn = function
    | x::_      when x <= p -> x
    | _::l                  -> fn l
    | _                     -> 0.0
  in
  fn env.prios

(** the maximum priority *)
let max_prio env = match env.prios with
  | x::_ -> x | [] -> 0.0

(** add a rule with the given priority *)
let add_rule prio r env =
  let old = try List.assoc prio env.rules with Not_found ->  [] in
  let rules = (List.filter (fun (p,_) -> prio <> p) env.rules) in
  { env with rules = (prio, r::old) :: rules }

(** get all the rule of a given priority *)
let get_rule : prio -> env -> float Grammar.t = fun p env ->
  let rules = List.assoc p env.rules in
  let rules = List.map (fun r -> r env) rules in
  Grammar.alt rules

let pr (_, p) = Printf.sprintf "%g" p

(** the parsing for expression *)
let%parser [@print_param pr] rec expr env (prio:prio) =
   (* constant *)
   (prio = 0.) (x::FLOAT)                           => x
   (* parenthesis, using max_prio *)
 ; (prio = 0.) '(' (x::expr env (max_prio env)) ')' => x
   (* incluse next priority level *)
 ; (prio > 0.) (x::expr env (next_prio prio env))   => x
   (* get all the rule for the level *)
 ; (prio > 0.) (x::get_rule prio env)               => x

(** a type of type *)
type _ ty =
  Flt : float ty
| Arr : 'a ty * 'b ty -> ('a -> 'b) ty

(** action of a given type , syntaxe, HP style *)
let%parser rec action : type a. a ty -> a Grammar.t
  = fun t ->
    "Cst" (x<:FLOAT) (f::action (Arr(Flt,t))) => f x
  ; (t =| Arr(Flt,t1)) "Op1" (s<:STRING_LIT) (f::action (Arr(Flt,t1))) =>
      (let g = get_op1 s in (fun x -> f (g x) : a))
  ; (t =| Arr(Flt,Arr(Flt,t1))) "Op2" (s<:STRING_LIT) (f::action (Arr(Flt,t1))) =>
      (let g = get_op2 s in (fun x y -> f (g y x) : a))
  ; (t =| Arr(Flt,Flt)) () => (fun x -> x)


(** the magic parsing : parse a BNF rule and return the parser
    for that BNF, parametrized by the current environment *)
(** Remark: we need fake, dependant sequence (<:) because other
    with the construction of the grammar loops producing bigger
    and bigger types. Dependant sequence builds the grammar lazily *)
let%parser rec rule : type a. a ty -> (env -> a Grammar.t) Grammar.t
  = fun t ->
    "Exp" (prio<:FLOAT) (r::rule (Arr(Flt,t))) =>
      (fun env -> (x::expr env (get_prio prio env)) (f::r env) => f x)
  ; "Str" (s<:STRING_LIT) (r::rule t) =>
      (fun env -> (STR s) (x::r env) => x)
  ; "=>" (a::action t) => (fun _ -> () => a)

(** reference use to keep the env in case of parse error *)
let env_ref = ref empty_env

(* A subtlety : we want to parse expression, one by one and print the
   result. Pacomb needs to do things that require buffer examination after
   each token. So printing after parsing the newline does not work.
   A trick that works is to test for the newline, not parsing it,
   using Grammar.test_after. Another solution would be to read each
   line with input_line and use Grammar.parse_string on the result.
*)
let nl _ b i _ _ =
  let (c,_,_) = Input.read b i in c = '\n'

let%parser top_expr env =
  (x::Grammar.test_after nl (expr env (max_prio env))) =>
    Printf.printf "%g\n=> %!" x

(** The command parsing a new rule *)
let%parser new_rule env =
  "rule" (p::FLOAT) ":" (r::Grammar.test_after nl (rule Flt)) =>
       let env = add_rule p r env in
       let env = add_prio p env in
       env_ref := env;
       Printf.printf "new rule accepted\n=> %!";
       (env, ())

(** main parsing, right recursion with no action is ok now *)
let%parser rec cmds env =
    ()                                          => ()
  ; (top_expr env) '\n' (cmds env)              => ()
  ; ((env,()) >: new_rule env) '\n' (cmds env)  => ()

let top = cmds empty_env

(* blanks *)
let blank = Blank.from_charset (Charset.singleton ' ')

let _ =
  try
    while true do
      let f () =
        Printf.printf "=> %!"; (* initial prompt *)
        (* no need to stack the buffer of in_channel and those of Pacomb. So
           file desciptor are preferred. *)
        (* as we parse stdin, we need to keed the whole buffer in memory
           to have line and column number, ~rescan:false only give byte
           position *)
        Grammar.parse_fd ~rescan:false (cmds !env_ref) blank Unix.stdin;
        raise End_of_file
      in
      (* [Pos] module provides a function to handle exception with
         an optional argument to call for error (default is to exit with
         code 1 *)
      Pos.handle_exception ~error:(fun _ -> ()) f ()
    done
  with
    End_of_file -> ()
