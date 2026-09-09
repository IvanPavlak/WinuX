function Resolve-AiSkillsConfig {
	<#
	.SYNOPSIS
		Resolves the AiSkills configuration section into expanded, ready-to-use paths.

	.DESCRIPTION
		Reads `AiSkills` from the merged configuration and returns one hashtable the AI skills
		functions share, so Deploy-AiSkills and Update-AiSkills agree on where skills live and
		where they are linked:

		  Root          The skills root on disk (default {RepoRoot}\AI\Skills). One subfolder
		                per source (a vendored upstream, or `own` for hand-written skills), each
		                holding flat <skill>\SKILL.md folders.
		  Harnesses     Windows directories that AI harnesses scan for user-level skills, with
		                placeholders expanded (default ~\.claude\skills for Claude Code and
		                ~\.agents\skills for Codex CLI and Gemini CLI).
		  WSLHarnesses  The same directories inside WSL, derived from Harnesses by mapping the
		                {User} profile onto /home/<DefaultWSLUsername>. Empty when
		                DefaultWSLUsername is not configured or a harness path is not under the
		                user profile.
		  Sources       The configured upstream sources (name -> Repository, Ref, Folders,
		                Exclude), untouched.

		Only the {User}, {RepoRoot} and {AppData} placeholders are expanded here - the section
		is machine-type independent, so it deliberately does not go through Expand-ConfigPaths.
		Every key falls back to the built-in default when the section or key is missing, so the
		empty base configuration resolves to a usable, empty setup.

	.PARAMETER Configuration
		The configuration hashtable to read. Defaults to $global:Configuration.

	.PARAMETER RepoRoot
		Repository root used for {RepoRoot}. Defaults to Get-RepositoryPath.

	.EXAMPLE
		(Resolve-AiSkillsConfig).Root
		Returns the expanded skills root, e.g. C:\Users\You\Development\WinuX\AI\Skills.

	.EXAMPLE
		(Resolve-AiSkillsConfig).WSLHarnesses
		Returns e.g. /home/you/.claude/skills and /home/you/.agents/skills.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[hashtable]$Configuration = $global:Configuration,

		[Parameter()]
		[string]$RepoRoot
	)

	if (-not $RepoRoot) {
		$RepoRoot = (Get-RepositoryPath).Repo
	}

	$section = @{}
	if ($Configuration -and $Configuration.AiSkills -is [hashtable]) {
		$section = $Configuration.AiSkills
	}

	$root = if ($section.Root) { [string]$section.Root } else { "{RepoRoot}\AI\Skills" }
	$harnesses = if ($section.Harnesses) { @($section.Harnesses) } else { @("{User}\.claude\skills", "{User}\.agents\skills") }
	$sources = if ($section.Sources -is [hashtable]) { $section.Sources } else { @{} }

	$userProfile = $env:USERPROFILE
	$expand = {
		param($value)
		([string]$value).Replace('{RepoRoot}', $RepoRoot).Replace('{User}', $userProfile).Replace('{AppData}', $env:APPDATA)
	}

	$expandedHarnesses = @($harnesses | ForEach-Object { & $expand $_ })

	$wslHarnesses = @()
	$wslUser = if ($Configuration) { [string]$Configuration.DefaultWSLUsername } else { "" }
	if ($wslUser) {
		foreach ($harness in $harnesses) {
			$template = [string]$harness
			if ($template.StartsWith('{User}\')) {
				$relative = $template.Substring('{User}\'.Length).Replace('\', '/')
				$wslHarnesses += "/home/$wslUser/$relative"
			}
		}
	}

	return @{
		Root         = & $expand $root
		Harnesses    = $expandedHarnesses
		WSLHarnesses = $wslHarnesses
		Sources      = $sources
	}
}
