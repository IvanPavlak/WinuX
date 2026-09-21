function Register-DeferredAction {
	<#
	.SYNOPSIS
		Queues work an opener hands back to the flow that called it, to run at a point the flow chooses.

	.DESCRIPTION
		The registry half of the deferral seam. A launch action inside Open-Workspace often has a
		slow tail that is pure waiting on its own application - the Obsidian CLI cannot answer until
		Obsidian has finished starting - and every action queued behind it used to pay that wait.
		An action that declares -Deferred (Open-Workspace injects it) does its launch, registers the
		tail here with the arguments it needs, and returns at once. Complete-DeferredActions runs
		every registered tail, in registration order, when the flow says the moment has come - for
		Open-Workspace, immediately before the layout starts waiting on window titles.

		Nothing here is specific to Obsidian or to Open-Workspace: the registry holds a label, a
		scriptblock and the hashtable to splat into it. The scriptblock keeps the session state it
		was created in, so a function defined in the registering module resolves when the flow runs
		it from another.

		The queue is module state of the Helper module and lives for the process. A flow that
		registers must also drain - Complete-DeferredActions clears the queue before running it - or
		a tail registered by one open would run inside the next.

	.PARAMETER Label
		What the tail does, for the warning Complete-DeferredActions writes when it throws.

	.PARAMETER Action
		The tail. Declares a param block matching the keys of -Parameters, or takes none.

	.PARAMETER Parameters
		Splatted into -Action when it runs. Captured by value now, so the caller's locals are safe
		to go out of scope.

	.EXAMPLE
		Register-DeferredAction -Label "Obsidian workspace [$Name]" -Parameters @{ CliPath = $cli; Vault = $vault; Name = $Name; ColdStart = $true } -Action {
			param([string]$CliPath, [string]$Vault, [string]$Name, [bool]$ColdStart)
			Complete-ObsidianWorkspaceLoad -CliPath $CliPath -Vault $Vault -Name $Name -ColdStart:$ColdStart
		}
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Label,

		[Parameter(Mandatory = $true)]
		[scriptblock]$Action,

		[Parameter()]
		[hashtable]$Parameters = @{}
	)

	if ($null -eq $script:DeferredActions) {
		$script:DeferredActions = [System.Collections.Generic.List[object]]::new()
	}

	$script:DeferredActions.Add([PSCustomObject]@{
			Label      = $Label
			Action     = $Action
			Parameters = $Parameters.Clone()
		})

	Write-LogDebug " [Register-DeferredAction] Queued [$Label] (#$($script:DeferredActions.Count))"
}
