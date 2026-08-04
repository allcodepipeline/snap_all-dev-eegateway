#!/bin/sh
# Shared helpers for install/configure hooks and start wrappers.
# all-dev-eegateway — Ubuntu Core snap packaging of Encrypted-Energy/gateway.

COMMON="${SNAP_COMMON:-/var/snap/all-dev-eegateway/common}"
DATA_DIR="${COMMON}/data"
LOG_DIR="${COMMON}/logs"
CADDY_DIR="${COMMON}/caddy"
CONFIG_JSON="${DATA_DIR}/config.json"
CADDY_PROXY_DECL="${CADDY_DIR}/${SNAP_NAME:-all-dev-eegateway}.proxy"
CADDY_FRAGMENT="${CADDY_DIR}/${SNAP_NAME:-all-dev-eegateway}.caddy"

DEFAULT_UI_PORT=7880
DEFAULT_SCAN_INTERVAL=15
DEFAULT_SCAN_TIMEOUT=10
DEFAULT_HEARTBEAT_INTERVAL=60
DEFAULT_EE_BASE_URL="https://encryptedenergy.com"
DEFAULT_PROXY_LOCAL_NAME="eegateway"
DEFAULT_PROXY_SCHEME="https"

null_or_empty() {
  [ -z "${1:-}" ] || [ "$1" = "null" ]
}

# Prefer the interpreter staged inside the snap (not the Core base).
resolve_python() {
  for candidate in \
    "${SNAP}/usr/bin/python3.12" \
    "${SNAP}/usr/bin/python3" \
    "${SNAP}/bin/python3.12" \
    "${SNAP}/bin/python3"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "python3 not found inside snap at ${SNAP}/usr/bin (rebuild required)" >&2
  ls -la "${SNAP}/usr/bin/python"* 2>/dev/null || true
  exit 127
}

# Shared runtime env so urllib can open https:// (needs _ssl + libssl + CA bundle).
export_python_runtime() {
  export PYTHONUNBUFFERED=1
  export PYTHONDONTWRITEBYTECODE=1
  export PYTHONPATH="${SNAP}/local/lib/python3.12/dist-packages:${SNAP}/lib/python3.12/site-packages:${SNAP}/usr/lib/python3/dist-packages:${SNAP}/usr/lib/python3.12/dist-packages${PYTHONPATH:+:${PYTHONPATH}}"
  export LD_LIBRARY_PATH="${SNAP}/usr/lib:${SNAP}/usr/lib/x86_64-linux-gnu:${SNAP}/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  export PATH="${SNAP}/usr/sbin:${SNAP}/usr/bin:${SNAP}/sbin:${SNAP}/bin:${PATH:-/usr/bin:/bin}"

  if [ -f "${SNAP}/etc/ssl/certs/ca-certificates.crt" ]; then
    export SSL_CERT_FILE="${SNAP}/etc/ssl/certs/ca-certificates.crt"
    export SSL_CERT_DIR="${SNAP}/etc/ssl/certs"
    export REQUESTS_CA_BUNDLE="${SSL_CERT_FILE}"
    export CURL_CA_BUNDLE="${SSL_CERT_FILE}"
  elif [ -f "${SNAP}/usr/lib/ssl/cert.pem" ]; then
    export SSL_CERT_FILE="${SNAP}/usr/lib/ssl/cert.pem"
    export REQUESTS_CA_BUNDLE="${SSL_CERT_FILE}"
    export CURL_CA_BUNDLE="${SSL_CERT_FILE}"
  fi
}

ensure_directories() {
  mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${CADDY_DIR}"
  chmod 700 "${DATA_DIR}"
}

ensure_defaults() {
  ui_port="$(snapctl get ui-port 2>/dev/null || true)"
  if [ -z "$ui_port" ]; then
    snapctl set ui-port="${DEFAULT_UI_PORT}"
  fi

  scan_interval="$(snapctl get scan-interval 2>/dev/null || true)"
  if [ -z "$scan_interval" ]; then
    snapctl set scan-interval="${DEFAULT_SCAN_INTERVAL}"
  fi

  scan_timeout="$(snapctl get scan-timeout 2>/dev/null || true)"
  if [ -z "$scan_timeout" ]; then
    snapctl set scan-timeout="${DEFAULT_SCAN_TIMEOUT}"
  fi

  heartbeat_interval="$(snapctl get heartbeat-interval 2>/dev/null || true)"
  if [ -z "$heartbeat_interval" ]; then
    snapctl set heartbeat-interval="${DEFAULT_HEARTBEAT_INTERVAL}"
  fi

  ee_base_url="$(snapctl get ee-base-url 2>/dev/null || true)"
  if [ -z "$ee_base_url" ]; then
    snapctl set ee-base-url="${DEFAULT_EE_BASE_URL}"
  fi

  proxy_enabled="$(snapctl get proxy-enabled 2>/dev/null || true)"
  if [ -z "$proxy_enabled" ]; then
    snapctl set proxy-enabled=false
  fi
}

validate_ui_port() {
  port="$(snapctl get ui-port 2>/dev/null || true)"
  if [ -z "$port" ]; then
    return 0
  fi
  case "$port" in
    *[!0-9]*)
      echo "ui-port must be a positive integer" >&2
      exit 1
      ;;
    0)
      echo "ui-port must be greater than zero" >&2
      exit 1
      ;;
  esac
}

validate_int_range() {
  key="$1"
  min="$2"
  max="$3"
  value="$(snapctl get "$key" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    return 0
  fi
  case "$value" in
    *[!0-9]*)
      echo "${key} must be an integer" >&2
      exit 1
      ;;
  esac
  if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
    echo "${key} must be between ${min} and ${max}" >&2
    exit 1
  fi
}

validate_ee_base_url() {
  url="$(snapctl get ee-base-url 2>/dev/null || true)"
  if [ -z "$url" ]; then
    return 0
  fi
  case "$url" in
    http://*|https://*)
      return 0
      ;;
    *)
      echo "ee-base-url must start with http:// or https://" >&2
      exit 1
      ;;
  esac
}

validate_coord() {
  key="$1"
  lo="$2"
  hi="$3"
  value="$(snapctl get "$key" 2>/dev/null || true)"
  if null_or_empty "$value"; then
    return 0
  fi
  # Basic numeric check (optional leading minus, digits, optional decimal).
  case "$value" in
    -*|*.*|*[0-9]*)
      ;;
    *)
      echo "${key} must be a decimal number" >&2
      exit 1
      ;;
  esac
  # Range check via awk for floats.
  if ! awk -v v="$value" -v lo="$lo" -v hi="$hi" 'BEGIN { exit !(v+0 == v && v >= lo && v <= hi) }'; then
    echo "${key} must be between ${lo} and ${hi}" >&2
    exit 1
  fi
}

validate_fixed_pair() {
  lat="$(snapctl get fixed-lat 2>/dev/null || true)"
  lon="$(snapctl get fixed-lon 2>/dev/null || true)"
  lat_set=0
  lon_set=0
  null_or_empty "$lat" || lat_set=1
  null_or_empty "$lon" || lon_set=1
  if [ "$lat_set" -ne "$lon_set" ]; then
    echo "fixed-lat and fixed-lon must both be set or both be cleared" >&2
    exit 1
  fi
  if [ "$lat_set" -eq 1 ] && [ "$lon_set" -eq 1 ]; then
    if awk -v lat="$lat" -v lon="$lon" 'BEGIN { exit !((lat+0)==0 && (lon+0)==0) }'; then
      echo "fixed-lat and fixed-lon cannot both be zero" >&2
      exit 1
    fi
  fi
}

validate_bool() {
  key="$1"
  value="$(snapctl get "$key" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    return 0
  fi
  case "$value" in
    true|false|1|0|yes|no|on|off)
      return 0
      ;;
    *)
      echo "${key} must be true or false" >&2
      exit 1
      ;;
  esac
}

validate_proxy_scheme() {
  scheme="$(snapctl get proxy-scheme 2>/dev/null || true)"
  if [ -z "$scheme" ]; then
    return 0
  fi
  case "$scheme" in
    http|https|both)
      return 0
      ;;
    *)
      echo "proxy-scheme must be http, https, or both" >&2
      exit 1
      ;;
  esac
}

validate_gps_baud() {
  baud="$(snapctl get gps-baud 2>/dev/null || true)"
  if null_or_empty "$baud"; then
    return 0
  fi
  case "$baud" in
    *[!0-9]*)
      echo "gps-baud must be a positive integer" >&2
      exit 1
      ;;
    0)
      echo "gps-baud must be greater than zero" >&2
      exit 1
      ;;
  esac
}

validate_all() {
  validate_ui_port
  validate_int_range scan-interval 0 3600
  validate_int_range scan-timeout 1 300
  validate_int_range heartbeat-interval 15 3600
  validate_ee_base_url
  validate_coord fixed-lat -90 90
  validate_coord fixed-lon -180 180
  validate_fixed_pair
  validate_bool proxy-enabled
  validate_proxy_scheme
  validate_gps_baud
}

# Merge snap keys into $SNAP_COMMON/data/config.json for the worker/UI.
# Writes when api-token is set (token alone authenticates; org-id is optional).
write_config_json() {
  api_token="$(snapctl get api-token 2>/dev/null || true)"
  if null_or_empty "$api_token"; then
    return 0
  fi

  jq_bin="${SNAP}/usr/bin/jq"
  if [ ! -x "$jq_bin" ]; then
    jq_bin="$(command -v jq || true)"
  fi
  if [ -z "$jq_bin" ] || [ ! -x "$jq_bin" ]; then
    echo "jq not found; cannot write config.json" >&2
    exit 1
  fi

  ensure_directories

  existing="{}"
  if [ -f "${CONFIG_JSON}" ]; then
    existing="$(cat "${CONFIG_JSON}")"
  fi

  org_id="$(snapctl get org-id 2>/dev/null || true)"
  scan_interval="$(snapctl get scan-interval 2>/dev/null || true)"
  scan_timeout="$(snapctl get scan-timeout 2>/dev/null || true)"
  heartbeat_interval="$(snapctl get heartbeat-interval 2>/dev/null || true)"
  ee_base_url="$(snapctl get ee-base-url 2>/dev/null || true)"
  fixed_lat="$(snapctl get fixed-lat 2>/dev/null || true)"
  fixed_lon="$(snapctl get fixed-lon 2>/dev/null || true)"

  payload="$(printf '%s\n' "$existing" | "$jq_bin" --arg token "$api_token" '.api_token = $token')"

  if ! null_or_empty "$org_id"; then
    payload="$(printf '%s\n' "$payload" | "$jq_bin" --arg org "$org_id" '.org_id = $org')"
  fi
  if ! null_or_empty "$scan_interval"; then
    payload="$(printf '%s\n' "$payload" | "$jq_bin" --argjson v "$scan_interval" '.scan_interval = $v')"
  fi
  if ! null_or_empty "$scan_timeout"; then
    payload="$(printf '%s\n' "$payload" | "$jq_bin" --argjson v "$scan_timeout" '.scan_timeout = $v')"
  fi
  if ! null_or_empty "$heartbeat_interval"; then
    payload="$(printf '%s\n' "$payload" | "$jq_bin" --argjson v "$heartbeat_interval" '.heartbeat_interval = $v')"
  fi
  if ! null_or_empty "$ee_base_url"; then
    payload="$(printf '%s\n' "$payload" | "$jq_bin" --arg v "$ee_base_url" '.ee_base_url = $v')"
  fi

  if ! null_or_empty "$fixed_lat" && ! null_or_empty "$fixed_lon"; then
    payload="$(printf '%s\n' "$payload" | "$jq_bin" \
      --argjson lat "$fixed_lat" --argjson lon "$fixed_lon" \
      '.fixed_lat = $lat | .fixed_lon = $lon')"
  fi

  tmp="${CONFIG_JSON}.tmp"
  printf '%s\n' "$payload" >"$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "${CONFIG_JSON}"
}

proxy_local_name() {
  _name="$(snapctl get proxy-local-name 2>/dev/null || true)"
  if [ -z "${_name}" ]; then
    _name="${SNAP_NAME:-all-dev-eegateway}"
    _name="${_name#all-dev-}"
  fi
  _name="$(printf '%s' "${_name}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  if [ -z "${_name}" ]; then
    _name="${DEFAULT_PROXY_LOCAL_NAME}"
  fi
  printf '%s\n' "${_name}"
}

proxy_scheme() {
  _scheme="$(snapctl get proxy-scheme 2>/dev/null || true)"
  _scheme="${_scheme:-${DEFAULT_PROXY_SCHEME}}"
  case "${_scheme}" in
    http|https|both) printf '%s\n' "${_scheme}" ;;
    *)
      echo "proxy-scheme must be http, https, or both (got: ${_scheme})" >&2
      return 1
      ;;
  esac
}

write_caddy_fragment() {
  enabled="$(snapctl get proxy-enabled 2>/dev/null || true)"
  enabled="${enabled:-false}"

  mkdir -p "${CADDY_DIR}"

  case "${enabled}" in
    true|1|yes|on) ;;
    *)
      rm -f "${CADDY_FRAGMENT}" "${CADDY_PROXY_DECL}"
      return 0
      ;;
  esac

  port="$(snapctl get ui-port 2>/dev/null || true)"
  port="${port:-${DEFAULT_UI_PORT}}"
  upstream="127.0.0.1:${port}"
  local_name="$(proxy_local_name)"
  scheme="$(proxy_scheme)" || exit 1

  {
    echo "# Declarative proxy for all-dev-caddy. LAN IP is detected by all-dev-caddy."
    printf 'local-name=%s\n' "${local_name}"
    printf 'port=%s\n' "${port}"
    printf 'upstream=%s\n' "${upstream}"
    printf 'scheme=%s\n' "${scheme}"
  } > "${CADDY_PROXY_DECL}.new"
  mv -f "${CADDY_PROXY_DECL}.new" "${CADDY_PROXY_DECL}"
  rm -f "${CADDY_FRAGMENT}"
}

ensure_runtime_config() {
  ensure_directories
  ensure_defaults
  write_config_json
  write_caddy_fragment
}
