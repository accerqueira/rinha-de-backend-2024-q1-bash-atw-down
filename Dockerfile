FROM alpine:latest

RUN apk add --update bash jq socat postgresql-client

WORKDIR /app/

ARG SOURCE_PATH=src/api.sh

COPY src/server.sh src/
COPY ${SOURCE_PATH} src/service.sh

ENTRYPOINT ["/app/src/server.sh"]
