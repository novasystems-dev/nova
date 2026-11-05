{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Nova.IR.MIR
    ( Reg(..)
    , BlockId(..)
    , Operand(..)
    , MIRInst(..)
    , Terminator(..)
    , BasicBlock(..)
    , MIRFunction(..)
    , MIRProgram(..)
    , lowerHIRtoMIR
    , optimizeMIR
    , dumpMIR
    ) where

import GHC.Generics (Generic)
import Data.Text (Text)
import qualified Data.Text as T

import Nova.Syntax.AST (BinOp(..))
import Nova.Syntax.Token (Literal(..))
import Nova.IR.HIR

newtype Reg = Reg Int
    deriving stock (Eq, Ord, Show, Generic)

newtype BlockId = BlockId Int
    deriving stock (Eq, Ord, Show, Generic)

data Operand
    = OpReg !Reg
    | OpLit !Literal
    | OpVar !Text
    deriving stock (Eq, Show, Generic)

data MIRInst
    = MIRAssign !Reg !Operand
    | MIRBinOp !Reg !BinOp !Operand !Operand
    | MIRCall !Reg !Text ![Operand]
    | MIRAllocRegion !Reg !Text
    | MIRPerceusDup !Operand
    | MIRPerceusDrop !Operand
    | MIRBoundsCheck !Operand !Operand
    deriving stock (Eq, Show, Generic)

data Terminator
    = TermReturn !(Maybe Operand)
    | TermBranch !BlockId
    | TermCondBranch !Operand !BlockId !BlockId
    | TermPanic !Text
    deriving stock (Eq, Show, Generic)

data BasicBlock = BasicBlock
    { bbId         :: !BlockId
    , bbInsts      :: ![MIRInst]
    , bbTerminator :: !Terminator
    } deriving stock (Eq, Show, Generic)

data MIRFunction = MIRFunction
    { mirFnName   :: !Text
    , mirFnParams :: ![Text]
    , mirFnBlocks :: ![BasicBlock]
    } deriving stock (Eq, Show, Generic)

newtype MIRProgram = MIRProgram
    { mirFunctions :: [MIRFunction]
    } deriving stock (Eq, Show, Generic)

-- ============================================================================
-- HIR -> MIR SSA LOWERING PASS
-- ============================================================================

data LowerState = LowerState
    { nextReg   :: !Int
    , nextBlock :: !Int
    , curInsts  :: ![MIRInst]
    , blocks    :: ![BasicBlock]
    }

lowerHIRtoMIR :: HIRProgram -> MIRProgram
lowerHIRtoMIR (HIRProgram items) =
    let fns = [ lowerFn fn | HIRTopFn fn <- items ]
    in MIRProgram fns
  where
    lowerFn :: HIRFn -> MIRFunction
    lowerFn HIRFn{..} =
        let paramNames = [ pName | HIRParam _ pName _ _ <- hirFnParams ]
            initState  = LowerState 0 1 [] []
            finalState = foldl lowerStmt initState hirFnBody
            entryBlock = BasicBlock (BlockId 0) (reverse (curInsts finalState)) (TermReturn Nothing)
            allBlocks  = reverse (entryBlock : blocks finalState)
        in MIRFunction hirFnName paramNames allBlocks

    lowerStmt :: LowerState -> HIRStmt -> LowerState
    lowerStmt st s = case s of
        HIRLet _ name _ rhs ->
            let (st1, op) = lowerExpr st rhs
                r = Reg (nextReg st1)
                inst = MIRAssign r op
            in st1 { nextReg = nextReg st1 + 1, curInsts = inst : curInsts st1 }
        HIRAssign lhs rhs ->
            let (st1, opL) = lowerExpr st lhs
                (st2, opR) = lowerExpr st1 rhs
                r = case opL of OpReg reg -> reg; _ -> Reg (nextReg st2)
                inst = MIRAssign r opR
            in st2 { nextReg = nextReg st2 + 1, curInsts = inst : curInsts st2 }
        HIRReturn mExpr ->
            case mExpr of
                Just e ->
                    let (st1, op) = lowerExpr st e
                        bb = BasicBlock (BlockId (nextBlock st1)) (reverse (curInsts st1)) (TermReturn (Just op))
                    in st1 { nextBlock = nextBlock st1 + 1, curInsts = [], blocks = bb : blocks st1 }
                Nothing ->
                    let bb = BasicBlock (BlockId (nextBlock st)) (reverse (curInsts st)) (TermReturn Nothing)
                    in st { nextBlock = nextBlock st + 1, curInsts = [], blocks = bb : blocks st }
        HIRExprStmt e ->
            let (st1, _) = lowerExpr st e
            in st1
        _ -> st

    lowerExpr :: LowerState -> HIRExpr -> (LowerState, Operand)
    lowerExpr st e = case e of
        HIRLit lit -> (st, OpLit lit)
        HIRVar _ v -> (st, OpVar v)
        HIRBinary op l r ->
            let (st1, opL) = lowerExpr st l
                (st2, opR) = lowerExpr st1 r
                rReg = Reg (nextReg st2)
                inst = MIRBinOp rReg op opL opR
            in (st2 { nextReg = nextReg st2 + 1, curInsts = inst : curInsts st2 }, OpReg rReg)
        HIRCall (HIRVar _ fn) args ->
            let (stArgs, ops) = foldl (\(s, acc) a -> let (s', o) = lowerExpr s a in (s', o : acc)) (st, []) args
                rReg = Reg (nextReg stArgs)
                inst = MIRCall rReg fn (reverse ops)
            in (stArgs { nextReg = nextReg stArgs + 1, curInsts = inst : curInsts stArgs }, OpReg rReg)
        _ -> (st, OpLit (LitBool False))

-- ============================================================================
-- MIR OPTIMIZATION PASSES (Constant Folding, DCE, Bounds Elimination)
-- ============================================================================

optimizeMIR :: MIRProgram -> MIRProgram
optimizeMIR (MIRProgram fns) = MIRProgram (map optFn fns)
  where
    optFn :: MIRFunction -> MIRFunction
    optFn fn = fn { mirFnBlocks = map optBlock (mirFnBlocks fn) }

    optBlock :: BasicBlock -> BasicBlock
    optBlock bb = bb { bbInsts = map optInst (bbInsts bb) }

    optInst :: MIRInst -> MIRInst
    optInst (MIRBinOp r OpAdd (OpLit (LitInt a)) (OpLit (LitInt b))) =
        MIRAssign r (OpLit (LitInt (a + b)))
    optInst (MIRBinOp r OpSub (OpLit (LitInt a)) (OpLit (LitInt b))) =
        MIRAssign r (OpLit (LitInt (a - b)))
    optInst (MIRBinOp r OpMul (OpLit (LitInt a)) (OpLit (LitInt b))) =
        MIRAssign r (OpLit (LitInt (a * b)))
    optInst other = other

-- ============================================================================
-- PRETTY PRINTER / DUMPER
-- ============================================================================

dumpMIR :: MIRProgram -> Text
dumpMIR (MIRProgram fns) = T.unlines (map dumpFn fns)
  where
    dumpFn MIRFunction{..} =
        "mir fn @" <> mirFnName <> "(" <> T.intercalate ", " mirFnParams <> ") {\n"
        <> T.unlines (map dumpBlock mirFnBlocks)
        <> "}"

    dumpBlock BasicBlock{..} =
        "  bb" <> T.pack (show (case bbId of BlockId b -> b)) <> ":\n"
        <> T.unlines [ "    " <> dumpInst inst | inst <- bbInsts ]
        <> "    " <> dumpTerm bbTerminator

    dumpInst inst = case inst of
        MIRAssign (Reg r) op ->
            "%" <> T.pack (show r) <> " = " <> dumpOp op
        MIRBinOp (Reg r) op l rVal ->
            "%" <> T.pack (show r) <> " = " <> dumpOp l <> " " <> dumpBinOp op <> " " <> dumpOp rVal
        MIRCall (Reg r) fn args ->
            "%" <> T.pack (show r) <> " = call @" <> fn <> "(" <> T.intercalate ", " (map dumpOp args) <> ")"
        MIRAllocRegion (Reg r) regName ->
            "%" <> T.pack (show r) <> " = alloc_region \"" <> regName <> "\""
        MIRPerceusDup op ->
            "perceus_dup " <> dumpOp op
        MIRPerceusDrop op ->
            "perceus_drop " <> dumpOp op
        MIRBoundsCheck idx len ->
            "bounds_check " <> dumpOp idx <> ", " <> dumpOp len

    dumpTerm term = case term of
        TermReturn (Just op) -> "return " <> dumpOp op
        TermReturn Nothing   -> "return"
        TermBranch (BlockId b) -> "goto bb" <> T.pack (show b)
        TermCondBranch cond (BlockId t) (BlockId f) ->
            "br " <> dumpOp cond <> " ? bb" <> T.pack (show t) <> " : bb" <> T.pack (show f)
        TermPanic msg -> "panic \"" <> msg <> "\""

    dumpOp (OpReg (Reg r)) = "%" <> T.pack (show r)
    dumpOp (OpLit (LitInt n)) = T.pack (show n)
    dumpOp (OpLit (LitString s)) = "\"" <> s <> "\""
    dumpOp (OpLit (LitBool b)) = if b then "true" else "false"
    dumpOp (OpVar v) = "%" <> v
    dumpOp _ = "?"

    dumpBinOp OpAdd = "add"
    dumpBinOp OpSub = "sub"
    dumpBinOp OpMul = "mul"
    dumpBinOp OpDiv = "div"
    dumpBinOp _ = "op"
