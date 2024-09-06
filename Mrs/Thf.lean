import Lean.Data.HashMap
import Lean.Data.RBMap
import Mrs.Basic

namespace MM

open Lean (RBMap)

structure Multimap (α β : Type) [BEq α] [Ord α] where
  map : RBMap α (List β) compare

class MultimapMethods (α β : Type) [BEq α] [Ord α] where
  empty : Multimap α β
  insert : Multimap α β → α → β → Multimap α β
  find? : Multimap α β → α → Option (List β)
  keys : Multimap α β → List α

instance [BEq α] [Ord α] : MultimapMethods α β where
  empty := ⟨RBMap.empty⟩
  insert m k v :=
    let newValues := match m.map.find? k with
      | some list => v :: list
      | none => [v]
    ⟨m.map.insert k newValues⟩
  find? m k := m.map.find? k
  keys m := m.map.toList.map Prod.fst

def Multimap.empty [BEq α] [Ord α] : Multimap α β := MultimapMethods.empty
def Multimap.insert [BEq α] [Ord α] (m : Multimap α β) (k : α) (v : β) : Multimap α β := MultimapMethods.insert m k v
def Multimap.find? [BEq α] [Ord α] (m : Multimap α β) (k : α) : Option (List β) := MultimapMethods.find? m k
def Multimap.keys [BEq α] [Ord α] (m : Multimap α β) : List α := MultimapMethods.keys m

end MM

namespace THF

open MRS (Var EP Constraint MRS)
open Lean (HashMap)
open MM

def libraryRoutines : String := 
  "thf(book_n_of_decl,type,book_n_of: x > $o).\n" ++
  "thf(love_v_1_decl,type,love_v_1: x > x > $o).\n" ++
  "thf(a_q_decl,type,every_q: (x > $o) > (x > $o) > $o).\n" ++ 
  "thf(every_q_decl,type,a_q: (x > $o) > (x > $o) > $o).\n" ++
  "thf(boy_n_1_decl,type,boy_n_1: x > $o)." 

def joinSep (l : List String) (sep : String) : String := l.foldr (fun s r => (if r == "" then s else r ++ sep ++ s)) ""

def Var.format.typeOnly (var : Var) : String :=
  if var.sort == 'e' then
    s!"{var.sort}"
  else if var.sort == 'h' then
    s!"{var.sort}{var.id}"
  else
    s!"{var.sort}"

def Var.format.labelOnly (var : Var) : String :=
  if var.sort == 'x' then
    s!"{var.sort.toUpper}{var.id}"
  else
    s!"{var.sort}{var.id}"

def Var.format.labelOnlyGround (var : Var) : String :=
  s!"{var.sort}{var.id}"

def Var.format.labelWithDep (var : Var) (em : Multimap Var Var) : String :=
  match (em.find? var) with
  | some extraList => "(" ++ (Var.format.labelOnlyGround var) ++ " @ " ++ (joinSep (extraList.map (fun item => Var.format.labelOnly item)) " @ ") ++ ")"
  | none => 
    if var.sort == 'h' then
      Var.format.labelOnlyGround var
    else
      Var.format.labelOnly var

def Var.format.pair (var : Var) : String :=
  if var.sort == 'x' then
    s!"{var.sort.toUpper}{var.id} : {var.sort}"
  else if var.sort == 'e' then
    s!"{var.sort}{var.id} : {var.sort}"
  else if var.sort == 'h' then 
    s!"{var.sort}{var.id} : {var.sort}{var.id}"
  else
    unreachable!

def Var.format.all (var : Var) : String :=
  s!"{var.sort}{var.id}{var.props}"

def lastTwoChars (s : String) : String :=
  if s.length <= 1 then
    s
  else
    s.drop (s.length - 2)

def insertArgsForEP (qm : HashMap Var Var) (ep : EP) : HashMap Var Var :=
  if lastTwoChars ep.predicate == "_q" then
    match ep.rargs with
    | a :: b :: c :: [] => 
      if a.1 == "ARG0" then
        (qm.insert b.2 a.2).insert c.2 a.2
      else if b.1 == "ARG0" then
        (qm.insert a.2 b.2).insert c.2 b.2
      else 
        (qm.insert a.2 c.2).insert b.2 c.2
    | _ => unreachable!
  else
    qm 

def collectQuantifierVars (preds : List EP) : HashMap Var Var :=
  preds.foldl (fun hmacc ep => insertArgsForEP hmacc ep) HashMap.empty

def collectExtraVarsForEPs (preds : List EP) (qm : HashMap Var Var) : Multimap Var Var :=
  let insertExtra (em : Multimap Var Var) (ep : EP) : Multimap Var Var :=
    if lastTwoChars ep.predicate == "_q" then
      em
    else
      ep.rargs.foldl (fun (emac : Multimap Var Var) (pair : (String × Var)) => 
         match (qm.find? ep.label) with
         | some value => 
           if pair.2.sort = 'x' && pair.2 != value then 
             match emac.find? ep.label with
             | some l => if l.contains pair.2 then emac else emac.insert ep.label pair.2
             | none => emac.insert ep.label pair.2
           else
             emac
         | none => emac) em
  preds.foldl insertExtra Multimap.empty

def augmentIndirect (em : Multimap Var Var) (ep : EP) : Multimap Var Var :=
  let add (emin : Multimap Var Var) (var : Var) : Multimap Var Var := 
    match (emin.find? var) with
    | some vals => vals.foldl (fun acc arg => acc.insert ep.label arg) emin
    | none => emin
  if lastTwoChars ep.predicate == "_q" then
    match ep.rargs with
    | a :: b :: c :: [] => 
      if a.1 == "ARG0" then
        add (add em b.2) c.2
      else if b.1 == "ARG0" then
        add (add em a.2) c.2
      else 
        add (add em a.2) b.2
    | _ => sorry
  else
    em

def collectHOExtraVarsForEPs (preds : List EP) (em : Multimap Var Var) : Multimap Var Var :=
  preds.foldl (fun emac ep => augmentIndirect emac ep) em
  
def EP.format.type (qm : HashMap Var Var) (em : Multimap Var Var) (ep : EP) : String :=
  let lookupArg (labelVar : Var) : String :=
    match (qm.find? labelVar) with
    | some value => (Var.format.typeOnly value) ++ " > "
    | none => ""

  let extraArgs (labelVar : Var) : String := 
    match (em.find? labelVar) with
    | some value => (joinSep (value.map (fun var => Var.format.typeOnly var)) " > ") ++ " > "
    | none => ""

  match ep with
  | {predicate := p, link := some (n,m), label := l, rargs := rs, carg := some c} =>
    "thf(" ++ Var.format.labelOnlyGround l ++ "_decl,type," ++ Var.format.labelOnlyGround l ++ ": " ++ (extraArgs l) ++ (lookupArg l) ++ "string > $o)."
  | {predicate := p, link := some (n,m), label := l, rargs := rs, carg := none} =>
    "thf(" ++ Var.format.labelOnlyGround l ++ "_decl,type," ++ Var.format.labelOnlyGround l ++ ": " ++ (extraArgs l) ++ (lookupArg l) ++ "$o)."
  | {predicate := p, link := none, label := l, rargs := rs, carg := some c} =>
    "thf(" ++ Var.format.labelOnlyGround l ++ "_decl,type," ++ Var.format.labelOnlyGround l ++ ": " ++ (extraArgs l) ++ (lookupArg l) ++ "string > $o)."
  | {predicate := p, link := none, label := l, rargs := rs, carg := none} =>
    "thf(" ++ Var.format.labelOnlyGround l ++ "_decl,type," ++ Var.format.labelOnlyGround l ++ ": " ++ (extraArgs l) ++ (lookupArg l) ++ "$o)."


def EP.format.axiom (qm : HashMap Var Var) (em : Multimap Var Var) (hm : Multimap Var EP) (handle : Var) : String :=
  let preds := match (hm.find? handle) with
  | some value => value
  | none => []

  let firstEp := match preds.head? with
  | some value => value
  | none => sorry

  let lookupArg (labelVar : Var) : String :=
    match (qm.find? labelVar) with
    | some value => Var.format.pair value
    | none => ""

  let getArgs (ep : EP) : List (String × Var) :=
    let ret1 := if lastTwoChars ep.predicate == "_q" then
                  ep.rargs.filter (fun item => item.1 != "ARG0") 
                else
                  ep.rargs
    ret1.filter (fun item => item.2.sort == 'x' || item.2.sort == 'h' || item.2.sort == 'e') 

  let extraArgs (qm : HashMap Var Var) (labelVar : Var) : String := 
    dbg_trace ("<" ++ (Var.format.pair labelVar)) ;
    match (em.find? labelVar) with
    | some value => 
      let larg := match (qm.find? labelVar) with
                  | some value => value
                  | none => sorry
      let l := value.filter (fun arg => arg != larg)
      let str := (joinSep (l.map (fun var => Var.format.pair var)) ",") ++ "," ;
      dbg_trace (str ++ ">") ;
      str
    | none => ""

  let fixName (PredName : String) : String :=
    match (PredName.get? 0) with
      | '_' => PredName.drop 1
      | _ => PredName

  let printNormal (l : Var) (preds : List EP) : String :=
    let joinArgs0 (ep : EP) := joinSep ((getArgs ep).map fun a => Var.format.labelWithDep a.2 em)  " @ "
    let joinArgs (ep : EP) := 
      match ep.carg with
      | some str => joinArgs0 ep ++ " @ " ++ str
      | none => joinArgs0 ep
    let combined := (extraArgs qm l) ++ (lookupArg l)
    if combined == "" then
      "thf(" ++ Var.format.labelOnlyGround l ++ ",axiom," ++ "\n   " ++ Var.format.labelOnlyGround l ++ " = " ++ fixName (firstEp.predicate) ++ " @ " ++ (joinArgs firstEp)  ++ ")."
    else
      let (lparen,rparen) := if preds.length > 1 then ("(",")") else ("","")
      let allCalls := preds.foldl (fun acc ep => (acc.1 ++ acc.2 ++ lparen ++ (fixName ep.predicate) ++ " @ " ++ (joinArgs ep) ++ rparen," & ")) ("","")
      "thf(" ++ Var.format.labelOnlyGround l ++ ",axiom," ++ "\n   " ++ Var.format.labelOnlyGround l ++ " = ( ^ [" ++ combined ++ "] : " ++ allCalls.1 ++ "))."

  printNormal firstEp.label preds

def collectEPsByHandle (preds : List EP) : Multimap Var EP :=
  preds.foldl (fun acc ep => acc.insert ep.label ep) Multimap.empty

def collectEvents (preds : List EP) : List Var :=
  let insertUnique (xs : List Var) (x : Var) : List Var :=
    if xs.contains x then xs else x :: xs
  let collectEventsForArgs (acc : List Var) (rs : List (String × Var)) : List Var := 
    rs.foldl (fun acc pair => if pair.2.sort == 'e' then insertUnique acc pair.2 else acc) acc
  preds.foldl (fun acc ep => collectEventsForArgs acc ep.rargs) []

def MRS.format (mrs : MRS.MRS) : String :=
 let header0 := "thf(x_decl,type,x : $tType)."
 let header1 := "thf(e_decl,type,e : $tType)."
 let headers := header0 ++ "\n" ++ header1 ++ "\n" ++ libraryRoutines ++ "\n"
 let eSet := collectEvents mrs.preds 
 let qm := collectQuantifierVars mrs.preds
 let em := collectHOExtraVarsForEPs mrs.preds $ collectExtraVarsForEPs mrs.preds qm
 let hm := collectEPsByHandle mrs.preds
 let rlt := (List.map (EP.format.type qm em) mrs.preds).eraseDups
 let rla := List.map (EP.format.axiom qm em hm) hm.keys 
 headers ++ (joinSep (eSet.map (fun (var : Var) => s!"thf({var.sort}{var.id},type,$int @ {var.id}).")) "\n") ++ "\n" ++ (joinSep rlt "\n") ++ "\n" ++ (joinSep rla "\n")

end THF


