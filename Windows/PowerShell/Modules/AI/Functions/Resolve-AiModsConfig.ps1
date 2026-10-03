function Resolve-AiModsConfig {
	<#
	.SYNOPSIS
		Resolves the AiMods configuration section into expanded, ready-to-use paths.

	.DESCRIPTION
		Reads `AiMods` from the merged configuration and returns one hashtable the AI mods
		functions share, so Deploy-AiMods and Update-AiMods agree on where mods live, where they
		are linked and which settings file carries the plugin list:

		  Root             The mods root on disk (default {RepoRoot}\AI\Mods). One subfolder per
		                   source (a vendored upstream, or `own` for hand-written mods), each
		                   holding <mod>\.claude-plugin\plugin.json folders.
		  Harnesses        Windows directories Claude Code mods are linked into, with placeholders
		                   expanded (default ~\.claude\mods).
		  WSLHarnesses     The same directories inside WSL, derived from Harnesses by mapping the
		                   {User} profile onto /home/<DefaultWSLUsername>. Empty when
		                   DefaultWSLUsername is not configured or a harness path is not under the
		                   user profile.
		  Sources          The configured upstream sources (name -> Repository, Ref, Folders,
		                   Exclude, SkipPaths), untouched.
		  SettingsPath     The Windows Claude Code user settings file (~\.claude\settings.json)
		                   whose env.CLAUDE_CODE_PLUGIN_DIRS names the linked mods. Derived, not a
		                   configuration key.
		  WSLSettingsPath  The same file inside WSL (/home/<DefaultWSLUsername>/.claude/settings.json),
		                   empty when DefaultWSLUsername is not configured. Derived, not a
		                   configuration key.

		Only the {User}, {RepoRoot} and {AppData} placeholders are expanded here - the section
		is machine-type independent, so it deliberately does not go through Expand-ConfigPaths.
		Every key falls back to the built-in default when the section or key is missing, so the
		empty base configuration resolves to a usable, empty setup.

	.PARAMETER Configuration
		The configuration hashtable to read. Defaults to $global:Configuration.

	.PARAMETER RepoRoot
		Repository root used for {RepoRoot}. Defaults to Get-RepositoryPath.

	.EXAMPLE
		(Resolve-AiModsConfig).Root
		Returns the expanded mods root, e.g. C:\Users\You\Development\WinuX\AI\Mods.

	.EXAMPLE
		(Resolve-AiModsConfig).WSLSettingsPath
		Returns e.g. /home/you/.claude/settings.json.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
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
	$aiMods = Get-ConfigSetting -Path 'AiMods' -Configuration $Configuration
	if ($aiMods -is [hashtable]) {
		$section = $aiMods
	}

	$root = if ($section.Root) { [string]$section.Root } else { "{RepoRoot}\AI\Mods" }
	$harnesses = if ($section.Harnesses) { @($section.Harnesses) } else { @("{User}\.claude\mods") }
	$sources = if ($section.Sources -is [hashtable]) { $section.Sources } else { @{} }

	$userProfile = $env:USERPROFILE
	$expand = {
		param($value)
		([string]$value).Replace('{RepoRoot}', $RepoRoot).Replace('{User}', $userProfile).Replace('{AppData}', $env:APPDATA)
	}

	$expandedHarnesses = @($harnesses | ForEach-Object { & $expand $_ })

	$wslHarnesses = @()
	$wslSettingsPath = ""
	$wslUser = [string](Get-ConfigSetting -Path 'DefaultWSLUsername' -Default '' -Configuration $Configuration)
	if ($wslUser) {
		foreach ($harness in $harnesses) {
			$template = [string]$harness
			if ($template.StartsWith('{User}\')) {
				$relative = $template.Substring('{User}\'.Length).Replace('\', '/')
				$wslHarnesses += "/home/$wslUser/$relative"
			}
		}
		$wslSettingsPath = "/home/$wslUser/.claude/settings.json"
	}

	return @{
		Root            = & $expand $root
		Harnesses       = $expandedHarnesses
		WSLHarnesses    = $wslHarnesses
		Sources         = $sources
		SettingsPath    = Join-Path $userProfile ".claude\settings.json"
		WSLSettingsPath = $wslSettingsPath
	}
}
