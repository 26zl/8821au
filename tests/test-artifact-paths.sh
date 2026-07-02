#!/bin/sh
# Guard: the monitor-mode artifact paths are duplicated across the writer
# (tools/monitor-mode.sh), the remover (remove-driver.sh) and the reporter
# (tools/status.sh) on purpose (mixed shells + heredocs, see CLAUDE.md).
# This asserts they stay byte-identical so a path change in one file can't
# silently drift from the others.

set -eu

cd "$(dirname "$0")/.."

fail=0
must_contain() { # must_contain <file> <literal>
	if grep -qF -- "$2" "$1"; then
		echo "ok   - $1 contains $2"
	else
		echo "FAIL - $1 is missing $2"
		fail=1
	fi
}

WRITER=tools/monitor-mode.sh
REMOVER=remove-driver.sh
REPORTER=tools/status.sh

# Paths the writer and remover must both agree on. (The remover composes the
# unit path as /etc/systemd/system/${SERVICE}, so the dir + service name are
# checked instead of a single unit literal.)
for p in \
	/usr/local/bin/wlan-monitor-8821au.sh \
	/etc/systemd/system/ \
	/etc/NetworkManager/conf.d/10-unmanaged-8821au.conf \
	/etc/udev/rules.d/90-8821au-monitor.rules \
	/etc/connman/.8821au-monitor-marker
do
	must_contain "$WRITER" "$p"
	must_contain "$REMOVER" "$p"
done

# The service name and the config paths the reporter inspects must match too.
for p in \
	wlan-monitor-8821au.service \
	/etc/NetworkManager/conf.d/10-unmanaged-8821au.conf \
	/etc/udev/rules.d/90-8821au-monitor.rules \
	/etc/connman/.8821au-monitor-marker
do
	must_contain "$WRITER" "$p"
	must_contain "$REMOVER" "$p"
	must_contain "$REPORTER" "$p"
done

exit "$fail"
