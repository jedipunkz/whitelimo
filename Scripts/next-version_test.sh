#!/bin/sh
#
# Checks next-version.sh, the version arithmetic the release workflow relies on.
# Run it with: sh Scripts/next-version_test.sh
set -eu

script="$(dirname "$0")/next-version.sh"
failures=0

# ok <bump> <latest> <want>
ok() {
	if got=$(sh "$script" "$1" "$2" 2>/dev/null); then
		:
	else
		got="(exit $?)"
	fi
	if [ "$got" != "$3" ]; then
		echo "FAIL: next-version.sh $1 '$2' = $got, want $3"
		failures=$((failures + 1))
	fi
}

# rejects <bump> <latest>
rejects() {
	if got=$(sh "$script" "$1" "$2" 2>/dev/null); then
		echo "FAIL: next-version.sh $1 '$2' = $got, want a failure"
		failures=$((failures + 1))
	fi
}

# The first release starts from v0.0.0, so the bump picks where to begin.
ok patch "" v0.0.1
ok minor "" v0.1.0
ok major "" v1.0.0

ok patch v1.2.3 v1.2.4
ok minor v1.2.3 v1.3.0
ok major v1.2.3 v2.0.0

# A bump resets everything below it.
ok minor v1.2.9 v1.3.0
ok major v1.9.9 v2.0.0

# Numbers, not strings: 9 is followed by 10, not by 91 or 1.
ok patch v0.9.9 v0.9.10
ok minor v1.9.0 v1.10.0
ok patch v1.2.19 v1.2.20

# Leading zeroes and large numbers stay arithmetic.
ok patch v10.20.30 v10.20.31

# A pre-release or build suffix on the latest tag is ignored.
ok patch v1.2.3-rc1 v1.2.4
ok minor v1.2.3-rc.2 v1.3.0
ok patch v1.2.3+build5 v1.2.4

# The leading v is optional on the way in and always present on the way out.
ok patch 1.2.3 v1.2.4

rejects patch "v1.2"
rejects patch "v1.2.3.4"
rejects patch "beta"
rejects patch "vX.Y.Z"
rejects beta "v1.2.3"
rejects "" "v1.2.3"

if [ "$failures" -ne 0 ]; then
	echo "$failures failure(s)"
	exit 1
fi
echo "next-version.sh: all cases pass"
