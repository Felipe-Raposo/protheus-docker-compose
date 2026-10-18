export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)

NATIVE := ./native/protheus-colima.sh

.PHONY: up deps down restart logs ps status up-container down-container logs-container native-install native-uninstall

# PostgreSQL, license e dbAccess no Docker; AppServer direto na VM do Colima.
up: deps
	$(NATIVE) start

# No Colima o daemon nao consegue chown em pastas de bind mount que ele mesmo cria.
deps:
	mkdir -p volume/data/psql volume/data/system_temp
	docker compose up -d --wait --wait-timeout 600

down:
	$(NATIVE) stop
	docker compose --profile container down

restart: down up

logs:
	$(NATIVE) logs

status:
	$(NATIVE) status

ps:
	docker compose --profile container ps

native-install:
	$(NATIVE) install

native-uninstall:
	$(NATIVE) uninstall

# Caminho antigo: AppServer tambem em container.
up-container:
	$(NATIVE) stop
	mkdir -p volume/data/psql volume/data/system_temp
	docker compose --profile container up -d --wait --wait-timeout 600

down-container:
	docker compose --profile container down

logs-container:
	docker compose --profile container logs -f
