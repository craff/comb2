
(** type of a word list with
    'a : the type of characters (typically, char or Uchar.t)
    'b : a value associated to each word *)
type ('a,'b) t

(** create a ne empty table *)
val create : unit -> ('a,'b) t

(**returns the number of bindings in the table *)
val size : ('a,'b) t -> int

(** [add_string tbl s v] adds a binding from [s] to [v] in [tbl],
    keep all previous bindings.

    a [map] function transforming character before addition (typically
    a case transformer) can be prvided (defaut to identity). *)
val add_string : ?map:(char -> char)
                 -> (char,'b) t -> string -> 'b -> unit

(** [add_string tbl s v] adds a binding from [s] to [v] in [tbl],
    remove all previous bindings *)
val replace_string : ?map:(char -> char)
                     -> (char,'b) t -> string -> 'b -> unit

(** same as above for an unicode string *)
val add_utf8 : ?map:(Uchar.t -> Uchar.t)
               -> (Uchar.t, 'b) t -> string -> 'b -> unit
val replace_utf8 : ?map:(Uchar.t -> Uchar.t)
                   -> (Uchar.t,'b) t -> string -> 'b -> unit

(** parses word from a dictionnary returning as action all
    the assiociated values (it is an ambiguous grammar if
    there is more than one value.

    [final_test] will be called after parsing. It may be used
    typically to ensure that the next character is not alphanumeric.
    Defaults to an always passing test.

    [map] is called on each character before searching in the table,
    typically a case conversion. Defaults to identity.
 *)
val word : ?final_test:(Input.buffer -> Input.pos -> bool)
           -> ?map:(char -> char) -> (char, 'a) t -> 'a Grammar.t

val utf8_word : ?final_test:(Input.buffer -> Input.pos -> bool)
           -> ?map:(Uchar.t -> Uchar.t) -> (Uchar.t, 'a) t -> 'a Grammar.t
