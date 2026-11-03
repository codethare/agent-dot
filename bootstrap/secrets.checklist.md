# Secrets to set by hand

Nothing listed here is stored in this repo, and no value from this list is ever
copied into it. Set these yourself after `install.sh` runs.

- `COMMAND_CODE_API_KEY` — provider key read by Pi. Put it in your shell
  environment; the tracked shell config lives in the `dot` repo, not here.
- ntfy topic — `~/.pi/agent/pi-ntfy.json` is tracked with an empty topic, which
  leaves notifications off. Set a fresh topic (or `NTFY_TOPIC`) to re-enable
  them; do not reuse the old one.
- `pi auth` — run it for any OAuth provider added later. Those credentials stay
  on the machine.
