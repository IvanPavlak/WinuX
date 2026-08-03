function Open-ProjectSwagger {
	<#
	.SYNOPSIS
		Opens the Swagger UI browser tab for a project, if it has one and it isn't already open.

	.DESCRIPTION
		The opt-in workspace action for per-project Swagger tabs. Resolves the project's entry
		in the BrowserGroups "Swagger" group via Resolve-SwaggerBrowserGroup (which also performs
		the probe-driven already-open check) and hands the resolved group to Open-Browser.

		Silently no-ops when no project is supplied, when the project has no Swagger entry, or
		when the tab is already open - so a setup without any Swagger configuration never does
		anything, and a workspace can declare the action unconditionally.

		Intended to be declared in WorkspaceActions AFTER the workspace's Open-Project and
		Open-Browser actions, with the {SelectedProjects} token supplying the project context:

			@{ Action = "Open-ProjectSwagger"; Parameters = @{ Project = "{SelectedProjects}" } }

	.PARAMETER Project
		The project name(s) to open the Swagger tab for. The first non-empty element is used.
		Deliberately optional: when the {SelectedProjects} token resolves to nothing the
		parameter is dropped and this action must no-op.

	.PARAMETER Browser
		Browser to open the tab in. Defaults to $Configuration.Universal.DefaultBrowser
		(resolved inside Resolve-SwaggerBrowserGroup and Open-Browser).

	.EXAMPLE
		Open-ProjectSwagger -Project "MyProject"
		# Opens MyProject's Swagger tab unless it is already open

	.EXAMPLE
		Open-ProjectSwagger -Project $selectedProjects -Browser "Firefox"
		# First non-empty project wins; the tab opens in Firefox
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string[]]$Project,

		[Parameter()]
		[string]$Browser
	)

	$projectName = $Project | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
	if ([string]::IsNullOrWhiteSpace($projectName)) {
		Write-LogDebug " [Open-ProjectSwagger] No project supplied - skipping swagger tab"
		return
	}

	$resolveParams = @{ Project = $Project }
	if (-not [string]::IsNullOrWhiteSpace($Browser)) {
		$resolveParams['Browser'] = $Browser
	}

	$swaggerGroup = Resolve-SwaggerBrowserGroup @resolveParams
	if (-not $swaggerGroup) {
		# No swagger entry for the project, or the tab is already open - nothing to do.
		return
	}

	# Never call Open-Browser with empty Groups - that opens its interactive group menu.
	$browserParams = @{ Groups = @($swaggerGroup) }
	if (-not [string]::IsNullOrWhiteSpace($Browser)) {
		$browserParams['Browser'] = $Browser
	}

	Open-Browser @browserParams
}
