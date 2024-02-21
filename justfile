start:
  ./src/server.sh

migrate:
  cat migrations/*.sql | sqlite3 db.sqlite3
