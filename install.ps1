# getout installer: installs the getout VS Code extension and writes the getout rule for the
# coding agents. Pure ASCII on purpose (a BOM breaks "irm | iex"): localized texts live in
# messages.json and rules/rule.*.md (UTF-8, no BOM). Windows PowerShell 5.1 compatible.
param(
    [ValidateSet('', 'en', 'fr')][string]$Lang = '',
    # '' = agents from state.json if any, else ask when interactive, else none;
    # 'none'; or a list among claude,codex,gemini (becomes the exact set).
    [string]$Agents = '',
    [switch]$Yes,
    [string]$Ref = 'main',
    [switch]$Uninstall,
    # Path of the VS Code command line (bin\code.cmd); default: code on the PATH, else the user
    # or the machine install of VS Code.
    [string]$CodeCli = '',
    # Passed to code --extensions-dir and --user-data-dir (tests only).
    [string]$ExtensionsDir = '',
    [string]$UserDataDir = '',
    # Holds state.json only. The default folder is also the install folder of getout 1.
    [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'getout'),
    [switch]$LibraryOnly
)

$script:BeginMarker = '<!-- getout:begin -->'
$script:EndMarker = '<!-- getout:end -->'
$script:ExtensionId = 'ceddup.getout'
$script:Messages = $null
$script:UiLang = 'en'
$script:ExitCode = 1
# Empty when run through "irm | iex" or a script block: sources are then downloaded,
# and the exit code goes to $LASTEXITCODE instead of "exit" (which would close the console, or
# end the calling script). $MyInvocation.MyCommand.Path is the caller's path under iex.
$script:ScriptDir = $PSScriptRoot
$script:FromFile = [bool]$PSScriptRoot
$script:RepoArchive = 'https://github.com/ceddup/getout/archive/{0}.zip'

# ---------------------------------------------------------------- messages

# The English texts of the uninstall messages (same as messages.json), for an uninstall that can
# neither read nor download messages.json: "irm | iex" offline.
$script:FallbackMessages = @{
    v1_installed      = '{0} holds getout 1 (local web server): uninstall it first with its own script (powershell -ExecutionPolicy Bypass -File "{0}\uninstall.ps1"), then run this script again.'
    agent_removed     = 'getout rule removed for {0}: {1}'
    extension_removed = 'VS Code extension ceddup.getout removed.'
    left_extension    = 'the VS Code extension ceddup.getout'
    uninstall_no_code = 'VS Code command line not found: the extension was not checked. If VS Code is installed elsewhere, run this script again with -CodeCli.'
    uninstall_done    = 'getout is uninstalled.'
    uninstall_left    = 'Could not remove: {0}'
}

function Import-Messages {
    param([Parameter(Mandatory)][string]$Dir)
    $path = Join-Path $Dir 'messages.json'
    $json = [IO.File]::ReadAllText($path, (New-Object Text.UTF8Encoding $false))
    $script:Messages = ConvertFrom-Json $json
}

# messages.json from the first of $Dirs that has one, else from the installer's source (the
# repository archive). If that fails too, Get-Message uses $script:FallbackMessages.
function Import-MessagesFrom {
    param([string[]]$Dirs)
    foreach ($d in $Dirs) {
        if ($d -and [IO.File]::Exists([IO.Path]::Combine($d, 'messages.json'))) { Import-Messages -Dir $d; return }
    }
    try {
        $src = Get-SourceDir
        try { Import-Messages -Dir $src.Dir }
        finally {
            if ($src.Temp) { Remove-Item -LiteralPath $src.Temp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    catch { }
}

function Get-Message {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Lang,
        [object[]]$Values = @()
    )
    $text = $null
    if ($null -ne $script:Messages) {
        foreach ($l in @($Lang, 'en')) {
            $section = $script:Messages.PSObject.Properties[$l]
            if ($section) {
                $prop = $section.Value.PSObject.Properties[$Key]
                if ($prop) { $text = [string]$prop.Value; break }
            }
        }
    }
    if ($null -eq $text -and $script:FallbackMessages.ContainsKey($Key)) { $text = $script:FallbackMessages[$Key] }
    if ($null -eq $text) { return $Key }
    if ($Values.Count -gt 0) { return [string]::Format($text, $Values) }
    return $text
}

# ---------------------------------------------------------------- text files

# Reads a text file keeping what is needed to write it back unchanged:
# encoding, BOM bytes. A missing file is empty UTF-8 without BOM.
function Read-TextFile {
    param([string]$Path)
    $utf8 = New-Object Text.UTF8Encoding $false
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Text = ''; Enc = $utf8; Bom = [byte[]]@() }
    }
    $b = [IO.File]::ReadAllBytes($Path)
    $bomLen = 0
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        $enc = $utf8; $bomLen = 3
    }
    elseif ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) {
        $enc = New-Object Text.UnicodeEncoding($false, $false); $bomLen = 2
    }
    elseif ($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) {
        $enc = New-Object Text.UnicodeEncoding($true, $false); $bomLen = 2
    }
    else {
        $enc = $utf8
        try {
            $strict = New-Object Text.UTF8Encoding($false, $true)
            [void]$strict.GetString($b)
        }
        catch { $enc = [Text.Encoding]::GetEncoding(1252) }
    }
    $bom = [byte[]]@()
    if ($bomLen -gt 0) { $bom = [byte[]]$b[0..($bomLen - 1)] }
    $text = $enc.GetString($b, $bomLen, $b.Length - $bomLen)
    return [pscustomobject]@{ Text = $text; Enc = $enc; Bom = $bom }
}

function Write-TextFile {
    param([string]$Path, $File, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    $body = $File.Enc.GetBytes($Text)
    [IO.File]::WriteAllBytes($Path, [byte[]]($File.Bom + $body))
}

function Get-Eol {
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    if ($Text.Contains("`n")) { return "`n" }
    return "`r`n"
}

# ---------------------------------------------------------------- agent rule

function Get-RuleText {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$Lang
    )
    $path = Join-Path (Join-Path $Dir 'rules') "rule.$Lang.md"
    $body = [IO.File]::ReadAllText($path, (New-Object Text.UTF8Encoding $false))
    $body = ($body -replace "`r?`n", "`n").Trim("`n")
    return $script:BeginMarker + "`n" + $body + "`n" + $script:EndMarker
}

# A block holds no other begin marker: a stray begin marker earlier in the file (user text, a
# truncated block) is left alone with the text after it. Used by Set-RuleBlock and Remove-RuleBlock.
function Get-BlockRegex {
    $b = [regex]::Escape($script:BeginMarker)
    return New-Object Text.RegularExpressions.Regex(
        ('(?s)' + $b + '(?:(?!' + $b + ').)*?' + [regex]::Escape($script:EndMarker)))
}

function Set-RuleBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Block
    )
    $f = Read-TextFile $Path
    $text = $f.Text
    $eol = Get-Eol $text
    $blk = ($Block -replace "`r?`n", "`n").Replace("`n", $eol)
    $m = (Get-BlockRegex).Match($text)
    if ($m.Success) {
        $new = $text.Substring(0, $m.Index) + $blk + $text.Substring($m.Index + $m.Length)
    }
    elseif ($text.Length -eq 0) {
        $new = $blk + $eol
    }
    else {
        $base = $text
        if (-not $base.EndsWith("`n", [StringComparison]::Ordinal)) { $base += $eol }
        $new = $base + $eol + $blk + $eol
    }
    Write-TextFile $Path $f $new
}

function Remove-RuleBlock {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $f = Read-TextFile $Path
    $text = $f.Text
    $m = (Get-BlockRegex).Match($text)
    if (-not $m.Success) { return $false }
    $eol = Get-Eol $text
    $before = $text.Substring(0, $m.Index)
    $after = $text.Substring($m.Index + $m.Length)
    # Ordinal: a culture comparison (ICU, PowerShell 7) can match "`n" inside "`r`n".
    if ($after.StartsWith($eol, [StringComparison]::Ordinal)) { $after = $after.Substring($eol.Length) }
    if ($before.EndsWith($eol + $eol, [StringComparison]::Ordinal)) {
        $before = $before.Substring(0, $before.Length - $eol.Length)
    }
    Write-TextFile $Path $f ($before + $after)
    return $true
}

# ---------------------------------------------------------------- console and files

function Write-Msg {
    param([string]$Key, [object[]]$Values = @(), [string]$Color = '')
    $text = Get-Message -Key $Key -Lang $script:UiLang -Values $Values
    if ($Color) { Write-Host $text -ForegroundColor $Color } else { Write-Host $text }
}

# Asks a yes/no question (Enter = yes). Only called in an interactive session.
function Read-YesNo {
    param([string]$Question)
    try { $answer = Read-Host ($Question + (Get-Message -Key 'yes_no' -Lang $script:UiLang)) }
    catch { return $false }
    if ($null -eq $answer) { return $false }
    $answer = $answer.Trim()
    return ($answer -eq '' -or $answer -match '^[yYoO]')
}

function Get-UiLang {
    param($State)
    if ($Lang) { return $Lang }
    if ($State -and @('en', 'fr') -contains [string]$State.lang) { return [string]$State.lang }
    if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'fr') { return 'fr' }
    return 'en'
}

function Resolve-FullPath {
    param([string]$Path)
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    return $full
}

function Read-JsonFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $null }
    try { return ConvertFrom-Json ([IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding $false))) }
    catch { return $null }
}

function Write-JsonFile {
    param([string]$Path, $Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 5
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}

# A state.json written by getout 1 (local web server), whose install folder is the default StateDir.
function Test-V1State {
    param($State)
    if (-not $State) { return $false }
    return [bool]($State.PSObject.Properties['nodeExe'] -or $State.PSObject.Properties['port'])
}

# Removes state.json, then the folder if nothing else is in it: the default StateDir can also hold
# getout 1, whose files are never deleted here.
function Remove-StateFile {
    param([string]$Dir)
    $path = [IO.Path]::Combine($Dir, 'state.json')
    if ([IO.File]::Exists($path)) { Remove-Item -LiteralPath $path -Force }
    if ([IO.Directory]::Exists($Dir) -and @([IO.Directory]::GetFileSystemEntries($Dir)).Count -eq 0) {
        try { [IO.Directory]::Delete($Dir) } catch { }
    }
}

function Enable-Tls12 {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
}

function Save-Download {
    param([string]$Url, [string]$OutFile)
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    return $OutFile
}

function New-TempDir {
    param([string]$Prefix)
    $dir = [IO.Path]::Combine([IO.Path]::GetTempPath(), $Prefix + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    return $dir
}

function Test-SourceDir {
    param([string]$Dir)
    return [IO.File]::Exists([IO.Path]::Combine($Dir, 'extension', 'package.json'))
}

# The clone holding this script, or the repository archive (-Ref) extracted in a temp folder.
function Get-SourceDir {
    $d = $script:ScriptDir
    if ($d -and (Test-SourceDir $d)) {
        return [pscustomobject]@{ Dir = $d; Temp = $null }
    }
    Enable-Tls12
    $tmp = New-TempDir 'getout-src-'
    try {
        $url = [string]::Format($script:RepoArchive, $Ref)
        Write-Host "getout: downloading $url"
        $zip = Save-Download $url ([IO.Path]::Combine($tmp, 'getout.zip'))
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $x = [IO.Path]::Combine($tmp, 'x')
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $x)
        $dir = @(Get-ChildItem -LiteralPath $x -Directory | Where-Object { Test-SourceDir $_.FullName })
        if ($dir.Count -eq 0) { throw "extension\package.json not found in $url" }
        return [pscustomobject]@{ Dir = $dir[0].FullName; Temp = $tmp }
    }
    catch {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

# ---------------------------------------------------------------- VSIX

# "%key%" placeholders of package.json resolved from package.nls.json.
function Resolve-NlsText {
    param([string]$Text, $Nls)
    $m = [regex]::Match($Text, '^%(.+)%$')
    if ($m.Success -and $Nls -and $Nls.PSObject.Properties[$m.Groups[1].Value]) {
        return [string]$Nls.PSObject.Properties[$m.Groups[1].Value].Value
    }
    return $Text
}

function Add-ZipText {
    param($Zip, [string]$Name, [string]$Text)
    $bytes = (New-Object Text.UTF8Encoding $false).GetBytes($Text)
    $s = $Zip.CreateEntry($Name).Open()
    try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
}

# Builds the VSIX of the extension folder: [Content_Types].xml, extension.vsixmanifest and every
# file of the folder under extension/ (what vsce would package, without vsce).
function New-Vsix {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$OutFile
    )
    $src = Resolve-FullPath $SourceDir
    $pkg = Read-JsonFile ([IO.Path]::Combine($src, 'package.json'))
    if (-not $pkg -or -not $pkg.name -or -not $pkg.publisher -or -not $pkg.version) {
        throw "invalid or missing package.json in $src"
    }
    $nls = Read-JsonFile ([IO.Path]::Combine($src, 'package.nls.json'))
    $displayName = Resolve-NlsText ([string]$pkg.displayName) $nls
    if (-not $displayName) { $displayName = [string]$pkg.name }
    $description = Resolve-NlsText ([string]$pkg.description) $nls

    $files = @([IO.Directory]::GetFiles($src, '*', [IO.SearchOption]::AllDirectories) | Sort-Object)
    $entries = @($files | ForEach-Object { 'extension/' + $_.Substring($src.Length + 1).Replace('\', '/') })

    $known = @{
        json = 'application/json'; js = 'application/javascript'; md = 'text/markdown'; txt = 'text/plain'
        vsixmanifest = 'text/xml'; xml = 'text/xml'; png = 'image/png'; svg = 'image/svg+xml'
    }
    $esc = { param($s) [Security.SecurityElement]::Escape([string]$s) }
    $types = New-Object Collections.Generic.List[string]
    $types.Add('vsixmanifest')
    $ct = '<?xml version="1.0" encoding="utf-8"?>' + "`r`n" +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' + "`r`n"
    $overrides = ''
    foreach ($e in $entries) {
        $x = [IO.Path]::GetExtension($e).TrimStart('.').ToLowerInvariant()
        if (-not $x) {
            $part = '/' + (($e.Split([char]'/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
            $overrides += '  <Override PartName="' + (& $esc $part) + '" ContentType="text/plain"/>' + "`r`n"
        }
        elseif (-not $types.Contains($x)) { $types.Add($x) }
    }
    foreach ($x in $types) {
        $type = $known[$x]
        if (-not $type) { $type = 'application/octet-stream' }
        $ct += '  <Default Extension=".' + (& $esc $x) + '" ContentType="' + $type + '"/>' + "`r`n"
    }
    $ct += $overrides + '</Types>' + "`r`n"

    $manifest = '<?xml version="1.0" encoding="utf-8"?>' + "`r`n" +
        '<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">' + "`r`n" +
        '  <Metadata>' + "`r`n" +
        '    <Identity Language="en-US" Id="' + (& $esc $pkg.name) + '" Version="' + (& $esc $pkg.version) +
        '" Publisher="' + (& $esc $pkg.publisher) + '"/>' + "`r`n" +
        '    <DisplayName>' + (& $esc $displayName) + '</DisplayName>' + "`r`n" +
        '    <Description xml:space="preserve">' + (& $esc $description) + '</Description>' + "`r`n" +
        '  </Metadata>' + "`r`n" +
        '  <Installation>' + "`r`n" +
        '    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>' + "`r`n" +
        '  </Installation>' + "`r`n" +
        '  <Dependencies/>' + "`r`n" +
        '  <Assets>' + "`r`n" +
        '    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>' + "`r`n" +
        '  </Assets>' + "`r`n" +
        '</PackageManifest>' + "`r`n"

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $out = Resolve-FullPath $OutFile
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out))
    $fs = [IO.File]::Open($out, [IO.FileMode]::Create)
    try {
        $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        try {
            Add-ZipText $zip '[Content_Types].xml' $ct
            Add-ZipText $zip 'extension.vsixmanifest' $manifest
            for ($i = 0; $i -lt $files.Count; $i++) {
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $files[$i], $entries[$i])
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $fs.Dispose() }
}

# ---------------------------------------------------------------- VS Code command line

# Quotes one argument for CreateProcess (CommandLineToArgvW rules) and for cmd.exe: an argument
# with blanks or cmd.exe special characters is quoted, backslashes before a quote are doubled.
function ConvertTo-ProcessArg {
    param([string]$Arg)
    if ($Arg.Length -gt 0 -and $Arg -notmatch '[\s"&|<>^(),;=]') { return $Arg }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq [char]'\') { $bs++; continue }
        if ($ch -eq [char]'"') { [void]$sb.Append([char]'\', 2 * $bs + 1) }
        elseif ($bs -gt 0) { [void]$sb.Append([char]'\', $bs) }
        $bs = 0
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append([char]'\', 2 * $bs) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Runs the VS Code command line and returns { Code, Out, Err }. code.cmd is a batch file: it runs
# through cmd.exe /d /s /c "...", which keeps the quotes of the inner command line as they are.
function Invoke-CodeCli {
    param(
        [Parameter(Mandatory)][string]$Cli,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 300
    )
    $line = (@($Arguments) | ForEach-Object { ConvertTo-ProcessArg $_ }) -join ' '
    $utf8 = New-Object Text.UTF8Encoding $false
    $psi = New-Object Diagnostics.ProcessStartInfo
    $ext = [IO.Path]::GetExtension($Cli)
    if ($ext -ieq '.cmd' -or $ext -ieq '.bat') {
        $psi.FileName = [IO.Path]::Combine([Environment]::SystemDirectory, 'cmd.exe')
        $psi.Arguments = '/d /s /c "' + (ConvertTo-ProcessArg $Cli) + ' ' + $line + '"'
    }
    else {
        $psi.FileName = $Cli
        $psi.Arguments = $line
    }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEndAsync()
        $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ Code = -1; Out = ''; Err = "timeout after $TimeoutSec s" }
        }
        [void]$out.Wait(10000)
        [void]$err.Wait(10000)
        return [pscustomobject]@{
            Code = $p.ExitCode
            Out  = $(if ($out.IsCompleted) { $out.Result } else { '' })
            Err  = $(if ($err.IsCompleted) { $err.Result } else { '' })
        }
    }
    finally { $p.Dispose() }
}

# The VS Code command line: -CodeCli (as given; $null if missing), else code on the PATH, else the
# user install, else the machine install of VS Code.
function Find-CodeCli {
    param([string]$Override = $CodeCli)
    if ($Override) {
        $full = Resolve-FullPath $Override
        if ([IO.File]::Exists($full)) { return $full }
        return $null
    }
    foreach ($c in @(Get-Command code -CommandType Application -ErrorAction SilentlyContinue)) {
        if (@('.cmd', '.bat', '.exe') -contains [IO.Path]::GetExtension($c.Path).ToLowerInvariant()) { return $c.Path }
    }
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'Microsoft VS Code', 'bin', 'code.cmd') }
    if ($env:ProgramFiles) { $candidates += [IO.Path]::Combine($env:ProgramFiles, 'Microsoft VS Code', 'bin', 'code.cmd') }
    foreach ($c in $candidates) { if ([IO.File]::Exists($c)) { return $c } }
    return $null
}

# --extensions-dir and --user-data-dir, when given (tests).
function Get-CodeDirArgs {
    $a = @()
    if ($ExtensionsDir) { $a += @('--extensions-dir', (Resolve-FullPath $ExtensionsDir)) }
    if ($UserDataDir) { $a += @('--user-data-dir', (Resolve-FullPath $UserDataDir)) }
    return $a
}

# The version of ceddup.getout that VS Code lists, $null if it is not listed, '?' if VS Code
# could not list its extensions (neither installed nor removed for sure).
function Get-ExtensionVersion {
    param([string]$Cli)
    $r = Invoke-CodeCli -Cli $Cli -Arguments (@('--list-extensions', '--show-versions') + @(Get-CodeDirArgs))
    if ($r.Code -ne 0) { return '?' }
    $rx = '^' + [regex]::Escape($script:ExtensionId) + '@(\S+)$'
    foreach ($line in ($r.Out -split "`r?`n")) {
        $m = [regex]::Match($line.Trim(), $rx, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return $null
}

# ---------------------------------------------------------------- agents

function Get-AgentDefinition {
    $codexDir = $env:CODEX_HOME
    if (-not $codexDir) { $codexDir = [IO.Path]::Combine($env:USERPROFILE, '.codex') }
    $defs = @(
        @('claude', 'Claude Code', [IO.Path]::Combine($env:USERPROFILE, '.claude'), 'CLAUDE.md'),
        @('codex', 'Codex', $codexDir, 'AGENTS.md'),
        @('gemini', 'Gemini CLI', [IO.Path]::Combine($env:USERPROFILE, '.gemini'), 'GEMINI.md')
    )
    foreach ($d in $defs) {
        [pscustomobject]@{ Name = $d[0]; Label = $d[1]; Dir = $d[2]; Path = [IO.Path]::Combine($d[2], $d[3]) }
    }
}

function Get-AgentLabel {
    param([string]$Name)
    $d = @(Get-AgentDefinition | Where-Object { $_.Name -eq $Name })
    if ($d.Count -gt 0) { return $d[0].Label }
    return $Name
}

# -Agents value: '' (previous install, else ask if interactive, else none), 'ask', 'none' or a list.
function ConvertFrom-AgentsParam {
    param([string]$Text)
    $t = $Text.Trim().ToLowerInvariant()
    if ($t -eq '') { return [pscustomobject]@{ Mode = 'default'; Names = @() } }
    if ($t -eq 'ask') { return [pscustomobject]@{ Mode = 'ask'; Names = @() } }
    if ($t -eq 'none') { return [pscustomobject]@{ Mode = 'list'; Names = @() } }
    $names = @()
    foreach ($n in ($t -split '[\s,;]+')) {
        if (-not $n) { continue }
        if (@('claude', 'codex', 'gemini') -notcontains $n) {
            throw (Get-Message -Key 'agent_unknown' -Lang $script:UiLang -Values @($n))
        }
        if ($names -notcontains $n) { $names += $n }
    }
    return [pscustomobject]@{ Mode = 'list'; Names = $names }
}

function Request-Agent {
    $found = @(Get-AgentDefinition | Where-Object { [IO.Directory]::Exists($_.Dir) })
    if ($found.Count -eq 0) { Write-Msg 'agent_none_detected'; return @() }
    $names = @()
    foreach ($d in $found) {
        if (Read-YesNo (Get-Message -Key 'agent_ask' -Lang $script:UiLang -Values @($d.Label, $d.Path))) {
            $names += $d.Name
        }
    }
    return $names
}

function Resolve-AgentName {
    param($Selection, $PrevState, [bool]$Interactive)
    if ($Selection.Mode -eq 'list') { return $Selection.Names }
    if ($Interactive -and ($Selection.Mode -eq 'ask' -or -not $PrevState)) { return Request-Agent }
    if ($PrevState) { return @(@($PrevState.agents) | Where-Object { $_ } | ForEach-Object { [string]$_.name }) }
    return @()
}

# Removes the rule block; a file that getout created and that is now empty is deleted.
function Remove-AgentRule {
    param($Entry)
    $file = [string]$Entry.file
    $removed = Remove-RuleBlock -Path $file
    if ($Entry.created -and [IO.File]::Exists($file) -and (Read-TextFile $file).Text.Trim().Length -eq 0) {
        Remove-Item -LiteralPath $file -Force
    }
    if ($removed) { Write-Msg 'agent_removed' @((Get-AgentLabel $Entry.name), $file) }
}

# Writes the rule for exactly the agents in $Names; returns the state entries.
function Set-AgentRule {
    param([string[]]$Names, $Previous, [string]$Block)
    $defs = @(Get-AgentDefinition)
    foreach ($p in $Previous) {
        $kept = @($defs | Where-Object { $Names -contains $_.Name -and $_.Name -eq $p.name -and $_.Path -ieq $p.file })
        if ($kept.Count -eq 0) { Remove-AgentRule $p }
    }
    $entries = @()
    foreach ($d in $defs) {
        if ($Names -notcontains $d.Name) { continue }
        if (-not [IO.Directory]::Exists($d.Dir)) { Write-Msg 'agent_not_detected' @($d.Label, $d.Dir) 'Yellow'; continue }
        $existed = [IO.File]::Exists($d.Path)
        $before = @($Previous | Where-Object { $_.name -eq $d.Name -and $_.file -ieq $d.Path -and $_.created })
        Set-RuleBlock -Path $d.Path -Block $Block
        $entries += [pscustomobject][ordered]@{
            name = $d.Name; file = $d.Path; created = ((-not $existed) -or $before.Count -gt 0)
        }
        Write-Msg 'agent_added' @($d.Label, $d.Path)
    }
    return $entries
}

# ---------------------------------------------------------------- verdict

function Write-Verdict {
    param($Checks, [string]$Version, $Agents)
    $failed = @($Checks | Where-Object { -not $_.Ok })
    Write-Host ''
    if ($failed.Count -eq 0) { Write-Msg 'verdict_ok' @($Version) 'Green' }
    foreach ($c in $Checks) {
        $mark = if ($c.Ok) { 'check_ok' } else { 'check_failed' }
        $line = '  [' + (Get-Message -Key $mark -Lang $script:UiLang) + '] ' +
            (Get-Message -Key $c.Key -Lang $script:UiLang -Values $c.Values)
        if ($c.Ok) { Write-Host $line } else { Write-Host $line -ForegroundColor Red }
    }
    $list = @($Agents | ForEach-Object { (Get-AgentLabel $_.name) + ' (' + $_.file + ')' })
    if ($list.Count -eq 0) { $list = @(Get-Message -Key 'agents_none' -Lang $script:UiLang) }
    Write-Msg 'verdict_agents' @($list -join ', ')
    if ($failed.Count -gt 0) { Write-Msg 'verdict_failed' @($failed.Count) 'Red' }
    else { Write-Msg 'verdict_reload' }
    return $failed.Count
}

# ---------------------------------------------------------------- install / uninstall

function Invoke-Install {
    $interactive = (-not $Yes) -and (-not [Console]::IsInputRedirected)
    $dir = Resolve-FullPath $StateDir
    $statePath = [IO.Path]::Combine($dir, 'state.json')
    $prevState = Read-JsonFile $statePath
    $script:UiLang = Get-UiLang $prevState
    $src = Get-SourceDir
    $vsixDir = $null
    try {
        Import-Messages -Dir $src.Dir
        if (Test-V1State $prevState) { Write-Msg 'v1_installed' @($dir) 'Red'; return 1 }
        $selection = ConvertFrom-AgentsParam $Agents
        $cli = Find-CodeCli
        if (-not $cli) {
            if ($CodeCli) { Write-Msg 'code_cli_missing' @($CodeCli) 'Red' } else { Write-Msg 'code_missing' @() 'Red' }
            return 1
        }
        Write-Msg 'code_found' @($cli)
        $names = @(Resolve-AgentName $selection $prevState $interactive)

        # 1. Extension
        $extDir = [IO.Path]::Combine($src.Dir, 'extension')
        $version = [string](Read-JsonFile ([IO.Path]::Combine($extDir, 'package.json'))).version
        $vsixDir = New-TempDir 'getout-vsix-'
        $vsix = [IO.Path]::Combine($vsixDir, "getout-$version.vsix")
        New-Vsix -SourceDir $extDir -OutFile $vsix
        Write-Msg 'extension_installing' @($version)
        $r = Invoke-CodeCli -Cli $cli -Arguments (@('--install-extension', $vsix, '--force') + @(Get-CodeDirArgs))
        if ($r.Code -ne 0) {
            Write-Msg 'extension_install_failed' @($r.Code, ($r.Out + ' ' + $r.Err).Trim()) 'Red'
        }

        # 2. state.json, then the agent rules
        [void][IO.Directory]::CreateDirectory($dir)
        $prevAgents = @()
        if ($prevState) { $prevAgents = @(@($prevState.agents) | Where-Object { $_ }) }
        $state = [ordered]@{ version = $version; lang = $script:UiLang; agents = $prevAgents }
        Write-JsonFile $statePath $state
        $block = Get-RuleText -Dir $src.Dir -Lang $script:UiLang
        $state.agents = @(Set-AgentRule $names $prevAgents $block)
        Write-JsonFile $statePath $state

        # 3. Verification and verdict
        $installed = Get-ExtensionVersion $cli
        $checks = @([pscustomobject]@{ Ok = ($installed -ceq $version); Key = 'check_extension'; Values = @($version) })
        $failed = Write-Verdict $checks $version $state.agents
        if ($failed -gt 0) { return 1 }
        return 0
    }
    finally {
        if ($src.Temp) { Remove-Item -LiteralPath $src.Temp -Recurse -Force -ErrorAction SilentlyContinue }
        if ($vsixDir) { Remove-Item -LiteralPath $vsixDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Uninstall {
    $dir = Resolve-FullPath $StateDir
    $statePath = [IO.Path]::Combine($dir, 'state.json')
    $state = Read-JsonFile $statePath
    $script:UiLang = Get-UiLang $state
    Import-MessagesFrom @($script:ScriptDir)
    # getout 1 has its own uninstall: its files, rule blocks and settings are left to it.
    if (Test-V1State $state) { Write-Msg 'v1_installed' @($dir) 'Red'; return 1 }

    $left = @()
    $cli = Find-CodeCli
    if ($cli) {
        $r = Invoke-CodeCli -Cli $cli -Arguments (@('--uninstall-extension', $script:ExtensionId) + @(Get-CodeDirArgs))
        if (Get-ExtensionVersion $cli) { $left += (Get-Message -Key 'left_extension' -Lang $script:UiLang) }
        elseif ($r.Code -eq 0) { Write-Msg 'extension_removed' }
    }
    else {
        Write-Msg 'uninstall_no_code' @() 'Yellow'
        # A recorded install means the extension may still be there: no green verdict.
        if ($state) { $left += (Get-Message -Key 'left_extension' -Lang $script:UiLang) }
    }

    # Rule blocks: files recorded in state.json, plus the detected agents' files.
    $entries = @()
    if ($state) { $entries = @(@($state.agents) | Where-Object { $_ }) }
    foreach ($d in @(Get-AgentDefinition)) {
        if (@($entries | Where-Object { $_.file -ieq $d.Path }).Count -eq 0) {
            $entries += [pscustomobject]@{ name = $d.Name; file = $d.Path; created = $false }
        }
    }
    foreach ($e in $entries) { Remove-AgentRule $e }

    Remove-StateFile $dir
    if ([IO.File]::Exists($statePath)) { $left += $statePath }
    if ($left.Count -gt 0) { Write-Msg 'uninstall_left' @($left -join ', ') 'Red'; return 1 }
    Write-Msg 'uninstall_done' @() 'Green'
    return 0
}

function Main {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    # Output read by an agent: UTF-8, not the OEM code page (accents). The console may be shared
    # with the caller, so its encoding is restored at the end. Interactive consoles are left alone.
    $savedEncoding = $null
    if ([Console]::IsOutputRedirected) {
        try {
            $current = [Console]::OutputEncoding
            [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
            $savedEncoding = $current
        }
        catch { }
    }
    try {
        if ($Uninstall) { $code = Invoke-Uninstall } else { $code = Invoke-Install }
        $last = @($code)[-1]
        if ($null -eq $last) { $last = 1 }
        $script:ExitCode = [int]$last
    }
    catch {
        $script:ExitCode = 1
        $m = $_.Exception.Message
        if ($script:Messages) { Write-Msg 'error' @($m) 'Red' } else { Write-Host "getout: $m" -ForegroundColor Red }
    }
    finally {
        if ($savedEncoding) { try { [Console]::OutputEncoding = $savedEncoding } catch { } }
    }
}

if ($LibraryOnly) { return }
Main
if ($script:FromFile) { exit $script:ExitCode }
$global:LASTEXITCODE = $script:ExitCode
