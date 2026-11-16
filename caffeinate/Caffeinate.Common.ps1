$script:CaffeinateRoot = Join-Path $env:LOCALAPPDATA "Caffeinate"
$script:CaffeinateStatePath = Join-Path $script:CaffeinateRoot "caffeinate.json"
$script:CaffeinateLogPath = Join-Path $script:CaffeinateRoot "caffeinate.log"
$script:CaffeinateLockPath = Join-Path $script:CaffeinateRoot "caffeinate.lock"

function Initialize-CaffeinateStorage {
    New-Item -ItemType Directory -Path $script:CaffeinateRoot -Force | Out-Null
    if (-not (Test-Path $script:CaffeinateLogPath)) {
        New-Item -ItemType File -Path $script:CaffeinateLogPath -Force | Out-Null
    }
}

function Get-CaffeinateState {
    if (-not (Test-Path $script:CaffeinateStatePath)) {
        return $null
    }

    try {
        return Get-Content -Raw -Path $script:CaffeinateStatePath | ConvertFrom-Json
    }
    catch {
        throw "Unable to read Caffeinate state: $($_.Exception.Message)"
    }
}

function Set-CaffeinateState {
    param([hashtable]$State)

    $temporaryPath = "$script:CaffeinateStatePath.$PID.tmp"
    $State | ConvertTo-Json | Set-Content -Path $temporaryPath -Encoding UTF8 -ErrorAction Stop
    Move-Item -Path $temporaryPath -Destination $script:CaffeinateStatePath -Force
}

function Acquire-CaffeinateLock {
    Initialize-CaffeinateStorage
    $lock = [System.IO.File]::Open(
        $script:CaffeinateLockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    return $lock
}

function Release-CaffeinateLock {
    param([System.IO.FileStream]$Lock)

    if ($null -ne $Lock) {
        $Lock.Dispose()
    }
}

function Remove-CaffeinateState {
    Remove-Item -Path $script:CaffeinateStatePath -Force -ErrorAction SilentlyContinue
}

function Get-CaffeinateProcess {
    param([psobject]$State)

    if ($null -eq $State -or $State.Pid -notmatch '^\d+$') {
        return $null
    }

    $process = Get-Process -Id ([int]$State.Pid) -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $null
    }

    if ($process.ProcessName -ne "pwsh" -or
        $State.ProcessStartTimeTicks -ne $process.StartTime.ToUniversalTime().Ticks) {
        return $null
    }

    return $process
}

function Get-LastCaffeinateLogLine {
    if (-not (Test-Path $script:CaffeinateLogPath)) {
        return "(no log yet)"
    }

    $line = Get-Content -Path $script:CaffeinateLogPath -Tail 1 -ErrorAction SilentlyContinue
    if ($null -eq $line) {
        return "(log is empty)"
    }
    return [string]$line
}
