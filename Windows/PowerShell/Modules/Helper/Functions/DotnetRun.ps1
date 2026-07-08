function DotnetRun {
	<#
	.SYNOPSIS
		Run a .NET project without building.

	.DESCRIPTION
		Executes `dotnet run` in the current directory.
		Assuming the project is already built.

	.EXAMPLE
		DotnetRun
	#>
	& dotnet run
}
