FROM hexpm/elixir:1.19.5-erlang-28.4.1-debian-bookworm-20260316-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=dev

CMD ["mix", "phx.server"]
