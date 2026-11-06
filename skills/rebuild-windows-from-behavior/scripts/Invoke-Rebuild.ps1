# Pass arguments unchanged; this wrapper never starts the original application.
$ErrorActionPreference = 'Stop'
$toolPath = Join-Path $PSScriptRoot 'rebuild.py'
if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 $toolPath @args
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python $toolPath @args
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    & python3 $toolPath @args
} else {
    throw 'Python 3.10 or later is required. Install Python, then run this command again.'
}
exit $LASTEXITCODE
