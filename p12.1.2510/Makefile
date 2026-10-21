export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)

.PHONY: up deps down restart logs status ps

# PostgreSQL, license, dbAccess e AppServer no Docker.
# mkdir antes do compose: se o diretorio nao existir, o daemon cria o bind
# mount como root e o Postgres (UID do host) nao consegue criar o PGDATA.
up:
	mkdir -p volume/data/psql volume/data/system_temp
	docker compose up -d --wait --wait-timeout 600

# Só PostgreSQL, license e dbAccess.
deps:
	mkdir -p volume/data/psql volume/data/system_temp
	docker compose up -d --wait --wait-timeout 600 db license dbaccess

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f

status:
	docker compose ps

ps:
	docker compose ps
