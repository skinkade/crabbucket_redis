import crabbucket/redis.{
  HasRemainingTokens, RedisTokenBucket, clear_key, remaining_tokens_for_key,
}
import gleam/erlang/process
import gleam/list
import gleam/otp/task
import gleam/result
import gleeunit
import gleeunit/should
import radish

pub fn main() {
  gleeunit.main()
}

pub fn insert_test() {
  let assert Ok(client) = radish.start("localhost", 6379, [radish.Timeout(500)])
  let window_duration_milliseconds = 60 * 1000
  let default_remaining_tokens = 2
  let key = "test entry"
  let bucket =
    RedisTokenBucket(
      redis_connection: client,
      window_duration_milliseconds: window_duration_milliseconds,
    )

  let HasRemainingTokens(remaining1, _) =
    remaining_tokens_for_key(bucket, key, default_remaining_tokens)
    |> should.be_ok()
  remaining1
  |> should.equal(default_remaining_tokens - 1)

  let HasRemainingTokens(remaining2, _) =
    remaining_tokens_for_key(bucket, key, default_remaining_tokens)
    |> should.be_ok()
  remaining2
  |> should.equal(default_remaining_tokens - 2)

  remaining_tokens_for_key(bucket, key, default_remaining_tokens)
  |> should.be_error()

  Nil
}

pub fn expiration_test() {
  let assert Ok(client) = radish.start("localhost", 6379, [radish.Timeout(500)])
  let window_duration_milliseconds = 1000
  let default_remaining_tokens = 1
  let key = "test entry 2"
  let bucket =
    RedisTokenBucket(
      redis_connection: client,
      window_duration_milliseconds: window_duration_milliseconds,
    )

  let HasRemainingTokens(remaining1, _) =
    remaining_tokens_for_key(bucket, key, default_remaining_tokens)
    |> should.be_ok()
  remaining1
  |> should.equal(default_remaining_tokens - 1)

  remaining_tokens_for_key(bucket, key, default_remaining_tokens)
  |> should.be_error()

  process.sleep(1000)

  let HasRemainingTokens(remaining1, _) =
    remaining_tokens_for_key(bucket, key, default_remaining_tokens)
    |> should.be_ok()
  remaining1
  |> should.equal(default_remaining_tokens - 1)
}

// Note: this fails with significantly high enough iteration counts
// (thousands per second or more),
// seemingly not due to atomicity issues with Redis,
// but rather the Erlang actor backing the radish client not being able to keep up,
// resulting in radish/error.Error(ActorError)
pub fn atomic_stress_test() {
  let assert Ok(client) = radish.start("localhost", 6379, [radish.Timeout(500)])
  let window_duration_milliseconds = 60 * 1000
  let default_remaining_tokens = 100
  let key = "test entry 3"
  let bucket =
    RedisTokenBucket(
      redis_connection: client,
      window_duration_milliseconds: window_duration_milliseconds,
    )

  let results =
    list.range(1, 500)
    |> list.map(fn(_) {
      task.async(fn() {
        remaining_tokens_for_key(bucket, key, default_remaining_tokens)
      })
    })
    |> list.map(task.await_forever)

  results
  |> list.count(fn(res) { result.is_ok(res) })
  |> should.equal(100)

  results
  |> list.count(fn(res) { result.is_error(res) })
  |> should.equal(400)
}

pub fn clear_key_test() {
  let assert Ok(client) = radish.start("localhost", 6379, [radish.Timeout(500)])
  let window_duration_milliseconds = 60 * 1000
  let default_remaining_tokens = 2
  let key = "test entry 4"
  let bucket =
    RedisTokenBucket(
      redis_connection: client,
      window_duration_milliseconds: window_duration_milliseconds,
    )

  let HasRemainingTokens(remaining1, _) =
    remaining_tokens_for_key(bucket, key, default_remaining_tokens)
    |> should.be_ok()
  remaining1
  |> should.equal(default_remaining_tokens - 1)

  clear_key(bucket, key)
  |> should.be_ok()
  |> should.be_true()

  let HasRemainingTokens(remaining1, _) =
    remaining_tokens_for_key(bucket, key, default_remaining_tokens)
    |> should.be_ok()
  remaining1
  |> should.equal(default_remaining_tokens - 1)

  Nil
}
