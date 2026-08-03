#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Test-TcpPortReachable.ps1"
}

Describe "Test-TcpPortReachable" {
	Context "Reachable and unreachable ports" {
		It "returns true for a listening loopback port" {
			$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
			try {
				$listener.Start()
				$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

				Test-TcpPortReachable -TargetHost "localhost" -Port $port | Should -BeTrue
			}
			finally {
				$listener.Stop()
			}
		}

		# Regression: "localhost" resolves to ::1 before 127.0.0.1 and the default TcpClient
		# constructor makes an IPv6 socket, so handing the NAME to ConnectAsync reported an
		# IPv4-only service - the shape of every dev API this probe exists for - as down.
		It "finds an IPv4-only listener when probed by host name" {
			$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
			try {
				$listener.Start()
				$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

				Test-TcpPortReachable -TargetHost "localhost" -Port $port | Should -BeTrue
			}
			finally {
				$listener.Stop()
			}
		}

		It "finds an IPv6-only listener when probed by host name" {
			$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::IPv6Loopback, 0)
			try {
				$listener.Start()
				$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

				Test-TcpPortReachable -TargetHost "localhost" -Port $port | Should -BeTrue
			}
			finally {
				$listener.Stop()
			}
		}

		It "returns true for a listening port given as an IP literal" {
			$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
			try {
				$listener.Start()
				$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

				Test-TcpPortReachable -TargetHost "127.0.0.1" -Port $port | Should -BeTrue
			}
			finally {
				$listener.Stop()
			}
		}

		It "returns false for a closed loopback port" {
			# Start a listener just to learn a port the OS considers free, then close it
			$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
			$listener.Start()
			$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
			$listener.Stop()

			Test-TcpPortReachable -TargetHost "localhost" -Port $port | Should -BeFalse
		}

		It "returns false for an unresolvable host instead of throwing" {
			Test-TcpPortReachable -TargetHost "no-such-host.invalid" -Port 80 | Should -BeFalse
		}
	}

	Context "Timeout" {
		It "gives up within the timeout on a non-routable address" {
			# 10.255.255.1 is non-routable, so the connect can only end by timeout.
			# The elapsed bound is deliberately generous to keep the test unflaky.
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
			$result = Test-TcpPortReachable -TargetHost "10.255.255.1" -Port 80 -TimeoutMs 100
			$stopwatch.Stop()

			$result | Should -BeFalse
			$stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 3
		}

		It "shares one timeout budget across every address the host resolves to" {
			# A closed port does not necessarily refuse quickly (a dropped SYN takes seconds
			# to give up), so probing localhost's addresses in sequence would cost the budget
			# once per address. The addresses are raced instead, keeping the whole probe
			# inside a single budget.
			$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
			$listener.Start()
			$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
			$listener.Stop()

			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
			$result = Test-TcpPortReachable -TargetHost "localhost" -Port $port -TimeoutMs 300
			$stopwatch.Stop()

			$result | Should -BeFalse
			$stopwatch.Elapsed.TotalMilliseconds | Should -BeLessThan 900
		}
	}

	Context "Parameter contract" {
		It "requires TargetHost and Port" {
			$cmd = Get-Command Test-TcpPortReachable
			foreach ($name in @('TargetHost', 'Port')) {
				$mandatoryAttr = $cmd.Parameters[$name].Attributes |
					Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
				$mandatoryAttr.Mandatory | Should -BeTrue
			}
		}

		It "accepts host and port positionally" {
			$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
			try {
				$listener.Start()
				$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

				Test-TcpPortReachable "localhost" $port | Should -BeTrue
			}
			finally {
				$listener.Stop()
			}
		}
	}
}
