{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Nova.Syntax.Span
    ( SourceLoc(..)
    , Span(..)
    , Spanned(..)
    , mergeSpans
    , emptySpan
    ) where

import GHC.Generics (Generic)
import Data.Text (Text)

-- | Represents an exact line and column in a source file
data SourceLoc = SourceLoc
    { locLine   :: !Int
    , locColumn :: !Int
    } deriving stock (Eq, Ord, Show, Generic)

-- | A source span delimited by start and end locations within a file
data Span = Span
    { spanFile  :: !Text
    , spanStart :: !SourceLoc
    , spanEnd   :: !SourceLoc
    } deriving stock (Eq, Ord, Show, Generic)

-- | Wrapper to attach source spans to arbitrary AST nodes
data Spanned a = Spanned
    { spannedNode :: !a
    , spannedSpan :: !Span
    } deriving stock (Eq, Ord, Show, Functor, Generic)

mergeSpans :: Span -> Span -> Span
mergeSpans (Span f s1 _) (Span _ _ e2) = Span f s1 e2

emptySpan :: Span
emptySpan = Span "" (SourceLoc 0 0) (SourceLoc 0 0)
