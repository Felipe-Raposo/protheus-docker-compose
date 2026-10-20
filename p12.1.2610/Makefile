export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)

NATIVE := ./native/protheus-colima.sh

.PHONY: up deps down restart logs ps status up-container down-container logs-container up-native down-native native-install native-uninstall

# PostgreSQL, license, dbAccess e AppServer no Docker.
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

up-container: up

down-container: down

logs-container: logs

# AppServer direto na VM do Colima. As portas coincidem com o container.
up-native: deps
	-docker compose stop protheus
	$(NATIVE) start

down-native:
	$(NATIVE) stop

native-install:
	$(NATIVE) install

native-uninstall:
	$(NATIVE) uninstall
