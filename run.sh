#!/bin/bash
# 115 Docker + KasmVNC — container entrypoint.
# Drop-in replacement for the TigerVNC + noVNC launcher of
# github.com/dream10201/115Docker (same env contract, see README).
set -Eeuo pipefail

DISPLAY_WIDTH=${DISPLAY_WIDTH:-1920}
DISPLAY_HEIGHT=${DISPLAY_HEIGHT:-1080}
WEB_PORT=${WEB_PORT:-2250}
VNC_USER=${VNC_USER:-kasm}
KVNC_REQUIRE_SSL=${KVNC_REQUIRE_SSL:-false}
KVNC_ALLOW_RESIZE=${KVNC_ALLOW_RESIZE:-true}
KVNC_MAX_FRAME_RATE=${KVNC_MAX_FRAME_RATE:-60}
KVNC_RECT_MIN_QUALITY=${KVNC_RECT_MIN_QUALITY:-7}
KVNC_RECT_MAX_QUALITY=${KVNC_RECT_MAX_QUALITY:-8}
KVNC_UDP_PUBLIC_IP=${KVNC_UDP_PUBLIC_IP:-127.0.0.1}
KVNC_FULL_FRAME_UPDATES=${KVNC_FULL_FRAME_UPDATES:-30}
KVNC_LOG_LEVEL=${KVNC_LOG_LEVEL:-30}
KVNC_BLACKLIST_THRESHOLD=${KVNC_BLACKLIST_THRESHOLD:-1000}
COOKIE_CID=${COOKIE_CID:-}
COOKIE_SEID=${COOKIE_SEID:-}
COOKIE_UID=${COOKIE_UID:-}
COOKIE_KID=${COOKIE_KID:-}

D="${DISPLAY#:}"                      # display number (e.g. :99 -> 99)
CFG="$HOME/.vnc/kasmvnc.yaml"         # per-user config: highest precedence
PASS_FILE="$HOME/.kasmpasswd"
SSL_DIR=/etc/kasmvnc/ssl
COOKIE_FILE=/usr/local/115Cookie/worker.js

log() { echo "[115-kasm] $*"; }
die() { echo "[115-kasm] FATAL: $*" >&2; exit 1; }
is_true() { [[ "${1:-}" == "true" ]]; }

# ------------------------------------------------------------ 1. cleanup
# Stale pid/lock/socket files from a killed container make KasmVNC refuse the
# display and the 115 (Chromium-based) browser refuse to start.
rm -f "/tmp/.X11-unix/X${D}" "/tmp/.X${D}-lock" \
      "$HOME/.vnc/kasmvnc.pid" "$HOME/.vnc/"*.log 2>/dev/null || true
rm -f /etc/115/SingletonLock /etc/115/SingletonSocket /etc/115/SingletonCookie 2>/dev/null || true
mkdir -p "$HOME/.vnc"

# ------------------------------------------------- 2. self-signed TLS cert
# KasmVNC's embedded web server needs a certificate pair. The packaged
# snakeoil files are group-readable only, so generate a private pair.
if [[ ! -s "$SSL_DIR/privkey.pem" ]]; then
  mkdir -p "$SSL_DIR"
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout "$SSL_DIR/privkey.pem" -out "$SSL_DIR/cert.pem" \
    -subj "/CN=115-kasmvnc" 2>/dev/null
  chmod 600 "$SSL_DIR/privkey.pem" "$SSL_DIR/cert.pem"
fi

# ------------------------------------------------------ 3. kasmvnc.yaml
# Regenerated from the environment on every start: ~/.vnc/kasmvnc.yaml
# overrides /etc/kasmvnc/kasmvnc.yaml, so a baked file would go stale.
cat > "$CFG" <<EOF
desktop:
  resolution:
    width: ${DISPLAY_WIDTH}
    height: ${DISPLAY_HEIGHT}
  allow_resize: ${KVNC_ALLOW_RESIZE}

network:
  protocol: http
  interface: 0.0.0.0
  websocket_port: ${WEB_PORT}
  use_ipv4: true
  use_ipv6: false
  udp:
    public_ip: ${KVNC_UDP_PUBLIC_IP}
    port: auto
    payload_size: auto
    stun_server: none
  ssl:
    require_ssl: ${KVNC_REQUIRE_SSL}
    pem_certificate: ${SSL_DIR}/cert.pem
    pem_key: ${SSL_DIR}/privkey.pem

user_session:
  idle_timeout: never
  new_session_disconnects_existing_exclusive_session: true
  concurrent_connections_prompt: false
  concurrent_connections_prompt_timeout: 10

command_line:
  prompt: false

runtime_configuration:
  allow_client_to_override_kasm_server_settings: true
  allow_override_standard_vnc_server_settings: true
  allow_override_list:
    - pointer.enabled
    - data_loss_prevention.clipboard.server_to_client.enabled
    - data_loss_prevention.clipboard.client_to_server.enabled

encoding:
  max_frame_rate: ${KVNC_MAX_FRAME_RATE}
  # Periodic full-frame updates heal lost UDP datagrams (WebRTC data channel).
  full_frame_updates: ${KVNC_FULL_FRAME_UPDATES}
  rect_encoding_mode:
    min_quality: ${KVNC_RECT_MIN_QUALITY}
    max_quality: ${KVNC_RECT_MAX_QUALITY}

data_loss_prevention:
  clipboard:
    server_to_client:
      enabled: true
    client_to_server:
      enabled: true

security:
  brute_force_protection:
    blacklist_threshold: ${KVNC_BLACKLIST_THRESHOLD}
    blacklist_timeout: 10

server:
  advanced:
    kasm_password_file: ${PASS_FILE}
  auto_shutdown:
    no_user_session_timeout: never
    active_user_session_timeout: never
    inactive_user_session_timeout: never
  allow_environment_variables_to_override_config_settings: true

logging:
  log_writer_name: all
  log_dest: logfile
  level: ${KVNC_LOG_LEVEL}
EOF

# KasmVNC exits on any unused KVNC_* name when env overrides are enabled,
# so export exactly the keys that exist in the schema.
export KVNC_DESKTOP_ALLOW_RESIZE="$KVNC_ALLOW_RESIZE"
export KVNC_NETWORK_SSL_REQUIRE_SSL="$KVNC_REQUIRE_SSL"
export KVNC_ENCODING_MAX_FRAME_RATE="$KVNC_MAX_FRAME_RATE"
export KVNC_NETWORK_WEBSOCKET_PORT="$WEB_PORT"

SCHEME=http; is_true "$KVNC_REQUIRE_SSL" && SCHEME=https
log "display=:${D} geometry=${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}"
log "web: ${SCHEME}://<host>:${WEB_PORT}/vnc.html"

# ----------------------------------------------------- 4. VNC user account
# KasmVNC has no anonymous mode (TigerVNC securitytypes=None does not exist):
# the web client always logs in against ~/.kasmpasswd. VNC_ENABLED=true uses
# PASSWORD; otherwise a convenience account kasm/kasm is created.
if is_true "${VNC_ENABLED:-true}"; then
  [[ ${#PASSWORD} -ge 6 ]] || die "PASSWORD must be >= 6 characters (KasmVNC enforces this)"
else
  PASSWORD=kasm; VNC_USER=kasm
  log "auth: convenience account kasm/kasm — set VNC_ENABLED=true and PASSWORD for production"
fi
printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
  | kasmvncpasswd -u "$VNC_USER" -w -o "$PASS_FILE" >/dev/null
chmod 600 "$PASS_FILE"
log "kasm user: ${VNC_USER}"

# ------------------------------------------------ 5. 115 cookie injection
# Same sed contract as upstream 115Docker/run.sh, applied to a pristine copy
# so a restart with new env values works.
if [[ -f "$COOKIE_FILE" ]]; then
  [[ -f "${COOKIE_FILE}.orig" ]] || cp -a "$COOKIE_FILE" "${COOKIE_FILE}.orig"
  cp -a "${COOKIE_FILE}.orig" "$COOKIE_FILE"
  if [[ -n "${COOKIE_CID}${COOKIE_SEID}${COOKIE_UID}${COOKIE_KID}" ]]; then
    EXPIRATION=$(date -d "+1 year" +%s)
    sed -i \
      -e "s|\(CID:\s*'\)[^']*'|\1${COOKIE_CID}'|" \
      -e "s|\(SEID:\s*'\)[^']*'|\1${COOKIE_SEID}'|" \
      -e "s|\(UID:\s*'\)[^']*'|\1${COOKIE_UID}'|" \
      -e "s|\(KID:\s*'\)[^']*'|\1${COOKIE_KID}'|" \
      -e "s|\(EXPIRATION_DATE:\s*\)[0-9]*|\1${EXPIRATION}|" \
      "$COOKIE_FILE"
  fi
  log "cookie injection: CID=${COOKIE_CID:-none} SEID=${COOKIE_SEID:-none} UID=${COOKIE_UID:-none} KID=${COOKIE_KID:-none}"
fi

# ------------------------------------------------------ 6. X session script
# KasmVNC runs ~/.vnc/xstartup after the X server is up and terminates the
# session when it exits, so it must stay in the foreground.
cat > "$HOME/.vnc/xstartup" <<'XSTARTUP'
#!/bin/bash
# KasmVNC-safe-to-replace-this-file
export DISPLAY="${DISPLAY:-:99}"
log() { echo "[xstartup] $*"; }

xset s off -dpms 2>/dev/null || true
xsetroot -solid '#1f2430' 2>/dev/null || true

# Window manager first: the 115 browser needs one for --start-maximized,
# window moves and resize (KasmVNC sends client-side resize hints).
if [[ -x /usr/bin/openbox ]]; then
  openbox &
  log "openbox wm started"
fi

# pcmanfm/tint2 need a writable, user-owned XDG config dir
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$XDG_CONFIG_HOME"
if [[ ! -f "$XDG_CONFIG_HOME/pcmanfm/UI/pcmanfm.conf" && -d /etc/115-kasm/skel-config ]]; then
  cp -a /etc/115-kasm/skel-config/. "$XDG_CONFIG_HOME/" 2>/dev/null || true
fi

pcmanfm --desktop --profile UI >>/tmp/pcmanfm.log 2>&1 &
log "pcmanfm desktop started"

if [[ -n "${TINT2_CONF:-}" && -f "${TINT2_CONF}" ]]; then
  G_SLICE=always-malloc tint2 -c "$TINT2_CONF" >>/tmp/tint2.log 2>&1 &
  log "tint2 panel started (${TINT2_CONF})"
fi

trap 'exit 0' TERM INT
while :; do sleep 2; done
XSTARTUP
chmod 700 "$HOME/.vnc/xstartup"
# Tell kasmvncserver the DE is already chosen, otherwise it launches the
# interactive select-de.sh (which aborts in a non-tty container).
touch "$HOME/.vnc/.de-was-selected"

# ------------------------------------------------------- 7. start KasmVNC
# -fg keeps the server in the foreground, -autokill tears the display down
# when xstartup goes away; KVNC_* env vars override the yaml above.
kasmvncserver ":${D}" \
  -fg -autokill \
  -geometry "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" \
  -depth 24 \
  -desktop 115 \
  -interface 0.0.0.0 \
  -websocketPort "${WEB_PORT}" \
  -cert "$SSL_DIR/cert.pem" -key "$SSL_DIR/privkey.pem" \
  $(is_true "$KVNC_REQUIRE_SSL" && echo -sslOnly) \
  -RawKeyboard 0 \
  -AcceptKeyEvents 1 -AcceptPointerEvents 1 -AcceptCutText 1 -SendCutText 1 \
  -MaxDisconnectionTime 0 \
  -BlacklistThreshold "${KVNC_BLACKLIST_THRESHOLD}" -BlacklistTimeout 10 \
  -DynamicQualityMin "${KVNC_RECT_MIN_QUALITY}" -DynamicQualityMax "${KVNC_RECT_MAX_QUALITY}" \
  -FrameRate "${KVNC_MAX_FRAME_RATE}" \
  -IdleTimeout 0 -QueryConnect 0 -prompt false \
  -KasmPasswordFile "$PASS_FILE" \
  -AllowOverride pointer.enabled,data_loss_prevention.clipboard.server_to_client.enabled,data_loss_prevention.clipboard.client_to_server.enabled \
  &
KASM_PID=$!

# ------------------------------------------------------ 8. 115 browser autostart
if is_true "${AUTO_START:-false}"; then
  for _ in $(seq 1 60); do
    [[ -S "/tmp/.X11-unix/X${D}" ]] && break
    sleep 0.5
  done
  if [[ -S "/tmp/.X11-unix/X${D}" ]]; then
    log "AUTO_START=true -> launching 115 browser"
    export DISPLAY=":${D}"
    /usr/local/115Browser/115.sh
  else
    log "WARN: X socket /tmp/.X11-unix/X${D} never appeared; skipping autostart"
  fi
fi

# ------------------------------------------------------------ 9. shutdown
cleanup() {
  trap - EXIT
  pkill -f 'pcmanfm --desktop' 2>/dev/null || true
  pkill -x tint2 2>/dev/null || true
  pkill -f '115Browser' 2>/dev/null || true
  kasmvncserver -kill ":${D}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'kill "$KASM_PID" 2>/dev/null || true' TERM INT

wait "$KASM_PID"
