-- migrate:up
create table items (
  id integer primary key,
  data jsonb not null
);


-- migrate:down
drop table items;
