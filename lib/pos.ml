(** Functions managing positions *)

(** Type to represent position *)
include Input.Pos

type interval = { start : pos Lazy.t; end_ : pos Lazy.t }

type t = pos Lazy.t

let max_pos p1 p2 =
  if p1.line > p2.line then p1
  else if p1.line < p2.line then p2
  else if p1.col < p2.col then p2
  else p1

let phantom = lazy { name = ""; line = 0; col  = 0; phantom = true }

type style = OCaml | Short

let print_pos ?(style=OCaml) () ch (lazy pos) =
  let open Printf in
  if pos.name = "" then
    let format : (_,_,_) format = match style with
      | OCaml -> "Line %d, character %d"
      | Short -> "%d:%d"
    in
    fprintf ch format pos.line pos.col
  else
    let format : (_,_,_) format = match style with
      | OCaml -> "File %S, line %d, character %d"
      | Short -> "%S:%d:%d"
    in
    fprintf ch format pos.name pos.line pos.col

let print_interval ?(style=OCaml) () ch { start = (lazy start)
                                        ; end_ = (lazy end_) } =
  let open Printf in
  if start.name = "" then
    if start.line = end_.line then
      let format : (_,_,_) format = match style with
        | OCaml -> "line %d, characters %d-%d"
        | Short -> "%d:%d-%d"
      in
      fprintf ch format start.line start.col end_.col
    else
      let format : (_,_,_) format = match style with
        | OCaml -> "line %d, character %d - line %d, character %d"
        | Short -> "%d:%d-%d:%d"
      in
      fprintf ch format start.line start.col end_.line end_.col
  else
    if start.line = end_.line then
      let format : (_,_,_) format = match style with
        | OCaml -> "File %S, line %d, characters %d-%d"
        | Short -> "%S:%d:%d-%d"
      in
      fprintf ch format start.name start.line start.col end_.col
    else
      let format : (_,_,_) format = match style with
        | OCaml -> "File %S, line %d, character %d - line %d, character %d"
        | Short -> "%S:%d:%d-%d:%d"
      in
      fprintf ch format start.name start.line start.col end_.line end_.col

let print_buf_pos ?(style=OCaml) () ch (buf,col) =
  print_pos ~style () ch (get_pos buf col)

(** exception returned by the parser *)
exception Parse_error of Input.buffer * Input.pos * string list

let fail_no_parse (_:exn) = exit 1

(** A helper to handle exceptions *)
let handle_exception ?(error=fail_no_parse) ?(style=OCaml) f a =
  try f a with Parse_error(buf, pos, msgs) as e ->
    let red fmt = "\027[31m" ^^ fmt ^^ "\027[0m%!" in
    Printf.eprintf (red "Parse error: %a.\n%!")
      (print_buf_pos ~style ()) (buf, pos);
    if msgs <> [] then
      begin
        Printf.eprintf "expecting:\n%!";
        List.iter (Printf.eprintf "\t%s\n%!") msgs;
      end;
    error e
