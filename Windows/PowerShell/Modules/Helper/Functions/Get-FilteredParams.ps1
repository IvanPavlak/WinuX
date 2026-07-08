function Get-FilteredParams {
	<#
	.SYNOPSIS
		Filters a parameter hashtable to include only parameters accepted by a target command.

	.DESCRIPTION
		Extracts the valid parameter names from a target command and returns only the
		target parameters from the input hashtable. Used for safe parameter forwarding when
		calling commands with a subset of parameters (e.g., splatting with Get-FilteredParams).

		Returns the original hashtable unchanged if the target command cannot be found.

	.PARAMETER CommandName
		Name of the target command whose parameters to match against.

	.PARAMETER Params
		Hashtable of parameters to filter.

	.EXAMPLE
		$all_params = @{ Name = "file.txt"; Size = 100; Invalid = "xyz" }
		$filtered = Get-FilteredParams -CommandName "Get-Item" -Params $all_params
		Returns only @{ Name = "file.txt" } (parameters accepted by Get-Item).
	#>
	param($CommandName, $Params)

	$filtered = @{}
	$cmdInfo = Get-Command $CommandName -ErrorAction SilentlyContinue
	if (-not $cmdInfo) { return $Params }

	$validParams = $cmdInfo.Parameters.Keys

	foreach ($key in $Params.Keys) {
		if ($validParams -contains $key) {
			$filtered[$key] = $Params[$key]
		}
	}
	return $filtered
}
