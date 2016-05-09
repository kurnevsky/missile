module Bot ( Bot
           , run
           , quit
           , stop
           , listCommands
           , Bot.init
           , name
           , version
           , play
           , genMove
           , genMoveWithComplexity
           , genMoveWithTime
           , undo
           ) where

import GHC.IO.Handle
import System.IO
import System.Process
import Control.Monad
import Data.List.Split
import Control.Concurrent
import Control.Exception
import Player
import Field

data Bot = Bot { stdInput :: Handle
               , stdOutput :: Handle
               , stdError :: Handle
               , processId :: ProcessHandle
               }

splitAnswer :: String -> [String]
splitAnswer = filter (not . null) . splitOn " "

botQuestion :: Bot -> String -> IO ()
botQuestion bot question =
  hPutStrLn (stdInput bot) $ "0 " ++ question

botAnswer :: Bot -> IO [String]
botAnswer bot =
  do ("=" : "0" : answer) <- liftM splitAnswer $ hGetLine $ stdOutput bot
     return answer

botPlayer :: Player -> String
botPlayer Red = "0"
botPlayer Black = "1"

run :: String -> IO Bot
run path =
  do (inp, out, err, pid) <- runInteractiveProcess path [] Nothing Nothing
     hSetBuffering inp NoBuffering
     hSetBuffering out NoBuffering
     hSetBuffering err NoBuffering
     return Bot { stdInput = inp
                , stdOutput = out
                , stdError = err
                , processId = pid
                }

quit :: Bot -> IO ()
quit bot =
  do botQuestion bot "quit"
     ["quit"] <- botAnswer bot
     return ()

stop :: Bot -> Int -> IO ()
stop bot delay =
  do answerEither <- try (quit bot) :: IO (Either SomeException ())
     case answerEither of
       Left _  -> terminateProcess (processId bot)
       Right _ ->
         do threadDelay delay
            maybeExitCode <- getProcessExitCode (processId bot)
            case maybeExitCode of
              Nothing -> terminateProcess (processId bot)
              Just _  -> return ()
     void $ waitForProcess (processId bot)

listCommands :: Bot -> IO [String]
listCommands bot =
  do botQuestion bot "list_commands"
     ("list_commands" : answer) <- botAnswer bot
     return answer

init :: Bot -> Int -> Int -> Int -> IO ()
init bot width height seed =
  do botQuestion bot $ "init " ++ show width ++ " " ++ show height ++ " " ++ show seed
     ["init"] <- botAnswer bot
     return ()

name :: Bot -> IO String
name bot =
  do botQuestion bot "name"
     ("name" : [answer]) <- botAnswer bot
     return answer

version :: Bot -> IO String
version bot =
  do botQuestion bot "version"
     ("version" : [answer]) <- botAnswer bot
     return answer

play :: Bot -> Pos -> Player -> IO ()
play bot pos player =
  do let strX = show $ fst pos
         strY = show $ snd pos
         strPlayer = botPlayer player
     botQuestion bot $ "play " ++ strX ++ " " ++ strY ++ " " ++ strPlayer
     ("play" : answerX : answerY : [answerPlayer]) <- botAnswer bot
     when (answerX /= strX || answerY /= strY || answerPlayer /= strPlayer) $
       error "play: invalid answer."

genMove :: Bot -> Player -> IO Pos
genMove bot player =
  do let strPlayer = botPlayer player
     botQuestion bot $ "gen_move " ++ strPlayer
     ("gen_move" : answerX : answerY : [answerPlayer]) <- botAnswer bot
     if answerPlayer /= strPlayer
       then error "genMove: invalid answer."
       else return (read answerX, read answerY)

genMoveWithComplexity :: Bot -> Player -> Int -> IO Pos
genMoveWithComplexity bot player complexity =
  do let strPlayer = botPlayer player
     botQuestion bot $ "gen_move_with_complexity " ++ strPlayer ++ " " ++ show complexity
     ("gen_move_with_complexity" : answerX : answerY : [answerPlayer]) <- botAnswer bot
     if answerPlayer /= strPlayer
       then error "genMoveWithComplexity: invalid answer."
       else return (read answerX, read answerY)

genMoveWithTime :: Bot -> Player -> Int -> IO Pos
genMoveWithTime bot player time =
  do let strPlayer = botPlayer player
     botQuestion bot $ "gen_move_with_time " ++ strPlayer ++ " " ++ show time
     ("gen_move_with_time" : answerX : answerY : [answerPlayer]) <- botAnswer bot
     if answerPlayer /= strPlayer
       then error "genMoveWithTime: invalid answer."
       else return (read answerX, read answerY)

undo :: Bot -> IO ()
undo bot =
  do botQuestion bot "undo"
     ["undo"] <- botAnswer bot
     return ()
