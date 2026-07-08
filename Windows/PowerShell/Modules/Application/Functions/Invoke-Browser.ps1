function Invoke-Browser {
	<#
    .SYNOPSIS
        Performs a Google search in the default browser, or shows the group menu if no query is given.

    .DESCRIPTION
        When called with a query string, calls `Open-Browser -Search <query>` to perform a
        Google search in the default browser.

        When called with no arguments, calls `Open-Browser` which shows the URL group
        selection menu.

        Alias: b

    .PARAMETER Query
        One or more words that form the search query. Words are joined with spaces.

    .EXAMPLE
        Invoke-Browser "powershell hashtable"
        Searches Google for "powershell hashtable".

    .EXAMPLE
        Invoke-Browser
        Opens the browser group selection menu.
    #>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
		[string[]]$Query
	)

	$searchString = $Query -join ' '

	Open-Browser -Search $searchString
}
