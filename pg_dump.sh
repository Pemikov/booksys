pg_dump \
  -h booksys.che2kuuoahyx.eu-west-2.rds.amazonaws.com \
  -U postgres \
  -d postgres \
  -p 5432 \
  > full_dump.sql