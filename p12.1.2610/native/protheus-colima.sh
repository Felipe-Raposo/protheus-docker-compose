#!/usr/bin/env bash
# AppServer Protheus 12.1.2610 rodando direto na VM do Colima, sem container.
#
# O binario e Linux amd64: roda num chroot extraido da imagem Docker, com o
# Rosetta da VM (binfmt com flag F, que continua valido dentro do chroot).
# PostgreSQL, license server e dbAccess continuam no docker compose; o AppServer
# os alcanca pelas portas publicadas em 127.0.0.1 (5555 e 7890).
#
# Uso (no Mac): native/protheus-colima.sh install|start|stop|restart|status|logs|uninstall
set -euo pipefail

IMAGE="${PROTHEUS_IMAGE:-docker.io/feliperaposo/protheus:p12.1.2610}"
APPSERVER_DATABASE="${APPSERVER_DATABASE:-POSTGRES}"
BASE="/mnt/lima-colima/protheus/p12.1.2610"
ROOT="$BASE/rootfs"
LOG="$BASE/appserver.log"
APPDIR="$ROOT/protheus12/bin/appserver"
LOCK="$APPDIR/startstop_1234.lck"
START_TIMEOUT="${START_TIMEOUT:-600}"

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SYSTEM_TEMP="$(cd "$(dirname "$SCRIPT")/.." && pwd)/volume/data/system_temp"

# No Mac, reexecuta dentro da VM como root. O home do Mac e montado na VM
# (virtiofs) no mesmo caminho, entao o script e o system_temp sao visiveis la.
if [[ "$(uname -s)" == "Darwin" ]]; then
	mkdir -p "$SYSTEM_TEMP"
	exec colima ssh -- sudo --preserve-env=PROTHEUS_IMAGE,APPSERVER_DATABASE,START_TIMEOUT \
		bash "$SCRIPT" "$@"
fi

[[ $EUID -eq 0 ]] || exec sudo bash "$SCRIPT" "$@"

log() { echo "[protheus-colima] $*"; }

# PIDs de processos cuja raiz e o chroot (appsrvlinux e filhos).
pids() {
	local p root
	for p in /proc/[0-9]*; do
		root="$(readlink "$p/root" 2>/dev/null)" || continue
		[[ "$root" == "$ROOT" ]] && echo "${p#/proc/}"
	done
	return 0
}

running() { [[ -n "$(pids)" ]]; }

do_install() {
	if [[ -x "$APPDIR/appsrvlinux" ]]; then
		log "rootfs ja instalado em $ROOT (use uninstall para reextrair)"
		return 0
	fi
	log "baixando/exportando $IMAGE para $ROOT"
	docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull --platform linux/amd64 "$IMAGE"
	mkdir -p "$ROOT"
	local cid
	cid="$(docker create --platform linux/amd64 "$IMAGE")"
	if ! docker export "$cid" | tar -xpf - -C "$ROOT" --numeric-owner; then
		docker rm -f "$cid" >/dev/null
		log "falha ao extrair a imagem"
		exit 1
	fi
	docker rm -f "$cid" >/dev/null
	docker image inspect "$IMAGE" --format '{{.Id}}' >"$BASE/image.id"
	log "rootfs extraido ($(du -sh "$ROOT" | cut -f1))"
}

mount_bind() {
	local src="$1" dst="$2" opt="$3"
	mkdir -p "$dst"
	mountpoint -q "$dst" || mount "$opt" "$src" "$dst"
	# A raiz da VM e "shared": sem rslave, o umount -R do chroot desmonta
	# /sys/fs/cgroup, /dev/pts etc. da propria VM e quebra o Docker.
	mount --make-rslave "$dst"
}

mount_all() {
	mount_bind /proc "$ROOT/proc" --rbind
	mount_bind /sys "$ROOT/sys" --rbind
	mount_bind /dev "$ROOT/dev" --rbind
	mkdir -p "$SYSTEM_TEMP"
	mount_bind "$SYSTEM_TEMP" "$ROOT/protheus12/protheus_data/system_temp" --bind

	# Nomes usados no appserver.ini da imagem.
	cat >"$ROOT/etc/hosts" <<-EOF
		127.0.0.1 localhost colima license-server dbaccess
		::1 localhost
	EOF
	cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true
}

umount_all() {
	local m
	for m in protheus12/protheus_data/system_temp dev sys proc; do
		mountpoint -q "$ROOT/$m" || continue
		mount --make-rslave "$ROOT/$m"
		umount -R -l "$ROOT/$m"
	done
	return 0
}

port_busy() { ss -Hltn "sport = :$1" | grep -q .; }

check_deps() {
	local port
	for port in 5555 7890; do
		port_busy "$port" || {
			log "porta $port nao esta publicada; suba o compose (make deps)"
			exit 1
		}
	done
	for port in 1234 8080 9995; do
		if port_busy "$port"; then
			log "porta $port ja em uso (container protheus ainda no ar? docker stop protheus)"
			exit 1
		fi
	done
}

healthy() {
	[[ -f "$LOCK" ]] &&
		(($(date +%s) - $(stat -c %Y "$LOCK") >= 60)) &&
		curl -sf -o /dev/null -m 5 http://127.0.0.1:1234/webapp/
}

do_start() {
	[[ -x "$APPDIR/appsrvlinux" ]] || do_install
	if running; then
		log "AppServer ja esta rodando (pids: $(pids | xargs))"
		return 0
	fi
	check_deps
	mount_all

	log "iniciando AppServer (log: $LOG)"
	# Ulimits da TOTVS: https://tdn.totvs.com/display/tec/Application+Server+-+ulimit+settings
	# "ulimit -s" e em KB: 1024 = 1 MB, o mesmo "stack: 1048576" (bytes) do compose.
	setsid bash -c '
		ulimit -c unlimited
		ulimit -n 65536
		ulimit -s 1024
		exec chroot "$0" /usr/bin/env -i \
			PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
			HOME=/root APPSERVER_DATABASE="$1" /protheus.sh
	' "$ROOT" "$APPSERVER_DATABASE" >>"$LOG" 2>&1 </dev/null &

	local start=$SECONDS
	until healthy; do
		if ! running; then
			log "AppServer caiu durante o start; ultimas linhas do log:"
			tail -n 40 "$LOG"
			umount_all
			exit 1
		fi
		if ((SECONDS - start > START_TIMEOUT)); then
			log "timeout de ${START_TIMEOUT}s esperando o AppServer"
			exit 1
		fi
		sleep 5
	done
	log "AppServer no ar em $((SECONDS - start))s: http://localhost:1234/webapp/"
}

do_stop() {
	if running; then
		log "parando AppServer (SIGTERM)"
		pids | xargs -r kill -TERM
		local i
		for i in $(seq 1 60); do
			running || break
			sleep 1
		done
		if running; then
			log "forcando SIGKILL"
			pids | xargs -r kill -KILL
			sleep 1
		fi
	else
		log "AppServer nao esta rodando"
	fi
	umount_all
}

do_status() {
	if running; then
		log "rodando (pids: $(pids | xargs))"
		if healthy; then log "saudavel"; else log "subindo ou nao saudavel"; fi
	else
		log "parado"
		return 3
	fi
}

do_uninstall() {
	do_stop
	log "removendo $BASE"
	rm -rf --one-file-system "$BASE"
}

case "${1:-}" in
	install) do_install ;;
	start) do_start ;;
	stop) do_stop ;;
	restart) do_stop; do_start ;;
	status) do_status ;;
	logs) exec tail -n 200 -F "$LOG" ;;
	uninstall) do_uninstall ;;
	*)
		echo "uso: $0 install|start|stop|restart|status|logs|uninstall" >&2
		exit 2
		;;
esac
