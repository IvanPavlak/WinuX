function ConvertTo-AiManagedSettings {
	<#
	.SYNOPSIS
		Renders a rules item's managed-settings.json for one managed-settings folder, and the ai-profile.conf the ownership guard reads next to it.

	.DESCRIPTION
		Claude Code's managed settings are deployed as an administrator-owned copy, never a
		link, so the copy can carry values the repository file does not: this function computes
		that copy. It reads nothing and writes nothing.

		Rendering the settings:

		  - Every {ManagedDir} token of the template becomes ManagedDir, with forward slashes
		    (C:/Program Files/ClaudeCode, /etc/claude-code), so a hook can name a script
		    deployed next to the settings.
		  - With an AI profile active, forceLoginOrgUUID is set from the profile's Plan: one
		    UUID as a string, several as an array. A profile without a Plan leaves the
		    template's value and reports it; a profile whose Plan is configured but unusable
		    (an OrgUuid that is not a UUID) renders nothing, so the deployed copy keeps its pin.
		  - With an AI profile active, the ownership guard is appended to hooks.UserPromptSubmit
		    and to hooks.PreToolUse (matcher *) as
		    bash "<ManagedDir>/ai-ownership-guard.sh" <Event>.

		The result is two-space indented JSON with LF line endings and a final newline, so the
		same input always renders the same text and a deploy can compare it with the deployed
		copy.

		ai-profile.conf (only with a profile active), one directive per line:

		  profile <name>                 the profile this machine runs
		  default-owner <name>           the owner of a repository no pattern matches
		  unattended on|off
		  plan <name> <org-uuid>         one line per Plan entry
		  shared <pattern>               one line per AiProfiles.Shared pattern
		  owns <profile> <pattern>       one line per pattern, every profile in name order
		  autonomous <pattern>           the active profile's autonomous repositories only

		Returns @{ Settings; ProfileConf; Problems }: ProfileConf is empty with profiles off,
		Problems lists what could not be rendered (an unparseable template and an unusable
		Plan are the two that leave Settings empty).

	.PARAMETER Template
		The text of the rules item's managed-settings.json.

	.PARAMETER ManagedDir
		The folder the managed settings are deployed to.

	.PARAMETER AiProfile
		A resolved AI profile (Resolve-AiProfile). Without one, or with profiles off, only the
		token is replaced.

	.EXAMPLE
		ConvertTo-AiManagedSettings -Template (Get-Content -Raw "C:\Repo\AI\Rules\own\MyRules\managed-settings.json") -ManagedDir "C:\Program Files\ClaudeCode" -AiProfile (Resolve-AiProfile)
		Returns the settings text and the ai-profile.conf text for the Windows managed folder.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Template,

		[Parameter(Mandatory = $true)]
		[string]$ManagedDir,

		[Parameter()]
		[hashtable]$AiProfile
	)

	$result = @{
		Settings    = ''
		ProfileConf = ''
		Problems    = @()
	}

	$dir = $ManagedDir.Replace('\', '/').TrimEnd('/')
	$text = $Template.Replace('{ManagedDir}', $dir)
	if ([string]::IsNullOrWhiteSpace($text)) { $text = '{}' }

	try {
		$document = $text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
	}
	catch {
		$result.Problems += "The managed-settings.json template does not parse => $($_.Exception.Message)"
		return $result
	}
	if ($document -isnot [System.Collections.IDictionary]) {
		$result.Problems += "The managed-settings.json template is not a JSON object"
		return $result
	}

	$active = $AiProfile -and $AiProfile.Enabled -and $AiProfile.Profile
	if ($active) {
		$selected = $AiProfile.Profile
		# A Plan that is configured but unusable fails closed: a copy without the pin would let
		# any Plan sign in, so nothing is rendered and the deployed copy stays as it is.
		$planErrors = @($selected.PlanErrors | Where-Object { $_ })
		if ($planErrors.Count -gt 0) {
			foreach ($planError in $planErrors) { $result.Problems += $planError }
			$result.Problems += "AI profile [$($AiProfile.Name)] has a Plan that cannot be used - the managed settings were not rendered, so the deployed copy keeps its pin"
			return $result
		}
		$uuids = @($selected.Plans | ForEach-Object { $_.OrgUuid })
		if ($uuids.Count -eq 1) {
			$document['forceLoginOrgUUID'] = $uuids[0]
		}
		elseif ($uuids.Count -gt 1) {
			$document['forceLoginOrgUUID'] = $uuids
		}
		else {
			$result.Problems += "AI profile [$($AiProfile.Name)] has no Plan - forceLoginOrgUUID was not set"
		}

		if ($null -eq $document['hooks']) { $document['hooks'] = [ordered]@{} }
		if ($document['hooks'] -isnot [System.Collections.IDictionary]) {
			$result.Problems += "The template's hooks is not an object - the ownership guard was not wired"
		}
		else {
			foreach ($hookEvent in @('UserPromptSubmit', 'PreToolUse')) {
				$entry = [ordered]@{}
				if ($hookEvent -eq 'PreToolUse') { $entry['matcher'] = '*' }
				$entry['hooks'] = @([ordered]@{ type = 'command'; command = "bash `"$dir/ai-ownership-guard.sh`" $hookEvent" })
				$existing = @($document['hooks'][$hookEvent] | Where-Object { $null -ne $_ })
				$document['hooks'][$hookEvent] = @($existing + $entry)
			}
		}

		$lines = @(
			'# Written by Deploy-AiArtifacts from the AI profile configuration; do not edit.'
			"profile $($AiProfile.Name)"
		)
		if ($AiProfile.DefaultOwner) { $lines += "default-owner $($AiProfile.DefaultOwner)" }
		$lines += "unattended $(if ($selected.Unattended) { 'on' } else { 'off' })"
		foreach ($plan in @($selected.Plans)) { $lines += "plan $($plan.Name) $($plan.OrgUuid)" }
		foreach ($pattern in @($AiProfile.Shared)) { $lines += "shared $pattern" }
		foreach ($name in @($AiProfile.Profiles.Keys)) {
			foreach ($pattern in @($AiProfile.Profiles[$name].Owns)) { $lines += "owns $name $pattern" }
		}
		foreach ($pattern in @($selected.Autonomous)) { $lines += "autonomous $pattern" }
		$result.ProfileConf = ($lines -join "`n") + "`n"
	}

	$json = $document | ConvertTo-Json -Depth 32
	$result.Settings = ($json -replace "`r`n", "`n") + "`n"
	return $result
}
