module GameWithBot where

import Data.IORef
import Control.Monad
import Data.StateVar
import Data.Maybe
import Settings
import Player
import Field
import Game
import Bot
import AsyncBot

data GameWithBot = GameWithBot { gwbGame :: IORef Game
                               , gwbBot :: IORef (Maybe Bot)
                               , gwbBusy :: IORef Bool
                               , gwbBotError :: IO ()
                               , gwbUpdated :: IO ()
                               }

loadBot :: Game -> IO () -> (Bot -> IO ()) -> IO ()
loadBot game callbackError callback =
    let settings = gameSettings game
    in void $ asyncRun (aiPath settings) callbackError $ \bot ->
           void $ asyncInit bot (gameWidth settings) (gameHeight settings) 0 callbackError $
               if length (gameFields game) == 1
               then callback bot
               else void $ asyncPlayMany bot (reverse $ moves $ head $ gameFields game) callbackError (callback bot)

loadGWBBot :: GameWithBot -> IO ()
loadGWBBot gwb =
    do game <- get (gwbGame gwb)
       botMaybe <- get (gwbBot gwb)
       when (aiPresent (gameSettings game) && isNothing botMaybe) $
         do gwbBusy gwb $= True
            loadBot game (
              do gwbBusy gwb $= False
                 gwbBotError gwb) $ \bot ->
                   do gwbBot gwb $= Just bot
                      gwbBusy gwb $= False

killGWBBot :: GameWithBot -> IO ()
killGWBBot gwb =
    do botMaybe <- get (gwbBot gwb)
       case botMaybe of
         Nothing  -> return ()
         Just bot -> do asyncStop bot 200
                        gwbBot gwb $= Nothing

reloadGWBBot :: GameWithBot -> IO ()
reloadGWBBot gwb =
    do killGWBBot gwb
       loadGWBBot gwb

gameWithBot :: Game -> IO () -> IO GameWithBot
gameWithBot game callbackError =
    do busyRef <- newIORef False
       botRef <- newIORef Nothing
       gameRef <- newIORef game
       let gwb = GameWithBot { gwbGame = gameRef
                             , gwbBot = botRef
                             , gwbBusy = busyRef
                             , gwbBotError = callbackError
                             , gwbUpdated = return ()
                             }
       loadGWBBot gwb
       return gwb

botError :: GameWithBot -> IO ()
botError gwb =
    do killGWBBot gwb
       modifyIORef (gwbGame gwb) (\game -> game { gameSettings = (gameSettings game) { aiPresent = False } })
       gwbBusy gwb $= False
       gwbBotError gwb

putGWBPlayersPoint' :: Game -> Pos -> Player -> GameWithBot -> IO ()
putGWBPlayersPoint' game pos player gwb =
    do let settings = gameSettings game
           game' = putGamePlayersPoint pos player game
           player' = curPlayer game'
       botMaybe <- get (gwbBot gwb)
       case botMaybe of
         Nothing  -> do gwbGame gwb $= game'
                        gwbUpdated gwb
         Just bot -> do gwbBusy gwb $= True
                        gwbGame gwb $= game'
                        gwbUpdated gwb
                        void $ asyncPlay bot pos player (botError gwb) $
                                if aiRespondent settings
                                then let gen = case aiGenMoveType settings of
                                                 Simple                    -> asyncGenMove bot player'
                                                 WithTime time             -> asyncGenMoveWithTime bot player' time
                                                 WithComplexity complexity -> asyncGenMoveWithComplexity bot player' complexity
                                     in void $ gen (botError gwb) $ \pos' -> do
                                            let game'' = putGamePlayersPoint pos' player' game'
                                            gwbGame gwb $= game''
                                            gwbUpdated gwb
                                            void $ asyncPlay bot pos' player' (botError gwb) $
                                                gwbBusy gwb $= False
                                else gwbBusy gwb $= False

putGWBPlayersPoint :: Pos -> Player -> GameWithBot -> IO ()
putGWBPlayersPoint pos player gwb =
    do busy <- get (gwbBusy gwb)
       game <- get (gwbGame gwb)
       unless (busy || not (isPuttingAllowed (head $ gameFields game) pos)) $
         putGWBPlayersPoint' game pos player gwb

putGWBPoint :: Pos -> GameWithBot -> IO ()
putGWBPoint pos gwb =
    do busy <- get (gwbBusy gwb)
       game <- get (gwbGame gwb)
       unless (busy || not (isPuttingAllowed (head $ gameFields game) pos)) $
         putGWBPlayersPoint' game pos (curPlayer game) gwb

backGWB :: GameWithBot -> IO ()
backGWB gwb =
    do busy <- get (gwbBusy gwb)
       game <- get (gwbGame gwb)
       botMaybe <- get (gwbBot gwb)
       unless (busy || length (gameFields game) == 1) $
         case botMaybe of
           Nothing  -> do gwbGame gwb $= backGame game
                          gwbUpdated gwb
           Just bot -> do gwbBusy gwb $= True
                          gwbGame gwb $= backGame game
                          void $ asyncUndo bot (botError gwb) $
                            do gwbBusy gwb $= False
                               gwbUpdated gwb

reflectHorizontallyGWB :: GameWithBot -> IO ()
reflectHorizontallyGWB gwb =
    do busy <- get (gwbBusy gwb)
       unless busy $
         do game <- get (gwbGame gwb)
            gwbGame gwb $= reflectHorizontallyGame game
            reloadGWBBot gwb

reflectVerticallyGWB :: GameWithBot -> IO ()
reflectVerticallyGWB gwb =
    do busy <- get (gwbBusy gwb)
       unless busy $
         do game <- get (gwbGame gwb)
            gwbGame gwb $= reflectVerticallyGame game
            reloadGWBBot gwb

updateGWBSettings :: GameWithBot -> Settings -> IO ()
updateGWBSettings gwb settings =
    do game <- get (gwbGame gwb)
       gwbGame gwb $= updateGameSettings game settings
       let oldSettings = gameSettings game
       if | aiPresent oldSettings && not (aiPresent settings) -> killGWBBot gwb
          | not (aiPresent oldSettings) && aiPresent settings -> loadGWBBot gwb
          | aiPath oldSettings /= aiPath settings -> reloadGWBBot gwb
          | otherwise -> return ()
       gwbUpdated gwb
