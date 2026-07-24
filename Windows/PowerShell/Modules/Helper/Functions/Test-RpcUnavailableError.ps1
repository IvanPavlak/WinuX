function Test-RpcUnavailableError {
	<#
	.SYNOPSIS
		Determines whether an error represents an unavailable or disconnected RPC/COM endpoint.

	.DESCRIPTION
		Classifies an ErrorRecord, exception, or plain message string as an RPC
		availability failure - the family of errors VirtualDesktop COM calls surface
		when the shell endpoint is gone or when this session's cached COM proxies have
		disconnected from a restarted explorer.exe:

		- 0x800706BA "The RPC server is unavailable"
		- 0x800706BE "The remote procedure call failed"
		- 0x80010108 "The object invoked has disconnected from its clients"
		- 0x800401FD "Object is not connected to server"

		Unlike a plain message match, the full InnerException chain is walked - a stale
		COM proxy often surfaces as a TypeInitializationException or MethodInvocation
		wrapper whose top-level message says nothing about RPC - and each exception's
		HRESULT is compared as well, so localized Windows error text still classifies
		correctly.

	.PARAMETER InputObject
		The ErrorRecord, Exception, or message string to classify. $null returns $false.

	.EXAMPLE
		try { New-Desktop } catch { if (Test-RpcUnavailableError $_) { [void](Reset-VirtualDesktopState) } }

	.OUTPUTS
		Boolean. $true when the error is an RPC availability failure, otherwise $false.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Position = 0)]
		[AllowNull()]
		$InputObject
	)

	$rpcPattern = '0x800706BA|0x800706BE|0x80010108|0x800401FD|RPC server is unavailable|remote procedure call failed|disconnected from its clients|not connected to server'

	if ($null -eq $InputObject) {
		return $false
	}

	$exception = $null
	if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
		$exception = $InputObject.Exception
	}
	elseif ($InputObject -is [Exception]) {
		$exception = $InputObject
	}

	if ($null -eq $exception) {
		return ([string]$InputObject) -match $rpcPattern
	}

	while ($null -ne $exception) {
		if ($exception.Message -match $rpcPattern) {
			return $true
		}

		# HRESULT check catches localized error text. {0:X8} renders the negative
		# Int32 HRESULT as its unsigned hex form (e.g. -2147023174 -> 800706BA).
		if ($exception.HResult -and (('0x{0:X8}' -f $exception.HResult) -match $rpcPattern)) {
			return $true
		}

		$exception = $exception.InnerException
	}

	return $false
}
