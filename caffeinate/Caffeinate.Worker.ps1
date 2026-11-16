[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$Minutes,
    [Parameter(Mandatory)]
    [string]$LogPath,
    [Parameter(Mandatory)]
    [string]$StatePath,
    [Parameter(Mandatory)]
    [string]$WorkerPath
)

. "$PSScriptRoot\Caffeinate.Common.ps1"

function Write-WorkerLog {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -Path $LogPath -Value $line
    Write-Verbose $Message
}

function MoveMouse {
    param([int]$XOffset, [int]$YOffset)
    $pos = [System.Windows.Forms.Cursor]::Position
    [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($pos.X + $XOffset, $pos.Y + $YOffset)
    Write-WorkerLog "Mouse moved by $XOffset, $YOffset"
}

function SendKey {
    param([string]$Key)
    $wShell.SendKeys($Key)
    Write-WorkerLog "$Key sent"
}

function RandomizedSleep {
    $duration = Get-Random -Minimum 20 -Maximum 40
    Write-WorkerLog "Sleeping for $duration seconds"
    Start-Sleep -Seconds $duration
}

try {
    Initialize-CaffeinateStorage
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $wShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
    $start = Get-Date
    $end = $start.AddMinutes($Minutes)
    Set-CaffeinateState -State @{
        Pid = $PID
        WorkerPath = $WorkerPath
        ProcessStartTimeTicks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
        StartTime = $start.ToString("o")
        EndTime = $end.ToString("o")
    }
    Write-WorkerLog "Caffeinating until $end"

    while ($true) {
        # Re-read the state file so that an external "extend" updates our end time.
        $currentState = Get-CaffeinateState
        if ($null -ne $currentState -and $currentState.EndTime) {
            $parsedEnd = [datetime]$currentState.EndTime
            if ($parsedEnd -ne $end) {
                $end = $parsedEnd
                Write-WorkerLog "End time updated to $end"
            }
        }
        if ((Get-Date) -ge $end) {
            break
        }

        MoveMouse -XOffset (Get-Random -Minimum -20 -Maximum 20) -YOffset (Get-Random -Minimum -20 -Maximum 20)
        RandomizedSleep
        SendKey -Key "{F$(Get-Random -Minimum 13 -Maximum 17)}"
        RandomizedSleep
    }

    Write-WorkerLog "Caffeination ended"
}
catch {
    try {
        Initialize-CaffeinateStorage
        Add-Content -Path $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ERROR: $($_.Exception.Message)"
    }
    catch {
        Write-Error "Unable to write worker failure to '$LogPath': $($_.Exception.Message)"
    }
    throw
}
finally {
    Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
}
