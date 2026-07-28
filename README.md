# all-dev-eegateway

Ubuntu Core 24 snap for [Encrypted-Energy/gateway](https://github.com/Encrypted-Energy/gateway) (GPL-3.0-only). Turns a Core device with Bluetooth into a BLE ground station that forwards packets over **outbound HTTPS** to encryptedenergy.com.

Persistent state lives under `$SNAP_COMMON` (FDE-backed on Ubuntu Core).

## Architecture

| Daemon | Role |
|--------|------|
| `all-dev-eegateway.worker` | BLE scan, SQLite queue, HTTPS ingest + heartbeat |
| `all-dev-eegateway.ui` | Flask setup wizard and status dashboard |

```
$SNAP_COMMON/
  data/          # config.json, state.json, packets.db  (EE_DATA_DIR)
  logs/          # hook / operational logs
  caddy/         # optional all-dev-caddy *.proxy fragment
```

## HTTPS

| Direction | Required? | Notes |
|-----------|-----------|--------|
| Outbound to `encryptedenergy.com` | **Yes** | Worker heartbeats and packet ingest. Needs `network` + CA certs (bundled). |
| Inbound TLS for the local UI | **No** | UI listens plain HTTP (default port 8080). Optional HTTPS via `all-dev-caddy`. |

## Build

```bash
make build          # destructive-mode on the host (needs sudo)
# or
make build-lxd      # isolated LXD build
```

Output: `dist/all-dev-eegateway_0.10.6.1_amd64.snap`

## Install (Ubuntu Core 24)

```bash
sudo snap install dist/all-dev-eegateway_*_amd64.snap --dangerous

# Bluetooth (required for scanning)
sudo snap install bluez
sudo snap connect all-dev-eegateway:bluetooth-client bluez:service

# Optional USB GPS dongle
sudo snap connect all-dev-eegateway:gps-serial

# Optional shared HTTPS reverse proxy
sudo snap connect all-dev-eegateway:caddy-proxy all-dev-caddy:proxy-config
```

## Setup

### Option A — Web UI

Open `http://<device-ip>:8080`, paste your `ee_live_…` API token from [encryptedenergy.com](https://encryptedenergy.com), set location, and start.

### Option B — Headless (`snap set`)

```bash
sudo snap set all-dev-eegateway api-token="ee_live_…"

# Optional fixed coordinates (stationary gateway, no GPS):
sudo snap set all-dev-eegateway \
  fixed-lat="37.7749" \
  fixed-lon="-122.4194"

# Optional tuning:
sudo snap set all-dev-eegateway ui-port=8080
sudo snap set all-dev-eegateway scan-interval=15
sudo snap set all-dev-eegateway scan-timeout=10
sudo snap set all-dev-eegateway heartbeat-interval=60
sudo snap set all-dev-eegateway ee-base-url=https://encryptedenergy.com
sudo snap set all-dev-eegateway gps-device=/dev/ttyUSB0
sudo snap set all-dev-eegateway gps-baud=38400
```

The **configure** hook validates keys and merges them into `$SNAP_COMMON/data/config.json`. The worker reloads config each scan cycle; no manual restart is required after `snap set`.

## snap set reference

| Key | Default | Description |
|-----|---------|-------------|
| `api-token` | *(empty)* | Required for headless start (`ee_live_…`). Writes `config.json`. |
| `org-id` | *(empty)* | Optional legacy field; not required by the worker. |
| `ui-port` | `8080` | Flask dashboard listen port (`EE_UI_PORT`). |
| `ee-base-url` | `https://encryptedenergy.com` | EE API base URL. |
| `scan-interval` | `15` | Seconds between BLE scan cycles (0–3600). |
| `scan-timeout` | `10` | Seconds per `ble.scan()` call (1–300). |
| `heartbeat-interval` | `60` | Seconds between EE heartbeats (15–3600). |
| `fixed-lat` / `fixed-lon` | unset | Both required to stamp packets; both empty clears override. |
| `gps-device` | auto | Force GPS path (e.g. `/dev/ttyUSB0` or `/dev/ttyACM0`). |
| `gps-baud` | unset | Optional gpsd baud hint (e.g. `38400` for u-blox M10). |
| `proxy-enabled` | `false` | Publish a fragment for `all-dev-caddy`. |
| `proxy-local-name` | `eegateway` | mDNS / Caddy local name. |
| `proxy-scheme` | `https` | `http`, `https`, or `both`. |

When `proxy-enabled=true`, the UI binds `127.0.0.1` and Caddy terminates TLS.

```bash
sudo snap set all-dev-eegateway proxy-enabled=true proxy-local-name=eegateway
# then open https://eegateway.local (after trusting the Caddy CA)
```

## Logs

```bash
sudo snap logs all-dev-eegateway.worker -f
sudo snap logs all-dev-eegateway.ui -f
```

## Interfaces

| Plug | Purpose |
|------|---------|
| `bluetooth-client` (bluez) | BLE scan via host bluetoothd |
| `network` | Outbound HTTPS to EE |
| `network-bind` | UI listener |
| `gps-serial` (serial-port) | Optional USB GPS |
| `hardware-observe` | Device enumeration for GPS discovery |
| `caddy-proxy` (content) | Optional HTTPS front-end via all-dev-caddy |

## Step-by-step: how this snap was packaged

1. **Identify runtime** — Upstream ships a Python **worker** + Flask **ui** sharing one data directory (`config.json`, `state.json`, `packets.db`).
2. **Choose Core24 strict snap** — Two `apps` daemons, `base: core24`, persistent `$SNAP_COMMON`.
3. **Build part** — Clone `v0.10.6`, `pip install` worker + ui into the snap prefix; include fonts via package-data fix; stage `python3`, `gpsd`, `ca-certificates`, `jq`.
4. **Start wrappers** — Set `EE_DATA_DIR=$SNAP_COMMON/data`, GPS auto-discovery / gpsd, and `PYTHONPATH` for pip-installed packages.
5. **install hook** — Create `$SNAP_COMMON/{data,logs,caddy}` and seed default `snapctl` keys.
6. **configure hook** — Validate `snap set` keys; write/merge `config.json`; optionally write Caddy `*.proxy`. Do **not** call `snapctl restart`.
7. **Plugs** — `bluez` for BLE, `network` for outbound HTTPS, optional `serial-port` + `caddy-proxy`.
8. **No inbound TLS in-app** — UI stays HTTP; use `all-dev-caddy` when browser HTTPS is needed.

## Version

Tracks upstream EE Gateway **v0.10.6** (snap packaging revision **0.10.6.1** includes a staged CPython runtime).
