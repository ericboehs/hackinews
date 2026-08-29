# HackiNews

A personal Hacker News reader. Stories are cached in Postgres and can be filtered by score or title.

## Requirements

- Ruby 4.0
- PostgreSQL
- [dbmate](https://github.com/amacneil/dbmate) (`brew install dbmate`)
- [overmind](https://github.com/DarthSim/overmind) or [foreman](https://github.com/ddollar/foreman) (required for `bin/dev`)

## Setup

```bash
bin/setup
```

This installs gems, creates `hackinews_development` / `hackinews_test`, writes `.env.local` if missing, and migrates both databases.

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
- Restart the web process after code changes (`overmind restart web`)

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

HTTP and worker tests are stubbed; they do not hit the live Hacker News API.

## Console

```bash
bin/console
```
