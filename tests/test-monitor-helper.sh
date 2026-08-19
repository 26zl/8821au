#!/bin/sh
# Guard: the boot helper embedded in tools/monitor-mode.sh, driven through the
# two paths that silently broke it before.
#
#  1. The interface name is resolved through a command substitution, so any
#     progress message on stdout gets concatenated into the name. Here the
#     interface only appears on the third poll, which is what makes it log.
#  2. The rfkill hard-block check must look at wifi only; an unrelated
#     hard-blocked Bluetooth radio must not abort monitor-mode setup.

set -eu

cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck disable=SC2016  # the sed pattern matches $HELPER_PATH literally
sed -n '/^cat <<.HELPER. > "\$HELPER_PATH"$/,/^HELPER$/p' tools/monitor-mode.sh \
    | sed '1d;$d;s/^main "\$@"$//' > "$WORK/helper.sh"

cat >> "$WORK/helper.sh" <<OUTER_EOF
: > "$WORK/polls"
find_iface() {
  echo x >> "$WORK/polls"
  [ "\$(wc -l < "$WORK/polls")" -ge 3 ] && { echo wlan9; return 0; }
  return 1
}
rfkill() {
  [ "\$1" = list ] || return 0
  [ "\${2:-}" = wifi ] || printf '0: hci0: Bluetooth\n\tHard blocked: yes\n'
  printf '1: phy0: Wireless LAN\n\tHard blocked: no\n'
}
ip() { :; }
iw() { echo "iw \$*" >> "$WORK/iw-calls"; }
sleep() { :; }
command_exists() { case "\$1" in ip|iw|rfkill) return 0;; *) return 1;; esac; }
main
OUTER_EOF

: > "$WORK/iw-calls"
if ! bash "$WORK/helper.sh" >/dev/null 2>&1; then
    echo "FAIL - helper exited non-zero"
    sed 's/^/       /' "$WORK/iw-calls"
    exit 1
fi

if grep -qx "iw dev wlan9 set type monitor" "$WORK/iw-calls"; then
    echo "ok   - helper reaches monitor mode while waiting, with Bluetooth blocked"
    exit 0
fi

echo "FAIL - helper passed a polluted interface name to iw:"
sed 's/^/       /' "$WORK/iw-calls"
exit 1
