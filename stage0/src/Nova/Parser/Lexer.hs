{-# LANGUAGE OverloadedStrings #-}

module Nova.Parser.Lexer
    ( Parser
    , sc
    , lexeme
    , symbol
    , parseIdentifier
    , parseKeyword
    , parseLiteral
    , parseOperator
    ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L
import Nova.Syntax.Token

type Parser = Parsec Void Text

-- | Space consumer (ignoring spaces and comments starting with #)
sc :: Parser ()
sc = L.space
    (void $ some (char ' ' <|> char '\t'))
    (L.skipLineComment "#")
    empty

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

symbol :: Text -> Parser Text
symbol = L.symbol sc

parseKeyword :: Parser Keyword
parseKeyword = lexeme $ choice
    [ KwFn       <$ string "fn"
    , KwLet      <$ string "let"
    , KwMut      <$ string "mut"
    , KwType     <$ string "type"
    , KwMatch    <$ string "match"
    , KwWhere    <$ string "where"
    , KwIf       <$ string "if"
    , KwElif     <$ string "elif"
    , KwElse     <$ string "else"
    , KwFor      <$ string "for"
    , KwWhile    <$ string "while"
    , KwReturn   <$ string "return"
    , KwBreak    <$ string "break"
    , KwContinue <$ string "continue"
    , KwPub      <$ string "pub"
    , KwImport   <$ string "import"
    , KwAs       <$ string "as"
    , KwTrait    <$ string "trait"
    , KwImpl     <$ string "impl"
    , KwUnsafe   <$ string "unsafe"
    , KwCap      <$ string "cap"
    , KwRegion   <$ string "region"
    , KwIso      <$ string "iso"
    , KwVal      <$ string "val"
    , KwRef      <$ string "ref"
    ] <* notFollowedBy alphaNumChar

parseIdentifier :: Parser Text
parseIdentifier = lexeme $ do
    c <- letterChar <|> char '_'
    cs <- many (alphaNumChar <|> char '_')
    let ident = T.pack (c:cs)
    return ident

parseLiteral :: Parser Literal
parseLiteral = lexeme $ choice
    [ try parseFloat
    , parseInt
    , parseString
    , parseBool
    ]
  where
    parseInt = LitInt <$> L.decimal
    parseFloat = LitFloat <$> L.float
    parseString = LitString . T.pack <$> (char '"' >> manyTill L.charLiteral (char '"'))
    parseBool = LitBool <$> choice [True <$ string "true", False <$ string "false"]

parseOperator :: Parser Token
parseOperator = lexeme $ choice
    [ TokEqEq     <$ symbol "=="
    , TokNotEq    <$ symbol "!="
    , TokLtEq     <$ symbol "<="
    , TokGtEq     <$ symbol ">="
    , TokArrow    <$ symbol "->"
    , TokFatArrow <$ symbol "=>"
    , TokEq       <$ symbol "="
    , TokLt       <$ symbol "<"
    , TokGt       <$ symbol ">"
    , TokPlus     <$ symbol "+"
    , TokMinus    <$ symbol "-"
    , TokStar     <$ symbol "*"
    , TokSlash    <$ symbol "/"
    , TokPercent  <$ symbol "%"
    , TokLParen   <$ symbol "("
    , TokRParen   <$ symbol ")"
    , TokLBracket <$ symbol "["
    , TokRBracket <$ symbol "]"
    , TokLBrace   <$ symbol "{"
    , TokRBrace   <$ symbol "}"
    , TokColon    <$ symbol ":"
    , TokComma    <$ symbol ","
    , TokDot      <$ symbol "."
    , TokQuestion <$ symbol "?"
    ]
