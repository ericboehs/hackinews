-- migrate:up

-- The homepage reads the newest stories above a score threshold. Without this
-- it sequentially scans the whole cache to return a few hundred stories, so
-- the cost grows with cached comments rather than with stories. Partial on
-- type so the index tracks the story count, and ordered to match `by_time`.
create index index_items_on_story_time
  on items ((data->'time') desc)
  where (data->>'type') = 'story';

-- migrate:down
drop index index_items_on_story_time;
