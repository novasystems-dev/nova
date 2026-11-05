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
    , diagMessage    :: !Text          -- Human-readable explanation
    , diagSpan       :: !Span
    , diagHelp       :: !(Maybe Text)  -- Concrete suggested fix
    } deriving (Eq, Show)

renderDiagnostic :: Text -> Diagnostic -> Text
renderDiagnostic sourceCode Diagnostic{..} =
    let header = case diagSeverity of
            Error      -> "error[" <> diagCode <> "]: " <> diagMessage
            Warning    -> "warning[" <> diagCode <> "]: " <> diagMessage
            Info       -> "info: " <> diagMessage
            Suggestion -> "help: " <> diagMessage

        locInfo = "  --> " <> spanFile diagSpan <> ":"
                  <> T.pack (show (locLine (spanStart diagSpan))) <> ":"
                  <> T.pack (show (locColumn (spanStart diagSpan)))

        lineNum = locLine (spanStart diagSpan)
        linesList = T.lines sourceCode
        codeSnippet = if lineNum > 0 && lineNum <= length linesList
                      then "   |\n"
                           <> T.justifyRight 4 ' ' (T.pack (show lineNum)) <> " | " <> (linesList !! (lineNum - 1)) <> "\n"
                           <> "   | " <> T.replicate (locColumn (spanStart diagSpan) - 1) " " <> "^^^"
                      else ""

        helpMsg = case diagHelp of
            Just h  -> "\n  = suggestion: " <> h
            Nothing -> ""

    in header <> "\n" <> locInfo <> "\n" <> codeSnippet <> helpMsg <> "\n"
