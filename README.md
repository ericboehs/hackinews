# HackiNews

A personal Hacker News reader. Stories are cached in Postgres and can be filtered by score or title.

## Requirements

- Ruby 4.0+
- PostgreSQL
- [dbmate](https://github.com/amacneil/dbmate) (`brew install dbmate`)
- [overmind](https://github.com/DarthSim/overmind) or [foreman](https://github.com/ddollar/foreman) (optional, for `bin/dev`)

## Setup

```bash
bin/setup
```

This installs gems, creates `hackinews_development` / `hackinews_test`, writes `.env.local` if missing, and runs migrations.

`.env.local` is loaded first and overrides `.env`. A typical local value:

```
DATABASE_URL=postgres:///hackinews_development
```

## Run

```bash
bin/dev
```

- Web: [http://localhost:3000](http://localhost:3000)
- Worker: fetches HN top stories every 5 minutes (`WORKER_INTERVAL`, seconds)

Or separately:

```bash
bundle exec puma -p 3000
bundle exec ruby worker.rb          # loop
bundle exec rake worker             # one shot
```

## Tests

```bash
DATABASE_URL=postgres:///hackinews_test bundle exec rake test
```

Client tests hit the live Hacker News API.

## Console

```bash
bin/console
```
