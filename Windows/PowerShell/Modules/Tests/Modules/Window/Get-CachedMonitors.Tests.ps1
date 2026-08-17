#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-CachedMonitors.ps1"

	# The function reaches for Screen.AllScreens and SystemInformation directly, so load the
	# assembly here: Ensure-WindowsFormsLoaded is mocked away below and cannot do it.
	# $script:WindowsFormsLoaded stays under each test's control - it is what gates the
	# topology fingerprint, independently of whether the assembly is really loaded.
	Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
}

Describe "Get-CachedMonitors" {
	BeforeEach {
		Mock Ensure-WindowsFormsLoaded { }
		$script:WindowsFormsLoaded = $false
	}

	Context "TTL" {
		It "returns cached monitor data when cache is still valid" {
			$cached = @("MonitorA")
			$script:MonitorCache = @{
				Monitors  = $cached
				Timestamp = [datetime]::Now
				MaxAgeSec = 9999
			}

			$result = Get-CachedMonitors

			$result | Should -Be $cached
			Should -Invoke Ensure-WindowsFormsLoaded -Times 0
		}

		It "refreshes when the cache has aged past its TTL" {
			$script:MonitorCache = @{
				Monitors  = @("StaleMonitor")
				Timestamp = ([datetime]::Now).AddSeconds(-60)
				MaxAgeSec = 5
			}

			$result = Get-CachedMonitors

			# Reaching the refresh branch is what loads Windows Forms.
			Should -Invoke Ensure-WindowsFormsLoaded -Exactly -Times 1
			$result | Should -Not -Be @("StaleMonitor")
		}

		It "refreshes when the cache is empty" {
			$script:MonitorCache = @{
				Monitors  = $null
				Timestamp = [datetime]::Now
				MaxAgeSec = 9999
			}

			$null = Get-CachedMonitors

			Should -Invoke Ensure-WindowsFormsLoaded -Exactly -Times 1
		}
	}

	Context "display topology fingerprint" {
		# Monitor labels are derived from physical position (Get-MonitorSpecs), so serving a
		# stale cache after the displays change hands out labels for an arrangement that no
		# longer exists. A changed fingerprint has to invalidate immediately instead of letting
		# the wrong answer stand until the TTL runs out.
		It "refreshes when the fingerprint no longer matches the live topology" {
			$script:WindowsFormsLoaded = $true
			$script:MonitorCache = @{
				Monitors    = @("StaleMonitor")
				Timestamp   = [datetime]::Now
				Fingerprint = "9|0,0,1,1"   # cannot match any real topology
				MaxAgeSec   = 9999
			}

			$result = Get-CachedMonitors

			Should -Invoke Ensure-WindowsFormsLoaded -Exactly -Times 1
			$result | Should -Not -Be @("StaleMonitor")
			$script:MonitorCache.Fingerprint | Should -Not -Be "9|0,0,1,1"
		}

		It "keeps serving the cache while the fingerprint is unchanged" {
			$script:WindowsFormsLoaded = $true
			$script:MonitorCache = @{
				Monitors    = $null
				Timestamp   = [datetime]::MinValue
				Fingerprint = $null
				MaxAgeSec   = 9999
			}

			# First call populates the cache and records the live fingerprint.
			$first = Get-CachedMonitors
			$primedFingerprint = $script:MonitorCache.Fingerprint

			$second = Get-CachedMonitors

			$second | Should -Be $first
			$script:MonitorCache.Fingerprint | Should -Be $primedFingerprint
			# Only the first call refreshed.
			Should -Invoke Ensure-WindowsFormsLoaded -Exactly -Times 1
		}

		It "baselines a fingerprint for a cache populated before Windows Forms was loaded" {
			# A session's first refresh computes its fingerprint before Forms is available, so it
			# stores none; the next call adopts the live one instead of leaving it null forever
			# and never being able to detect a change.
			$script:WindowsFormsLoaded = $true
			$script:MonitorCache = @{
				Monitors    = @("MonitorA")
				Timestamp   = [datetime]::Now
				Fingerprint = $null
				MaxAgeSec   = 9999
			}

			$result = Get-CachedMonitors

			$script:MonitorCache.Fingerprint | Should -Not -BeNullOrEmpty
			# Baselining is not a refresh - the cached value is still served.
			$result | Should -Be @("MonitorA")
			Should -Invoke Ensure-WindowsFormsLoaded -Times 0
		}

		It "does not compute a fingerprint before Windows Forms is loaded" {
			# Validating the cache must never drag the assembly in on its own.
			$script:WindowsFormsLoaded = $false
			$script:MonitorCache = @{
				Monitors    = @("MonitorA")
				Timestamp   = [datetime]::Now
				Fingerprint = $null
				MaxAgeSec   = 9999
			}

			$result = Get-CachedMonitors

			$result | Should -Be @("MonitorA")
			$script:MonitorCache.Fingerprint | Should -BeNullOrEmpty
			Should -Invoke Ensure-WindowsFormsLoaded -Times 0
		}
	}
}
