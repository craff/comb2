(** Dependant association list *)

(* extensible type of key used for elimination of left recursion,
   see elim_left_rec below *)
type _ ty =  ..
type ('a,'b) eq = NEq : ('a, 'b) eq | Eq : ('a, 'a) eq
type 'a key = { k : 'a ty; eq : 'b.'b ty -> ('a,'b) eq }

type t = Nil : t | Cons : 'a key * 'a * t -> t

let new_key : type a. unit -> a key = fun () ->
  let module M = struct type _ ty += T : a ty end in
  let open M in
  let eq : type b. b ty -> (a, b) eq = function T -> Eq | _ -> NEq in
  { k = T; eq }

let empty = Nil

let add : 'a key -> 'a -> t -> t = fun k x l -> Cons(k,x,l)

let find : type a.a key -> t -> a = fun k l ->
  let rec fn : t -> a = function
    | Nil -> raise Not_found
    | Cons(k',x,l) ->
       match k'.eq k.k with
       | Eq -> x
       | NEq -> fn l
  in fn l

let mem : type a.a key -> t -> bool = fun k l ->
  let rec fn : t -> bool = function
    | Nil -> false
    | Cons(k',_,l) ->
       match k'.eq k.k with
       | Eq -> true
       | NEq -> fn l
  in fn l
