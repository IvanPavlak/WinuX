#!/usr/bin/env bash
# ai-repository-policy.sh - Claude Code hook that applies the trust level of the repository a session
# works in.
#
# Deployed by Deploy-AiArtifacts next to the managed settings copy, together with ai-profile.conf,
# and wired into the managed settings (with an AI profile active) as:
#   PreToolUse (matcher *)  bash "<dir>/ai-repository-policy.sh"
# One file for both halves: WinuX and Foundation ship it at this path as a mirror file (a `mirror`
# line in Windows/PowerShell/Upstream.conf and Unix/config/upstream.conf), so it stays identical.
#
# The repository is the one holding the hook input's `cwd`, named by its `origin` remote normalised
# to host/owner/name (lowercase, no scheme, no user, no .git). Its level comes from ai-profile.conf:
#   policy LEVEL PATTERN...       the repositories at LEVEL (shell globs, no braces)
#   autonomous PATTERN...         a synonym of `policy autonomous PATTERN...`
#   default-policy LEVEL          a repository no line matches, or a folder without an origin
#                                 (default: branch; a level that is not one below: readonly)
#   merge-without-checks PATTERN...  autonomous repositories that may merge a pull request with no
#                                 CI check reported
# The last matching line wins. The levels, a closed set from most to least trust:
#   autonomous  everything branch allows, plus `gh pr merge` when every CI check of the pull request
#               passed (`gh pr checks`); with no check reported only in a merge-without-checks
#               repository
#   branch      commit, push a non-default branch, open and ready pull requests; no merge
#   draft       as branch, but pull requests are opened with --draft, never readied or merged
#   readonly    no Bash or PowerShell call and no Edit, Write, MultiEdit or NotebookEdit call
#   blocked     nothing: the ownership guard refuses the prompt and every tool call (this hook also
#               denies the tools it sees)
# Every level denies, with a reason the agent sees:
#   - force pushes (--force, --force-with-lease, -f, +refspec), which is what rewriting pushed
#     history needs
#   - a push to the default branch (an explicit master/main/default refspec, or a push while the
#     checked-out branch is the default one)
#   - deleting branches (git branch -d/-D, git push --delete, git push REMOTE :branch)
#   - remotes, upstreams and git configuration (git remote add/set-url/..., git branch -u,
#     --set-upstream-to, --track, git config writes, a branch created off a remote branch without
#     --no-track)
# Everything else passes untouched, so unattended runs never stall on a prompt. Any review a merge
# also needs (a judge score, say) is the agent's own check, not this hook's.
#
# A command is matched as a whole, each of its lines ending like a `;`, with two kinds of text taken
# out first so prose never reads as git arguments: the body of a heredoc fed to `cat` or to a
# `-F -`/`--file -`/`--body-file -` option, and a quoted value with whitespace in it given to a
# message option (-m, --message, -t, --title, -b, --body, --notes, --subject; a PowerShell
# here-string included). A refspec or flag never holds whitespace, so neither can hide one.
#
# A missing or empty ai-profile.conf, or one without a `profile` line, allows everything (no
# profiles in use). Levels are cached per session and folder under ${TMPDIR:-/tmp}/ai-repository-policy/.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
conf="${AI_PROFILE_CONF:-$here/ai-profile.conf}"
input="$(cat)"

[ -s "$conf" ] || exit 0

json_field() {
	# The first string value of key $1 in the hook input, for values that never hold a quote (paths,
	# ids, tool names); a Windows path's backslashes become forward slashes (C:/Users/...).
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

valid_level() {
	case "$1" in autonomous | branch | draft | readonly | blocked) return 0 ;; esac
	return 1
}

policy_level() {
	# The level of repository $1 (empty: no origin): the last matching policy or autonomous line,
	# else default-policy, else branch.
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

merges_without_checks() {
	local kind rest pattern
	[ -n "$repo" ] || return 1
	set -f
	while read -r kind rest; do
		[ "$kind" = "merge-without-checks" ] || continue
		for pattern in $rest; do
			case "$pattern" in '#'*) break ;; esac
			# shellcheck disable=SC2254
			case "$repo" in $(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')) set +f; return 0 ;; esac
		done
	done <"$conf"
	set +f
	return 1
}

[ -n "$(conf_value profile)" ] || exit 0

tool="$(json_field tool_name)"
case "$tool" in
Bash | PowerShell) kind="shell" ;;
Edit | Write | MultiEdit | NotebookEdit) kind="edit" ;;
*) exit 0 ;;
esac

cwd="$(json_field cwd)"
[ -n "$cwd" ] || cwd="$PWD"
session="$(json_field session_id)"
[ -n "$session" ] || session="nosession"

repo=""
if remote="$(git -C "$cwd" remote get-url origin 2>/dev/null)" && [ -n "$remote" ]; then
	repo="$(normalise_remote "$remote")"
fi

cache_dir="${TMPDIR:-/tmp}/ai-repository-policy"
cache_file="$cache_dir/$(printf '%s' "$session" | tr -c 'A-Za-z0-9_-' '_')"
key="$(printf '%s' "$cwd" | tr '\t\n' '  ')"
level=""
if [ -f "$cache_file" ]; then
	level="$(awk -F '\t' -v k="$key" '$1 == k { v = $2 } END { print v }' "$cache_file")"
fi
if ! valid_level "$level"; then
	level="$(policy_level "$repo")"
	mkdir -p "$cache_dir" 2>/dev/null && printf '%s\t%s\n' "$key" "$level" >>"$cache_file" 2>/dev/null
fi

deny() {
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"AI repository policy (%s, %s): %s"}}\n' "${repo:-no origin}" "$level" "$1"
	exit 0
}

case "$level" in
blocked) deny "this repository is blocked for AI agents" ;;
readonly)
	if [ "$kind" = "edit" ]; then deny "the repository is read-only for AI agents; files are not edited"; fi
	deny "the repository is read-only for AI agents; Bash and PowerShell calls are not allowed"
	;;
esac
[ "$kind" = "shell" ] || exit 0

# The command: the JSON string decoded, prose taken out (see the header), each line ending like a
# `;`, so a match never spans two commands or two lines.
raw="$(printf '%s' "$input" | sed -n -E 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' | head -n 1)"
decoded="$(printf '%s' "$raw" | awk '
{
	s = $0; out = ""; n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c == "\\" && i < n) {
			d = substr(s, ++i, 1)
			if (d == "n") out = out "\n"
			else if (d == "t" || d == "r") out = out " "
			else if (d == "u") { out = out " "; i += 4 }
			else out = out d
		}
		else out = out c
	}
	printf "%s", out
}')"
in="$(printf '%s\n' "$decoded" | awk '
function heredoc_word(line,    start, word) {
	# The terminator of a heredoc opened on line (not a <<< here-string), empty when none.
	start = 1
	while (match(substr(line, start), /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
		at = start + RSTART - 1
		if (at == 1 || substr(line, at - 1, 1) != "<") {
			word = substr(line, at, RLENGTH)
			sub(/^<<-?[ \t]*["\047]?/, "", word)
			return word
		}
		start = at + RLENGTH
	}
	return ""
}
{
	if (word != "") {
		check = $0
		sub(/^\t+/, "", check)
		if (check == word) { word = ""; text = text $0 "\n" }
		else text = text (prose ? "" : $0) "\n"
		next
	}
	text = text $0 "\n"
	word = heredoc_word($0)
	prose = ($0 ~ /(^|[^A-Za-z0-9_])cat[ \t]*<</ || $0 ~ /(-F|--file|--body-file)[ \t=]+-([ \t]|$)/)
}
END {
	# Quoted values with whitespace given to a message option become empty quotes.
	n = length(text); out = ""; i = 1
	while (i <= n) {
		c = substr(text, i, 1)
		if (c != "\"" && c != "\047") { out = out c; i++; continue }
		here = (substr(out, length(out), 1) == "@" && substr(text, i + 1, 1) == "\n")
		j = i + 1
		while (j <= n) {
			d = substr(text, j, 1)
			if (here) {
				if (d == "\n" && substr(text, j + 1, 2) == c "@") { j++; break }
			}
			else if (c == "\"" && (d == "\\" || d == "`")) j++
			else if (d == c) {
				if (substr(text, j + 1, 1) == c) j++
				else break
			}
			j++
		}
		content = substr(text, i + 1, j - i - 1)
		message = (out ~ /(^|[ \t])(-m|--message|-t|--title|-b|--body|--notes|--subject)[ \t=]*@?$/)
		if (message && content ~ /[ \t\n]/) out = out c c
		else out = out c content c
		i = j + 1
	}
	gsub(/\n/, ";", out)
	gsub(/\t/, " ", out)
	printf "%s", out
}')"

has() { printf '%s' "$in" | grep -qiE "$1"; }

# A git command and its arguments up to the end of that command.
G='(^|[^a-z])git([" ]+[^" &|;]+)*[" ]+'
E='[^&|;]*'

if has "${G}push${E}(--force|--force-with-lease|[\" ]-f([\" ;]|$)|[\" ]\+[^\" ]+)"; then
	deny "force pushes are not allowed; pushed history is never rewritten"
fi
if has "${G}push${E}(--delete|[\" ]-d([\" ;]|$)|[\" ]:[^\" ]+)" || has "${G}branch${E}[\" ](-d|-D|--delete)([\" ;]|$)"; then
	deny "deleting branches is not allowed"
fi
if has "${G}remote[\" ]+(add|set-url|rename|remove|rm|set-branches|set-head)([\" ;]|$)"; then
	deny "changing remotes is not allowed"
fi
if has "${G}branch${E}[\" ](-u|--set-upstream-to|--unset-upstream)([\" =;]|$)" || has "${G}(switch|checkout|branch)${E}[\" ](--track|-t)([\" =;]|$)"; then
	deny "changing upstream tracking is not allowed"
fi
if has "${G}(switch[\" ]+(-c|-C|--create|--force-create)|checkout[\" ]+(-b|-B))[\" ]+[^\" &|;-][^\" &|;]*[\" ]+[^\" &|;-][^\" &|;]*/" && ! has 'no-track'; then
	deny "a branch cut from a remote branch must use --no-track"
fi
if has "${G}config([\" ;]|$)" && ! has "${G}config${E}(--get|--list|[\" ]-l([\" ;]|$)|[\" ](get|list)[\" ;]|--show)"; then
	deny "changing git configuration is not allowed"
fi

default_branch() {
	local ref
	ref="$(git -C "$cwd" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)" && { printf '%s' "${ref##*/}"; return; }
	printf 'master'
}

if has "${G}push([\" ;]|$)"; then
	def="$(default_branch)"
	if has "${G}push${E}[\" :](${def}|master|main|HEAD:(${def}|master|main))([\" ;]|$)"; then
		deny "pushing to the default branch ($def) is not allowed; it only changes through a merged pull request"
	fi
	current="$(git -C "$cwd" branch --show-current 2>/dev/null)"
	if [ -n "$current" ] && { [ "$current" = "$def" ] || [ "$current" = "master" ] || [ "$current" = "main" ]; } &&
		! has "${G}push${E}[\" ][^\" -][^\" ]*[\" ]+[^\" -]"; then
		deny "the checked-out branch is the default branch ($current); push a feature branch instead"
	fi
fi

pr_selector() {
	# The pull request a `gh pr merge` names: its first argument that is not a flag (a number, URL
	# or branch), empty for the current branch's pull request.
	printf '%s' "$in" | sed -n -E 's/.*(^|[^a-z])gh[" ]+pr[" ]+merge(([" ]+-[^" &|;]+)*)[" ]+([^" &|;{}-][^" &|;{}]*).*/\4/p' | head -n 1
}

checks_state() {
	# green when every check passed, none when no check is reported, red otherwise. gh pr checks
	# exits 0 only when every check passed (8 while pending, 1 on a failure or with no check).
	local selector output
	command -v gh >/dev/null 2>&1 || { printf 'red'; return; }
	selector="$(pr_selector)"
	# shellcheck disable=SC2086
	if output="$(cd "$cwd" 2>/dev/null && gh pr checks $selector 2>&1)"; then
		printf 'green'
	else
		case "$output" in *"no checks reported"*) printf 'none' ;; *) printf 'red' ;; esac
	fi
}

GH='(^|[^a-z])gh[" ]+pr[" ]+'
case "$level" in
autonomous)
	if has "${GH}merge([\" ;]|$)"; then
		state="$(checks_state)"
		if [ "$state" = "none" ] && merges_without_checks; then
			exit 0
		fi
		if [ "$state" != "green" ]; then
			deny "gh pr merge needs every CI check of the pull request to have passed (gh pr checks); none reported counts as not green unless the repository is listed by merge-without-checks"
		fi
	fi
	;;
branch)
	if has "${GH}merge([\" ;]|$)"; then
		deny "gh pr merge is allowed only in an autonomous repository; the owner merges here"
	fi
	;;
*)
	if has "${GH}(merge|ready)([\" ;]|$)"; then
		deny "agents never merge or mark pull requests ready here; the owner does"
	fi
	if has "${GH}create([\" ;]|$)" && ! has "${GH}create${E}--draft"; then
		deny "pull requests are opened as drafts here (gh pr create --draft)"
	fi
	;;
esac
exit 0
