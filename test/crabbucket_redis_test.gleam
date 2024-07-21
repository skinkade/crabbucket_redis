import crabbucket/redis.{
  HasRemainingTokens, RedisTokenBucket, remaining_tokens_for_key,
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

pub fn atomic_stress_test() {
  let assert Ok(client) = radish.start("localhost", 6379, [radish.Timeout(500)])
  let window_duration_milliseconds = 60 * 1000
  let default_remaining_tokens = 500
  let key = "test entry 3"
  let bucket =
    RedisTokenBucket(
      redis_connection: client,
      window_duration_milliseconds: window_duration_milliseconds,
    )

  let results =
    list.range(1, 5000)
    |> list.map(fn(_) {
      task.async(fn() {
        remaining_tokens_for_key(bucket, key, default_remaining_tokens)
      })
    })
    |> list.map(task.await_forever)

  results
  |> list.count(fn(res) { result.is_ok(res) })
  |> should.equal(500)

  results
  |> list.count(fn(res) { result.is_error(res) })
  |> should.equal(4500)
}
