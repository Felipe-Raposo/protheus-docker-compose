# Protheus Docker Compose

Ambientes de desenvolvimento do **TOTVS Protheus 12** com Docker Compose, montados a partir das imagens `feliperaposo/protheus-*`.

## Descrição

Cada pasta é uma stack independente:

| Pasta | Ambiente | Serviços |
|---|---|---|
| `p12.1.2610/` | Protheus 12.1.2610 (AppServer 26.3.0.0) | PostgreSQL 18, License Server, dbAccess 26, AppServer |
| `p12.1.2510/` | Protheus 12.1.2510 (AppServer 24.x) | PostgreSQL 16, License Server, dbAccess 24, AppServer |
| `compiler/` | Compilador de fontes/patches (AppServer 24.x) | Compiler |

As stacks `p12.1.2610` e `p12.1.2510` usam os mesmos nomes de container e as mesmas portas. Suba uma de cada vez.

### Portas

| Porta | Serviço |
|---|---|
| 1234 | AppServer: SmartClient, WebApp (`/webapp`) e TDS |
| 8080 | AppServer: REST (`/api`) |
| 9995 | AppServer: HTTP Server (`/rest`) |
| 7890 | dbAccess |
| 5432 | PostgreSQL |
| 8081 | License Server Monitor (WebApp) |
| 5555 | License Server (publicada só na 2610, para o AppServer nativo) |

## Pré-requisitos

- Docker com Compose v2. No macOS (Apple Silicon), Colima com `vmType: vz` e Rosetta habilitado, já que as imagens do Protheus são `linux/amd64`:

```bash
colima start --vm-type vz --vz-rosetta --memory 4 --cpu 2
```

- `make`, para a stack 2610.

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

Na 2610, o `.env` também traz `HOST_UID`/`HOST_GID`. O `Makefile` exporta os valores de `id -u` e `id -g`, e o PostgreSQL roda com esse usuário para o bind mount funcionar no Colima sem `chown`.

Os dados ficam em `volume/` de cada stack (fora do Git):

- `volume/data/psql`: dados do PostgreSQL
- `volume/data/system_temp`: arquivos temporários do AppServer
- `compiler/volume/apo` e `compiler/volume/patches`: RPO e patches do compilador

## Uso

### Protheus 12.1.2610

Por padrão, o AppServer roda **fora do Docker**, como processo na VM do Colima. PostgreSQL, License Server e dbAccess continuam em containers.

```bash
cd p12.1.2610

make up        # sobe db, license e dbaccess e depois o AppServer nativo
make status    # estado do AppServer nativo
make logs      # log do AppServer nativo
make ps        # containers da stack
make down      # para o AppServer nativo e derruba os containers
```

Para rodar o AppServer em container, como nas versões anteriores:

```bash
make up-container
make logs-container
make down-container
```

Só para as dependências, sem o AppServer:

```bash
make deps
```

#### AppServer nativo no Colima

O script [`p12.1.2610/native/protheus-colima.sh`](p12.1.2610/native/protheus-colima.sh) roda no Mac e se reexecuta dentro da VM com `sudo`:

- extrai a imagem `feliperaposo/protheus:p12.1.2610` uma vez para `/mnt/lima-colima/protheus/p12.1.2610/rootfs`, no disco de dados da VM (`install`)
- executa `/protheus.sh` num `chroot` desse rootfs, com o binário x86-64 rodando pelo Rosetta
- aplica os ulimits da TOTVS (`nofile` 65536, `core` ilimitado e `stack` de 1 MB)
- resolve `license-server` e `dbaccess` para `127.0.0.1`, usando as portas 5555 e 7890 publicadas pelos containers
- aguarda o AppServer ficar de pé por 60 s e responder em `/webapp/` (`START_TIMEOUT`, padrão 600 s)

```bash
./native/protheus-colima.sh install|start|stop|restart|status|logs|uninstall
```

O log fica em `/mnt/lima-colima/protheus/p12.1.2610/appserver.log`, dentro da VM.

### Protheus 12.1.2510

```bash
cd p12.1.2510
mkdir -p volume/data/psql volume/data/system_temp
docker compose up -d --wait --wait-timeout 600
docker compose logs -f
docker compose down
```

### Compiler

```bash
cd compiler
docker compose up -d
```

## Healthchecks

- **PostgreSQL:** fica `healthy` só depois que o banco do Protheus foi criado/reconciliado.
- **License Server e dbAccess:** porta TCP aberta (5555 e 7890).
- **AppServer:** com o multiprotocolo ligado, o WebApp responde em `/webapp/` na 1234. O check exige que o `startstop_1234.lck` tenha pelo menos 60 s, além dessa resposta. O `start_period` é de 180 s, porque a extração da systemload no primeiro start leva cerca de 2,5 min no Colima.

## Problemas conhecidos

- **12.1.2610, multiprotocolo:** o AppServer 26.3.0.0, com `NewRestOnInit` no padrão, sobe o job `MPPORT_REST_INIT` e encerra o processo no pool `MAIN|SD|HTTP` sem `Slaves` (`Invalid REST Port`, erro -107). O `appserver.ini` da base 26 desliga esse job (`[MPP_CLima]` `NewRestOnInit=0`) e entrega a porta do `[HTTPSERVER]` (`NewRestOnStart=1`): servidor na 9995, `Path=/app-root`, `RootPath` em `/protheus12/protheus_data/http-root/app-root` e um pool cujo `Slaves` aponta para outra seção (`Environment=P12`, `MinThreads=1`). O `protheus.sh` cria esse diretório antes do start. O broker escuta na porta TCP 1234; o socket do `[WebApp]` fica na 1236 para não disputar esse bind (`Address already in use`). O endereço público continua `http://localhost:1234/webapp/`. `MultiProtocolPort` permanece ligado.

## Imagens

| Imagem | Repositório |
|---|---|
| `feliperaposo/protheus:p12.1.2610` | [protheus-docker-12.1.2610](https://github.com/Felipe-Raposo/protheus-docker-12.1.2610) |
| `feliperaposo/protheus:p12.1.2510` | [protheus-docker-12.1.2510](https://github.com/Felipe-Raposo/protheus-docker-12.1.2510) |
| `feliperaposo/protheus-docker-base:26` | [protheus-docker-base-26](https://github.com/Felipe-Raposo/protheus-docker-base-26) |
| `feliperaposo/protheus-docker-base:24` | [protheus-docker-base-24](https://github.com/Felipe-Raposo/protheus-docker-base-24) |
| `feliperaposo/protheus-docker-baselight:26` | [protheus-docker-baselight-26](https://github.com/Felipe-Raposo/protheus-docker-baselight-26) |
| `feliperaposo/protheus-docker-baselight:24` | [protheus-docker-baselight-24](https://github.com/Felipe-Raposo/protheus-docker-baselight-24) |
| `feliperaposo/protheus-dbaccess:26` | [protheus-docker-dbaccess-26](https://github.com/Felipe-Raposo/protheus-docker-dbaccess-26) |
| `feliperaposo/protheus-dbaccess:24` | [protheus-docker-dbaccess-24](https://github.com/Felipe-Raposo/protheus-docker-dbaccess-24) |
| `feliperaposo/protheus-license` | [protheus-docker-license](https://github.com/Felipe-Raposo/protheus-docker-license) |
| `feliperaposo/protheus-postgresql` | [protheus-docker-postgresql](https://github.com/Felipe-Raposo/protheus-docker-postgresql) |
| `feliperaposo/protheus-compiler:24` | [protheus-docker-compiler](https://github.com/Felipe-Raposo/protheus-docker-compiler) |

## Licença

Este projeto está sob a [GNU General Public License v3.0](LICENSE).

## Mantenedor

Felipe Raposo — [feliperaposo@gmail.com](mailto:feliperaposo@gmail.com)
