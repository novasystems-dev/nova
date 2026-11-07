{-# LANGUAGE OverloadedStrings #-}

module Main where

import System.Environment (getArgs, getExecutablePath, lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (takeBaseName, takeDirectory, (</>))
import System.Process (callCommand)
import System.Directory (getCurrentDirectory, doesFileExist, getTemporaryDirectory)
import qualified System.Info as Info
import Data.Text (Text)
import qualified Data.Text.IO as TIO
import qualified Data.Text as T

import Nova.Parser.Parser (parseNovaProgram)
import Nova.Typecheck.Checker (typecheckProgram, TypeError(..))
import Nova.IR.HIR (lowerASTtoHIR, dumpHIR)
import Nova.IR.MIR (lowerHIRtoMIR, optimizeMIR, dumpMIR)
import Nova.Codegen.C99 (emitC99Program, compileAndLinkC99)
import Nova.Codegen.LLVM (emitLLVMProgram)

banner :: Text
banner = T.unlines
    [ "=========================================================="
    , "  NOVAC - Genesis Stage 0 Bootstrap Compiler"
    , "  Nova Systems Programming Language v0.1.0-alpha"
    , "=========================================================="
    ]

helpText :: Text
helpText = T.unlines
    [ "Usage:"
    , "  novac <command> [options] <source.nova>"
    , ""
    , "Commands:"
    , "  check <file>       Run lexer, parser, typechecker, and Z3 SMT verifier"
    , "  build <file>       Transpile to C99 and compile to native executable"
    , "  run   <file>       Compile and execute native binary immediately"
    , "  repl               Launch interactive Nova REPL"
    , "  --emit-c <file>    Emit transpiled C99 source code to stdout"
    , "  --emit-llvm <file> Emit target LLVM IR assembly (.ll) to stdout"
    , "  --dump-hir <file>  Dump High-Level Intermediate Representation"
    , "  --dump-mir <file>  Dump SSA Control Flow Graph Mid-Level IR"
    , "  version            Display compiler build and version info"
    ]

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["version"] -> do
            TIO.putStrLn banner
            TIO.putStrLn "novac version 0.1.0-alpha (Haskell Genesis Bootstrap)"
            exitSuccess

        ["help"] -> do
            TIO.putStrLn helpText
            exitSuccess

        ["check", file] -> do
            TIO.putStrLn banner
            _ <- checkFile file
            exitSuccess

        ["build", file] -> do
            TIO.putStrLn banner
            outBin <- buildFile file
            TIO.putStrLn $ "-> Compilation finished: " <> T.pack outBin
            exitSuccess

        ["run", file] -> do
            TIO.putStrLn banner
            outBin <- buildFile file
            let runCmd = if Info.os == "mingw32" then "." </> outBin else "./" <> outBin
            TIO.putStrLn $ "-> Executing binary: " <> T.pack runCmd
            TIO.putStrLn "----------------------------------------------------------"
            callCommand runCmd
            exitSuccess

        ["repl"] -> do
            callCommand "nova-repl"
            exitSuccess

        ["--emit-c", file] -> do
            content <- TIO.readFile file
            case parseNovaProgram (T.pack file) content of
                Left parseErr -> do
                    TIO.putStrLn $ "Parse Error:\n" <> T.pack (show parseErr)
                    exitFailure
                Right ast -> do
                    TIO.putStrLn (emitC99Program ast)
                    exitSuccess

        ["--emit-llvm", file] -> do
            content <- TIO.readFile file
            case parseNovaProgram (T.pack file) content of
                Left parseErr -> do
                    TIO.putStrLn $ "Parse Error:\n" <> T.pack (show parseErr)
                    exitFailure
                Right ast -> do
                    TIO.putStrLn (emitLLVMProgram ast)
                    exitSuccess

        ["--dump-hir", file] -> do
            content <- TIO.readFile file
            case parseNovaProgram (T.pack file) content of
                Left parseErr -> do
                    TIO.putStrLn $ "Parse Error:\n" <> T.pack (show parseErr)
                    exitFailure
                Right ast -> do
                    let hir = lowerASTtoHIR ast
                    TIO.putStrLn (dumpHIR hir)
                    exitSuccess

        ["--dump-mir", file] -> do
            content <- TIO.readFile file
            case parseNovaProgram (T.pack file) content of
                Left parseErr -> do
                    TIO.putStrLn $ "Parse Error:\n" <> T.pack (show parseErr)
                    exitFailure
                Right ast -> do
                    let hir = lowerASTtoHIR ast
                    let mir = optimizeMIR (lowerHIRtoMIR hir)
                    TIO.putStrLn (dumpMIR mir)
                    exitSuccess

        [] -> do
            TIO.putStrLn banner
            TIO.putStrLn helpText
            exitFailure

        _ -> do
            TIO.putStrLn "Error: Invalid command-line arguments. Run `novac help` for usage."
            exitFailure

checkFile :: FilePath -> IO (Either String ())
checkFile file = do
    TIO.putStrLn $ "-> Checking source file: " <> T.pack file
    exists <- doesFileExist file
    if not exists
        then do
            TIO.putStrLn $ "Error: File not found: " <> T.pack file
            exitFailure
        else do
            content <- TIO.readFile file
            TIO.putStrLn $ "-> Loaded source (" <> T.pack (show (T.length content)) <> " bytes)."
            case parseNovaProgram (T.pack file) content of
                Left parseErr -> do
                    TIO.putStrLn $ "Parse Error:\n" <> T.pack (show parseErr)
                    exitFailure
                Right ast -> do
                    TIO.putStrLn "   [1/3] Lexing & Indentation Layout... OK"
                    TIO.putStrLn "   [2/3] Surface AST Parsing (Pratt)... OK"
                    case typecheckProgram ast of
                        Left (TypeError msg _ code) -> do
                            TIO.putStrLn $ "Type/Proof Error [" <> code <> "]: " <> msg
                            exitFailure
                        Right () -> do
                            TIO.putStrLn "   [3/3] Bidirectional Typing & Z3 SMT Verification... OK"
                            TIO.putStrLn "-> All formal properties verified. Ready for code generation."
                            return (Right ())

findRuntimeDir :: IO FilePath
findRuntimeDir = do
    mEnv <- lookupEnv "NOVA_RUNTIME"
    case mEnv of
        Just p -> return p
        Nothing -> do
            currDir <- getCurrentDirectory
            let currRt = currDir </> "runtime"
            currExists <- doesFileExist (currRt </> "nova_rt.h")
            if currExists
                then return currRt
                else do
                    exePath <- getExecutablePath
                    let parentRt = takeDirectory (takeDirectory exePath) </> "runtime"
                    parentExists <- doesFileExist (parentRt </> "nova_rt.h")
                    if parentExists
                        then return parentRt
                        else return currRt

buildFile :: FilePath -> IO FilePath
buildFile file = do
    content <- TIO.readFile file
    case parseNovaProgram (T.pack file) content of
        Left parseErr -> do
            TIO.putStrLn $ "Parse Error:\n" <> T.pack (show parseErr)
            exitFailure
        Right ast -> do
            case typecheckProgram ast of
                Left (TypeError msg _ code) -> do
                    TIO.putStrLn $ "Type/Proof Error [" <> code <> "]: " <> msg
                    exitFailure
                Right () -> do
                    let cCode = emitC99Program ast
                    let base = takeBaseName file
                    tmpDir <- getTemporaryDirectory
                    let cFile = tmpDir </> (base <> ".c")
                    let exeExt = if Info.os == "mingw32" then ".exe" else ""
                    let outBin = base <> ".out" <> exeExt
                    TIO.writeFile cFile cCode
                    runtimeDir <- findRuntimeDir
                    compileAndLinkC99 cFile runtimeDir outBin
                    return outBin
