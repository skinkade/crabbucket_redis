import crabbucket/redis.{
  type RedisTokenBucket, HasRemainingTokens, MustWaitUntil, RedisError,
  RedisTokenBucket, remaining_tokens_for_key,
}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import mist
import radish
import wisp

type TokenBuckets {
  TokenBuckets(api_bucket: RedisTokenBucket)
}

type Context {
  Context(
    redis_connection: process.Subject(radish.Message),
    buckets: TokenBuckets,
  )
}

fn set_header_if_not_present(resp: wisp.Response, name: String, value: String) {
  case list.key_find(resp.headers, name) {
    Ok(_) -> resp
    Error(_) -> resp |> wisp.set_header(name, value)
  }
}

const limit_header = "x-rate-limit-limit"

const remaining_header = "x-rate-limit-remaining"

const reset_header = "x-rate-limit-reset"

fn with_rate_limit(
  bucket: RedisTokenBucket,
  key: String,
  default_token_count: Int,
  handler: fn() -> wisp.Response,
) -> wisp.Response {
  let limit_result = remaining_tokens_for_key(bucket, key, default_token_count)

  case limit_result {
    Error(RedisError(e)) -> {
      io.debug(e)
      wisp.internal_server_error()
    }
    Error(MustWaitUntil(next_reset)) -> {
      wisp.response(429)
      |> wisp.set_header(limit_header, default_token_count |> int.to_string())
      |> wisp.set_header(remaining_header, "0")
      |> wisp.set_header(reset_header, next_reset |> int.to_string())
    }
    Ok(HasRemainingTokens(tokens, next_reset)) -> {
      handler()
      |> set_header_if_not_present(
        limit_header,
        default_token_count |> int.to_string(),
      )
      |> set_header_if_not_present(remaining_header, tokens |> int.to_string())
      |> set_header_if_not_present(reset_header, next_reset |> int.to_string())
    }
  }
}

const global_api_limit_per_minute = 100

const secure_api_limit_per_minute = 10

fn secure_handler(_req: wisp.Request, ctx: Context, user_id: String) {
  use <- with_rate_limit(
    ctx.buckets.api_bucket,
    "limit:api_secure:user:" <> user_id,
    secure_api_limit_per_minute,
  )
  wisp.ok()
}

fn api_handler(req: wisp.Request, ctx: Context) {
  let user_id = "12345"
  use <- with_rate_limit(
    ctx.buckets.api_bucket,
    "limit:api:user:" <> user_id,
    global_api_limit_per_minute,
  )

  case wisp.path_segments(req) |> list.drop(1) {
    ["get-something"] -> wisp.ok()
    ["secure"] -> secure_handler(req, ctx, user_id)
    _ -> wisp.not_found()
  }
}

fn handle_request(req: wisp.Request, ctx: Context) {
  case wisp.path_segments(req) {
    ["api", ..] -> api_handler(req, ctx)
    _ -> wisp.not_found()
  }
}

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(client) = radish.start("localhost", 6379, [radish.Timeout(500)])
  let buckets =
    TokenBuckets(api_bucket: RedisTokenBucket(
      redis_connection: client,
      window_duration_milliseconds: 1000 * 60,
    ))
  let context = Context(redis_connection: client, buckets: buckets)

  let assert Ok(_) =
    wisp.mist_handler(handle_request(_, context), secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}
