{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Nova.Syntax.AST
    ( Program(..)
    , TopLevel(..)
    , FnDecl(..)
    , Param(..)
    , TypeDecl(..)
    , TypeDef(..)
    , TypeExpr(..)
    , TraitDecl(..)
    , ImplDecl(..)
    , Capability(..)
    , Stmt(..)
    , Expr(..)
    , Pattern(..)
    , BinOp(..)
    , UnOp(..)
    ) where

import GHC.Generics (Generic)
import Data.Text (Text)
import Nova.Syntax.Span (Spanned)
import Nova.Syntax.Token (Literal)

newtype Program = Program
    { progItems :: [Spanned TopLevel]
    } deriving stock (Eq, Show, Generic)

data TopLevel
    = TopFn !(FnDecl)
    | TopType !(TypeDecl)
    | TopTrait !(TraitDecl)
    | TopImpl !(ImplDecl)
    | TopImport ![Text] !(Maybe Text) ![Text]
    deriving stock (Eq, Show, Generic)

data TraitDecl = TraitDecl
    { traitIsPub   :: !Bool
    , traitName    :: !Text
    , traitParams  :: ![Text]
    , traitMethods :: ![FnDecl]
    } deriving stock (Eq, Show, Generic)

data ImplDecl = ImplDecl
    { implTraitName :: !Text
    , implForType   :: !TypeExpr
    , implMethods   :: ![FnDecl]
    } deriving stock (Eq, Show, Generic)

data Capability
    = CapIso
    | CapVal
    | CapRef
    | CapToken
    deriving stock (Eq, Show, Generic)

data FnDecl = FnDecl
    { fnIsPub      :: !Bool
    , fnName       :: !Text
    , fnTypeParams :: ![Text]
    , fnParams     :: ![Param]
    , fnReturnType :: !(Maybe TypeExpr)
    , fnContract   :: !(Maybe (Spanned Expr))
    , fnBody       :: ![Spanned Stmt]
    } deriving stock (Eq, Show, Generic)

data Param = Param
    { paramIsMut   :: !Bool
    , paramCap     :: !(Maybe Capability)
    , paramName    :: !Text
    , paramType    :: !TypeExpr
    , paramWhere   :: !(Maybe (Spanned Expr))
    } deriving stock (Eq, Show, Generic)

data TypeDecl = TypeDecl
    { typeIsPub  :: !Bool
    , typeName   :: !Text
    , typeParams :: ![Text]
    , typeDef    :: !TypeDef
    } deriving stock (Eq, Show, Generic)

data TypeDef
    = TypeAlias !TypeExpr
    | TypeStruct ![(Text, TypeExpr)]
    | TypeEnum ![(Text, [TypeExpr])]
    | TypeRefinement !Text !TypeExpr !(Spanned Expr)
    deriving stock (Eq, Show, Generic)

data TypeExpr
    = TyNamed !Text
    | TyGeneric !Text ![TypeExpr]
    | TyCapability !Capability !TypeExpr
    | TyRawPtr !Bool !TypeExpr
    | TyTuple ![TypeExpr]
    | TyList !TypeExpr
    | TyFn ![TypeExpr] !TypeExpr
    deriving stock (Eq, Show, Generic)

data Stmt
    = StmtLet !Pattern !(Maybe TypeExpr) !(Spanned Expr)
    | StmtAssign !(Spanned Expr) !(Spanned Expr)
    | StmtReturn !(Maybe (Spanned Expr))
    | StmtIf !(Spanned Expr) ![Spanned Stmt] ![(Spanned Expr, [Spanned Stmt])] !(Maybe [Spanned Stmt])
    | StmtWhile !(Spanned Expr) ![Spanned Stmt]
    | StmtFor !Pattern !(Spanned Expr) ![Spanned Stmt]
    | StmtMatch !(Spanned Expr) ![(Pattern, Maybe (Spanned Expr), [Spanned Stmt])]
    | StmtUnsafe !Text ![Spanned Stmt]
    | StmtRegion !Text ![Spanned Stmt]
    | StmtAsm !Text
    | StmtExpr !(Spanned Expr)
    deriving stock (Eq, Show, Generic)

data Pattern
    = PatWildcard
    | PatLit !Literal
    | PatVar !Bool !Text   -- (isMut, varName)
    | PatTuple ![Pattern]
    | PatVariant !Text ![Pattern]
    deriving stock (Eq, Show, Generic)

data Expr
    = ExprLit !Literal
    | ExprVar !Text
    | ExprBinary !BinOp !(Spanned Expr) !(Spanned Expr)
    | ExprUnary !UnOp !(Spanned Expr)
    | ExprCall !(Spanned Expr) ![Spanned Expr]
    | ExprIndex !(Spanned Expr) !(Spanned Expr)
    | ExprField !(Spanned Expr) !Text
    | ExprTuple ![Spanned Expr]
    | ExprList ![Spanned Expr]
    deriving stock (Eq, Show, Generic)

data BinOp
    = OpAdd | OpSub | OpMul | OpDiv | OpMod
    | OpEq | OpNotEq | OpLt | OpLtEq | OpGt | OpGtEq
    | OpAnd | OpOr
    | OpBitAnd | OpBitOr | OpBitXor | OpShl | OpShr
    deriving stock (Eq, Show, Generic)

data UnOp
    = OpNeg | OpNot | OpBitNot | OpDeref | OpAddrOf
    deriving stock (Eq, Show, Generic)
