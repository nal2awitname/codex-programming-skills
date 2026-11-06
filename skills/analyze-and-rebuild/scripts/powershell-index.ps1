param([Parameter(Mandatory = $true)][string]$SourceFile)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$tokens = $null
$parseErrors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $SourceFile).Path, [ref]$tokens, [ref]$parseErrors)
$symbols = @($tree.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
    $node -is [System.Management.Automation.Language.FunctionMemberAst] -or
    $node -is [System.Management.Automation.Language.TypeDefinitionAst]
}, $true) | ForEach-Object {
    $kind = $_.GetType().Name
    @{ name = $_.Name; qualified_name = ($kind + ':' + $_.Name); kind = $kind
       line = $_.Extent.StartLineNumber; end_line = $_.Extent.EndLineNumber
       column = $_.Extent.StartColumnNumber; calls = @(); discovery = 'ast' }
})
$notes = @('Syntactic inventory; dynamic commands, script blocks and runtime dispatch require review.')
if (@($parseErrors).Count -gt 0) {
    $notes += 'PowerShell syntax errors found; inventory is partial.'
}
@{ parser = 'powershell_ast'; confirmed_language = 'PowerShell'; symbols = $symbols
   imports = @(); notes = $notes; parse_errors = @($parseErrors | ForEach-Object {
       @{ id = $_.ErrorId; line = $_.Extent.StartLineNumber }
   }) } | ConvertTo-Json -Depth 8 -Compress
