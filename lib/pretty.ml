(* camlp5r *)
(* $Id: pretty.ml,v 1.4 2007/09/17 10:22:31 deraugla Exp $ *)
(* Copyright (c) INRIA 2007 *)

exception GiveUp;

value line_length = ref 78;
value horiz_ctx = ref False;

value after_print s =
  if horiz_ctx.val then
    if String.contains s '\n' || String.length s > line_length.val then
      raise GiveUp
    else s
  else s
;

value sprintf fmt = Printf.kprintf after_print fmt;

value horiz_vertic horiz vertic =
  try Ploc.call_with horiz_ctx True horiz () with
  [ GiveUp -> if horiz_ctx.val then raise GiveUp else vertic () ]
;
