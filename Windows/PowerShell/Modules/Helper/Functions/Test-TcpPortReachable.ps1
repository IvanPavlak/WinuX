function Test-TcpPortReachable {
	<#
	.SYNOPSIS
		Tests whether a TCP port on a host accepts connections within a timeout.

	.DESCRIPTION
		Attempts a plain TCP connect to the given host and port and reports whether the
		connection succeeded before the timeout elapsed. Deliberately NOT an HTTP(S)
		request: a raw socket connect never performs TLS negotiation, so endpoints with
		self-signed certificates (e.g. https://localhost dev APIs) can never fail the
		probe for certificate reasons. Any failure - refused connection, unreachable
		host, unresolvable name, timeout - returns $false rather than throwing.

		A host name is resolved first and every address it maps to is probed CONCURRENTLY,
		the first successful connection winning. Handing the name straight to
		TcpClient.ConnectAsync instead does not work here: "localhost" resolves to ::1
		before 127.0.0.1, the default TcpClient constructor creates an IPv6 socket, and a
		service listening only on IPv4 is then reported unreachable. Racing the addresses
		also keeps the whole probe inside one $TimeoutMs budget - trying them in sequence
		would cost that budget per address, since an unreachable port does not necessarily
		refuse quickly (a dropped SYN takes seconds to give up).

	.PARAMETER TargetHost
		The host name or IP address to connect to.

	.PARAMETER Port
		The TCP port to connect to.

	.PARAMETER TimeoutMs
		Maximum time in milliseconds to wait for a connection, shared across every address
		the host resolves to. Defaults to 500.

	.EXAMPLE
		Test-TcpPortReachable -TargetHost "localhost" -Port 5287
		# $true when something is listening on localhost:5287, otherwise $false

	.EXAMPLE
		if (Test-TcpPortReachable localhost 44300 -TimeoutMs 250) { "API is up" }

	.OUTPUTS
		Boolean. $true when the port accepted the connection within the timeout.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$TargetHost,

		[Parameter(Mandatory = $true, Position = 1)]
		[int]$Port,

		[Parameter()]
		[int]$TimeoutMs = 500
	)

	# Resolve up front so each address gets a socket of its own family (see DESCRIPTION).
	$addresses = @()
	$parsedAddress = [System.Net.IPAddress]::Any
	if ([System.Net.IPAddress]::TryParse($TargetHost, [ref]$parsedAddress)) {
		$addresses = @($parsedAddress)
	}
	else {
		try {
			$addresses = @([System.Net.Dns]::GetHostAddresses($TargetHost))
		}
		catch {
			# Unresolvable name - nothing to probe.
			return $false
		}
	}

	if ($addresses.Count -eq 0) {
		return $false
	}

	$clients = [System.Collections.Generic.List[System.Net.Sockets.TcpClient]]::new()
	$pendingTasks = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
	$pendingClients = [System.Collections.Generic.List[System.Net.Sockets.TcpClient]]::new()

	try {
		foreach ($address in $addresses) {
			try {
				$client = [System.Net.Sockets.TcpClient]::new($address.AddressFamily)
				$clients.Add($client)
				$pendingTasks.Add($client.ConnectAsync($address, $Port))
				$pendingClients.Add($client)
			}
			catch {
				# This address family is unusable on this machine - try the rest.
			}
		}

		$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

		# WaitAny returns the index of the first task to finish - success OR failure - and
		# does not throw for a faulted one, so a refused address just drops out of the race
		# while the others keep the remaining budget.
		while ($pendingTasks.Count -gt 0) {
			$remaining = $TimeoutMs - $stopwatch.ElapsedMilliseconds
			if ($remaining -le 0) {
				return $false
			}

			$completedIndex = [System.Threading.Tasks.Task]::WaitAny($pendingTasks.ToArray(), [int]$remaining)
			if ($completedIndex -lt 0) {
				# Timed out with connects still in flight.
				return $false
			}

			if ($pendingTasks[$completedIndex].Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion -and
				$pendingClients[$completedIndex].Connected) {
				return $true
			}

			$pendingTasks.RemoveAt($completedIndex)
			$pendingClients.RemoveAt($completedIndex)
		}

		return $false
	}
	catch {
		return $false
	}
	finally {
		foreach ($openedClient in $clients) {
			try { $openedClient.Dispose() } catch { }
		}
	}
}
