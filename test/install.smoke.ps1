# End-to-end test of install.ps1 and uninstall.ps1 (Windows PowerShell 5.1) with the VS Code CLI
# of this machine. Every run happens in a child powershell whose USERPROFILE, APPDATA and
# LOCALAPPDATA point to a fake profile (CODEX_HOME removed), with -StateDir, --extensions-dir and
# --user-data-dir under %TEMP%: the real profile, VS Code extensions and settings are never touched.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:failures = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { $script:failures++; Write-Host "  FAIL $msg" }
}

$utf8 = New-Object Text.UTF8Encoding $false
$eacute = [string][char]0xE9
$begin = '<!-- getout:begin -->'

. (Join-Path $root 'install.ps1') -LibraryOnly
$cli = Find-CodeCli
if (-not $cli) {
    Write-Host 'skip: no VS Code command line (code) found on this machine: install smoke test not run'
    exit 0
}
Write-Host "VS Code CLI: $cli"
$version = [string]([IO.File]::ReadAllText((Join-Path $root 'extension\package.json'), $utf8) | ConvertFrom-Json).version

$tmp = Join-Path $env:TEMP ('getout-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($tmp)
# Spaces, accents and parentheses in every path handed to code.cmd.
$extDir = Join-Path $tmp "ext $eacute (x)"
$userData = Join-Path $tmp "user data $eacute"
$stateDir = Join-Path $tmp "state $eacute x"
$fake = Join-Path $tmp 'profile'
$appdata = Join-Path $fake 'AppData\Roaming'
$localAppData = Join-Path $fake 'AppData\Local'
$claudeMd = Join-Path $fake '.claude\CLAUDE.md'

function Count-Of($text, $needle) { ([regex]::Matches($text, [regex]::Escape($needle))).Count }
function Same-Bytes($a, $b) { ($a.Length -eq $b.Length) -and ($a.Length -eq 0 -or -not (Compare-Object $a $b -SyncWindow 0)) }
function Read-Bytes($p) { if (Test-Path -LiteralPath $p) { , [IO.File]::ReadAllBytes($p) } else { , [byte[]]@() } }

# Runs a script in a child powershell with the fake profile and stdin redirected from an empty input.
function Invoke-Child {
    param([string]$Script, [string[]]$Arguments, [int]$TimeoutSec = 300)
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = ($all | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $tmp
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Read the output the way an agent does: UTF-8.
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $e = $psi.Environment
    $e['USERPROFILE'] = $fake
    $e['APPDATA'] = $appdata
    $e['LOCALAPPDATA'] = $localAppData
    [void]$e.Remove('CODEX_HOME')
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit($TimeoutSec * 1000)
    if ($timedOut) { try { $p.Kill() } catch { }; [void]$p.WaitForExit(5000) }
    $closed = $out.Wait(10000) -and $err.Wait(10000)
    $r = [pscustomobject]@{
        Code     = $(if ($timedOut) { -1 } else { $p.ExitCode })
        TimedOut = $timedOut
        Closed   = $closed
        Out      = $(if ($out.IsCompleted) { $out.Result } else { '' })
        Err      = $(if ($err.IsCompleted) { $err.Result } else { '' })
    }
    Write-Host ($r.Out.TrimEnd() -replace '(?m)^', '    | ')
    if ($r.Err.Trim()) { Write-Host ($r.Err.TrimEnd() -replace '(?m)^', '    ! ') }
    return $r
}

function Test-Args([string[]]$More) {
    $More + @('-CodeCli', $cli, '-ExtensionsDir', $extDir, '-UserDataDir', $userData, '-StateDir', $stateDir)
}

# The extensions listed by the VS Code CLI in the test's extensions folder.
function Get-TestExtension {
    $r = Invoke-CodeCli -Cli $cli -Arguments @('--list-extensions', '--show-versions',
        '--extensions-dir', $extDir, '--user-data-dir', $userData)
    return @($r.Out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# extensions.json of the test's extensions folder, read without the VS Code CLI.
function Get-Registered {
    $p = Join-Path $extDir 'extensions.json'
    if (Test-Path -LiteralPath $p) { return [IO.File]::ReadAllText($p, $utf8) }
    return ''
}

# What the test must never change: the real state.json (v1 or v2), the real CLAUDE.md and the
# getout extensions of the real VS Code profile.
function Get-RealMark {
    $home0 = [Environment]::GetFolderPath('UserProfile')
    $items = @((Join-Path $env:LOCALAPPDATA 'getout\state.json'), (Join-Path $home0 '.claude\CLAUDE.md'))
    $marks = @($items | ForEach-Object { if (Test-Path -LiteralPath $_) { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks } else { 'absent' } })
    $real = Join-Path $home0 '.vscode\extensions'
    if (Test-Path -LiteralPath $real) {
        $marks += @(Get-ChildItem -LiteralPath $real -Directory -Filter 'ceddup.getout*' | ForEach-Object { $_.Name })
    }
    return ($marks -join ',')
}

$realBefore = Get-RealMark

try {
    # --- fake profile
    [void][IO.Directory]::CreateDirectory((Split-Path $claudeMd))
    [void][IO.Directory]::CreateDirectory($appdata)
    [void][IO.Directory]::CreateDirectory($localAppData)
    $claudeOrig = [byte[]](@(0xEF, 0xBB, 0xBF) + $utf8.GetBytes("# Notes`r`n${eacute}t${eacute}`r`n"))
    [IO.File]::WriteAllBytes($claudeMd, $claudeOrig)
    $installPs1 = Join-Path $root 'install.ps1'

    # --- 0. a state folder holding a getout v1 install is refused, untouched
    Write-Host 'Step 0: getout v1 in the state folder'
    $v1Dir = Join-Path $tmp 'v1'
    [void][IO.Directory]::CreateDirectory($v1Dir)
    $v1State = $utf8.GetBytes('{ "version": "1.4.0", "port": 8765, "nodeExe": "node.exe", "agents": [] }')
    [IO.File]::WriteAllBytes((Join-Path $v1Dir 'state.json'), $v1State)
    $r = Invoke-Child $installPs1 @('-Yes', '-Lang', 'en', '-Agents', 'claude', '-CodeCli', $cli,
        '-ExtensionsDir', $extDir, '-UserDataDir', $userData, '-StateDir', $v1Dir)
    Assert ($r.Code -eq 1) "install refused (exit code $($r.Code))"
    Assert ($r.Out.Contains('uninstall')) 'the message says to uninstall v1 first'
    Assert (Same-Bytes $v1State (Read-Bytes (Join-Path $v1Dir 'state.json'))) 'v1 state.json untouched'
    Assert (Same-Bytes $claudeOrig (Read-Bytes $claudeMd)) 'CLAUDE.md untouched'
    Assert (-not (Test-Path -LiteralPath $extDir)) 'no extension installed'
    $r = Invoke-Child (Join-Path $root 'uninstall.ps1') @('-Yes', '-CodeCli', $cli, '-ExtensionsDir', $extDir,
        '-UserDataDir', $userData, '-StateDir', $v1Dir)
    Assert ($r.Code -eq 1) "uninstall refused (exit code $($r.Code))"
    Assert (Same-Bytes $v1State (Read-Bytes (Join-Path $v1Dir 'state.json'))) 'v1 state.json untouched by uninstall'

    # --- 1. first install, in French, for Claude Code
    Write-Host 'Step 1: install -Lang fr -Agents claude'
    $r = Invoke-Child $installPs1 (Test-Args @('-Yes', '-Lang', 'fr', '-Agents', 'claude'))
    Assert ($r.Code -eq 0) "exit code 0 (got $($r.Code))"
    Assert $r.Closed 'output closed when the installer exits'
    Assert ($r.Out.Contains("getout $version est install${eacute}") -and
        -not $r.Out.Contains([string][char]0xFFFD)) 'French verdict readable as UTF-8'
    Assert ((Get-TestExtension) -contains "ceddup.getout@$version") "VS Code lists ceddup.getout@$version in the test folder"
    Assert (Test-Path -LiteralPath (Join-Path $extDir "ceddup.getout-$version\extension.js")) 'extension files unpacked in the test folder'
    Assert ((Get-Registered).Contains('ceddup.getout')) 'extension registered in extensions.json'
    $b = Read-Bytes $claudeMd
    Assert ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'CLAUDE.md keeps its BOM'
    $t = $utf8.GetString($b)
    Assert ((Count-Of $t $begin) -eq 1) 'CLAUDE.md has one block'
    Assert ($t.Contains('Liens vers les fichiers locaux')) 'the block is in French'
    Assert ($t -notmatch "(?<!`r)`n") 'CLAUDE.md stays CRLF'
    $st = $null
    try { $st = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $stateDir 'state.json'), $utf8)) } catch { }
    Assert ($null -ne $st -and $st.version -ceq $version -and $st.lang -ceq 'fr') 'state.json: version and lang'
    $ag = @()
    if ($st) { $ag = @(@($st.agents) | Where-Object { $_ }) }
    Assert ($ag.Count -eq 1 -and $ag[0].name -ceq 'claude' -and $ag[0].file -ieq $claudeMd -and $ag[0].created -eq $false) 'state.json: Claude Code, existing file'
    $claude1 = Read-Bytes $claudeMd

    # --- 2. reinstall: no -Yes, stdin redirected from an empty input, no -Lang, no -Agents
    Write-Host 'Step 2: reinstall with the previous choices, empty stdin'
    $r = Invoke-Child $installPs1 (Test-Args @()) -TimeoutSec 300
    Assert (-not $r.TimedOut) 'did not wait for an answer'
    Assert ($r.Code -eq 0) "exit code 0 (got $($r.Code))"
    Assert ($r.Out.Contains("install${eacute}")) 'still in French'
    Assert (Same-Bytes $claude1 (Read-Bytes $claudeMd)) 'CLAUDE.md unchanged: still one block'
    Assert ((Get-TestExtension) -contains "ceddup.getout@$version") 'extension still listed'

    # --- 3. uninstall
    Write-Host 'Step 3: uninstall'
    $r = Invoke-Child (Join-Path $root 'uninstall.ps1') (Test-Args @('-Yes'))
    Assert ($r.Code -eq 0) "exit code 0 (got $($r.Code))"
    Assert (@(Get-TestExtension | Where-Object { $_ -like 'ceddup.getout@*' }).Count -eq 0) 'extension no longer listed'
    # The CLI unregisters the extension; VS Code deletes its unregistered folder at its next start.
    Assert (-not (Get-Registered).Contains('ceddup.getout')) 'extension no longer registered in extensions.json'
    Assert (Same-Bytes $claudeOrig (Read-Bytes $claudeMd)) 'CLAUDE.md restored byte for byte'
    Assert (-not (Test-Path -LiteralPath $stateDir)) 'state folder removed'
}
catch {
    $script:failures++
    Write-Host "ERROR: $($_.Exception.Message)"
}
finally {
    for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $tmp); $i++) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $tmp) { Start-Sleep -Milliseconds 250 }
    }
    if (Test-Path -LiteralPath $tmp) { Write-Host "warning: could not remove $tmp" }
}

if ((Get-RealMark) -ne $realBefore) { $script:failures++; Write-Host 'FAIL the real state.json, CLAUDE.md or VS Code extensions changed' }

if ($script:failures -gt 0) { Write-Host "$($script:failures) failure(s)"; exit 1 }
Write-Host 'install smoke test: all passed'
exit 0
