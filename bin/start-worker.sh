#!/bin/sh
# all-dev-eegateway — BLE worker launcher for strict snap confinement.
# GPS discovery adapted from Encrypted-Energy/gateway worker/entrypoint.sh (GPL-3.0-only).
set -eu

# shellcheck source=hooks-lib.sh
. "${SNAP:?}/bin/hooks-lib.sh"

ensure_directories

export EE_DATA_DIR="${DATA_DIR}"
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SNAP}/local/lib/python3.12/dist-packages:${SNAP}/lib/python3.12/site-packages:${SNAP}/usr/lib/python3/dist-packages${PYTHONPATH:+:${PYTHONPATH}}"

# Optional env overrides (also written into config.json by the configure hook).
ee_base_url="$(snapctl get ee-base-url 2>/dev/null || true)"
if ! null_or_empty "$ee_base_url"; then
  export EE_BASE_URL="$ee_base_url"
fi

scan_interval="$(snapctl get scan-interval 2>/dev/null || true)"
if ! null_or_empty "$scan_interval"; then
  export EE_SCAN_INTERVAL="$scan_interval"
fi

scan_timeout="$(snapctl get scan-timeout 2>/dev/null || true)"
if ! null_or_empty "$scan_timeout"; then
  export EE_SCAN_TIMEOUT="$scan_timeout"
fi

heartbeat_interval="$(snapctl get heartbeat-interval 2>/dev/null || true)"
if ! null_or_empty "$heartbeat_interval"; then
  export EE_HEARTBEAT_INTERVAL="$heartbeat_interval"
fi

api_token="$(snapctl get api-token 2>/dev/null || true)"
if ! null_or_empty "$api_token"; then
  export EE_API_TOKEN="$api_token"
fi

org_id="$(snapctl get org-id 2>/dev/null || true)"
if ! null_or_empty "$org_id"; then
  export EE_ORG_ID="$org_id"
fi

fixed_lat="$(snapctl get fixed-lat 2>/dev/null || true)"
fixed_lon="$(snapctl get fixed-lon 2>/dev/null || true)"
if ! null_or_empty "$fixed_lat" && ! null_or_empty "$fixed_lon"; then
  export EE_GPS_FIXED_LAT="$fixed_lat"
  export EE_GPS_FIXED_LON="$fixed_lon"
fi

GPSD="${SNAP}/usr/sbin/gpsd"
if [ ! -x "$GPSD" ]; then
  GPSD="$(command -v gpsd || true)"
fi

EE_GPS_DEVICE="$(snapctl get gps-device 2>/dev/null || true)"
EE_GPS_BAUD="$(snapctl get gps-baud 2>/dev/null || true)"

DEVICES=""
if ! null_or_empty "$EE_GPS_DEVICE" && [ -e "$EE_GPS_DEVICE" ]; then
  DEVICES="$EE_GPS_DEVICE"
  echo "[worker] using snap-set GPS device: $EE_GPS_DEVICE"
else
  for candidate in /dev/ttyUSB* /dev/ttyACM*; do
    [ -e "$candidate" ] || continue
    DEVICES="${DEVICES} ${candidate}"
  done
  DEVICES="${DEVICES# }"
fi

BAUD_HINT=""
if ! null_or_empty "$EE_GPS_BAUD"; then
  BAUD_HINT="-s ${EE_GPS_BAUD}"
  echo "[worker] gpsd baud hint: $EE_GPS_BAUD"
fi

if [ -n "$DEVICES" ] && [ -n "$GPSD" ] && [ -x "$GPSD" ]; then
  # Loopback only — never pass -G (exposes GPS feed on the LAN).
  # shellcheck disable=SC2086
  if $GPSD -n $BAUD_HINT $DEVICES; then
    echo "[worker] gpsd started on: $DEVICES"
  else
    echo "[worker] gpsd failed on: $DEVICES; continuing without GPS"
  fi
elif [ -n "$DEVICES" ]; then
  echo "[worker] gpsd binary not found; continuing without GPS"
else
  echo "[worker] no GPS device found; use fixed-lat/fixed-lon or the UI"
fi

PYTHON="$(resolve_python)"
exec "${PYTHON}" -m ee_gateway_worker.main
