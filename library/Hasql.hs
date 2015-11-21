module Hasql
(
  -- * Connection
  Connection,
  Settings.Settings(..),
  ConnectionError(..),
  connect,
  disconnect,
  -- * Query
  Query(..),
  ResultsError(..),
  ResultError(..),
  RowError(..),
  query,
)
where

import Hasql.Prelude
import qualified Database.PostgreSQL.LibPQ as LibPQ
import qualified Hasql.PreparedStatementRegistry as PreparedStatementRegistry
import qualified Hasql.Decoding.Results as ResultsDecoding
import qualified Hasql.Decoding as Decoding
import qualified Hasql.Encoding.Params as ParamsEncoding
import qualified Hasql.Encoding as Encoding
import qualified Hasql.Settings as Settings
import qualified Hasql.IO as IO


-- |
-- A single connection to the database.
data Connection =
  Connection !LibPQ.Connection !Bool !PreparedStatementRegistry.PreparedStatementRegistry

data ResultsError =
  -- |
  -- An error on the client-side,
  -- with a message generated by the \"libpq\" library.
  -- Usually indicates problems with connection.
  ClientError !(Maybe ByteString) |
  ResultError !ResultError
  deriving (Show, Eq)

data ResultError =
  -- | 
  -- An error reported by the DB. Code, message, details, hint.
  -- 
  -- * The SQLSTATE code for the error. The SQLSTATE code identifies the type of error that has occurred; 
  -- it can be used by front-end applications to perform specific operations (such as error handling) 
  -- in response to a particular database error. 
  -- For a list of the possible SQLSTATE codes, see Appendix A.
  -- This field is not localizable, and is always present.
  -- 
  -- * The primary human-readable error message (typically one line). Always present.
  -- 
  -- * Detail: an optional secondary error message carrying more detail about the problem. 
  -- Might run to multiple lines.
  -- 
  -- * Hint: an optional suggestion what to do about the problem. 
  -- This is intended to differ from detail in that it offers advice (potentially inappropriate) 
  -- rather than hard facts. Might run to multiple lines.
  ServerError !ByteString !ByteString !(Maybe ByteString) !(Maybe ByteString) |
  -- |
  -- The database returned an unexpected result.
  -- Indicates an improper statement or a schema mismatch.
  UnexpectedResult !Text |
  -- |
  -- An error of the row reader, preceded by the index of the row.
  RowError !Int !RowError |
  -- |
  -- An unexpected amount of rows.
  UnexpectedAmountOfRows !Int
  deriving (Show, Eq)

data RowError =
  EndOfInput |
  UnexpectedNull |
  ValueError !Text
  deriving (Show, Eq)

-- |
-- A connection acquistion error.
type ConnectionError =
  Maybe ByteString

-- |
-- Acquire a connection using the provided settings.
connect :: Settings.Settings -> IO (Either ConnectionError Connection)
connect settings =
  {-# SCC "connect" #-} 
  runEitherT $ do
    pqConnection <- lift (IO.acquireConnection settings)
    lift (IO.checkConnectionStatus pqConnection) >>= traverse left
    lift (IO.initConnection pqConnection)
    integerDatetimes <- lift (IO.getIntegerDatetimes pqConnection)
    registry <- lift (IO.acquirePreparedStatementRegistry)
    pure (Connection pqConnection integerDatetimes registry)

-- |
-- Release the connection.
disconnect :: Connection -> IO ()
disconnect (Connection pqConnection _ _) =
  LibPQ.finish pqConnection


-- |
-- A strictly single-statement query, which can be parameterized and prepared.
-- 
-- SQL template, params encoder, result decoder and a flag, determining whether it should be prepared.
-- 
type Query a b =
  (ByteString, Encoding.Params a, Decoding.Result b, Bool)

-- |
-- Execute a parametric query, producing either a deserialization failure or a successful result.
query :: Connection -> Query a b -> a -> IO (Either ResultsError b)
query (Connection pqConnection integerDatetimes registry) (template, encoder, decoder, preparable) params =
  {-# SCC "query" #-} 
  fmap (mapLeft coerceResultsError) $ runEitherT $ do
    EitherT $ IO.sendParametricQuery pqConnection integerDatetimes registry template (coerceEncoder encoder) preparable params
    EitherT $ IO.getResults pqConnection integerDatetimes (coerceDecoder decoder)

-- |
-- WARNING: We need to take special care that the structure of
-- the "ResultsDecoding.Error" type in the public API is an exact copy of
-- "Error", since we're using coercion.
coerceResultsError :: ResultsDecoding.Error -> ResultsError
coerceResultsError =
  unsafeCoerce

coerceDecoder :: Decoding.Result a -> ResultsDecoding.Results a
coerceDecoder =
  unsafeCoerce

coerceEncoder :: Encoding.Params a -> ParamsEncoding.Params a
coerceEncoder =
  unsafeCoerce
