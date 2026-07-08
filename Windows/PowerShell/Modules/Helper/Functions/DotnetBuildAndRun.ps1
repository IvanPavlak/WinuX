function DotnetBuildAndRun {
	<#
	.SYNOPSIS
		Build and run a .NET project in sequence.

	.DESCRIPTION
		Invokes `dotnet build` followed by `dotnet run` in the current directory.
		Runs in current shell, not background.

	.EXAMPLE
		DotnetBuildAndRun
	#>
	& dotnet build ; dotnet run
}
