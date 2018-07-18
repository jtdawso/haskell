{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Main where

import           Network.Pubnub
import           Network.Pubnub.Types

import           Control.Concurrent.Async
import           Control.Monad
import           Data.Aeson
import           Data.Maybe
import           GHC.Generics
import           System.Environment       (getArgs)

import qualified Data.ByteString.Lazy     as L
import qualified Data.Text                as T
import qualified Data.Text.IO             as I

data Msg = Msg { username :: T.Text
               , msg      :: T.Text }
           deriving (Show, Generic)

instance ToJSON Msg

instance FromJSON Msg

main :: IO ()
main = do
  args <- getArgs
  let pubKey = "pub-c-cc6cb3da-965a-450d-925c-ee50a0bdd838"
  let subKey = "sub-c-3c6311f6-1bb4-11e6-9327-02ee2ddab7fe"
  main2 pubKey subKey args

main2 :: T.Text -> T.Text -> [String] -> IO ()
main2 pubk subk ["producer"] = do
  putStrLn "Enter Username: "
  username <- I.getLine
  putStrLn "Enter Channel: "
  chan <- I.getLine
  pn <- newClient pubk subk username False
  runClient (pn{channels=[chan]})

main2 pubk subk ["consumer"] = do
    putStrLn "Enter Username: "
    username <- I.getLine
    putStrLn "Enter Channels (space separated): "
    chans <- I.getLine
    pn <- newClient pubk subk username False
    res <- channelGroupAddChannel pn "channelGroupTest" (T.words chans)
    case  res of
      Just cgr -> when (cgrError cgr) $
                    print $  "Error Adding channels to group: " ++  show cgr
      Nothing -> putStrLn "Error: Unable to connect with PubNub services"


    subscribe pn{channel_groups=["channelGroupTest"]} defaultSubscribeOptions{ onPresence = Just outputPresence
                                                                             , onMsg = output
                                                                             , onConnect = putStrLn "Connected..." }
    return ()


main2 _ _ _ = do
              putStrLn "Help:\n Create a producer by adding 'producer' as an argument."
              putStrLn "Multiple producers can be created using different channels.\n "



newClient :: T.Text -> T.Text -> T.Text -> Bool -> IO PN
newClient pubk subk name encrypt
  | encrypt = either (error . show) (\x -> x{ uuid_key = Just name }) <$> encKey
  | otherwise       = newPN
  where
    encKey = do
                pn <- newPN
                return $ setEncryptionKey pn "enigma"

    newPN  = do
                pn <- defaultPN
                return pn { uuid_key = Just name
                          , sub_key  = subk
                          , pub_key  = pubk
                          , ssl      = False
                          }

runClient :: PN -> IO ()
runClient pn = do
  a <- receiver
  withAsync (cli a) $ \b -> do
    _ <- waitAnyCancel [a, b]
    return ()
  where
    cli a = forever $ do
      msg <- I.getLine
      case msg of
        "/leave" -> do
          leave pn (head $ channels pn) (fromJust $ uuid_key pn)
          unsubscribe a
          mzero
        _ ->
          publish pn (head $ channels pn) Msg { username = fromJust $ uuid_key pn
                                              , msg=msg }

    receiver =
      subscribe pn defaultSubscribeOptions{ onPresence = Just outputPresence
                                          , onMsg = output
                                          , onConnect = putStrLn "Connected..." }

outputPresence :: Presence -> IO ()
outputPresence Presence{..} = do
  I.putStr "** "
  I.putStr uuid
  case action of
    Join ->
      putStrLn " has joined channel"
    Leave ->
      putStrLn " has left channel"
    Timeout ->
      putStrLn " has dropped from channel"

output :: Maybe Msg -> IO ()
output (Just m) =
  I.putStrLn $ T.concat ["<", username m, "> : ", msg m]
output Nothing = return ()

encodeMsg :: Msg -> L.ByteString
encodeMsg = encode

decodeMsg :: L.ByteString -> Maybe [Msg]
decodeMsg = decode
