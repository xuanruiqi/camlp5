#!/bin/sh
# $Id: mk_q_ast.sh,v 1.3 2010/09/08 09:41:24 deraugla Exp $

IFILE=pa_r.ml
OFILE=q_ast.ml
(
sed -e '/^    value rec ctyp =$/,$d' $OFILE
ocamlrun ./camlp5r -nolib ./pa_macro.cmo ../etc/pa_mkast.cmo ../etc/pr_r.cmo -ignloaddir -impl ../main/mLast.mli |
sed -e 's/\(..Xtr .*\) ->$/IFDEF STRICT THEN/' |
sed -e 's/C.node "PaXtr".*$/PaXtr loc s _ -> C.xtr_or_anti loc (fun r -> C.node "PaAnt" [r]) s\n        END ]/; s/C.node "ExXtr".*$/ExXtr loc s _ -> C.xtr_or_anti loc (fun r -> C.node "ExAnt" [r]) s\n        END ]/; s/C.node "\(..\)Xtr".*$/\1Xtr loc s _ -> C.xtr loc s\n        END ]/' |
sed -e '1,/^  struct/d;/external/,$d'
grep 'value anti_anti n' $OFILE
sed -e '1,/anti_anti/d' $OFILE
)
