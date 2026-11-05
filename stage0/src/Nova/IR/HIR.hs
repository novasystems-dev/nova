{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Nova.IR.HIR
    ( DefId(..)
    , HIRProgram(..)
    , HIRTopLevel(..)
    , HIRFn(..)
    , HIRParam(..)
    , HIRStmt(..)
    , HIRExpr(..)
    , lowerASTtoHIR
    , dumpHIR
    ) where

import GHC.Generics (Generic)
import Data.Text (Text)
import qualified Data.Text as T

import Nova.Syntax.Span
import Nova.Syntax.AST
import Nova.Syntax.Token

newtype DefId = DefId Int
    deriving stock (Eq, Ord, Show, Generic)

data HIRProgram = HIRProgram
    { hirItems :: [HIRTopLevel]
    } deriving stock (Eq, Show, Generic)

data HIRTopLevel
    = HIRTopFn !HIRFn
    | HIRTopType !TypeDecl
    deriving stock (Eq, Show, Generic)

data HIRFn = HIRFn
    { hirFnId         :: !DefId
    , hirFnName       :: !Text
    , hirFnParams     :: ![HIRParam]
    , hirFnReturnType :: !(Maybe TypeExpr)
    , hirFnBody       :: ![HIRStmt]
    } deriving stock (Eq, Show, Generic)

data HIRParam = HIRParam
    { hirParamId   :: !DefId
    , hirParamName :: !Text
    , hirParamType :: !TypeExpr
    , hirParamCap  :: !(Maybe Capability)
    } deriving stock (Eq, Show, Generic)

data HIRStmt
    = HIRLet !DefId !Text !(Maybe TypeExpr) !HIRExpr
    | HIRAssign !HIRExpr !HIRExpr
    | HIRReturn !(Maybe HIRExpr)
    | HIRIf !HIRExpr ![HIRStmt] !(Maybe [HIRStmt])
    | HIRWhile !HIRExpr ![HIRStmt]
    | HIRMatch !HIRExpr ![(Pattern, Maybe HIRExpr, [HIRStmt])]
    | HIRRegion !Text ![HIRStmt]
    | HIRExprStmt !HIRExpr
    deriving stock (Eq, Show, Generic)

data HIRExpr
    = HIRLit !Literal
    | HIRVar !DefId !Text
    | HIRBinary !BinOp !HIRExpr !HIRExpr
    | HIRUnary !UnOp !HIRExpr
    | HIRCall !HIRExpr ![HIRExpr]
    | HIRIndex !HIRExpr !HIRExpr
    | HIRField !HIRExpr !Text
    | HIRTuple ![HIRExpr]
    deriving stock (Eq, Show, Generic)

-- ============================================================================
-- AST -> HIR LOWERING PASS
-- ============================================================================

lowerASTtoHIR :: Program -> HIRProgram
lowerASTtoHIR (Program items) =
    let (_, loweredItems) = foldl lowerItem (0, []) items
    in HIRProgram (reverse loweredItems)
  where
    lowerItem (nextId, acc) (Spanned item _) = case item of
        TopFn fn ->
            let (nextId', hirFn) = lowerFn nextId fn
            in (nextId', HIRTopFn hirFn : acc)
        TopType ty ->
            (nextId, HIRTopType ty : acc)
        TopTrait _ ->
            (nextId, acc)
        TopImpl ImplDecl{..} ->
            let (nextId', fns) = foldl (\(nid, fs) fn -> let (nid', hf) = lowerFn nid fn in (nid', HIRTopFn hf : fs)) (nextId, acc) implMethods
            in (nextId', fns)
        TopImport _ _ _ ->
            (nextId, acc)

lowerFn :: Int -> FnDecl -> (Int, HIRFn)
lowerFn startId FnDecl{..} =
    let (nextId1, params) = foldl lowerParam (startId + 1, []) fnParams
        (nextId2, stmts)  = foldl lowerStmt (nextId1, []) fnBody
    in (nextId2, HIRFn (DefId startId) fnName (reverse params) fnReturnType (reverse stmts))
  where
    lowerParam (curId, acc) Param{..} =
        (curId + 1, HIRParam (DefId curId) paramName paramType paramCap : acc)

    lowerStmt (curId, acc) (Spanned stmt _) = case stmt of
        StmtLet (PatVar _ name) mty expr ->
            (curId + 1, HIRLet (DefId curId) name mty (lowerExpr expr) : acc)
        StmtAssign lhs rhs ->
            (curId, HIRAssign (lowerExpr lhs) (lowerExpr rhs) : acc)
        StmtReturn mExpr ->
            (curId, HIRReturn (fmap lowerExpr mExpr) : acc)
        StmtIf cond thenB elifs elseB ->
            let loweredThen = snd $ foldl lowerStmt (curId, []) thenB
                -- Desugar elif chains into nested HIR if-else
                loweredElse = lowerElifs elifs elseB
            in (curId, HIRIf (lowerExpr cond) (reverse loweredThen) loweredElse : acc)
        StmtWhile cond body ->
            let loweredBody = snd $ foldl lowerStmt (curId, []) body
            in (curId, HIRWhile (lowerExpr cond) (reverse loweredBody) : acc)
        StmtFor (PatVar _ name) iter body ->
            -- Desugaring for-loop into HIR while-loop
            let loopVar = HIRLet (DefId curId) name (Just (TyNamed "Int")) (lowerExpr iter)
                loopBody = snd $ foldl lowerStmt (curId + 1, []) body
            in (curId + 2, loopVar : HIRWhile (HIRLit (LitBool True)) (reverse loopBody) : acc)
        StmtMatch expr arms ->
            let loweredArms = [ (pat, fmap lowerExpr mGuard, reverse (snd (foldl lowerStmt (curId, []) b)))
                              | (pat, mGuard, b) <- arms ]
            in (curId, HIRMatch (lowerExpr expr) loweredArms : acc)
        StmtRegion rName body ->
            let loweredBody = snd $ foldl lowerStmt (curId, []) body
            in (curId, HIRRegion rName (reverse loweredBody) : acc)
        StmtExpr expr ->
            (curId, HIRExprStmt (lowerExpr expr) : acc)
        _ ->
            (curId, acc)

    lowerElifs [] Nothing = Nothing
    lowerElifs [] (Just eb) =
        Just (reverse (snd (foldl lowerStmt (startId, []) eb)))
    lowerElifs ((c, b) : rest) mbElse =
        let loweredB = reverse (snd (foldl lowerStmt (startId, []) b))
            nestedElse = lowerElifs rest mbElse
        in Just [HIRIf (lowerExpr c) loweredB nestedElse]

lowerExpr :: Spanned Expr -> HIRExpr
lowerExpr (Spanned expr _) = case expr of
    ExprLit lit -> HIRLit lit
    ExprVar v -> HIRVar (DefId 0) v
    ExprBinary op l r -> HIRBinary op (lowerExpr l) (lowerExpr r)
    ExprUnary op e -> HIRUnary op (lowerExpr e)
    ExprCall fn args -> HIRCall (lowerExpr fn) (map lowerExpr args)
    ExprIndex base idx -> HIRIndex (lowerExpr base) (lowerExpr idx)
    ExprField base f -> HIRField (lowerExpr base) f
    ExprTuple items -> HIRTuple (map lowerExpr items)
    _ -> HIRLit (LitBool False)

-- ============================================================================
-- PRETTY PRINTER / DUMPER
-- ============================================================================

dumpHIR :: HIRProgram -> Text
dumpHIR (HIRProgram items) = T.unlines (map dumpItem items)
  where
    dumpItem (HIRTopFn HIRFn{..}) =
        "hir fn " <> hirFnName <> " [#" <> T.pack (show hirFnId) <> "] ("
        <> T.intercalate ", " [ pName <> ": " <> T.pack (show pTy) | HIRParam _ pName pTy _ <- hirFnParams ]
        <> ") {\n"
        <> T.unlines [ "    " <> dumpStmt s | s <- hirFnBody ]
        <> "}"
    dumpItem (HIRTopType TypeDecl{..}) =
        "hir type " <> typeName
    dumpStmt s = case s of
        HIRLet (DefId did) name _ rhs ->
            "let " <> name <> " (#" <> T.pack (show did) <> ") = " <> dumpExpr rhs
        HIRAssign lhs rhs ->
            dumpExpr lhs <> " = " <> dumpExpr rhs
        HIRReturn (Just e) ->
            "return " <> dumpExpr e
        HIRReturn Nothing ->
            "return"
        HIRIf cond _ _ ->
            "if " <> dumpExpr cond <> " { ... }"
        HIRWhile cond _ ->
            "while " <> dumpExpr cond <> " { ... }"
        HIRExprStmt e ->
            dumpExpr e
        _ -> "..."

    dumpExpr e = case e of
        HIRLit (LitInt n) -> T.pack (show n)
        HIRLit (LitString s) -> "\"" <> s <> "\""
        HIRLit (LitBool b) -> if b then "true" else "false"
        HIRVar _ v -> v
        HIRBinary op l r -> "(" <> dumpExpr l <> " " <> dumpBinOp op <> " " <> dumpExpr r <> ")"
        HIRCall f args -> dumpExpr f <> "(" <> T.intercalate ", " (map dumpExpr args) <> ")"
        _ -> "<?>"

    dumpBinOp OpAdd = "+"
    dumpBinOp OpSub = "-"
    dumpBinOp OpMul = "*"
    dumpBinOp OpDiv = "/"
    dumpBinOp OpMod = "%"
    dumpBinOp OpEq = "=="
    dumpBinOp OpNotEq = "!="
    dumpBinOp OpLt = "<"
    dumpBinOp OpLtEq = "<="
    dumpBinOp OpGt = ">"
    dumpBinOp OpGtEq = ">="
    dumpBinOp OpAnd = "and"
    dumpBinOp OpOr = "or"
    dumpBinOp OpBitAnd = "&"
    dumpBinOp OpBitOr = "|"
    dumpBinOp OpBitXor = "^"
    dumpBinOp OpShl = "<<"
    dumpBinOp OpShr = ">>"
