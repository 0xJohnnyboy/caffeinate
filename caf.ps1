[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "status", "logs", "stop", "extend")]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$scriptRoot = Join-Path $PSScriptRoot "caffeinate"
. (Join-Path $scriptRoot "Caffeinate.Common.ps1")

# Parse the remaining args ourselves (rather than binding $Minutes positionally),
# since callers invoke this script through caf.cmd which just forwards raw args and
# flags like "--force" can appear before or after the minutes value.
$Force = $false
$Minutes = $null
if ($Rest) {
    foreach ($arg in $Rest) {
        if ($arg -match '^--?force$') {
            $Force = $true
        }
        elseif ($null -eq $Minutes -and $arg -match '^\d+$') {
            $Minutes = $arg
        }
    }
}
$MinutesProvided = $null -ne $Minutes
if ($null -eq $Minutes) {
    $Minutes = "300"
}

function Format-EndTime {
    param([datetime]$EndTime)
    return $EndTime.ToString("yyyy-MM-dd HH:mm")
}

function Confirm-ExtendPrompt {
    param([psobject]$State, [System.Diagnostics.Process]$Running)

    Write-Output "Caffeinate is already running (PID $($Running.Id)) until $($State.EndTime)."
    $answer = Read-Host "Would you like to extend it? [Y/n]"
    if ($answer -match '^(n|no)$') {
        throw "Caffeinate is already running (PID $($Running.Id))."
    }

    $minutesAnswer = Read-Host "How many minutes?"
    Extend-Caffeinate -DurationText $minutesAnswer
}

function Extend-Caffeinate {
    param([string]$DurationText)

    if ($DurationText -notmatch '^\d+$' -or [int64]$DurationText -le 0 -or [int64]$DurationText -gt [int]::MaxValue) {
        throw "Duration must be a positive integer number of minutes."
    }

    Initialize-CaffeinateStorage
    $lock = $null
    try {
        $lock = Acquire-CaffeinateLock
        $state = Get-CaffeinateState
        if ($null -eq $state) {
            throw "Caffeinate is not running."
        }

        $running = Get-CaffeinateProcess -State $state
        if ($null -eq $running) {
            Remove-CaffeinateState
            throw "Caffeinate is not running."
        }

        $duration = [int]$DurationText
        $currentEnd = [datetime]$state.EndTime
        $newEnd = $currentEnd.AddMinutes($duration)

        Set-CaffeinateState -State @{
            Pid = $state.Pid
            WorkerPath = $state.WorkerPath
            ProcessStartTimeTicks = $state.ProcessStartTimeTicks
            StartTime = $state.StartTime
            EndTime = $newEnd.ToString("o")
        }

        Write-Output "Caffeinating for $duration more minutes, ending at $(Format-EndTime $newEnd)."
    }
    finally {
        Release-CaffeinateLock -Lock $lock
    }
}

function Start-Caffeinate {
    param([string]$DurationText, [switch]$Force)

    if ($DurationText -notmatch '^\d+$' -or [int64]$DurationText -le 0 -or [int64]$DurationText -gt [int]::MaxValue) {
        throw "Duration must be a positive integer number of minutes."
    }

    Initialize-CaffeinateStorage
    $lock = $null
    try {
        $lock = Acquire-CaffeinateLock
        $state = Get-CaffeinateState
        if ($null -ne $state) {
            $running = Get-CaffeinateProcess -State $state
            if ($null -ne $running) {
                if ($Force) {
                    Stop-Process -Id $running.Id -Force
                    Remove-CaffeinateState
                }
                else {
                    Release-CaffeinateLock -Lock $lock
                    $lock = $null
                    Confirm-ExtendPrompt -State $state -Running $running
                    return
                }
            }
            else {
                Remove-CaffeinateState
            }
        }

        $duration = [int]$DurationText

        $workerPath = Join-Path $scriptRoot "Caffeinate.Worker.ps1"
        $arguments = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$workerPath`"",
            "-Minutes", $duration, "-LogPath", "`"$CaffeinateLogPath`"",
            "-StatePath", "`"$CaffeinateStatePath`"", "-WorkerPath", "`"$workerPath`"", "-Verbose"
        )
        $worker = Start-Process -FilePath "pwsh.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru

        $deadline = (Get-Date).AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 100
            $state = Get-CaffeinateState
        if ($null -ne $state) {
            $running = Get-CaffeinateProcess -State $state
            if ($null -ne $running) {
                Write-Output "Caffeinate started (PID $($running.Id)) until $($state.EndTime)."
                return
            }
        }

        $worker.Refresh()
        if ($worker.HasExited) {
            throw "Caffeinate worker exited during startup. Check $CaffeinateLogPath."
        }
    } while ((Get-Date) -lt $deadline)

    throw "Caffeinate worker did not confirm startup within 5 seconds. Check $CaffeinateLogPath."
    }
    finally {
        Release-CaffeinateLock -Lock $lock
    }
}

function Show-CaffeinateStatus {
    $state = Get-CaffeinateState
    if ($null -eq $state) {
        Write-Output "Caffeinate is not running."
        return
    }

    $process = Get-CaffeinateProcess -State $state
    if ($null -eq $process) {
        Write-Output "Caffeinate state is stale (PID $($state.Pid) is not the expected worker)."
        return
    }

    Write-Output "State: running"
    Write-Output "PID: $($process.Id)"
    Write-Output "Started: $($state.StartTime)"
    Write-Output "Ends: $($state.EndTime)"
    Write-Output "Last log: $(Get-LastCaffeinateLogLine)"
}

function Show-CaffeinateLogs {
    Initialize-CaffeinateStorage
    Get-Content -Path $CaffeinateLogPath -Tail 20 -Wait
}

function Stop-Caffeinate {
    $state = Get-CaffeinateState
    if ($null -eq $state) {
        Write-Output "Caffeinate is not running."
        return
    }

    $process = Get-CaffeinateProcess -State $state
    if ($null -eq $process) {
        throw "Refusing to stop PID $($state.Pid): it is not the expected Caffeinate worker."
    }

    Stop-Process -Id $process.Id -Force
    Remove-CaffeinateState
    Write-Output "Caffeinate stopped (PID $($process.Id))."
}

switch ($Command) {
    "start" { Start-Caffeinate -DurationText $Minutes -Force:$Force }
    "extend" {
        if (-not $MinutesProvided) {
            throw "Usage: caf extend <minutes>"
        }
        Extend-Caffeinate -DurationText $Minutes
    }
    "status" { Show-CaffeinateStatus }
    "logs" { Show-CaffeinateLogs }
    "stop" { Stop-Caffeinate }
    default {
        Write-Output "Usage: caf start [minutes] [--force] | caf extend <minutes> | caf status | caf logs | caf stop"
        exit 2
    }
}
