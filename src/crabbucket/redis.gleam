import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/result
import radish.{type Message}
import radish/error.{type Error}
import radish/hash
import radish/resp
import radish/utils

@external(erlang, "os", "system_time")
fn system_time(second_division: Int) -> Int

/// `window_duration_milliseconds` describes the length of the time window
/// valid for a number of tokens.
/// For instance, a value of 1,000 with a default token count of 100 would mean
/// an action could occur 100 times per second.
pub type RedisTokenBucket {
  RedisTokenBucket(
    redis_connection: Subject(Message),
    window_duration_milliseconds: Int,
  )
}

pub type RemainingTokenCountSuccess {
  HasRemainingTokens(remaining_tokens: Int, next_reset_timestamp: Int)
}

pub type RemainingTokenCountFailure {
  MustWaitUntil(next_reset_timestamp: Int)
  RedisError(error: Error)
}

/// Logic:
/// - Try to get the current value for this token bucket key
/// - If there is none, the action should be allowed,
///   with the current time and remaining tokens being cached
/// - If there was a value, check if its time window has passed,
///   in which case we can 'reset' it to a fresh value, like above
/// - If no tokens remain in the current entry, return -1
/// - Else, decrement remaining tokens, saving and returned that value
/// - All of the above return values are part of a tuple:
///   {remaining_tokens, timestamp_of_next_time_window}
const script = "local key = KEYS[1]
local window_start_arg = tonumber(ARGV[1])
local window_duration_arg = tonumber(ARGV[2])
local tokens_arg = tonumber(ARGV[3])
local window_start = tonumber(redis.call('HGET', key, 'window_start'))
local tokens = tonumber(redis.call('HGET', key, 'tokens'))
if window_start == nil or tokens == nil then
    redis.call('HSET', key, 'window_start', window_start_arg, 'tokens', tokens_arg)
    return {tokens_arg, window_start_arg + window_duration_arg}
end
local time_arr = redis.call('TIME')
local time_ms = (time_arr[1] * 1000) + (math.floor(time_arr[2] / 1000))
if (window_start + window_duration_arg) < time_ms then
    redis.call('HSET', key, 'window_start', window_start_arg, 'tokens', tokens_arg)
    return {tokens_arg, window_start_arg + window_duration_arg}
end
if tokens <= 0 then
    return {-1, window_start + window_duration_arg}
end
redis.call('HSET', key, 'tokens', tokens - 1)
return {tokens - 1, window_start + window_duration_arg}"

/// Takes an arbitrary string key, inserting a record if non-existing.
/// 
/// Suggestion: you may wish to format you string key such that it indicates
/// usage, purpose, value type, and value.
/// For instance, if you're limiting a specific endpoint for a given user,
/// the key might look something like:
/// `limit:some_endpoint_name:user:12345`
/// 
/// Return should be either `HasRemainingTokens(remaining_tokens: Int)`,
/// which indicates that an action may proceed and contains how many more times
/// the action may occur with the current window,
/// or it may be `MustWaitFor(milliseconds: Int)`,
/// which indicates that no tokens remain for this keep and how many
/// milliseconds remain until the end of the current window.
pub fn remaining_tokens_for_key(
  bucket: RedisTokenBucket,
  key: String,
  default_token_count: Int,
) -> Result(RemainingTokenCountSuccess, RemainingTokenCountFailure) {
  let cmd =
    utils.prepare([
      "EVAL",
      script,
      "1",
      key,
      system_time(1000) |> int.to_string(),
      bucket.window_duration_milliseconds |> int.to_string(),
      default_token_count - 1 |> int.to_string(),
    ])

  use results <- result.try(
    utils.execute(bucket.redis_connection, cmd, 500)
    |> result.map_error(fn(e) { RedisError(e) }),
  )

  // Implementation detail:
  // Lua script executed by Redis returns _how many tokens are remaining_,
  // so we can't check for tokens_remaining <= 0, which would cause issues
  // in the case of having just used the last token in a window.
  // Therefore, a negative remaining token value is used to indicate the case
  // of the cache entry not having remaining tokens.
  case results {
    [resp.Array([resp.Integer(tokens_remaining), resp.Integer(next_reset)])] -> {
      case tokens_remaining < 0 {
        True -> {
          Error(MustWaitUntil(next_reset))
        }
        False -> Ok(HasRemainingTokens(tokens_remaining, next_reset))
      }
    }
    other -> {
      io.debug(other)
      panic as "Should be unreachable"
    }
  }
}

/// Returns True if record was deleted, False if record didn't exist
pub fn clear_key(bucket: RedisTokenBucket, key: String) -> Result(Bool, Error) {
  use result <- result.try({
    hash.del(bucket.redis_connection, key, ["window_start", "tokens"], 500)
  })

  Ok(result > 0)
}
