# crabbucket_redis

[![Package Version](https://img.shields.io/hexpm/v/crabbucket_redis)](https://hex.pm/packages/crabbucket_redis)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/crabbucket_redis/)

```sh
gleam add crabbucket_redis@1
```

## Usage

[The Wisp API example](./examples/wisp_api_limit_example/src/wisp_api_limit_example.gleam)
showcases how to use this library with Wisp middleware to apply rate limiting to an API.

Further documentation can be found at <https://hexdocs.pm/crabbucket_redis>.

## Development

Unit tests run against a Valkey instance, spun up via `podman-compose`

```sh
make test
```
