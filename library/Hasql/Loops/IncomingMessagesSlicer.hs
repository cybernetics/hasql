module Hasql.Loops.IncomingMessagesSlicer where

import Hasql.Prelude
import Hasql.Model
import qualified Hasql.ReadStream as C
import qualified Hasql.MessageTypeNames as A


{-# INLINABLE loop #-}
loop :: IO ByteString -> (Message -> IO ()) -> IO ()
loop getNextChunk sendMessage =
  C.run read getNextChunk $> ()
  where
    read =
      do
        message <- C.fetchMessage Message
        traceM ("Received a message of type " <> case message of Message type_ _ -> A.string type_)
        liftIO (sendMessage message)
        read
