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
#               repository; and the one force push the list below excepts
#   branch     commit, push a non-default branch, open and ready pull requests; no merge
#   draft       as branch, but pull requests are opened with --draft, never readied or merged
#   readonly    no Bash or PowerShell call and no Edit, Write, MultiEdit or NotebookEdit call
#   blocked     nothing: the ownership guard refuses the prompt and every tool call (this hook also
#               denies the tools it sees)
# Every level denies, with a reason the agent sees:
#   - force pushes (--force, --force-with-lease, -f, +refspec), which is what rewriting pushed
#     history needs. One exception, at autonomous only: exactly
#     `git push --force-with-lease --force-if-includes origin BRANCH` (the flags in either order), for
#     one local non-default BRANCH, run in the repository's own folder. --force-if-includes keeps the
#     lease meaningful after a fetch, which moves the remote-tracking ref the lease compares against
#   - a push to the default branch (an explicit master/main/default refspec, refs/heads/ or not; a
#     push naming no branch, or HEAD, while the checked-out branch is the default one; a push naming
#     no branch after a folder change, cd or git -C, whose branch the hook cannot see)
#   - a push of every branch (--all, --mirror, a glob refspec)
#   - deleting branches (git branch -d/-D, git push --delete, git push REMOTE :branch)
#   - remotes, upstreams and git configuration (git remote add/set-url/..., git branch -u,
#     --set-upstream-to, --track, git config writes, push, remote, branch or url settings given to
#     git -c, a branch created off a remote branch without --no-track)
#   - merges, ref updates and file commits through the GitHub API (a gh api call that writes to
#     pulls/N/merge, merges, merge-upstream, git/refs, contents/, branches/, rulesets or the default
#     branch, or a GraphQL merge or ref mutation, or a GraphQL query read from a file), and
#     repository and gh changes (gh repo sync/edit/rename/delete/archive, gh alias set, gh config set)
#   - a gh pr merge that names another repository than the folder's (-R, --repo, a pull request
#     URL, GH_REPO, a cd), whose own level would not be the one checked
# gh pr calls are matched with flags before the subcommand too (gh -R x pr merge, gh pr --repo x
# merge). Everything else passes untouched, so unattended runs never stall on a prompt. Any review a
# merge also needs (a judge score, say) is the agent's own check, not this hook's. The hook reads the
# command text, so it stops the ways an agent would reach a default branch by accident or habit, not
# a determined one (a script file it runs is not read): GitHub branch protection, where the plan has
# it, is the backstop.
#
# A command is matched as a whole, each of its lines ending like a `;`, with two kinds of text taken
# out first so prose never reads as git arguments: the body of a heredoc fed to `cat` or to a
# `-F -`/`--file -`/`--body-file -` option, and a quoted value with whitespace in it given to a
# message option (-m, --message, -t, --title, -b, --body, --notes, --subject; a PowerShell
# here-string included). A refspec or flag never holds whitespace, so neither can hide one.
#
# A missing or empty ai-profile.conf, or one without a `profile` line, allows everything (no
# profiles in use). Levels and repository names are cached per session and folder under
# ${TMPDIR:-/tmp}/ai-repository-policy/.

set -u

# This runs before every tool call and a process costs about 30 ms under Git for Windows, so the path
# most calls take starts one (the awk below): helpers set variables instead of printing into $(...).
nl=$'\n'
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

valid_level() {
	case "$1" in autonomous | branch | draft | readonly | blocked) return 0 ;; esac
	return 1
}

policy_level() {
	# Sets level for repository $1 (empty: no origin): the last matching policy or autonomous line,
	# else default-policy, else branch.
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

merges_without_checks() {
	local kind rest pattern
	[ -n "$repo" ] || return 1
	set -f
	while read -r kind rest; do
		[ "$kind" = "merge-without-checks" ] || continue
		for pattern in $rest; do
			case "$pattern" in '#'*) break ;; esac
			lower "$pattern"
			# shellcheck disable=SC2254
			case "$repo" in $lowered) set +f; return 0 ;; esac
		done
	done <"$conf"
	set +f
	return 1
}

conf_value profile
[ -n "$value" ] || exec cat >/dev/null

# The hook input, parsed by the one process most calls start: the tool, the session, the folder, and
# for a shell tool the command, its JSON string decoded and its prose taken out (see the header), each
# line ending like a `;`, so a match never spans two commands or two lines.
parsed="$(awk '
function field(key,    value) {
	# The string value of key, for values that never hold a quote (paths, ids, tool names); a Windows
	# path'"'"'s backslashes become forward slashes (C:/Users/...).
	if (!match(json, ".*\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")) return ""
	value = substr(json, 1, RLENGTH - 1)
	sub(/.*"/, "", value)
	gsub(/\\/, "/", value)
	gsub(/\/+/, "/", value)
	return value
}
function command_text(    value, at, next_char, out) {
	if (!match(json, /.*"command"[[:space:]]*:[[:space:]]*"(\\.|[^"\\])*"/)) return ""
	value = substr(json, 1, RLENGTH - 1)
	sub(/.*"command"[[:space:]]*:[[:space:]]*"/, "", value)
	out = ""
	while ((at = index(value, "\\")) > 0) {
		out = out substr(value, 1, at - 1)
		next_char = substr(value, at + 1, 1)
		if (next_char == "n") out = out "\n"
		else if (next_char == "t" || next_char == "r") out = out " "
		else if (next_char == "u") { out = out " "; at += 4 }
		else out = out next_char
		value = substr(value, at + 2)
	}
	return out value
}
function heredoc_word(line, start, word) {
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
function without_prose(command, count, lines, l, line, check, text, n, out, i, c, d, j, here, content, message) {
	sub(/\n+$/, "", command)
	count = split(command, lines, "\n")
	text = ""
	word = ""
	for (l = 1; l <= count; l++) {
		line = lines[l]
		if (word != "") {
			check = line
			sub(/^\t+/, "", check)
			if (check == word) { word = ""; text = text line "\n" }
			else text = text (prose ? "" : line) "\n"
			continue
		}
		text = text line "\n"
		word = heredoc_word(line)
		prose = (line ~ /(^|[^A-Za-z0-9_])cat[ \t]*<</ || line ~ /(-F|--file|--body-file)[ \t=]+-([ \t]|$)/)
	}
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
	return out
}
{ json = json (NR > 1 ? "\n" : "") $0 }
END {
	tool = field("tool_name")
	shell = (tool == "Bash" || tool == "PowerShell") ? without_prose(command_text()) : ""
	printf "%s\n%s\n%s\n%s.", tool, field("session_id"), field("cwd"), shell
}')"
tool=${parsed%%$nl*}
parsed=${parsed#*$nl}
session=${parsed%%$nl*}
parsed=${parsed#*$nl}
cwd=${parsed%%$nl*}
in=${parsed#*$nl}
in=${in%.}

case "$tool" in
Bash | PowerShell) kind="shell" ;;
Edit | Write | MultiEdit | NotebookEdit) kind="edit" ;;
*) exit 0 ;;
esac

[ -n "$cwd" ] || cwd="$PWD"
[ -n "$session" ] || session="nosession"

cache_dir="${TMPDIR:-/tmp}/ai-repository-policy"
cache_file="$cache_dir/${session//[!A-Za-z0-9_-]/_}"
tab=$'\t'
key="${cwd//$tab/ }"
level=""
repo=""
if [ -f "$cache_file" ]; then
	# A line is folder, level and repository (- for no origin).
	while IFS="$tab" read -r cached_key cached_level cached_repo; do
		if [ "$cached_key" = "$key" ] && [ -n "$cached_repo" ]; then
			level="$cached_level"
			repo="$cached_repo"
		fi
	done <"$cache_file"
	[ "$repo" != "-" ] || repo=""
fi
if ! valid_level "$level"; then
	repo=""
	if remote="$(git -C "$cwd" remote get-url origin 2>/dev/null)" && [ -n "$remote" ]; then
		normalise_remote "$remote"
		repo="$normalised"
	fi
	policy_level "$repo"
	[ -d "$cache_dir" ] || mkdir -p "$cache_dir" 2>/dev/null
	printf '%s\t%s\t%s\n' "$key" "$level" "${repo:--}" 2>/dev/null >>"$cache_file"
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

# Everything below is about git or gh.
case "$in" in
*[gG][iI][tT]* | *[gG][hH]*) ;;
*) exit 0 ;;
esac

has() {
	# Bash's own match, which starts no process, while the command is short; grep for a long one, whose
	# matcher does not slow down with length, and when bash could not run the match (status 2).
	local status=2
	if [ "${#in}" -le 4096 ]; then
		shopt -s nocasematch
		[[ $in =~ $1 ]]
		status=$?
		shopt -u nocasematch
	fi
	[ "$status" -eq 2 ] || return "$status"
	printf '%s' "$in" | grep -qiE "$1"
}

# A git command and its arguments up to the end of that command.
G='(^|[^a-z])git([" ]+[^" &|;]+)*[" ]+'
E='[^&|;]*'
# Flags, each with an optional value (gh -R x pr, gh pr --repo x merge).
F='([" ]+-[^" &|;]+([" ]+[^" &|;-][^" &|;]*)?)*'

changes_folder() {
	has '(^|[^a-z])(cd|pushd|chdir|set-location|push-location)([" ;]|$)'
}

default_branch() {
	local ref
	ref="$(git -C "$cwd" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)" && { printf '%s' "${ref##*/}"; return; }
	printf 'master'
}

force_push_refusal() {
	# What the force push $1 (a git push call, from just before git on) gets wrong, empty when it is
	# the one form an autonomous repository allows. A word that is no plain name fails the
	# local-branch check, so a variable, a refspec, a tag or a quote never passes.
	local name def
	if changes_folder || has '(^|[^a-z_])GIT_[a-z_]+[" ]*='; then
		printf 'it must run in the repository'"'"'s own folder, with no cd or GIT_ variable, so its own level applies'
		return
	fi
	set -f
	# shellcheck disable=SC2046
	set -- $(printf '%s' "$1" | sed -E 's/^[^gG]*//')
	set +f
	if [ "${1:-} ${2:-}" != "git push" ]; then
		printf 'it must start with exactly git push, with no -C, -c or other option before push'
		return
	fi
	case "${3:-} ${4:-}" in
	"--force-with-lease --force-if-includes" | "--force-if-includes --force-with-lease") ;;
	*)
		printf 'it needs both flags, --force-with-lease and --force-if-includes, with no value and no other flag'
		return
		;;
	esac
	if [ "$#" -ne 6 ] || [ "$5" != "origin" ]; then
		printf 'it must name the remote origin and one branch, and nothing else'
		return
	fi
	name="$(printf '%s' "$6" | tr '[:upper:]' '[:lower:]')"
	def="$(default_branch | tr '[:upper:]' '[:lower:]')"
	case "$name" in
	"$def" | master | main)
		printf 'it must not target the default branch'
		return
		;;
	esac
	if ! git -C "$cwd" show-ref --verify --quiet "refs/heads/$6"; then
		printf 'its target must be a local branch of this repository, by its plain name (not HEAD, a refspec, a tag or a variable)'
	fi
}

force_push="${G}push${E}(--force|[\" ]-f([\" ;]|$)|[\" ]\+[^\" ]+)"
if has "$force_push"; then
	[ "$level" = "autonomous" ] || deny "force pushes are not allowed; pushed history is never rewritten"
	while IFS= read -r call; do
		refusal="$(force_push_refusal "$call")"
		[ -z "$refusal" ] || deny "force pushes are not allowed here except git push --force-with-lease --force-if-includes origin BRANCH; $refusal"
	done <<<"$(printf '%s' "$in" | grep -oiE "${force_push}${E}")"
fi
if has "${G}push${E}[\" ](--all|--branches|--mirror)([\" =;]|$)" || has "${G}push${E}[\" ][^\" ;]*\*"; then
	deny "pushing every branch (--all, --mirror or a glob refspec) is not allowed; push one named branch"
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
if has "(^|[^a-z])git${E}[\" ](-c|--config-env)[\" =]*(push|remote|branch|url)\."; then
	deny "changing git configuration is not allowed, git -c push, remote, branch and url settings included"
fi

gh_api_writes() {
	# The gh api calls of the command that write, one per line: a method other than GET, or a field
	# or --input (which make gh send a POST) without -X GET.
	printf '%s' "$in" | grep -oiE "(^|[^a-z])gh${F}[\" ]+api[\" ][^&|;]*" |
		grep -iE '[" ](-X|--method)[" =]*(post|put|patch|delete)|[" ](-f|--field|--raw-field|--input)([" =]|$)' |
		grep -viE '[" ](-X|--method)[" =]*get([" ]|$)'
}

if has "(^|[^a-z])gh${F}[\" ]+api[\" ]" && gh_api_writes | grep -qiE '/pulls/[^/" ]+/merge|/merges([" /?]|$)|/merge-upstream|/git/refs|/contents/|/branches/|/rulesets|default_branch|mergePullRequest|mergeBranch|updateRefs?[^a-z]|createRef|deleteRef|createCommitOnBranch|PullRequestAutoMerge|updateRepository|query=@|graphql.*--input|--input.*graphql'; then
	deny "merges, ref updates and file commits through the GitHub API (gh api) are not allowed; push a feature branch and merge with gh pr merge"
fi
if has "(^|[^a-z])gh${F}[\" ]+repo${F}[\" ]+(sync|edit|rename|delete|archive|unarchive)([\" ;]|$)"; then
	deny "changing a GitHub repository (gh repo sync, edit, rename, delete, archive) is not allowed; the owner does"
fi
if has "(^|[^a-z])gh${F}[\" ]+(alias[\" ]+(set|import|delete)|config[\" ]+set)([\" ;]|$)"; then
	deny "changing gh configuration (gh alias, gh config set) is not allowed"
fi

if has "${G}push([\" ;]|$)"; then
	def="$(default_branch)"
	if has "${G}push${E}[\" :](refs/heads/)?(${def}|master|main|HEAD:(refs/heads/)?(${def}|master|main))([\" ;]|$)"; then
		deny "pushing to the default branch ($def) is not allowed; it only changes through a merged pull request"
	fi
	# A push naming no branch, or HEAD, goes to the branch checked out where it runs.
	if ! has "${G}push${E}[\" ][^\" -][^\" ]*[\" ]+[^\" -]" || has "${G}push${E}[\" ][^\" -][^\" ]*[\" ]+(HEAD|@)([\" ;]|$)"; then
		if changes_folder || has "(^|[^a-z])git[\" ]${E}(-C|--git-dir|--work-tree)([\" =]|$)${E}[\" ]push([\" ;]|$)"; then
			deny "a push from another folder (cd, git -C) must name its branch (git push origin <branch>); the hook cannot see the branch checked out there"
		fi
		current="$(git -C "$cwd" branch --show-current 2>/dev/null)"
		if [ -n "$current" ] && { [ "$current" = "$def" ] || [ "$current" = "master" ] || [ "$current" = "main" ]; }; then
			deny "the checked-out branch is the default branch ($current); push a feature branch instead"
		fi
	fi
fi

# gh with its flags, then pr with its flags, then the subcommand.
GH="(^|[^a-z])gh${F}[\" ]+pr${F}[\" ]+"

gh_pr_call() {
	# The words of the first gh pr $1 call of the command, from gh on, quotes removed (an empty
	# quoted value kept as _, so it still takes its flag's place).
	printf '%s' "$in" | grep -oiE "${GH}$1([\" ][^&|;]*)?" | head -n 1 | sed -E -e 's/^[^gG]*//' -e "s/\"\"|''/_/g" | tr -d "\"'"
}

pr_target() {
	# Sets selector (the pull request the gh pr $1 call names, empty for the current branch's) and
	# target (the repository it names by -R, --repo or a pull request URL, normalised; empty: none).
	local word stage=0 value=""
	selector="" target=""
	set -f
	for word in $(gh_pr_call "$1"); do
		if [ -n "$value" ]; then
			[ "$value" = "repo" ] && target="$word"
			value=""
			continue
		fi
		case "$word" in
		-R | --repo) value="repo" ;;
		--repo=*) target="${word#--repo=}" ;;
		-R?*) target="${word#-R}" ;;
		-A | --author-email | -b | --body | -F | --body-file | --match-head-commit | -t | --subject) value="skip" ;;
		-*) ;;
		*)
			case "$stage" in
			0) [ "$word" = "pr" ] && stage=1 ;;
			1) stage=2 ;;
			*) [ -n "$selector" ] || selector="$word" ;;
			esac
			;;
		esac
	done
	set +f
	case "$selector" in */pull/*) target="${selector%%/pull/*}" ;; esac
	[ -n "$target" ] || return 0
	normalise_remote "$target"
	target="$normalised"
	case "$target" in */*/*) ;; *) target="github.com/$target" ;; esac
}

checks_state() {
	# green when every check passed, none when no check is reported, red otherwise. gh pr checks
	# exits 0 only when every check passed (8 while pending, 1 on a failure or with no check).
	local output
	command -v gh >/dev/null 2>&1 || { printf 'red'; return; }
	pr_target merge
	# shellcheck disable=SC2086
	if output="$(cd "$cwd" 2>/dev/null && gh pr checks $selector 2>&1)"; then
		printf 'green'
	else
		case "$output" in *"no checks reported"*) printf 'none' ;; *) printf 'red' ;; esac
	fi
}

if has "${GH}merge([\" ;]|$)"; then
	pr_target merge
	if { [ -n "$target" ] && [ "$target" != "$repo" ]; } || has 'GH_REPO' || changes_folder; then
		deny "gh pr merge acts on another repository (${target:-GH_REPO or a cd}); run it in that repository's own folder, with no -R, --repo, URL, GH_REPO or cd pointing elsewhere, so its own level applies"
	fi
fi

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
