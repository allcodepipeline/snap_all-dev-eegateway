# Deploy manifests

Device install / refresh config for **all-dev-eegateway** plus **bluez**.

No `all-dev-caddy` — the UI is plain HTTP on port 7880. Outbound HTTPS to encryptedenergy.com is handled by the snap itself.

## Files

| File | Purpose |
|------|---------|
| `install.json` | Landscape / Tower install plan |

Put site-specific secrets (`api-token`, optional `fixed-lat` / `fixed-lon`) into `snap_config` via an orchestrator overlay or a private copy of `install.json` — do not commit real tokens.

## Tower-supported keys

| Key | Purpose |
|-----|---------|
| `snaps` | Install/refresh snap list |
| `snap_config` | `snap set` settings |
| `ignore_failures` | Continue on non-fatal errors |
| `pre_service_actions` | Service actions before config |
| `post_service_actions` | Service start/restart after config |
| `interface_connections` | `snap connect` plugs/slots |

**Not supported:** `post_commands` (Tower rejects unknown keys).

## Order of operations

1. Install/refresh snaps: `bluez` → `all-dev-eegateway`
2. Connect interfaces (network, network-bind, bluez)
3. Apply `snap_config` via `snap set`
4. Restart `all-dev-eegateway.worker` + `all-dev-eegateway.ui`

## Secrets overlay (add privately)

```json
{
  "snap": "all-dev-eegateway",
  "settings": {
    "api-token": "ee_live_…",
    "fixed-lat": "37.7749",
    "fixed-lon": "-122.4194"
  }
}
```

Without `api-token`, the UI stays on the setup wizard at `http://<device-ip>:7880`.

## Optional GPS

Do **not** put `gps-serial` in Tower `interface_connections` unless the gadget exposes a matching `serial-port` slot. Connect manually when needed:

```bash
sudo snap connect all-dev-eegateway:gps-serial
```

## Manual NUC equivalent

```bash
sudo snap install bluez
sudo snap install ./dist/all-dev-eegateway_*.snap --dangerous

sudo snap connect all-dev-eegateway:bluetooth-client bluez:service

sudo snap set all-dev-eegateway \
  ui-port=7880 \
  proxy-enabled=false \
  api-token='ee_live_…' \
  fixed-lat='…' \
  fixed-lon='…'

sudo snap restart all-dev-eegateway.worker
sudo snap restart all-dev-eegateway.ui
```

Access: `http://<device-ip>:7880`
