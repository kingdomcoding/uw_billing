FROM elixir:1.18-alpine AS build

RUN apk add --no-cache build-base git

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get --only prod

COPY config config
COPY lib lib
COPY priv priv
COPY rel rel
COPY assets assets

RUN MIX_ENV=prod mix assets.deploy
RUN MIX_ENV=prod mix compile
RUN MIX_ENV=prod mix release

FROM alpine:3.21 AS app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app
RUN chown nobody:nobody /app

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/uw_billing ./

USER nobody

ENV MIX_ENV=prod
ENV PORT=4000

EXPOSE 4000

CMD ["bin/server"]
