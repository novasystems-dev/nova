{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Nova.Syntax.Token
    ( Token(..)
    , Keyword(..)
    , Literal(..)
    ) where

import GHC.Generics (Generic)
import Data.Text (Text)

data Keyword
    = KwFn        -- fn
    | KwLet       -- let
    | KwMut       -- mut
    | KwType      -- type
    | KwMatch     -- match
    | KwWhere     -- where
    | KwIf        -- if
    | KwElif      -- elif
    | KwElse      -- else
    | KwFor       -- for
    | KwWhile     -- while
    | KwReturn    -- return
    | KwBreak     -- break
    | KwContinue  -- continue
    | KwPub       -- pub
    | KwImport    -- import
    | KwAs        -- as
    | KwTrait     -- trait
    | KwImpl      -- impl
    | KwUnsafe    -- unsafe
    | KwCap       -- cap
    | KwRegion    -- region
    | KwIso       -- iso
    | KwVal       -- val
    | KwRef       -- ref
    deriving stock (Eq, Ord, Show, Generic)

data Literal
    = LitInt !Integer
    | LitFloat !Double
    | LitString !Text
    | LitChar !Char
    | LitBool !Bool
    deriving stock (Eq, Ord, Show, Generic)

data Token
    -- Identifiers and Literals
    = TokIdent !Text
    | TokKeyword !Keyword
    | TokLiteral !Literal

    -- Layout / Indentation Tokens
    | TokNewline
    | TokIndent
    | TokDedent

    -- Delimiters
    | TokLParen      -- (
    | TokRParen      -- )
    | TokLBracket    -- [
    | TokRBracket    -- ]
    | TokLBrace      -- {
    | TokRBrace      -- }
    | TokColon       -- :
    | TokComma       -- ,
    | TokDot         -- .
    | TokArrow       -- ->
    | TokFatArrow    -- =>
    | TokQuestion    -- ?

    -- Operators
    | TokEq          -- =
    | TokEqEq        -- ==
    | TokNotEq       -- !=
    | TokLt          -- <
    | TokLtEq        -- <=
    | TokGt          -- >
    | TokGtEq        -- >=
    | TokPlus        -- +
    | TokMinus       -- -
    | TokStar        -- *
    | TokSlash       -- /
    | TokPercent     -- %
    | TokAnd         -- and
    | TokOr          -- or
    | TokNot         -- not

    -- End of File
    | TokEOF
    deriving stock (Eq, Ord, Show, Generic)
