@{
	ModuleVersion     = "1.0"
	Author            = "Ivan Pavlak"
	Description       = "Fork-owned Custom area loader - aggregates fork-local functions kept under Modules/Custom. See docs/contributing/fork-model.md (the Custom area)."
	RootModule        = "Custom.psm1"
	# Upstream ships this list EMPTY. Your fork adds one entry per Custom function it defines,
	# exactly like every engine module's manifest - and that is what lets the Custom module
	# AUTOLOAD lazily on first use (PowerShell builds its autoload index from these names; a
	# wildcard would disable it). Whole fork-owned modules under Modules/Custom/<Name> carry
	# their own manifest and are NOT listed here. Keep this in sync with the function files under
	# Modules/Custom/<Module>/Functions/*.ps1.
	FunctionsToExport = @()
}
