FROM hexpm/elixir:1.18.4-erlang-27.3-debian-bookworm-20250429

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=dev

CMD ["mix", "phx.server"]
