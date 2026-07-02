#!/bin/sh
# Contract test for the connman NetworkInterfaceBlacklist add/remove logic.
# Mirrors the add snippet in tools/monitor-mode.sh and the remove awk in
# remove-driver.sh. The point is substring safety (wlan1 must not match wlan10)
# and idempotency. Linux/CI-targeted (uses GNU `sed -i`).

set -eu

fail=0
check() { # check <label> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   - $1"
	else
		echo "FAIL - $1"
		echo "       expected: [$2]"
		echo "       actual:   [$3]"
		fail=1
	fi
}

# --- add: mirrors tools/monitor-mode.sh connman branch ---
add_iface() { # add_iface <file> <iface>
	f=$1; iface=$2
	if grep -q "^NetworkInterfaceBlacklist" "$f"; then
		if ! awk -v iface="$iface" '
				/^NetworkInterfaceBlacklist=/ {
					n = split(substr($0, index($0, "=") + 1), a, ",")
					for (i = 1; i <= n; i++) if (a[i] == iface) found = 1
				}
				END { exit(found ? 0 : 1) }
			' "$f"; then
			# Same substitution as monitor-mode.sh; -i omitted for BSD/macOS portability.
			sed "/^NetworkInterfaceBlacklist=/ s/\$/,${iface}/" "$f" > "$f.new" && mv "$f.new" "$f"
		fi
	else
		echo "NetworkInterfaceBlacklist=${iface}" >> "$f"
	fi
}

# --- remove: mirrors remove-driver.sh awk ---
remove_iface() { # remove_iface <file> <iface>
	f=$1; iface=$2
	awk -v iface="$iface" '
			/^NetworkInterfaceBlacklist=/ {
				n = split(substr($0, index($0, "=") + 1), a, ",")
				out = ""
				for (i = 1; i <= n; i++)
					if (a[i] != iface && a[i] != "")
						out = (out == "" ? a[i] : out "," a[i])
				if (out == "") next
				print "NetworkInterfaceBlacklist=" out
				next
			}
			{ print }
		' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

blk() { grep '^NetworkInterfaceBlacklist=' "$1" || true; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cf="$work/main.conf"

# 1. append to an existing entry
printf '[General]\nNetworkInterfaceBlacklist=eth0\n' > "$cf"
add_iface "$cf" wlan1
check "append to existing" "NetworkInterfaceBlacklist=eth0,wlan1" "$(blk "$cf")"

# 2. adding the same exact token is idempotent
add_iface "$cf" wlan1
check "add is idempotent" "NetworkInterfaceBlacklist=eth0,wlan1" "$(blk "$cf")"

# 3. substring must not count as present: wlan1 appends even if wlan10 exists
printf '[General]\nNetworkInterfaceBlacklist=wlan10\n' > "$cf"
add_iface "$cf" wlan1
check "substring is not a match on add" "NetworkInterfaceBlacklist=wlan10,wlan1" "$(blk "$cf")"

# 4. no blacklist line yet -> a new one is appended
printf '[General]\n' > "$cf"
add_iface "$cf" wlan1
check "add when no key present" "NetworkInterfaceBlacklist=wlan1" "$(blk "$cf")"

# 5. remove exact token, keep substring sibling (wlan1 removed, wlan10 stays)
printf '[General]\nNetworkInterfaceBlacklist=eth0,wlan10,wlan1\n' > "$cf"
remove_iface "$cf" wlan1
check "remove exact token, keep substring" "NetworkInterfaceBlacklist=eth0,wlan10" "$(blk "$cf")"

# 6. removing the only token drops the whole line
printf '[General]\nNetworkInterfaceBlacklist=wlan1\n' > "$cf"
remove_iface "$cf" wlan1
check "remove sole token drops line" "" "$(blk "$cf")"

exit "$fail"
