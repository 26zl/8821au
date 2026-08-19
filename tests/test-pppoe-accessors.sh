#!/bin/sh
# Guard: core/rtw_br_ext.c reaches the PPPoE tags by pointer arithmetic because
# the kernel-visible headers dropped their trailing flexible arrays. A wrong
# offset would still compile and would silently corrupt relay tags, so assert
# the accessors land where the original members did. The userspace copy of the
# header still declares those members, so it can be compared against.

set -eu

cd "$(dirname "$0")/.."

if ! command -v gcc >/dev/null 2>&1; then
    echo "skip - gcc not installed"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Keep these in step with the macros in core/rtw_br_ext.c.
for macro in 'PPPOE_HDR_TAGS(ph)	((unsigned char *)((ph) + 1))' \
             'PPPOE_TAG_DATA(tag)	((unsigned char *)((tag) + 1))'
do
    if ! grep -qF "#define $macro" core/rtw_br_ext.c; then
        echo "FAIL - core/rtw_br_ext.c no longer defines: $macro"
        exit 1
    fi
done

cat > "$WORK/t.c" <<'CEOF'
#include <linux/if_pppox.h>
#include <assert.h>

#define PPPOE_HDR_TAGS(ph)	((unsigned char *)((ph) + 1))
#define PPPOE_TAG_DATA(tag)	((unsigned char *)((tag) + 1))

int main(void)
{
	unsigned char buf[64] = {0};
	struct pppoe_hdr *ph = (struct pppoe_hdr *)buf;
	struct pppoe_tag *tag = (struct pppoe_tag *)(buf + 16);

	assert((unsigned char *)ph->tag == PPPOE_HDR_TAGS(ph));
	assert((unsigned char *)tag->tag_data == PPPOE_TAG_DATA(tag));
	return 0;
}
CEOF

if ! gcc -Wall -O2 -o "$WORK/t" "$WORK/t.c" 2>"$WORK/err"; then
    echo "skip - could not build against <linux/if_pppox.h>"
    sed 's/^/       /' "$WORK/err"
    exit 0
fi

if "$WORK/t"; then
    echo "ok   - PPPoE accessors match the original flexible-array members"
    exit 0
fi

echo "FAIL - PPPoE accessors point somewhere else than the original members"
exit 1
