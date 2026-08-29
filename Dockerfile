# syntax=docker/dockerfile:1
ARG RUBY_VERSION=4.0.6

FROM ruby:${RUBY_VERSION}-slim AS build

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y build-essential ca-certificates curl libpq-dev \
 && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install \
 && rm -rf "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# dbmate is a static Go binary; the entrypoint uses it to migrate on boot.
ARG DBMATE_VERSION=v2.28.0
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      amd64) asset=dbmate-linux-amd64 ;; \
      arm64) asset=dbmate-linux-arm64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /usr/local/bin/dbmate \
      "https://github.com/amacneil/dbmate/releases/download/${DBMATE_VERSION}/${asset}" \
 && chmod +x /usr/local/bin/dbmate \
 && dbmate --version


FROM ruby:${RUBY_VERSION}-slim

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y ca-certificates libpq5 \
 && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    RACK_ENV=production \
    PORT=3000

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /usr/local/bin/dbmate /usr/local/bin/dbmate
COPY . .

RUN groupadd --system app \
 && useradd --system --gid app --home-dir /app app \
 && chown -R app:app /app
USER app

EXPOSE 3000

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["sh", "-c", "exec bundle exec puma -t 5:5 -p ${PORT:-3000} -e ${RACK_ENV:-production}"]
