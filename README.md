# HackiNews

A personal Hacker News reader. Stories are cached in Postgres and can be filtered by score, title, or by what has arrived since your last visit.

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

## New since last visit

The listing marks stories that were not there on your previous load, and the
pill under the score filter narrows the page to just those. It runs in the
browser: the pages are served with public cache headers and a single ETag, so
per-visitor state cannot live on the server without sessions or giving up
caching. The baseline is the set of story ids from the last load (kept in
`localStorage` under `hn.visit.v1` for seven days), not a posting timestamp,
because stories are often hours old by the time their score lifts them into the
listing. Rapid refreshes within five minutes keep the same marks rather than
clearing them before they have been read.

To exercise it without waiting for HN, run this in the console on the listing to
forget the top five stories and push the baseline past the grace window, then
reload -- they come back marked new:

```js
;(() => {
  const KEY = 'hn.visit.v1', N = 5
  const s = JSON.parse(localStorage.getItem(KEY) || '{}')
  s.seen = s.seen || {}
  s.lastVisit = Date.now() - 10 * 60 * 1000
  s.cutoff = s.lastVisit - 1000
  Object.keys(s.seen).forEach(id => { s.seen[id] = s.lastVisit - 60000 })
  Array.from(document.querySelectorAll('tr[date]')).slice(0, N).forEach(r => delete s.seen[r.id])
  localStorage.setItem(KEY, JSON.stringify(s))
  location.reload()
})()
```

`N = 0` gives the empty case, and `localStorage.removeItem('hn.visit.v1')`
resets to a first visit, where nothing is new.

## Keyboard

On the listing:

| Key | Does |
| --- | --- |
| `j` / `k` | Down / up a row, holding the column (comments, points, title) |
| `h` / `l` | Previous / next link |
| `space` | Activate the focused filter |
| `?` | Show the cheatsheet |

`k` past the first story steps up into the filters -- the new-since-last-visit
pill, then the score pills, landing on the score already in effect -- where
`h`/`l` moves along that row and `space` applies it. `j` walks back down into
the listing.

Story pages take the same keys, minus the filters; `?` there lists what applies.

## Tests

```bash
DATABASE_URL=postgres:///hackinews_test bundle exec rake test
```

HTTP and worker tests are stubbed; they do not hit the live Hacker News API.

## Console

```bash
bin/console
```
