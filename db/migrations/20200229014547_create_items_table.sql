-- migrate:up
create table items (
  id integer primary key,
  data jsonb not null,
  created_at timestamp without time zone NOT NULL,
  updated_at timestamp without time zone NOT NULL
);


-- migrate:down
drop table items;
