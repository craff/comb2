(** {1 Functions managing positions} *)

(** Type to represent position *)
type pos = { name : string  (** file's name *)
           ; line  : int    (** line number *)
           ; col   : int    (** column number *)
           ; utf8_col : int (** column number with unicode *)
           ; phantom : bool (** is the postion a "phantom", i.e. not really
                                in the file *) }

type interval = { start : pos; end_ : pos }

(** Abbreviation *)
type t = pos

(** a phantom position, used for grammar accepting the empty input *)
val phantom : pos

(** the max of to position (further in the file *)
val max_pos : pos -> pos -> pos

(** if false (the default) [utf8_col] field is set to [-1] by [get_pos] *)
val compute_utf8_col : bool ref

(** Get a position from an input buffer and a column number *)
val get_pos : Input.buffer -> int -> pos

(** Style for printing positions: *)
type style = OCaml (** like OCaml *)
           | Short (** like gcc *)

(** printting for position *)
val print_pos
    : ?utf8_col:bool -> ?style:style -> unit -> out_channel -> pos -> unit

(** and interval *)
val print_interval : ?style:style -> unit -> out_channel -> interval -> unit

(** [print_buf_pos () ch (buf,pos) = print_pos () ch (get_pos buf pos)] *)
val print_buf_pos : ?utf8_col:bool -> ?style:style -> unit -> out_channel
                    -> (Input.buffer * int) -> unit

(** Exception raised by the function below when parsing fails *)
exception Parse_error of Input.buffer * int * string list

(** [handle_exception  fn v] applies  the function [fn]  to [v] and  handles the
    [Parse_error] exception. In  particular, a parse error  message is presented
    to the user  in case of a failure,  then [error e] is called where  e is the
    raised exception.   The default  [error] is  [fun _ ->  exit 1].  [raise] is
    another possibility. *)
val handle_exception : ?utf8_col:bool -> ?error:(exn -> 'b) -> ?style:style
                       -> ('a -> 'b) -> 'a -> 'b
