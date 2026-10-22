# Protheus Docker Compose

Ambientes de desenvolvimento do **TOTVS Protheus 12** com Docker Compose, montados a partir das imagens `feliperaposo/protheus-*`.

## Descrição

Cada pasta é uma stack independente. As duas usam os mesmos nomes de container (`postgresql`, `license-server`, `dbaccess`, `protheus`) e as mesmas portas. Suba uma de cada vez.

| Pasta | Ambiente | Serviços |
|---|---|---|
| `p12.1.2610/` | Protheus 12.1.2610 (AppServer 26.x — Arara Azul) | PostgreSQL 18, License Server, dbAccess 26, AppServer |
| `p12.1.2510/` | Protheus 12.1.2510 (AppServer 24.x — Onça Preta) | PostgreSQL 18, License Server, dbAccess 26, AppServer |

As duas stacks usam `feliperaposo/protheus-dbaccess:26`. O AppServer recebe `APPSERVER_DATABASE=POSTGRES`.

### Portas

| Porta | Serviço |
|---|---|
| 1234 | AppServer: SmartClient, WebApp (`/webapp`) e TDS |
| 8080 | AppServer: REST (`/rest`) |
| 32033 | AppServer: App Monitor (`/app-monitor`) |
| 7890 | dbAccess |
| 5432 | PostgreSQL |
| 8081 | License Server Monitor (WebApp) |

Na rede do Compose, o License Server escuta na 5555 e o dbAccess publica o `dbapi.so` na 7891. Essas portas ficam entre os containers.

No 12.1.2610 o socket TCP do AppServer é a 1235; a 1234 publicada é o proxy do multiprotocolo, que também atende `/webapp/`. No 12.1.2510 o TCP e o multiprotocolo compartilham a 1234.

## Pré-requisitos

- Docker com Compose v2.
- `make`.

As imagens do Protheus, do License Server e do dbAccess são `linux/amd64`. No macOS com Apple Silicon, execute-as com emulação. No Colima:

```bash
colima start --vm-type vz --vz-rosetta --memory 4 --cpu 2
```

## Configuração

Cada stack tem um `.env` com as credenciais do PostgreSQL. São dados de desenvolvimento local:

```bash
POSTGRES_DB=postgres
POSTGRES_USER=postgres
POSTGRES_PASSWORD=Protheus12!

# Banco do Protheus (padrão: protheus/protheus/protheus)
# PROTHEUS_DB=protheus
# PROTHEUS_USER=protheus
# PROTHEUS_PASSWORD=protheus
```

O `Makefile` exporta `HOST_UID` e `HOST_GID` com `id -u` e `id -g`. O PostgreSQL roda com esse usuário, via `gosu` no entrypoint da imagem, para gravar no bind mount. Na 2610 o `.env` também define esses valores; com `make`, vale o usuário atual.

Os dados ficam em `volume/` de cada stack (fora do Git):

- `volume/data/psql`: dados do PostgreSQL 18 (`PGDATA` em `/var/lib/postgresql/18/docker`)
- `volume/data/system_temp`: arquivos temporários do AppServer

O `make up` cria esses diretórios antes do Compose. Se o daemon criar o bind mount, ele fica com dono root e o PostgreSQL não consegue iniciar o `PGDATA`.

## Uso

Os alvos são os mesmos nas duas stacks:

```bash
cd p12.1.2610   # ou p12.1.2510

make up         # sobe PostgreSQL, License Server, dbAccess e AppServer
make deps       # só PostgreSQL, License Server e dbAccess
make status     # estado dos containers
make ps         # o mesmo que status
make logs       # logs da stack
make restart    # down e up
make down       # derruba os containers
```

`make up` e `make deps` usam `docker compose up -d --wait --wait-timeout 600`.

## Healthchecks

- **PostgreSQL:** fica `healthy` só depois que o banco do Protheus foi criado ou reconciliado. O `start_period` é de 40 s.
- **License Server:** porta TCP 5555 aberta. O `start_period` é de 40 s.
- **dbAccess:** portas TCP 7890 e 7891 abertas. O `start_period` é de 30 s. Sobe depois do PostgreSQL e do License Server.
- **AppServer:** `curl` em `http://localhost:1234/webapp/` e o lock de start com pelo menos 10 s. No 12.1.2610 o lock é `startstop_1235.lck`, com fallback para `startstop_1234.lck`. No 12.1.2510 é `startstop_1234.lck`. O `start_period` é de 90 s. Sobe depois do dbAccess.

## Imagens

| Imagem | Repositório |
|---|---|
| `feliperaposo/protheus:p12.1.2610` | [protheus-docker-12.1.2610](https://github.com/Felipe-Raposo/protheus-docker-12.1.2610) |
| `feliperaposo/protheus:p12.1.2510` | [protheus-docker-12.1.2510](https://github.com/Felipe-Raposo/protheus-docker-12.1.2510) |
| `feliperaposo/protheus-dbaccess:26` | [protheus-docker-dbaccess-26](https://github.com/Felipe-Raposo/protheus-docker-dbaccess-26) |
| `feliperaposo/protheus-license:latest` | [protheus-docker-license](https://github.com/Felipe-Raposo/protheus-docker-license) |
| `feliperaposo/protheus-postgresql:18` | [protheus-docker-postgresql](https://github.com/Felipe-Raposo/protheus-docker-postgresql) |

## Licença

Este projeto está sob a [GNU General Public License v3.0](LICENSE).

## Mantenedor

Felipe Raposo — [feliperaposo@gmail.com](mailto:feliperaposo@gmail.com)
