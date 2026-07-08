function Get-EfCoreDbContexts {
	<#
	.SYNOPSIS
		Gets discoverable EF Core DbContext names from dotnet ef.

	.DESCRIPTION
		Runs `dotnet ef dbcontext list` for the provided project/startup pair and parses
		the output into unique context names. Returns an empty array when discovery fails.

	.PARAMETER ProjectPath
		Migration project path to pass to --project.

	.PARAMETER StartupProjectPath
		Startup project path to pass to --startup-project.

	.PARAMETER WorkingDirectory
		Directory where dotnet ef should run (typically solution root).

	.EXAMPLE
		Get-EfCoreDbContexts -ProjectPath "src\Domain.PostgreMigrations" -StartupProjectPath "src\Api" -WorkingDirectory "C:\src\MySolution"
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$ProjectPath,

		[Parameter(Mandatory = $true)]
		[string]$StartupProjectPath,

		[Parameter(Mandatory = $true)]
		[string]$WorkingDirectory
	)

	if (-not (Test-Path -Path $WorkingDirectory -PathType Container)) {
		return @()
	}

	Push-Location $WorkingDirectory
	try {
		$command = "dotnet ef dbcontext list --project `"$ProjectPath`" --startup-project `"$StartupProjectPath`""
		$outputLines = @(Invoke-Expression "$command 2>&1")

		$contexts = @()
		foreach ($line in $outputLines) {
			$text = "$line".Trim()
			if ([string]::IsNullOrWhiteSpace($text)) { continue }

			if ($text -match '^(Build started|Build succeeded\.|Using project|Using startup project|Writing|dotnet msbuild|MSBUILD|Command exited|Unable to retrieve|No DbContext|The Entity Framework tools version|See https://aka\.ms)') { continue }
			if ($text -match '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\s+[A-Z]{3}\]') { continue }

			if ($text -match '^[A-Za-z_][A-Za-z0-9_\.]*$') {
				$contexts += $text
			}
		}

		return @($contexts | Sort-Object -Unique)
	}
	catch {
		return @()
	}
	finally {
		Pop-Location
	}
}
