# getout uninstaller: runs "install.ps1 -Uninstall" from this folder (a clone), else the
# install.ps1 of the main branch. Pure ASCII. Windows PowerShell 5.1 compatible.
param(
    [ValidateSet('', 'en', 'fr')][string]$Lang = '',
    [switch]$Yes,
    [string]$CodeCli,
    [string]$ExtensionsDir,
    [string]$UserDataDir,
    [string]$StateDir
)

$forward = @{ Uninstall = $true }
foreach ($k in $PSBoundParameters.Keys) { $forward[$k] = $PSBoundParameters[$k] }

$local = $null
if ($PSScriptRoot) { $local = Join-Path $PSScriptRoot 'install.ps1' }
if ($local -and (Test-Path -LiteralPath $local)) {
    & $local @forward
}
else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
    $code = (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/ceddup/getout/main/install.ps1')
    & ([scriptblock]::Create($code)) @forward
}

# "exit" only when run as a file: through "irm | iex" it would close the console, or end the
# calling script ($PSScriptRoot is empty under iex, $MyInvocation.MyCommand.Path is the caller's).
if ($PSScriptRoot) { exit $LASTEXITCODE }
