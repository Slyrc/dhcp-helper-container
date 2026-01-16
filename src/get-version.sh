#!/bin/sh
set -eu

# Optional: Only consider tags matching this glob (as used by `git describe --match`)
# Examples:
#   TAG_MATCH='v[0-9]*'   # only tags like v1.2.3
#   TAG_MATCH=''          # (empty) accept any tag name
TAG_MATCH="${TAG_MATCH:-v[0-9]*}"

# Prefer Docker build-arg if provided and not "UNKNOWN"
# Dockerfile example: ARG DHCP_HELPER_VERSION=UNKNOWN
# If DHCP_HELPER_VERSION is set (and not UNKNOWN), use it instead of git-describe flow.
if [ -n "${DHCP_HELPER_VERSION:-}" ] && [ "${DHCP_HELPER_VERSION}" != "UNKNOWN" ]; then
    # Always strip a leading "v" from the output (cosmetic).
    printf '%s\n' "${DHCP_HELPER_VERSION#v}"
    exit 0
fi

# This line is intended to be substituted by `git archive` when export-subst is enabled.
subst='$Format:%d$'

# Build the literal placeholder string at runtime so `git archive` does NOT substitute it here.
placeholder='$'"Format:%d"'$'

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
        # Always strip a leading "v" (cosmetic)
        printf '%s\n' "${tag#v}"
    fi

elif [ "$subst" = "$placeholder" ]; then
    # Unsubstituted file (no git information embedded) and no git available
    printf '%s\n' UNKNOWN
else
    # Fallback: try to extract v* tags from substituted ref information
    vers="$(printf '%s' "$subst" \
        | sed 's/[(), ]/,/g' \
        | tr ',' '\n' \
        | grep -E '^v[0-9]' || true)"

    if [ -n "${vers:-}" ]; then
        # If multiple v* tags exist, sort and pick the first; then always strip leading "v"
        printf '%s\n' "$vers" | sort | head -n 1 | sed 's/^v//'
    else
        # Nothing matched; print the raw substituted string
        printf '%s\n' "$subst"
    fi
fi

exit 0
