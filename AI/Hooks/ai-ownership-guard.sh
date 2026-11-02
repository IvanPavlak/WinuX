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

# This runs before every tool call and a process costs about 30 ms under Git for Windows, so a cached
# call starts one (the awk below): helpers set variables instead of printing into $(...).
nl=$'\n'
tab=$'\t'
event="${1:-PreToolUse}"
here="${BASH_SOURCE[0]%/*}"
[ "$here" != "${BASH_SOURCE[0]}" ] || here="."
conf="${AI_PROFILE_CONF:-$here/ai-profile.conf}"

# The input is read even when it is ignored, so the caller's write to this hook never fails.
[ -s "$conf" ] || exec cat >/dev/null

lower() {
	# Sets lowered to $1 with A-Z lowercased (bash 3.2 has no ${x,,}).
	local i upper=ABCDEFGHIJKLMNOPQRSTUVWXYZ small=abcdefghijklmnopqrstuvwxyz
	lowered="$1"
	for ((i = 0; i < 26; i++)); do
		lowered="${lowered//${upper:i:1}/${small:i:1}}"
	done
}

normalise_remote() {
	# Sets normalised from https://user@github.com/Owner/Name.git, git@github.com:Owner/Name.git or
	# ssh://git@host/Owner/Name.
	local scheme='^[a-z+]+://' user='^[^@/]+@' scp='^([^/:]+):([^0-9].*)$' suffix='\.git/?$'
	lower "$1"
	normalised="$lowered"
	if [[ $normalised =~ $scheme ]]; then normalised="${normalised#*://}"; fi
	if [[ $normalised =~ $user ]]; then normalised="${normalised#*@}"; fi
	if [[ $normalised =~ $scp ]]; then normalised="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; fi
	if [[ $normalised =~ $suffix ]]; then
		normalised="${normalised%/}"
		normalised="${normalised%.git}"
	fi
	while [ "${normalised%/}" != "$normalised" ]; do normalised="${normalised%/}"; done
}

conf_value() {
	# Sets value to the value of the last $1 line of ai-profile.conf (a line starting with $1).
	local line
	value=""
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in "$1"[[:space:]]*) ;; *) continue ;; esac
		line="${line#"$1"}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%%[[:space:]#]*}"
		[ -z "$line" ] || value="$line"
	done <"$conf"
}

owner_of() {
	# Sets owner for repository $1: * for a shared one, else the first owns line, else default-owner.
	local remote="$1" kind a b
	while read -r kind a b; do
		case "$kind" in
		shared)
			lower "$a"
			# shellcheck disable=SC2254
			case "$remote" in $lowered) owner='*'; return ;; esac
			;;
		esac
	done <"$conf"
	while read -r kind a b; do
		case "$kind" in
		owns)
			lower "$b"
			# shellcheck disable=SC2254
			case "$remote" in $lowered) owner="$a"; return ;; esac
			;;
		esac
	done <"$conf"
	conf_value default-owner
	owner="$value"
}

valid_level() {
	case "$1" in autonomous | branch | draft | readonly | blocked) return 0 ;; esac
	return 1
}

policy_level() {
	# Sets level for repository $1 (empty: no origin), read the way ai-repository-policy.sh reads it:
	# the last matching policy or autonomous line, else default-policy, else branch.
	local repo="$1" kind first rest pattern
	conf_value default-policy
	level="$value"
	[ -n "$level" ] || level="branch"
	valid_level "$level" || level="readonly"
	[ -n "$repo" ] || return 0
	set -f
	while read -r kind first rest; do
		case "$kind" in
		policy) valid_level "$first" || continue; set -- $rest ;;
		autonomous) set -- $first $rest; first="autonomous" ;;
		*) continue ;;
		esac
		for pattern in "$@"; do
			case "$pattern" in '#'*) break ;; esac
			lower "$pattern"
			# shellcheck disable=SC2254
			case "$repo" in $lowered) level="$first" ;; esac
		done
	done <"$conf"
	set +f
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

conf_value profile
profile="$value"
[ -n "$profile" ] || exec cat >/dev/null

# The session and the folder from the hook input, by the one process a cached call starts. Each is the
# first line holding its key. Paths and session ids never hold a quote, so a value runs to the next
# one; a Windows path's backslashes become forward slashes, which git and bash take (C:/Users/...).
parsed="$(awk '
function take(key,    value) {
	if (key in found) return
	if (!match($0, ".*\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")) return
	value = substr($0, 1, RLENGTH - 1)
	sub(/.*"/, "", value)
	gsub(/\\/, "/", value)
	gsub(/\/+/, "/", value)
	found[key] = value
}
{ take("session_id"); take("cwd") }
END { printf "%s\n%s.", found["session_id"], found["cwd"] }')"
session=${parsed%%$nl*}
cwd=${parsed#*$nl}
cwd=${cwd%.}
[ -n "$cwd" ] || cwd="$PWD"
[ -n "$session" ] || session="nosession"

cache_dir="${TMPDIR:-/tmp}/ai-ownership-guard"
cache_file="$cache_dir/${session//[!A-Za-z0-9_-]/_}"
key="${cwd//$tab/ }"
if [ -f "$cache_file" ]; then
	cached=""
	while IFS="$tab" read -r cached_key cached_verdict; do
		[ "$cached_key" != "$key" ] || cached="$cached_verdict"
	done <"$cache_file"
	case "$cached" in
	allow) exit 0 ;;
	refuse:*) refuse "${cached#refuse:}" ;;
	esac
fi

verdict="allow"
repo=""
if remote="$(git -C "$cwd" remote get-url origin 2>/dev/null)" && [ -n "$remote" ]; then
	normalise_remote "$remote"
	repo="$normalised"
	owner_of "$repo"
	if [ "$owner" != "*" ] && [ -n "$owner" ] && [ "$owner" != "$profile" ]; then
		verdict="refuse:AI profile guard: $repo belongs to the $owner AI profile, and this machine runs $profile. Work on it from a $owner machine, or classify it in the AI profile configuration and redeploy."
	fi
fi
if [ "$verdict" = "allow" ]; then
	policy_level "$repo"
	if [ "$level" = "blocked" ]; then
		verdict="refuse:AI repository policy: ${repo:-this folder} is blocked for AI agents under the $profile AI profile. Change its level in the AI profile configuration and redeploy."
	else
		lower "${AI_UNATTENDED:-}"
		case "$lowered" in
		1 | on | true | yes)
			conf_value unattended
			case "$value" in
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

[ -d "$cache_dir" ] || mkdir -p "$cache_dir" 2>/dev/null
printf '%s\t%s\n' "$key" "$verdict" 2>/dev/null >>"$cache_file"

case "$verdict" in
refuse:*) refuse "${verdict#refuse:}" ;;
esac
exit 0
