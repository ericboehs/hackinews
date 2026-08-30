-- migrate:up

-- The homepage reads the newest stories above a score threshold. Without this
-- it sequentially scans every cached row (46k+) to return a few hundred
-- stories. Partial on type so the index stays roughly the size of the story
-- count rather than the whole cache, and ordered to match `by_time`.
create index index_items_on_story_time
  on items ((data->'time') desc)
  where (data->>'type') = 'story';

-- migrate:down
drop index index_items_on_story_time;
