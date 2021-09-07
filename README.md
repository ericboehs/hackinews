To run migrations in docker:
```
docker run --rm -it --network=home_rev_proxy_default -v "$(pwd)/db:/db" --env "DATABASE_URL=postgres://hackinews@database/hackinews?sslmode=disable" amacneil/dbmate up
```
