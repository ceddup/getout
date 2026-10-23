# Library tests of install.ps1 (Windows PowerShell 5.1): no VS Code, no network, no real profile.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:failures = 0
function Assert($cond, $msg) {
    if (-not $cond) { $script:failures++; Write-Host "FAIL: $msg" }
}

$tmp = Join-Path $env:TEMP ("getout-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$eacute = [string][char]0xE9
$begin = '<!-- getout:begin -->'
$end = '<!-- getout:end -->'

function Count-Of($text, $needle) { ([regex]::Matches($text, [regex]::Escape($needle))).Count }
function Same-Bytes($a, $b) { ($a.Length -eq $b.Length) -and (-not (Compare-Object $a $b -SyncWindow 0)) }
function Test-NoBom($path) {
    $b = [IO.File]::ReadAllBytes($path)
    return -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

try {
    . (Join-Path $root 'install.ps1') -LibraryOnly

    # --- Set-RuleBlock / Remove-RuleBlock
    $blockA = "$begin`nrule A $eacute`n$end"
    $blockB = "$begin`nrule B`n$end"

    $p = Join-Path $tmp 'new\AGENTS.md'
    New-Item -ItemType Directory -Path (Split-Path $p) | Out-Null
    Set-RuleBlock -Path $p -Block $blockA
    $b = [IO.File]::ReadAllBytes($p)
    Assert (Test-NoBom $p) 'created file has no BOM'
    Assert ((Count-Of ($utf8.GetString($b)) $begin) -eq 1) 'created file has one begin marker'
    Assert ($utf8.GetString($b).Contains("rule A $eacute")) 'created file has the rule text (UTF-8)'

    $p = Join-Path $tmp 'bom.md'
    $orig = [byte[]](@(0xEF, 0xBB, 0xBF) + $utf8.GetBytes("# Notes`r`n${eacute}t${eacute}`r`n"))
    [IO.File]::WriteAllBytes($p, $orig)
    Set-RuleBlock -Path $p -Block $blockA
    $b = [IO.File]::ReadAllBytes($p)
    $prefixOk = ($b.Length -gt $orig.Length) -and (Same-Bytes $orig ([byte[]]$b[0..($orig.Length - 1)]))
    Assert $prefixOk 'original bytes are an exact prefix'
    $tail = $utf8.GetString($b, 3, $b.Length - 3)
    Assert ($tail -notmatch "(?<!`r)`n") 'block uses CRLF'
    Assert ((Count-Of $tail $begin) -eq 1) 'one begin marker after first call'
    Set-RuleBlock -Path $p -Block $blockB
    $tail = $utf8.GetString([IO.File]::ReadAllBytes($p))
    Assert ((Count-Of $tail $begin) -eq 1) 'still one begin marker after second call'
    Assert ($tail.Contains('rule B') -and -not $tail.Contains('rule A')) 'new block replaces old one'
    $r = Remove-RuleBlock -Path $p
    Assert ($r -eq $true) 'Remove-RuleBlock returns true'
    Assert (Same-Bytes $orig ([IO.File]::ReadAllBytes($p))) 'Remove-RuleBlock restores original bytes'
    Assert ((Remove-RuleBlock -Path $p) -eq $false) 'Remove-RuleBlock returns false when no block'

    $p = Join-Path $tmp 'lf.md'
    $orig = $utf8.GetBytes("line`n")
    [IO.File]::WriteAllBytes($p, $orig)
    Set-RuleBlock -Path $p -Block $blockA
    Assert (-not $utf8.GetString([IO.File]::ReadAllBytes($p)).Contains("`r")) 'LF file stays LF'
    Remove-RuleBlock -Path $p | Out-Null
    Assert (Same-Bytes $orig ([IO.File]::ReadAllBytes($p))) 'LF file restored'

    # Windows-1252 file (no BOM, not valid UTF-8): written back in 1252.
    $p = Join-Path $tmp 'ansi.md'
    $cp1252 = [Text.Encoding]::GetEncoding(1252)
    $orig = $cp1252.GetBytes("caf${eacute}`r`n")
    [IO.File]::WriteAllBytes($p, $orig)
    Set-RuleBlock -Path $p -Block $blockA
    Assert ($cp1252.GetString([IO.File]::ReadAllBytes($p)).Contains("rule A $eacute")) 'Windows-1252 file stays Windows-1252'
    Remove-RuleBlock -Path $p | Out-Null
    Assert (Same-Bytes $orig ([IO.File]::ReadAllBytes($p))) 'Windows-1252 file restored'

    # A stray begin marker (user text, truncated block) before the real block stays with its text.
    $p = Join-Path $tmp 'stray.md'
    $orig = $utf8.GetBytes("keep 1`n$begin`nkeep 2`n")
    [IO.File]::WriteAllBytes($p, $orig)
    Set-RuleBlock -Path $p -Block $blockA
    Set-RuleBlock -Path $p -Block $blockB
    $t = $utf8.GetString([IO.File]::ReadAllBytes($p))
    Assert ($t.Contains('keep 2') -and $t.Contains('rule B') -and -not $t.Contains('rule A')) 'stray marker: Set replaces only the real block'
    Assert ((Remove-RuleBlock -Path $p) -eq $true) 'stray marker: block removed'
    Assert (Same-Bytes $orig ([IO.File]::ReadAllBytes($p))) 'stray marker: user text before the block survives'

    # Culture comparisons (ICU under PowerShell 7) mishandle "`r`n": every comparison is ordinal.
    $calls = @([IO.File]::ReadAllLines((Join-Path $root 'install.ps1')) | Where-Object {
            $_ -match '\.(StartsWith|EndsWith|IndexOf|LastIndexOf)\(' -and $_ -notmatch 'StringComparison'
        })
    Assert ($calls.Count -eq 0) "install.ps1 compares strings ordinally ($($calls -join ' | '))"

    # --- Get-RuleText
    foreach ($l in 'en', 'fr') {
        $txt = Get-RuleText -Dir $root -Lang $l
        Assert ($txt.StartsWith($begin + "`n", [StringComparison]::Ordinal) -and
            $txt.EndsWith("`n" + $end, [StringComparison]::Ordinal)) "$l rule is wrapped in the markers"
        Assert (-not $txt.Contains('{{')) "$l rule has no unreplaced variable"
        Assert ($txt.Contains('[C:\\Users\\me\\Plans\\archi.drawio](C:/Users/me/Plans/archi.drawio)')) "$l rule has the example link"
        Assert (-not $txt.Contains('http://localhost:')) "$l rule has no localhost link"
        Assert (-not $txt.Contains("`r")) "$l rule is normalized to LF"
    }
    Assert ((Get-RuleText -Dir $root -Lang 'fr').Contains("Liens vers les fichiers locaux")) 'fr rule is in French'

    # --- UTF-8 without BOM for the localized files
    foreach ($f in 'messages.json', 'rules\rule.en.md', 'rules\rule.fr.md') {
        Assert (Test-NoBom (Join-Path $root $f)) "$f has no BOM"
    }

    # --- messages
    $m = [IO.File]::ReadAllText((Join-Path $root 'messages.json'), $utf8) | ConvertFrom-Json
    $en = @($m.en.PSObject.Properties.Name | Sort-Object)
    $fr = @($m.fr.PSObject.Properties.Name | Sort-Object)
    Assert (($en -join ',') -ceq ($fr -join ',')) 'messages.json: same keys in en and fr'
    Import-Messages -Dir $root
    Assert ((Get-Message -Key 'agent_added' -Lang 'en' -Values @('A', 'F')) -like '*A*F') 'Get-Message formats values'
    Assert ((Get-Message -Key 'verdict_ok' -Lang 'fr' -Values @('2.0.0')) -like "*install${eacute}*") 'Get-Message fr accents'
    Assert ((Get-Message -Key 'nope' -Lang 'en') -eq 'nope') 'Get-Message unknown key returns key'
    foreach ($k in $script:FallbackMessages.Keys) {
        Assert ($script:FallbackMessages[$k] -ceq [string]$m.en.$k) "fallback message $k is the messages.json text"
    }

    # Uninstall through "irm | iex": messages.json is downloaded; if that fails too, the uninstall
    # messages are in English, never raw keys.
    $saved = @($script:Messages, $script:ScriptDir, $script:RepoArchive)
    try {
        $script:Messages = $null
        $script:ScriptDir = $null
        $script:RepoArchive = 'http://127.0.0.1:1/{0}.zip'
        Import-MessagesFrom @($null, (Join-Path $tmp 'absent'))
        Assert ($null -eq $script:Messages) 'no messages.json and no download: no error'
        Assert ((Get-Message -Key 'uninstall_done' -Lang 'fr') -ceq [string]$m.en.uninstall_done) 'uninstall message falls back to English'
        Import-MessagesFrom @((Join-Path $tmp 'absent'), $root)
        Assert ((Get-Message -Key 'uninstall_done' -Lang 'fr') -ceq [string]$m.fr.uninstall_done) 'messages.json loaded from the first folder that has one'
    }
    finally { $script:Messages, $script:ScriptDir, $script:RepoArchive = $saved }

    # --- agents: Codex follows CODEX_HOME; a file created by getout and emptied is deleted
    $savedCodex = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = Join-Path $tmp 'codex home'
        $codex = @(Get-AgentDefinition | Where-Object { $_.Name -eq 'codex' })
        Assert ($codex.Count -eq 1 -and $codex[0].Path -ceq (Join-Path $tmp 'codex home\AGENTS.md')) 'Codex file under CODEX_HOME'
        Remove-Item Env:\CODEX_HOME
        $codex = @(Get-AgentDefinition | Where-Object { $_.Name -eq 'codex' })
        Assert ($codex[0].Path -ceq [IO.Path]::Combine($env:USERPROFILE, '.codex', 'AGENTS.md')) 'Codex file under ~\.codex without CODEX_HOME'
    }
    finally { $env:CODEX_HOME = $savedCodex }
    $p = Join-Path $tmp 'created\GEMINI.md'
    New-Item -ItemType Directory -Path (Split-Path $p) | Out-Null
    Set-RuleBlock -Path $p -Block $blockA
    Remove-AgentRule ([pscustomobject]@{ name = 'gemini'; file = $p; created = $true })
    Assert (-not (Test-Path -LiteralPath $p)) 'agent file created by getout and emptied is deleted'
    $p = Join-Path $tmp 'kept\GEMINI.md'
    New-Item -ItemType Directory -Path (Split-Path $p) | Out-Null
    Set-RuleBlock -Path $p -Block $blockA
    Remove-AgentRule ([pscustomobject]@{ name = 'gemini'; file = $p; created = $false })
    Assert (Test-Path -LiteralPath $p) 'agent file not created by getout is kept even when empty'

    # --- state folder: only state.json is getout's (the folder may hold a v1 install)
    $d = Join-Path $tmp 'state only'
    New-Item -ItemType Directory -Path $d | Out-Null
    Write-JsonFile (Join-Path $d 'state.json') @{ version = '2.0.0' }
    Remove-StateFile $d
    Assert (-not (Test-Path -LiteralPath $d)) 'state folder holding only state.json is removed'
    $d = Join-Path $tmp 'state shared'
    New-Item -ItemType Directory -Path $d | Out-Null
    Write-JsonFile (Join-Path $d 'state.json') @{ version = '2.0.0' }
    [IO.File]::WriteAllText((Join-Path $d 'server.js'), '// other', $utf8)
    Remove-StateFile $d
    Assert (-not (Test-Path -LiteralPath (Join-Path $d 'state.json'))) 'state.json removed from a shared folder'
    Assert (Test-Path -LiteralPath (Join-Path $d 'server.js')) 'other files of the state folder are kept'
    Remove-StateFile (Join-Path $tmp 'absent state')
    Assert (Test-V1State ([pscustomobject]@{ version = '1.4.0'; port = 8765; nodeExe = 'node.exe'; agents = @() })) 'v1 state.json recognized'
    Assert (-not (Test-V1State ([pscustomobject]@{ version = '2.0.0'; lang = 'fr'; agents = @() }))) 'v2 state.json is not v1'
    Assert (-not (Test-V1State $null)) 'no state.json is not v1'

    # --- VS Code CLI
    $fakeDir = Join-Path $tmp "fake code $eacute (x86)"
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    $fake = Join-Path $fakeDir 'code.cmd'
    Assert ((Find-CodeCli -Override (Join-Path $fakeDir 'absent.cmd')) -eq $null) 'Find-CodeCli: a missing -CodeCli is not found'
    $node = @(Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue)
    if ($node.Count -gt 0) {
        # Like code.cmd: a batch file that hands %* to a node process.
        $js = 'console.log(JSON.stringify(process.argv.slice(1))); process.exit(3)'
        [IO.File]::WriteAllText($fake, "@echo off`r`n`"$($node[0].Path)`" -e `"$js`" -- %*`r`n", [Text.Encoding]::ASCII)
        Assert ((Find-CodeCli -Override $fake) -ceq $fake) 'Find-CodeCli: -CodeCli wins'
        $argsIn = @('--install-extension', (Join-Path $tmp "a b\$eacute t\getout.vsix"), 'C:\dir with space\', 'plain', 'x&y')
        $r = Invoke-CodeCli -Cli $fake -Arguments $argsIn
        Assert ($r.Code -eq 3) "Invoke-CodeCli returns the exit code ($($r.Code))"
        $got = $null
        try { $got = @(ConvertFrom-Json $r.Out.Trim() | ForEach-Object { $_ }) } catch { }
        Assert ($null -ne $got -and (($got -join '|') -ceq ($argsIn -join '|'))) "Invoke-CodeCli passes the arguments through the batch file ($($r.Out.Trim()))"
    }
    else { Write-Host 'skip: no node.exe on the PATH, Invoke-CodeCli not tested' }

    # --- New-Vsix
    $ext = Join-Path $root 'extension'
    $pkg = [IO.File]::ReadAllText((Join-Path $ext 'package.json'), $utf8) | ConvertFrom-Json
    $vsix = Join-Path $tmp 'out dir\getout.vsix'
    New-Vsix -SourceDir $ext -OutFile $vsix
    New-Vsix -SourceDir $ext -OutFile $vsix
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($vsix)
    try {
        $names = @($z.Entries | ForEach-Object { $_.FullName })
        foreach ($n in 'extension.vsixmanifest', '[Content_Types].xml', 'extension/package.json', 'extension/extension.js') {
            Assert ($names -ccontains $n) "vsix contains $n"
        }
        Assert (@($names | Where-Object { $_.Contains('\') }).Count -eq 0) 'vsix entry names use forward slashes'
        $extFiles = @([IO.Directory]::GetFiles($ext, '*', [IO.SearchOption]::AllDirectories))
        foreach ($f in $extFiles) {
            $n = 'extension/' + $f.Substring($ext.Length + 1).Replace('\', '/')
            Assert ($names -ccontains $n) "vsix contains $n"
        }
        Assert ($names.Count -eq ($extFiles.Count + 2)) 'vsix holds nothing else'
        function Read-Entry($name) {
            $s = $z.GetEntry($name).Open()
            try { $ms = New-Object IO.MemoryStream; $s.CopyTo($ms); return , $ms.ToArray() } finally { $s.Dispose() }
        }
        Assert (Same-Bytes ([IO.File]::ReadAllBytes((Join-Path $ext 'package.json'))) (Read-Entry 'extension/package.json')) 'package.json copied as is'
        [xml]$man = $utf8.GetString((Read-Entry 'extension.vsixmanifest'))
        $id = $man.PackageManifest.Metadata.Identity
        Assert (($id.Publisher + '.' + $id.Id) -ceq 'ceddup.getout') "manifest identity is ceddup.getout ($($id.Publisher).$($id.Id))"
        Assert ($id.Version -ceq [string]$pkg.version) "manifest version is the package.json version ($($id.Version))"
        Assert ($man.PackageManifest.Version -ceq '2.0.0') 'manifest format version 2.0.0'
        Assert ($man.PackageManifest.Installation.InstallationTarget.Id -ceq 'Microsoft.VisualStudio.Code') 'manifest targets VS Code'
        $asset = @($man.PackageManifest.Assets.Asset | Where-Object { $_.Type -ceq 'Microsoft.VisualStudio.Code.Manifest' })
        Assert ($asset.Count -eq 1 -and $asset[0].Path -ceq 'extension/package.json' -and $asset[0].Addressable -ceq 'true') 'manifest asset points to extension/package.json'
        Assert (-not $man.PackageManifest.Metadata.Description.InnerText.Contains('%')) 'manifest description is resolved from package.nls.json'
        [xml]$ct = $utf8.GetString((Read-Entry '[Content_Types].xml'))
        $defaults = @($ct.Types.Default | Where-Object { $_ } | ForEach-Object { $_.Extension.TrimStart('.').ToLowerInvariant() })
        $overrides = @($ct.Types.Override | Where-Object { $_ } | ForEach-Object { $_.PartName })
        foreach ($n in $names) {
            if ($n -ceq '[Content_Types].xml') { continue }
            $e = [IO.Path]::GetExtension($n).TrimStart('.').ToLowerInvariant()
            Assert (($e -and $defaults -contains $e) -or ($overrides -contains ('/' + $n))) "content type declared for $n"
        }
    }
    finally { $z.Dispose() }

    # --- exit only when run as a file: through iex inside a calling script, the caller goes on
    $code = [IO.File]::ReadAllText((Join-Path $root 'install.ps1')) -replace '(?m)^Main\r?$', '$script:ExitCode = 7'
    Assert ($code.Contains('$script:ExitCode = 7')) 'test setup: Main call replaced'
    [IO.File]::WriteAllText((Join-Path $tmp 'code.txt'), $code, $utf8)
    $caller = Join-Path $tmp 'caller.ps1'
    $codePath = (Join-Path $tmp 'code.txt').Replace("'", "''")
    [IO.File]::WriteAllText($caller, "[IO.File]::ReadAllText('$codePath') | iex`r`n'iex exit ' + `$LASTEXITCODE`r`n'caller continues'`r`nexit 0`r`n", $utf8)
    $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $caller)
    $callerCode = $LASTEXITCODE
    Assert ($callerCode -eq 0 -and ($out -contains 'caller continues') -and ($out -contains 'iex exit 7')) "iex in a calling script: exit code in LASTEXITCODE, caller goes on ($callerCode, $($out -join ' / '))"

    # --- Invoke-Uninstall without a VS Code CLI, in a fake profile
    $savedProfile = $env:USERPROFILE; $savedCodex = $env:CODEX_HOME
    $savedStateDir = $StateDir; $savedCli = $CodeCli
    try {
        $env:USERPROFILE = Join-Path $tmp 'home'; $env:CODEX_HOME = $null
        New-Item -ItemType Directory -Path $env:USERPROFILE | Out-Null
        $CodeCli = Join-Path $tmp 'absent.cmd'
        $StateDir = Join-Path $tmp 'state-v2'
        New-Item -ItemType Directory -Path $StateDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $StateDir 'state.json'), '{"version":"2.0.0","lang":"en","agents":[]}', $utf8)
        $rc = Invoke-Uninstall 6> $null
        Assert ($rc -eq 1) "uninstall without CLI after an install: exit 1, extension unchecked ($rc)"
        $StateDir = Join-Path $tmp 'state-none'
        $rc = Invoke-Uninstall 6> $null
        Assert ($rc -eq 0) "uninstall without CLI and nothing installed: exit 0 ($rc)"
    }
    finally {
        $env:USERPROFILE = $savedProfile; $env:CODEX_HOME = $savedCodex
        $StateDir = $savedStateDir; $CodeCli = $savedCli
    }

    # --- ASCII only
    foreach ($f in 'install.ps1', 'uninstall.ps1') {
        $fp = Join-Path $root $f
        Assert (Test-Path -LiteralPath $fp) "$f exists"
        if (Test-Path -LiteralPath $fp) {
            $bad = @([IO.File]::ReadAllBytes($fp) | Where-Object { $_ -gt 0x7F }).Count
            Assert ($bad -eq 0) "$f is pure ASCII"
        }
    }
}
catch {
    $script:failures++
    Write-Host "ERROR: $($_.Exception.Message)"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

if ($script:failures -gt 0) { Write-Host "$($script:failures) failure(s)"; exit 1 }
Write-Host 'install tests: all passed'
exit 0
