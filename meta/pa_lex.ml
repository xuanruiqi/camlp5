(* camlp4r *)
(* $Id$ *)
(* Copyright (c) INRIA 2007 *)

(* Simplified syntax of parsers of characters streams *)

#load "pa_extend.cmo";
#load "q_MLast.cmo";

open Pcaml;

(**)
value var = "buf";
value add_char loc c cl = <:expr< B.add $cl$ $c$ >>;
value get_buf loc cl = <:expr< B.get $cl$ >>;

(*
value var = "cl";
value add_char loc c cl = <:expr< [$c$ :: $cl$] >>;
value get_buf loc cl = cl;
*)

value fresh_c cl =
  let n =
    List.fold_left
      (fun n c ->
         match c with
         [ <:expr< $lid:_$ >> -> n + 1
         | _ -> n ])
      0 cl
  in
  if n = 0 then "c" else "c" ^ string_of_int n
;

value accum_chars loc cl =
  List.fold_right (add_char loc) cl <:expr< $lid:var$ >>
;

value conv_rules loc rl =
  List.map
    (fun (sl, cl, a) ->
       let a =
         let b = accum_chars loc cl in
         match a with
         [ Some e -> e
         | None -> b ]
       in
       (List.rev sl, None, a))
    rl
;

value mk_lexer loc rl =
  Exparser.cparser loc None (conv_rules loc rl)
;

value mk_lexer_match loc e rl =
  Exparser.cparser_match loc e None (conv_rules loc rl)
;

value isolate_char_patt_list =
  loop [] where rec loop pl =
    fun
    [ [([(Exparser.SpTrm _ p None, None)], [_], None) :: rl] ->
        let p =
          match p with
          [ <:patt< $chr:_$ >> -> p
          | <:patt< ($p$ as $lid:_$) >> -> p
          | p -> p ]
        in
        loop [p :: pl] rl
    | rl -> (List.rev pl, rl) ]
;

value or_patt_of_patt_list loc =
  fun
  [ [p :: pl] -> List.fold_left (fun p1 p2 -> <:patt< $p1$ | $p2$ >>) p pl
  | [] -> invalid_arg "or_patt_of_patt_list" ]
;

value isolate_char_patt loc rl =
  match isolate_char_patt_list rl with
  [ ([] | [_], _) -> (None, rl)
  | (pl, rl) -> (Some (or_patt_of_patt_list loc pl), rl) ]
;

value gcl = ref [];

EXTEND
  GLOBAL: expr;
  expr:
    [ [ "lexer"; rl = rules ->
          let rl =
            match isolate_char_patt loc rl with
            [ (Some p, rl) ->
                let p = <:patt< ($p$ as c) >> in
                let e = <:expr< c >> in
                [([(Exparser.SpTrm loc p None, None)], [e], None) :: rl]
            | (None, rl) -> rl ]
          in
          <:expr< fun $lid:var$ -> $mk_lexer loc rl$ >>
      | "match"; e = expr; "with"; "lexer"; rl = rules ->
          mk_lexer_match loc e rl ] ]
  ;
  expr: LEVEL "simple"
    [ [ "$"; LIDENT "buf" ->
          let b = accum_chars loc gcl.val in
          <:expr< $get_buf loc b$ >>
      | "$"; LIDENT "pos" ->
          <:expr< Stream.count $lid:Exparser.strm_n$ >> ] ]
  ;
  rules:
    [ [ "["; rl = LIST0 rule SEP "|"; "]" -> rl ] ]
  ;
  rule:
    [ [ (sl, cl) = symb_list; a = act -> (sl, cl, a) ] ]
  ;
  symb_list:
    [ [ (sl, cl) = symbs -> do { gcl.val := cl; (sl, cl) } ] ]
  ;
  symbs:
    [ [ (sl, cl) = symbs; "_"; norec = no_rec; errk = err_kont ->
          let (p, cl) =
            if norec then (<:patt< _ >>, cl)
            else
              let c = fresh_c cl in
              (<:patt< $lid:c$ >>, [<:expr< $lid:c$ >> :: cl])
          in
          let s = (Exparser.SpTrm loc p None, errk) in
          ([s :: sl], cl)
      | (sl, cl) = symbs; s = STRING; norec = no_rec; errk = err_kont ->
          let pl =
            let next_char s i =
              if i = String.length s then invalid_arg "next_char"
              else if s.[i] = '\\' then
                if i + 1 = String.length s then ("\\", i + 1)
                else
                  match s.[i+1] with
                  [ '0'..'9' ->
                      if i + 3 < String.length s then
                        (Printf.sprintf "\\%c%c%c" s.[i+1] s.[i+2] s.[i+3],
                         i + 4)
                      else ("\\", i + 1)
                  | c -> ("\\" ^ String.make 1 c, i + 2) ]
              else (String.make 1 s.[i], i + 1)
            in
            loop 0 where rec loop i =
              if i = String.length s then []
              else
                let (c, i) = next_char s i in
                let p = <:patt< $chr:c$ >> in
                let (p, i) =
                  if i < String.length s - 2 && s.[i] = '.' &&
                      s.[i+1] = '.'
                  then
                    let (c, i) = next_char s (i + 2) in
                    (<:patt< $p$ .. $chr:c$ >>, i)
                  else
                    (p, i)
                in
                [p :: loop i]
          in
          match pl with
          [ [] -> (sl, cl)
          | [<:patt< $chr:c$ >>] ->
              let s = (Exparser.SpTrm loc <:patt< $chr:c$ >> None, errk) in
              let cl = if norec then cl else [<:expr< $chr:c$ >> :: cl] in
              ([s :: sl], cl)
          | pl ->
              let c = fresh_c cl in
              let s =
                let p =
                  let p = or_patt_of_patt_list loc pl in
                  if norec then p else <:patt< ($p$ as $lid:c$) >>
                in
                (Exparser.SpTrm loc p None, errk)
              in
              let cl = if norec then cl else [<:expr< $lid:c$ >> :: cl] in
              ([s :: sl], cl) ]
      | (sl, cl) = symbs; (f, po) = simple_expr; errk = err_kont ->
          let s =
            let buf = accum_chars loc cl in
            let e = <:expr< $f$ $buf$ >> in
            let p =
              match po with
              [ Some p -> p
              | None -> <:patt< $lid:var$ >> ]
            in
            (Exparser.SpNtr loc p e, errk)
          in
          ([s :: sl], [])
      | (sl, cl) = symbs; "?="; "["; pll = LIST1 lookahead SEP "|"; "]";
        errk = err_kont ->
          let s = (Exparser.SpLhd loc pll, errk) in
          ([s :: sl], cl)
      | (sl, cl) = symbs; rl = rules; errk = err_kont ->
          match isolate_char_patt loc rl with
          [ (Some p, []) ->
              let c = fresh_c cl in
              let s =
                let p = <:patt< ($p$ as $lid:c$) >> in
                (Exparser.SpTrm loc p None, errk)
              in
              ([s :: sl], [<:expr< $lid:c$ >> :: cl])
          | x ->
              let rl =
                match x with
                [ (Some p, rl) ->
                    let r =
                      let p = <:patt< ($p$ as c) >> in
                      let e = <:expr< c >> in
                      ([(Exparser.SpTrm loc p None, None)], [e], None)
                    in
                    [r :: rl]
                | (None, rl) -> rl ]
              in
              let errk =
                match List.rev rl with
                [ [([], _, _) :: _] -> Some None
                | _ -> errk ]
              in
              let sl =
                if cl = [] then sl
                else
                  let s =
                    let b = accum_chars loc cl in
                    let e = Exparser.cparser loc None [([], None, b)] in
                    (Exparser.SpNtr loc <:patt< $lid:var$ >> e, Some None)
                  in
                  [s :: sl]
              in
              let s =
                let e = mk_lexer loc rl in
                (Exparser.SpNtr loc <:patt< $lid:var$ >> e, errk)
              in
              ([s :: sl], []) ]
      | -> ([], []) ] ]
  ;
  simple_expr:
    [ [ i = LIDENT -> (<:expr< $lid:i$ >>, None)
      | "("; e = expr; ")" -> (e, None)
      | "("; e = expr; "as"; p = patt; ")" -> (e, Some p) ] ]
  ;
  lookahead:
    [ [ pl = LIST1 lookahead_char -> pl ] ]
  ;
  lookahead_char:
    [ [ c = CHAR -> <:patt< $chr:c$ >>
      | "_" -> <:patt< _ >> ] ]
  ;
  no_rec:
    [ [ "/" -> True
      | -> False ] ]
  ;
  err_kont:
    [ [ "!" -> Some None
      | "?"; s = STRING -> Some (Some <:expr< $str:s$ >>)
      | -> None ] ]
  ;
  act:
    [ [ "->"; e = expr -> Some e
      | -> None ] ]
  ;
END;
