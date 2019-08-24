(** {1 Lexing: grouping characters before parsing}

    It is traditionnal to do parsing  in two phases (scanning/parsing).  This is
    not necessary  with combinators in  general this  is still true  with Pacomb
    (scannerless). However, this makes the grammar more readable to use a lexing
    phase.

    Moreover,  lexing is  often done  with  a longuest  match rule  that is  not
    semantically equivalent to the semantics of context free grammar.

    This modules  provide combinator  to create terminals  that the  parser will
    call.

    It also provide functions to eliminate "blank" characteres. *)

(** {2 Types and exception} *)
type buf = Input.buffer
type pos = Input.pos

(** A blank function is just a function progressing in a buffer *)
type blank = buf -> pos -> buf * pos

(** Type of terminal function, similar to blank, but with a returned value *)
type 'a lexeme = buf -> pos -> 'a * buf * pos

(** The previous type encapsulated in a record *)
type 'a terminal = { n : string    (** name *)
                   ; f : 'a lexeme (** the terminal itself *)
                   ; c : Charset.t (** the set of characters accepted
                                       at the beginning of input *) }

(** Abbreviation *)
type 'a t = 'a terminal

(** exception when failing,
    - can be raised (but not captured) by terminal
    - can  be raised  (but not  captured)  by action  code in  the grammar,  see
      [Combinator.give_up]
    - will be raise and captured by [Combinator.parse_buffer] that will give the
      most advanced position
 *)
exception NoParse

(** from action ony may give an error message when rejecting a rule *)
exception Give_up of string

(** [give_up ()] rejects parsing from a corresponding semantic action.
    Can be used both in the semantics of terminals and parsing rules. *)
val give_up : ?msg:string -> unit -> 'a

(** {2 Combinators to create terminals} *)

(** accept any character, except eof*)
val any : ?name:string -> unit -> char t

(**  Terminal  accepting  then  end  of   a  buffer  only.   remark:  [eof]  is
    automatically added  at the end  of a grammar  by [Combinator.parse_buffer].
    [name] default is ["EOF"] *)
val eof : ?name:string -> 'a -> 'a t

(** Terminal  accepting a  given char,  remark: [char  '\255'] is  equivalent to
    [eof].
    [name] default is the given charater. *)
val char : ?name:string -> char -> 'a -> 'a t

(**  Accept a  character  for  which the  test  returns  [true].
    [name]  default to the result of [Charset.show]. *)
val test : ?name:string -> (char -> bool) -> char t

(** Accept a character in the given charset. [name] default as in [test] *)
val charset : ?name:string -> Charset.t -> char t

(** Reject  the input  (raises [Noparse])  if the first  character of  the input
    passed the  test. Does  not read  the character if  the test  fails.
    [name] default to ["^"] prepended to the result of [Charset.show]. *)
val not_test : ?name:string -> (char -> bool) -> 'a -> 'a t

(** Reject the input  (raises [Noparse]) if the first character  of the input is
    in the charset. Does  not read the character if not  in the charset.
    [name] default as in [not_test] *)
val not_charset : ?name:string -> Charset.t -> 'a -> 'a t

(** Compose  two terminals in sequence.  [name] default is the  concatenation of
    the two names. *)
val seq : ?name:string -> 'a t -> 'b t -> ('a -> 'b -> 'c) -> 'c t

(** variation on the above *)
val seq1 : ?name:string -> 'a t -> 'b t -> 'a t
val seq2 : ?name:string -> 'a t -> 'b t -> 'b t
val seqs : 'a t list -> ('a -> 'a -> 'a) -> 'a t

(** save the part of the input parsed by the terminal *)
val save : ?name:string -> 'a t -> (string -> 'a -> 'b) -> 'b t

(** [alt  t1 t2]  parses the  input with  [t1] or  [t2].  Contrary  to grammars,
    terminals does not use continuations, if  [t1] succeds, no backtrack will be
    performed to try [t2].  For instance,
      {[seq1 (alt (char 'a' ())
                 (seq1 (char 'a' ()) (char 'b' ())))
            (char 'b' ())]}
    will reject "ab".
    If both [t1] and [t2] accept the input, longuest match is selected.
    [name] default to [sprintf "(%s)|(%s)" t1.n t2.n]. *)
val alt : ?name:string -> 'a t -> 'a t -> 'a t
val alts : 'a t list -> 'a t

(** [option x  t] parses the given terminal  0 or 1 time. [x] is  returned if 0.
    [name] defaults to [sprintf "(%s)?" t.n]. *)
val option : ?name:string -> 'a -> 'a t -> 'a t

(** Applies a function to the result  of the given terminal.
    [name] defaults to the terminal name. *)
val appl : ?name:string -> ('a -> 'b) -> 'a t -> 'b t

(** [star t a f] Repetition of a  given terminal 0,1 or more times.  The type of
    function   to  compose   the  action   allows  for   ['b  =   Buffer.t]  for
    efficiency. The returned value  is [f ( ... (f(f (a ())  x_1) x_2) ...) x_n]
    if [t]  returns [x_1] ...  [x_n].
    [name] defaults to  [sprintf "(%s)*" t.n] *)
val star : ?name:string -> 'a t -> (unit -> 'b) -> ('b -> 'a -> 'b) -> 'b t

(** Same as above but parses at least once .*)
val plus : ?name:string -> 'a t -> (unit -> 'b) -> ('b -> 'a -> 'b) -> 'b t

(** [string s] Accepts only the given string.
    Raises [Invalid_argument] if [s = ""].
    [name] defaults to [sprintf "%S" s]. *)
val string : ?name:string -> string -> 'a -> 'a t

(** Parses an integer in base 10. ["+42"] is accepted.
    [name] defaults to ["INT"] *)
val int : ?name:string -> unit -> int t

(** Parses a float in base 10. [".1"] is accepted as ["0.1"]
    [name] defaults to ["FLOAT"] *)
val float : ?name:string -> unit -> float t

(** Parses a char litteral 'c' using ocaml escaping convention
    [name] defaults to ["CHARLIT"] *)
val char_lit : ?name:string -> unit -> char t

(** Parses a string litteral "cccc" using ocaml escaping convention
    [name] defaults to ["STRINGLIT"] *)
val string_lit : ?name:string -> unit -> string t

(** Parses a unicode UTF8 char
    [name] defauls to ["UTF8"] *)
val utf8 : ?name:string -> unit -> Uchar.t t

(** [keyword ~name k cs x = seq ~name (string  k ()) (test f ()) (fun _ _ -> x)]
     usefull to  accept a  keyword only  when not  followed by  an alpha-numeric
     char *)
val keyword : ?name:string -> string -> (char -> bool) -> 'a -> 'a t

(** {2 Functions managing blanks} *)

(** Use when you have no blank chars *)
val noblank : blank

(** Blank from a charset *)
val blank_charset : Charset.t -> blank

(** Blank from a terminal *)
val blank_terminal : 'a t -> blank

(** Test wether a terminal accept the  empty string. Such a terminal are illegal
   in a grammar, but may be used in combinator below to create terminals *)
val accept_empty : 'a t -> bool

(** Test constructor for the test constructor in [Grammar] *)
val test_from_lex : bool t -> buf -> pos -> buf -> pos -> bool
val blank_test_from_lex : bool t -> buf -> pos -> buf -> pos -> bool

type layout_config =
  { old_blanks_before : bool
  (** Ignoring blanks with the old blank function before parsing? *)
  ; new_blanks_before : bool
  (** Then ignore blanks with the new blank function (before parsing)? *)
  ; new_blanks_after  : bool
  (** Use the new blank function one last time before resuming old layout? *)
  ; old_blanks_after  : bool
  (** Use then the old blank function one last time as well? *) }

(** Default configuration,  parsing with the old blanks before  (i.e., the field
    [old_blanks_before] is  [true]), and the  new blanks after (i.e.,  the field
    [old_blanks_after] is also [true]). The other two fields are [false]. *)
val default_layout_config : layout_config

(** where to put it ... *)
val default : 'a -> 'a option -> 'a
