open Pacomb
open Pos
open Grammar

type sexp = { l: Pos.t; r: Pos.t; e : sexp' }
and sexp' =
  | Idt of string
  | Lst of sexp list

let rec size e = match e.e with
  | Idt _ -> 1
  | Lst l -> List.fold_left (fun a e -> a + size e) 1 l

let id = "[a-zA-Z_][a-zA-Z_0-9]*[']*"
let%parser rec sexp
   = (x::RE id)         => { l = _lpos; r = _rpos; e = Idt x }
   ; '(' (l::sexps) ')' => { l = _lpos; r = _rpos; e = Lst (List.rev l) }
and sexps = () => []
          ; (l::sexps) (e::sexp) => e::l

let blank = Blank.from_charset (Charset.from_string " \t\n\r")

let _ =
  let e = handle_exception (parse_channel sexp blank) stdin in
  Printf.printf "=> %d\n%!" (size e)
