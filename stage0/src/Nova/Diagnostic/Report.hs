{-# LANGUAGE OverloadedStrings #-}

module Nova.Diagnostic.Report
    ( Diagnostic(..)
    , Severity(..)
    , renderDiagnostic
    ) where

import Data.Text (Text)
import qualified Data.Text as T
import Nova.Syntax.Span (Span(..), SourceLoc(..))

data Severity = Error | Warning | Info | Suggestion
    deriving (Eq, Show)

data Diagnostic = Diagnostic
    { diagSeverity   :: !Severity
    , diagCode       :: !Text          -- e.g. "E0101"
    , diagMessage    :: !Text          -- Human readable description
    , diagSpan       :: !Span
    , diagHelp       :: !(Maybe Text)  -- Concrete fix suggestion
    } deriving (Eq, Show)

renderDiagnostic :: Text -> Diagnostic -> Text
renderDiagnostic sourceCode Diagnostic{..} =
    let header = case diagSeverity of
            Error      -> "❌ [LỖI " <> diagCode <> "]: " <> diagMessage
            Warning    -> "⚠️  [CẢNH BÁO " <> diagCode <> "]: " <> diagMessage
            Info       -> "ℹ️  [THÔNG TIN]: " <> diagMessage
            Suggestion -> "💡 [GỢI Ý]: " <> diagMessage

        locInfo = "  --> " <> spanFile diagSpan <> ":"
                  <> T.pack (show (locLine (spanStart diagSpan))) <> ":"
                  <> T.pack (show (locColumn (spanStart diagSpan)))

        lineNum = locLine (spanStart diagSpan)
        linesList = T.lines sourceCode
        codeSnippet = if lineNum > 0 && lineNum <= length linesList
                      then "   | \n"
                           <> T.pack (show lineNum) <> " | " <> (linesList !! (lineNum - 1)) <> "\n"
                           <> "   | " <> T.replicate (locColumn (spanStart diagSpan) - 1) " " <> "^^^"
                      else ""

        helpMsg = case diagHelp of
            Just h  -> "\n  = Gợi ý sửa: " <> h
            Nothing -> ""

    in header <> "\n" <> locInfo <> "\n" <> codeSnippet <> helpMsg <> "\n"
