function Test-HasEfCoreDesign {
	<#
	.SYNOPSIS
		Check if a project file references EF Core Design package.

	.DESCRIPTION
		Reads project file and searches for Microsoft.EntityFrameworkCore.Design reference.
		Used to determine if project supports EF Core migrations.

	.PARAMETER projectPath
		Full path to the .csproj or .vbproj file.

	.EXAMPLE
		if (Test-HasEfCoreDesign -projectPath "MyApp.csproj") { Write-Host "Has EF" }
	#>
	param([string]$projectPath)
	$content = Get-Content -Path $projectPath -Raw -ErrorAction SilentlyContinue
	return $content -match "Microsoft\.EntityFrameworkCore\.Design"
}
