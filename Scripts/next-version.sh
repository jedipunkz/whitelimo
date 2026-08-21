#!/bin/sh
#
# Print the version that follows the latest one when bumped.
#
#   next-version.sh <major|minor|patch> [latest-tag]
#
# The latest tag may be empty, which is how the first release works: the base is
# v0.0.0, so a patch bump gives v0.0.1, a minor bump v0.1.0 and a major bump
# v1.0.0. A pre-release suffix on the latest tag is ignored, so bumping the patch
# of v1.2.3-rc1 gives v1.2.4.
#
# This is a plain function of its arguments -- it never looks at git -- so the
# release workflow's version arithmetic can be tested on any machine. See
# next-version_test.sh.
set -eu

usage() {
	echo "usage: next-version.sh <major|minor|patch> [latest-tag]" >&2
	exit 2
}

[ $# -ge 1 ] || usage
bump=$1
latest=${2:-}

fail() {
	echo "next-version: $1" >&2
	exit 1
}

case "$latest" in
"")
	major=0
	minor=0
	patch=0
	;;
*.*.*)
	version=${latest#v}
	version=${version%%-*} # drop a pre-release suffix
	version=${version%%+*} # drop build metadata
	major=${version%%.*}
	rest=${version#*.}
	minor=${rest%%.*}
	patch=${rest#*.}
	;;
*)
	fail "cannot read a version out of '$latest'"
	;;
esac

for part in "$major" "$minor" "$patch"; do
	case "$part" in
	'' | *[!0-9]*) fail "cannot read a version out of '$latest'" ;;
	esac
done

case "$bump" in
major)
	major=$((major + 1))
	minor=0
	patch=0
	;;
minor)
	minor=$((minor + 1))
	patch=0
	;;
patch)
	patch=$((patch + 1))
	;;
*)
	fail "unknown bump '$bump', want major, minor or patch"
	;;
esac

printf 'v%s.%s.%s\n' "$major" "$minor" "$patch"
