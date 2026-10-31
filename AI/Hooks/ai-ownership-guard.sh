#!/usr/bin/env bash
# ai-ownership-guard.sh - Claude Code hook that refuses work in a repository another AI profile owns.
#
# Deployed by Deploy-AiArtifacts next to the managed settings copy, together with ai-profile.conf
# (the machine's profile and the ownership patterns), and wired into the managed settings as:
#   UserPromptSubmit  bash "<dir>/ai-ownership-guard.sh" UserPromptSubmit
#   PreToolUse        bash "<dir>/ai-ownership-guard.sh" PreToolUse
# One file for both halves: WinuX and Foundation ship it at this path as a mirror file (a `mirror`
# line in Windows/PowerShell/Upstream.conf and Unix/config/upstream.conf), so it stays identical.
#
# Reads the hook input (JSON) on stdin and uses its `cwd` and `session_id`. The repository is the
# one holding cwd; its owner is decided from the `origin` remote, normalised to host/owner/name
# (lowercase, no scheme, no user, no .git):
#   1. a `shared PATTERN` line matches          -> allowed under every profile
#   2. an `owns PROFILE PATTERN` line matches   -> owned by PROFILE (the first matching line wins)
#   3. otherwise                                -> owned by the `default-owner` profile
# The work is allowed when the owner is this machine's `profile`, refused otherwise. A folder outside
# any repository, or a repository without an `origin`, is allowed. PATTERN is a shell glob
# (github.com/my-org/*). A missing or empty ai-profile.conf allows everything (no profiles in use).
#
# The guard is also the one place that blocks a session for the repository policy
# (ai-repository-policy.sh holds the levels): it refuses a repository whose level is `blocked`, and,
# in an unattended run (the AI_UNATTENDED environment variable set to 1, on, true or yes by the
# launcher), a profile with `unattended off` and a repository at `draft` or `readonly`.
#
# Verdicts are cached per session and folder under ${TMPDIR:-/tmp}/ai-ownership-guard/, so a tool
# call costs one file read after the first.

set -u

event="${1:-PreToolUse}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
conf="${AI_PROFILE_CONF:-$here/ai-profile.conf}"
input="$(cat)"

[ -s "$conf" ] || exit 0

json_field() {
	# The first string value of key $1 in the hook input. Paths and session ids never hold a quote,
	# so a value runs to the next one; a Windows path's backslashes become forward slashes, which
	# git and bash take (C:/Users/...).
	printf '%s' "$input" | sed -n -E 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n 1 | tr '\\' '/' | sed -E 's#/+#/#g'
}

normalise_remote() {
	# https://user@github.com/Owner/Name.git, git@github.com:Owner/Name.git, ssh://git@host/Owner/Name
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E \
		-e 's#^[a-z+]+://##' \
		-e 's#^[^@/]+@##' \
		-e 's#^([^/:]+):([^0-9])#\1/\2#' \
		-e 's#\.git/?$##' \
		-e 's#/+$##'
}

conf_value() {
	sed -n -E "s/^$1[[:space:]]+([^[:space:]#]+).*/\1/p" "$conf" | tail -n 1
}

owner_of() {
	local remote="$1" kind a b
	while read -r kind a b; do
		case "$kind" in
		shared)
			# shellcheck disable=SC2254
			case "$remote" in $(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')) printf '*'; return ;; esac
			;;
		esac
	done <"$conf"
	while read -r kind a b; do
		case "$kind" in
		owns)
			# shellcheck disable=SC2254
			case "$remote" in $(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')) printf '%s' "$a"; return ;; esac
			;;
		esac
	done <"$conf"
	conf_value default-owner
}

valid_level() {
	case "$1" in autonomous | branch | draft | readonly | blocked) return 0 ;; esac
	return 1
}

policy_level() {
	# The repository policy level of $1 (empty: no origin), read the way ai-repository-policy.sh
	# reads it: the last matching policy or autonomous line, else default-policy, else branch.
	local repo="$1" level kind first rest pattern
	level="$(conf_value default-policy)"
	[ -n "$level" ] || level="branch"
	valid_level "$level" || level="readonly"
	[ -n "$repo" ] || { printf '%s' "$level"; return; }
	set -f
	while read -r kind first rest; do
		case "$kind" in
		policy) valid_level "$first" || continue; set -- $rest ;;
		autonomous) set -- $first $rest; first="autonomous" ;;
		*) continue ;;
		esac
		for pattern in "$@"; do
			case "$pattern" in '#'*) break ;; esac
			# shellcheck disable=SC2254
			case "$repo" in $(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')) level="$first" ;; esac
		done
	done <"$conf"
	set +f
	printf '%s' "$level"
}

refuse() {
	local reason="$1"
	if [ "$event" = "UserPromptSubmit" ]; then
		printf '{"decision":"block","reason":"%s"}\n' "$reason"
	else
		printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
	fi
	exit 0
}

profile="$(conf_value profile)"
[ -n "$profile" ] || exit 0

cwd="$(json_field cwd)"
[ -n "$cwd" ] || cwd="$PWD"
session="$(json_field session_id)"
[ -n "$session" ] || session="nosession"

cache_dir="${TMPDIR:-/tmp}/ai-ownership-guard"
cache_file="$cache_dir/$(printf '%s' "$session" | tr -c 'A-Za-z0-9_-' '_')"
key="$(printf '%s' "$cwd" | tr '\t\n' '  ')"
if [ -f "$cache_file" ]; then
	cached="$(awk -F '\t' -v k="$key" '$1 == k { v = $2 } END { print v }' "$cache_file")"
	case "$cached" in
	allow) exit 0 ;;
	refuse:*) refuse "${cached#refuse:}" ;;
	esac
fi

verdict="allow"
repo=""
if remote="$(git -C "$cwd" remote get-url origin 2>/dev/null)" && [ -n "$remote" ]; then
	repo="$(normalise_remote "$remote")"
	owner="$(owner_of "$repo")"
	if [ "$owner" != "*" ] && [ -n "$owner" ] && [ "$owner" != "$profile" ]; then
		verdict="refuse:AI profile guard: $repo belongs to the $owner AI profile, and this machine runs $profile. Work on it from a $owner machine, or classify it in the AI profile configuration and redeploy."
	fi
fi
if [ "$verdict" = "allow" ]; then
	level="$(policy_level "$repo")"
	if [ "$level" = "blocked" ]; then
		verdict="refuse:AI repository policy: ${repo:-this folder} is blocked for AI agents under the $profile AI profile. Change its level in the AI profile configuration and redeploy."
	else
		case "$(printf '%s' "${AI_UNATTENDED:-}" | tr '[:upper:]' '[:lower:]')" in
		1 | on | true | yes)
			case "$(conf_value unattended)" in
			on | yes | true | 1)
				case "$level" in
				draft | readonly) verdict="refuse:AI repository policy: unattended runs need a repository at the autonomous or branch level, and ${repo:-this folder} is at $level." ;;
				esac
				;;
			*) verdict="refuse:AI repository policy: unattended runs are off for the $profile AI profile." ;;
			esac
			;;
		esac
	fi
fi

mkdir -p "$cache_dir" 2>/dev/null && printf '%s\t%s\n' "$key" "$verdict" >>"$cache_file" 2>/dev/null

case "$verdict" in
refuse:*) refuse "${verdict#refuse:}" ;;
esac
exit 0
