#!/bin/sh
set -eu

# Optional: Only consider tags matching this glob (as used by `git describe --match`)
# Examples:
#   TAG_MATCH='v[0-9]*'   # only tags like v1.2.3
#   TAG_MATCH=''          # (empty) accept any tag name
TAG_MATCH="${TAG_MATCH:-v[0-9]*}"

# Optional: Strip a leading "v" from the output (cosmetic)
# 1 = yes (default), 0 = no
STRIP_V_PREFIX="${STRIP_V_PREFIX:-1}"

subst='$Format:%d$'

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Determine the currently checked out local branch.
    # If we're in a detached HEAD state, fall back to HEAD.
    ref="$(git symbolic-ref -q --short HEAD 2>/dev/null || printf '%s' HEAD)"

    # Build arguments for `git describe`:
    # --tags     : consider lightweight tags too (not only annotated tags)
    # --abbrev=0 : print only the tag name (no "-N-g<hash>" suffix)
    set -- --tags --abbrev=0
    if [ -n "$TAG_MATCH" ]; then
        # Restrict to a tag naming scheme (optional)
        set -- "$@" --match "$TAG_MATCH"
    fi

    # Find the most recent tag reachable from the current ref
    tag="$(git describe "$@" "$ref" 2>/dev/null || true)"

    if [ -z "${tag:-}" ]; then
        printf '%s\n' UNKNOWN
    else
        if [ "$STRIP_V_PREFIX" = "1" ]; then
            printf '%s\n' "${tag#v}"
        else
            printf '%s\n' "$tag"
        fi
    fi

elif printf '%s' "$subst" | grep -q '\$Format:%d\$'; then
    # Unsubstituted file (no git information embedded) and no git available
    printf '%s\n' UNKNOWN
else
    # Fallback: try to extract v* tags from substituted ref information
    vers="$(printf '%s' "$subst" \
        | sed 's/[(), ]/,/g' \
        | tr ',' '\n' \
        | grep -E '^v[0-9]' || true)"

    if [ -n "${vers:-}" ]; then
        # If multiple v* tags exist, sort and pick the first; then strip leading "v"
        printf '%s\n' "$vers" | sort | head -n 1 | sed 's/^v//'
    else
        # Nothing matched; print the raw substituted string
        printf '%s\n' "$subst"
    fi
fi

exit 0
