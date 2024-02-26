start-api-standalone:
  ./src/server.sh src/api-standalone.sh

start-api:
  ./src/server.sh src/api.sh

start-lb:
  ./src/server.sh src/lb.sh

start-db:
  ./src/server.sh src/db.sh

migrate:
  cat migrations/*.sql | sqlite3 db.sqlite3
