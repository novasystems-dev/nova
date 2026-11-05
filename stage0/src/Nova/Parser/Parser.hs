{-# LANGUAGE OverloadedStrings #-}

module Nova.Parser.Parser
    ( parseNovaProgram
    , parseExpr
    , parseStmt
    ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Control.Monad.Combinators.Expr as E

import Nova.Syntax.Span
import Nova.Syntax.Token
import Nova.Syntax.AST
import Nova.Parser.Lexer

type P = Parsec Void Text

-- | Helper to wrap an AST node into a Spanned container
spanned :: P a -> P (Spanned a)
spanned p = do
    startPos <- getSourcePos
    val <- p
    endPos <- getSourcePos
    let sp = Span
            { spanFile  = T.pack (sourceName startPos)
            , spanStart = SourceLoc (unPos (sourceLine startPos)) (unPos (sourceColumn startPos))
            , spanEnd   = SourceLoc (unPos (sourceLine endPos)) (unPos (sourceColumn endPos))
            }
    return (Spanned val sp)

-- ============================================================================
-- TOP-LEVEL PARSER
-- ============================================================================

parseNovaProgram :: Text -> Text -> Either (ParseErrorBundle Text Void) Program
parseNovaProgram filename input = runParser (programParser <* eof) (T.unpack filename) input

programParser :: P Program
programParser = sc >> Program <$> many topLevelItem

topLevelItem :: P (Spanned TopLevel)
topLevelItem = spanned $ choice
    [ TopFn     <$> parseFnDecl
    , TopType   <$> parseTypeDecl
    , parseImportDecl
    ]

parseImportDecl :: P TopLevel
parseImportDecl = do
    _ <- symbol "import"
    modPath <- sepBy1 parseIdentifier (symbol ".")
    alias <- optional (symbol "as" >> parseIdentifier)
    symbols <- option [] (between (symbol "{") (symbol "}") (sepBy parseIdentifier (symbol ",")))
    return $ TopImport modPath alias symbols

-- ============================================================================
-- FUNCTION DECLARATIONS
-- ============================================================================

parseFnDecl :: P FnDecl
parseFnDecl = do
    fnPos <- getSourcePos
    let baseCol = unPos (sourceColumn fnPos)
    isPub <- isJust <$> optional (symbol "pub")
    _ <- symbol "fn"
    name <- parseIdentifier
    tparams <- parseOptionalTypeParams
    params <- symbol "(" >> parseParamList <* symbol ")"
    retType <- optional (symbol "->" >> parseTypeExpr)
    contract <- optional (symbol "where" >> spanned parseExpr)
    _ <- symbol ":"
    body <- parseBlock baseCol
    return $ FnDecl isPub name tparams params retType contract body
  where
    isJust (Just _) = True
    isJust Nothing  = False

parseParamList :: P [Param]
parseParamList = sepBy parseParam (symbol ",")

parseParam :: P Param
parseParam = do
    isMut <- isJust <$> optional (symbol "mut")
    cap <- optional parseCapability
    name <- parseIdentifier
    _ <- symbol ":"
    ty <- parseTypeExpr
    whereClause <- optional (symbol "where" >> spanned parseExpr)
    return $ Param isMut cap name ty whereClause
  where
    isJust (Just _) = True
    isJust Nothing  = False

parseOptionalTypeParams :: P [Text]
parseOptionalTypeParams = option [] $ between (symbol "[") (symbol "]") (sepBy parseIdentifier (symbol ","))

-- ============================================================================
-- TYPE DECLARATIONS
-- ============================================================================

parseTypeDecl :: P TypeDecl
parseTypeDecl = do
    typePos <- getSourcePos
    let baseCol = unPos (sourceColumn typePos)
    isPub <- isJust <$> optional (symbol "pub")
    _ <- symbol "type"
    name <- parseIdentifier
    tparams <- parseOptionalTypeParams
    _ <- symbol "="
    def <- parseTypeDef baseCol
    return $ TypeDecl isPub name tparams def
  where
    isJust (Just _) = True
    isJust Nothing  = False

parseTypeDef :: Int -> P TypeDef
parseTypeDef baseCol = choice
    [ try parseRefinementDef
    , try (parseStructDef baseCol)
    , try (parseEnumDef baseCol)
    , TypeAlias <$> parseTypeExpr
    ]

parseRefinementDef :: P TypeDef
parseRefinementDef = do
    varName <- parseIdentifier
    _ <- symbol ":"
    baseTy <- parseTypeExpr
    _ <- symbol "where"
    predExpr <- spanned parseExpr
    return $ TypeRefinement varName baseTy predExpr

parseStructDef :: Int -> P TypeDef
parseStructDef baseCol = do
    _ <- symbol "struct"
    choice
        [ between (symbol "{") (symbol "}") (sepBy parseStructField (symbol ",")) >>= return . TypeStruct
        , do
            _ <- symbol ":"
            fields <- some (try (checkIndent baseCol) >> parseStructField)
            return (TypeStruct fields)
        ]
  where
    checkIndent col = do
        pos <- getSourcePos
        if unPos (sourceColumn pos) > col then return () else empty

parseStructField :: P (Text, TypeExpr)
parseStructField = do
    fname <- parseIdentifier
    _ <- symbol ":"
    fty <- parseTypeExpr
    return (fname, fty)

parseEnumDef :: Int -> P TypeDef
parseEnumDef baseCol = do
    _ <- symbol "enum"
    choice
        [ between (symbol "{") (symbol "}") (sepBy parseEnumVariant (symbol ",")) >>= return . TypeEnum
        , do
            _ <- symbol ":"
            variants <- some (try (checkIndent baseCol) >> parseEnumVariant)
            return (TypeEnum variants)
        ]
  where
    checkIndent col = do
        pos <- getSourcePos
        if unPos (sourceColumn pos) > col then return () else empty

parseEnumVariant :: P (Text, [TypeExpr])
parseEnumVariant = do
    vname <- parseIdentifier
    vpayload <- option [] (between (symbol "(") (symbol ")") (sepBy parseVariantField (symbol ",")))
    return (vname, vpayload)
  where
    parseVariantField = try (parseIdentifier >> symbol ":" >> parseTypeExpr) <|> parseTypeExpr

parseTypeExpr :: P TypeExpr
parseTypeExpr = choice
    [ TyCapability <$> parseCapability <*> parseTypeExpr
    , try parseGenericType
    , TyList <$> between (symbol "[") (symbol "]") parseTypeExpr
    , TyNamed <$> parseIdentifier
    ]

parseGenericType :: P TypeExpr
parseGenericType = do
    name <- parseIdentifier
    args <- between (symbol "[") (symbol "]") (sepBy parseTypeExpr (symbol ","))
    return $ TyGeneric name args

parseCapability :: P Capability
parseCapability = choice
    [ CapIso   <$ symbol "iso"
    , CapVal   <$ symbol "val"
    , CapRef   <$ symbol "ref"
    , CapToken <$ symbol "cap"
    ]

-- ============================================================================
-- STATEMENTS & BLOCKS (Indentation-Aware)
-- ============================================================================

parseBlock :: Int -> P [Spanned Stmt]
parseBlock baseCol = choice
    [ between (symbol "{") (symbol "}") (many (spanned parseStmt))
    , some (try (checkIndent baseCol) >> spanned parseStmt)
    ]
  where
    checkIndent col = do
        pos <- getSourcePos
        if unPos (sourceColumn pos) > col
            then return ()
            else empty

parseStmt :: P Stmt
parseStmt = do
    stmtPos <- getSourcePos
    let baseCol = unPos (sourceColumn stmtPos)
    choice
        [ parseLetStmt
        , parseReturnStmt
        , parseIfStmt baseCol
        , parseMatchStmt baseCol
        , parseWhileStmt baseCol
        , parseForStmt baseCol
        , parseUnsafeBlock baseCol
        , parseRegionBlock baseCol
        , try parseAssignStmt
        , StmtExpr <$> spanned parseExpr
        ]

parseMatchStmt :: Int -> P Stmt
parseMatchStmt baseCol = do
    _ <- symbol "match"
    target <- spanned parseExpr
    _ <- symbol ":"
    arms <- choice
        [ between (symbol "{") (symbol "}") (many parseMatchArm)
        , some (try (checkIndent baseCol) >> parseMatchArm)
        ]
    return $ StmtMatch target arms
  where
    checkIndent col = do
        pos <- getSourcePos
        if unPos (sourceColumn pos) > col then return () else empty

    parseMatchArm = do
        armPos <- getSourcePos
        let armCol = unPos (sourceColumn armPos)
        pat <- parsePattern
        guard <- optional (symbol "if" >> spanned parseExpr)
        _ <- symbol "=>"
        body <- choice
            [ parseBlock armCol
            , do
                s <- spanned parseStmt
                return [s]
            , do
                e <- spanned parseExpr
                return [Spanned (StmtReturn (Just e)) (spannedSpan e)]
            ]
        return (pat, guard, body)

parseLetStmt :: P Stmt
parseLetStmt = do
    _ <- symbol "let"
    pat <- parsePattern
    annot <- optional (symbol ":" >> parseTypeExpr)
    _ <- symbol "="
    val <- spanned parseExpr
    return $ StmtLet pat annot val

parseAssignStmt :: P Stmt
parseAssignStmt = do
    lhs <- spanned parseExpr
    _ <- symbol "="
    rhs <- spanned parseExpr
    return $ StmtAssign lhs rhs

parseReturnStmt :: P Stmt
parseReturnStmt = do
    _ <- symbol "return"
    val <- optional (spanned parseExpr)
    return $ StmtReturn val

parseIfStmt :: Int -> P Stmt
parseIfStmt baseCol = do
    _ <- symbol "if"
    cond <- spanned parseExpr
    _ <- symbol ":"
    thenBlk <- parseBlock baseCol
    elifs <- many parseElif
    elseBlk <- optional (symbol "else" >> symbol ":" >> parseBlock baseCol)
    return $ StmtIf cond thenBlk elifs elseBlk
  where
    parseElif = do
        _ <- symbol "elif"
        c <- spanned parseExpr
        _ <- symbol ":"
        b <- parseBlock baseCol
        return (c, b)

parseWhileStmt :: Int -> P Stmt
parseWhileStmt baseCol = do
    _ <- symbol "while"
    choice
        [ try $ do
            _ <- symbol "let"
            _ <- parsePattern
            _ <- symbol "="
            condExpr <- spanned parseExpr
            _ <- symbol ":"
            body <- parseBlock baseCol
            return $ StmtWhile condExpr body
        , do
            cond <- spanned parseExpr
            _ <- symbol ":"
            body <- parseBlock baseCol
            return $ StmtWhile cond body
        ]

parseForStmt :: Int -> P Stmt
parseForStmt baseCol = do
    _ <- symbol "for"
    pat <- parsePattern
    _ <- symbol "in"
    iter <- spanned parseExpr
    _ <- symbol ":"
    body <- parseBlock baseCol
    return $ StmtFor pat iter body

parseUnsafeBlock :: Int -> P Stmt
parseUnsafeBlock baseCol = do
    _ <- symbol "unsafe"
    tokenName <- between (symbol "(") (symbol ")") parseIdentifier
    _ <- symbol ":"
    body <- parseBlock baseCol
    return $ StmtUnsafe tokenName body

parseRegionBlock :: Int -> P Stmt
parseRegionBlock baseCol = do
    _ <- symbol "region"
    regName <- parseIdentifier
    _ <- symbol ":"
    body <- parseBlock baseCol
    return $ StmtRegion regName body

-- ============================================================================
-- PATTERN MATCHING
-- ============================================================================

parsePattern :: P Pattern
parsePattern = choice
    [ PatWildcard <$ symbol "_"
    , PatLit      <$> parseLiteral
    , try (between (symbol "(") (symbol ")") (PatTuple <$> sepBy parsePattern (symbol ",")))
    , try (PatVar True  <$> (symbol "mut" >> parseIdentifier))
    , try parseVariantPattern
    , PatVar False <$> parseIdentifier
    ]

parseVariantPattern :: P Pattern
parseVariantPattern = do
    vname <- parseIdentifier
    args <- between (symbol "(") (symbol ")") (sepBy parsePattern (symbol ","))
    return $ PatVariant vname args

-- ============================================================================
-- PRATT EXPRESSION PARSER
-- ============================================================================

parseExpr :: P Expr
parseExpr = E.makeExprParser parsePostfixExpr operatorTable

operatorTable :: [[E.Operator P Expr]]
operatorTable =
    [ [ E.Prefix ((\e -> ExprUnary OpNot (Spanned e emptySpan)) <$ symbol "not")
      , E.Prefix ((\e -> ExprUnary OpNeg (Spanned e emptySpan)) <$ symbol "-")
      ]
    , [ E.InfixL (binaryOp OpMul <$ symbol "*")
      , E.InfixL (binaryOp OpDiv <$ symbol "/")
      , E.InfixL (binaryOp OpMod <$ symbol "%")
      ]
    , [ E.InfixL (binaryOp OpAdd <$ symbol "+")
      , E.InfixL (binaryOp OpSub <$ symbol "-")
      ]
    , [ E.InfixN (binaryOp OpLtEq  <$ symbol "<=")
      , E.InfixN (binaryOp OpGtEq  <$ symbol ">=")
      , E.InfixN (binaryOp OpLt    <$ symbol "<")
      , E.InfixN (binaryOp OpGt    <$ symbol ">")
      , E.InfixN (binaryOp OpEq    <$ symbol "==")
      , E.InfixN (binaryOp OpNotEq <$ symbol "!=")
      ]
    , [ E.InfixL (binaryOp OpAnd <$ symbol "and") ]
    , [ E.InfixL (binaryOp OpOr  <$ symbol "or")  ]
    ]
  where
    binaryOp op lhs rhs =
        ExprBinary op (Spanned lhs emptySpan) (Spanned rhs emptySpan)

parsePostfixExpr :: P Expr
parsePostfixExpr = do
    base <- parsePrimaryExpr
    suffixes <- many parseSuffix
    return (foldl applySuffix base suffixes)
  where
    parseSuffix = choice
        [ parseCallSuffix
        , parseIndexSuffix
        , parseFieldSuffix
        ]

    parseCallSuffix = do
        args <- between (symbol "(") (symbol ")") (sepBy (spanned parseExpr) (symbol ","))
        return (\e -> ExprCall (Spanned e emptySpan) args)

    parseIndexSuffix = do
        idx <- between (symbol "[") (symbol "]") (spanned parseExpr)
        return (\e -> ExprIndex (Spanned e emptySpan) idx)

    parseFieldSuffix = do
        _ <- symbol "."
        f <- parseIdentifier
        return (\e -> ExprField (Spanned e emptySpan) f)

    applySuffix expr f = f expr

parsePrimaryExpr :: P Expr
parsePrimaryExpr = choice
    [ between (symbol "(") (symbol ")") parseExpr
    , try parseLambdaExpr
    , try parseStructInit
    , try (parseCapability >> parsePrimaryExpr)
    , ExprLit  <$> parseLiteral
    , ExprVar  <$> parseIdentifier
    , ExprList <$> between (symbol "[") (symbol "]") (sepBy (spanned parseExpr) (symbol ","))
    ]
  where
    parseLambdaExpr = do
        _ <- symbol "fn"
        _ <- symbol "("
        _ <- sepBy parseIdentifier (symbol ",")
        _ <- symbol ")"
        _ <- symbol "=>"
        parseExpr

    parseStructInit = do
        _ <- optional parseCapability
        name <- parseIdentifier
        fields <- between (symbol "{") (symbol "}") (sepBy parseFieldInit (symbol ","))
        return $ ExprCall (Spanned (ExprVar name) emptySpan) fields

    parseFieldInit = do
        _ <- parseIdentifier
        _ <- symbol ":"
        spanned parseExpr
