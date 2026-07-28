#!/bin/sh
# all-dev-eegateway — Flask UI launcher for strict snap confinement.
set -eu

# shellcheck source=hooks-lib.sh
. "${SNAP:?}/bin/hooks-lib.sh"

ensure_directories
export_python_runtime

export EE_DATA_DIR="${DATA_DIR}"

ui_port="$(snapctl get ui-port 2>/dev/null || true)"
ui_port="${ui_port:-${DEFAULT_UI_PORT}}"
export EE_UI_PORT="$ui_port"

ee_base_url="$(snapctl get ee-base-url 2>/dev/null || true)"
if ! null_or_empty "$ee_base_url"; then
  export EE_BASE_URL="$ee_base_url"
fi

# When all-dev-caddy fronts the UI, bind localhost only.
proxy_enabled="$(snapctl get proxy-enabled 2>/dev/null || true)"
case "${proxy_enabled:-false}" in
  true|1|yes|on)
    export EE_UI_HOST="127.0.0.1"
    ;;
  *)
    export EE_UI_HOST="0.0.0.0"
    ;;
esac

PYTHON="$(resolve_python)"
exec "${PYTHON}" -m ee_gateway_ui.app
