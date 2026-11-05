module Nova.Parser.Indent
    ( layoutProcess
    , IndentState(..)
    ) where

import Nova.Syntax.Token

data IndentState = IndentState
    { indentStack :: ![Int]   -- Stack of indentation column numbers
    } deriving (Eq, Show)

-- | Process raw indentation column levels and emit virtual INDENT / DEDENT / NEWLINE tokens
layoutProcess :: [Int] -> [Token]
layoutProcess = go (IndentState [0])
  where
    go :: IndentState -> [Int] -> [Token]
    go (IndentState []) cols = go (IndentState [0]) cols
    go (IndentState stack) [] =
        -- Reached EOF: Emit DEDENT for every active indent level > 0
        replicate (length stack - 1) TokDedent ++ [TokEOF]

    go st@(IndentState (top:rest)) (col:cols)
        | col > top =
            -- Indent deeper: Push new column and emit TokIndent
            TokIndent : go (IndentState (col:top:rest)) cols
        | col == top =
            -- Same indentation: Emit TokNewline
            TokNewline : go st cols
        | otherwise =
            -- Dedent: Pop stack until we find matching column
            let dedents = countDedents top rest col
            in replicate dedents TokDedent ++ [TokNewline] ++ go (IndentState (drop dedents (top:rest))) cols

    countDedents _ [] _ = 0
    countDedents current (lvl:lvls) targetCol
        | current <= targetCol = 0
        | otherwise = 1 + countDedents lvl lvls targetCol
