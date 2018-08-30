# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------
if($global:gw_log -eq $null){
    $global:gw_log = @{}
    $global:gw_log.level = 1 # debug=0 | info = 1 | warning = 2 | error = 3
    $global:gw_log.suspended = $false
    $global:gw_log.startTime = $null
    $global:gw_log.timePadding = 19
    $global:gw_log.sourcePadding = 11
    $global:gw_log.transcriptActive = $false
    $global:gw_log.transcriptStartTime = $null
    $global:gw_log.transcriptPath = $null
    $global:gw_log.createHtmlReport = $false
}

function Write-Step {
    Write-LogMessage "STEP" $args
    $a = New-Object System.Collections.ArrayList
    @("-Blue", "*", "-Gray") |% { $a.Add($_) | Out-Null }
    $args |% {
        if ($_ -eq "-Normal") {
            $_ = "-Gray"
        }
        $a.Add($_) | Out-Null
    }

    if ($host.ui.rawui.CursorPosition.X -ne 0) { Write-Host "" }

    $log_indent = 0
    Write-ColorTokens $a | Out-Null
}

function Write-SubStep {
    Write-LogMessage "SUBSTEP" $args
    $a = New-Object System.Collections.ArrayList
    @("-DarkRed", "*", "-DarkGray") |% { $a.Add($_) | Out-Null }
    $args |% {
        if ($_ -eq "-Normal") {
            $_ = "-DarkGray"
        }
        $a.Add($_) | Out-Null
    }

    if ($host.ui.rawui.CursorPosition.X -ne 0) { Write-Host "" }

    $log_indent = 2
    Write-ColorTokens $a | Out-Null
    $log_indent = 0
}

function Write-SubSubStep {
    Write-LogMessage "SUBSUBSTEP" $args
    $a = New-Object System.Collections.ArrayList
    @("-DarkYellow", "*", "-DarkGray") |% { $a.Add($_) | Out-Null }
    $args |% {
        if ($_ -eq "-Normal") {
            $_ = "-DarkGray"
        }
        $a.Add($_) | Out-Null
    }

    if ($host.ui.rawui.CursorPosition.X -ne 0) { Write-Host "" }

    $log_indent = 4
    Write-ColorTokens $a | Out-Null
    $log_indent = 0
}


function Write-Color {
    Write-LogMessage "COLOR" $args
    # DO NOT SPECIFY param(...)
    #    we parse colors ourselves.
    Write-ColorTokens $args | Out-Null
}

function Write-ColorTokens {
    param(
        $tokens
    )
    $args

    $allColors = @("-Black","-DarkBlue","-DarkGreen","-DarkCyan","-DarkRed","-DarkMagenta","-DarkYellow","-Gray", "-DarkGray","-Blue","-Green","-Cyan","-Red","-Magenta","-Yellow","-White")
    $aliases = @{ "-Success" = "Green"; "-Highlight" = "Magenta"; "-Error" = "Red"; "-Warning" = "Yellow"; "-Info" = "Gray"; "-Normal" = "Gray"; "-Quiet" = "DarkGray"; }

    $foreground = (Get-Host).UI.RawUI.ForegroundColor
    $background = (Get-Host).UI.RawUI.BackgroundColor

    [bool]$nonewline = $false
    $color = $aliases["-Normal"]
    $sofar = "" + (" " * $log_indent)

    foreach($t in $tokens) {
        if ($t -eq "-nonewline") {
            $nonewline = $true

        } elseif ($t -eq "-foreground" -or $t -eq "-normal") {
            if ($sofar) {
                Write-Host $sofar -foreground $color -nonewline
            }
            $color = $foreground
            $sofar = ""

        } elseif ($allColors -contains $t -or $aliases.Keys -contains $t) {
            if ($sofar) {
                Write-Host $sofar -foreground $color -nonewline
            }

            if ($aliases.Keys -contains $t) {
                $color = $aliases[$t]
            } else {
                $color = $t.substring(1)
            }

            if ($color -eq "Normal") {
                $color = $foreground
            }
            $sofar = ""

        } else {
            $sofar += "$t "
        }
    }

    # last bit done special
    if (!$nonewline) {
        Write-Host $sofar -foreground $color
    } elseif ($sofar) {
        Write-Host $sofar -foreground $color -nonewline
    }
}

function Write-Debug {
    Write-LogMessage "DEBUG" $args
    if ($global:gw_log.level -le 0) {
        $a = New-Object System.Collections.ArrayList
        @("-Quiet", "DEBUG: ") |% { $a.Add($_) | Out-Null }
        $args |% {
            if ($_ -eq "-Normal") {
                $_ = "-Quiet"
            }
            $a.Add($_) | Out-Null
        }

        if ($host.ui.rawui.CursorPosition.X -ne 0) { Write-Host "" }
        Write-ColorTokens $a
    }
}

function Write-Info {
    Write-LogMessage "INFO" $args
    if ($global:gw_log.level -le 1) {
        $a = New-Object System.Collections.ArrayList
        @("-Info") |% { $a.Add($_) | Out-Null }
        $args |% {
            if ($_ -eq "-Normal") {
                $_ = "-Info"
            }
            $a.Add($_) | Out-Null
        }

        if ($host.ui.rawui.CursorPosition.X -ne 0) { Write-Host "" }
        Write-ColorTokens $a | Out-Null
    }
}

function Write-Warning {
    Write-LogMessage "WARNING" $args
    if ($global:gw_log.level -le 2) {
        $a = New-Object System.Collections.ArrayList
        @("-Warning", "  WARN:") |% { $a.Add($_) | Out-Null }
        $args |% {
            if ($_ -eq "-Normal") {
                $_ = "-Warning"
            }
            $a.Add($_) | Out-Null
        }

        if ($host.ui.rawui.CursorPosition.X -ne 0) { Write-Host "" }
        Write-ColorTokens $a | Out-Null
    }
}

function Write-Error {
    Write-LogMessage "ERROR" $args
    if ($global:gw_log.level -le 3) {
        $a = New-Object System.Collections.ArrayList
        @("-Error", "  ERROR:") |% { $a.Add($_) | Out-Null }
        $args |% {
            if ($_ -eq "-Normal") {
                $_ = "-Error"
            }
            $a.Add($_) | Out-Null
        }

        if ($host.ui.rawui.CursorPosition.X -ne 0) { Write-Host "" }
        Write-ColorTokens $a | Out-Null
    }
}

function Write-Success {
    Write-LogMessage "SUCCESS" $args
    $a = New-Object System.Collections.ArrayList
    @("-Success") |% { $a.Add($_) | Out-Null }
    $args |% {
        if ($_ -eq "-Normal") {
            $_ = "-Success"
        }
        $a.Add($_) | Out-Null
    }

    Write-ColorTokens $a | Out-Null
}

function Write-Added {
    Write-LogMessage "ADDED" $args
    $a = New-Object System.Collections.ArrayList
    @("-Green") |% { $a.Add($_) | Out-Null }
    $args |% {
        if ($_ -eq "-Normal") {
            $_ = "-Green"
        }
        $a.Add($_) | Out-Null
    }

    Write-ColorTokens $a | Out-Null
}

function Write-Deleted {
    Write-LogMessage "DELETED" $args
    $a = New-Object System.Collections.ArrayList
    @("-DarkRed") |% { $a.Add($_) | Out-Null }
    $args |% {
        if ($_ -eq "-Normal") {
            $_ = "-DarkRed"
        }
        $a.Add($_) | Out-Null
    }

    Write-ColorTokens $a | Out-Null
}

function Write-Updated {
    Write-LogMessage "UPDATED" $args
    $a = New-Object System.Collections.ArrayList
    @("-DarkCyan") |% { $a.Add($_) | Out-Null }
    $args |% {
        if ($_ -eq "-Normal") {
            $_ = "-DarkCyan"
        }
        $a.Add($_) | Out-Null
    }

    Write-ColorTokens $a | Out-Null
}

function Write-Exception {
    param(
        $ex,
        $methodName
    )

    if ($methodName) {
        Suspend-LogTranscript {
            Write-Error "An Exception occurred in $methodName. Full exception stack trace is:"
        }
    } else {
        Suspend-LogTranscript {
            Write-Error "An Exception occurred. Full exception stack trace is:"
        }
    }

    while ($ex) {
        $msg = $ex | Format-List -force | Out-String
        Suspend-LogTranscript {
            Write-Error "`n" + $msg.Trim() + "`n----------------------------------------------------------------------------"
        }
        $trace += "`n" + $msg.Trim() + "`n----------------------------------------------------------------------------"
        $ex = $ex.InnerException
    }

    if ($methodName) {
        Write-LogMessage "ERROR" "An Exception occurred in $methodName. Full exception stack trace is: `n$trace"
    } else {
        Write-LogMessage "ERROR" "An Exception occurred. Full exception stack trace is: `n$trace"
    }
}

function Get-ErrorRecord($ErrorRecord=$Error[0]) {
    $result = $ErrorRecord.InvocationInfo.PositionMessage
    $ex = $ErrorRecord.Exception
    for ($i = 0; $ex; $i++, ($ex = $ex.InnerException)) {
        $result += ("`n{0}{1} -> {2}" -f (" " * $i), $ex.GetType().FullName, $ex.Message)
    }
    return $result
}

function Format-ElapsedTime($ts) {
    $elapsedTime = ""

    if ( $ts.Hours -gt 0 ) {
        $elapsedTime = [string]::Format( "{0}h {1}min {2}sec {3}ms.", $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds );
    } elseif ( $ts.Minutes -gt 0 ) {
        $elapsedTime = [string]::Format( "{0}min {1}sec {2}ms.", $ts.Minutes, $ts.Seconds, $ts.Milliseconds );
    } else {
        $elapsedTime = [string]::Format( "{0}sec {1}ms", $ts.Seconds, $ts.Milliseconds );
    }
    if ($ts.Hours -eq 0 -and $ts.Minutes -eq 0 -and $ts.Seconds -eq 0) {
        $elapsedTime = [string]::Format("{0}ms", $ts.Milliseconds);
    }
    if ($ts.Milliseconds -eq 0) {
        $elapsedTime = [string]::Format("{0}ms", $ts.TotalMilliseconds);
    }

    return $elapsedTime
}

# see http://stackoverflow.com/a/19316226 for inspiration
function Write-TimedBlock( $title, $block ) {

    $startMessage = "Executing '{0}' @ {1}" -f $title, (Get-Date -f "HH:mm:ss")
    Write-LogMessage "TIMER-START" $startMessage

    Write-Host
    Write-Host $startMessage -f white -b blue
    Write-Host

    $sw = [Diagnostics.Stopwatch]::StartNew()
    &$block
    $sw.Stop()
    $time = $sw.Elapsed

    $formatTime = Format-ElapsedTime $time
    Write-LogMessage "TIMER-END" "'$title' took $formatTime"
    Suspend-LogTranscript {
        Write-Info -DarkGray "`r`n-->" -Highlight $title -DarkGray "took" -Highlight $formatTime
    }
}


function Write-LogHeader {
    param (
        [string] $filePath
    )

    $timestamp = "TIME".PadRight($global:gw_log.timePadding)
    $source = "SOURCE".PadRight($global:gw_log.sourcePadding)
    $header = "$timestamp`t`t`t$source`t`t`tMESSAGE"

    $header | Out-File -Append -filepath $filePath
}

function Write-LogMessage {
    param (
        [string]$source,
        [array]$arguments
    )

    if($global:gw_log.suspended) {
        return;
    }

    [DateTime]$time = Get-Date

    if(-not $global:gw_log.entries) {
        Clear-Log
    }

    $severity = -1
    if ($source -like "SUCCESS") {
        $severity = 0
    } elseif ($source -like "WARNING") {
        $severity = 1
    } elseif ($source -like "ERROR") {
        $severity = 2
    }

    $logEntry = New-OBject PSObject
    $logEntry | Add-Member -Type NoteProperty –Name Timestamp –Value $time
    $logEntry | Add-Member -Type NoteProperty –Name Source –Value $source
    $logEntry | Add-Member -Type NoteProperty –Name Severity –Value $severity
    $logEntry | Add-Member -Type NoteProperty –Name Arguments –Value $arguments

    $message = Format-LogMessageAsText $source $arguments
    $logEntry | Add-Member -Type NoteProperty –Name Message –Value $message

    $log = Format-LogLineAsText $logEntry $global:gw_log.timePadding $global:gw_log.sourcePadding
    $logEntry | Add-Member -Type NoteProperty –Name Log –Value $log

    $global:gw_log.entries += $logEntry;

    if ($global:gw_log.transcriptActive) {
        $logEntry.Log | Out-File -Append -filepath $global:gw_log.transcriptPath
    }
}

function Format-LogLineAsText {
    param (
        [object] $logEntry,
        [int] $timePadding,
        [int] $sourcePadding
    )

    $timestamp = $logEntry.Timestamp.ToString().PadRight($timePadding)
    $source = $logEntry.Source.PadRight($sourcePadding)
    $message = $logEntry.Message

    return "$timestamp`t`t`t$source`t`t`t$message"
}

function Format-LogMessageAsText {
    param (
        [string] $source,
        [array] $arguments
    )

    $text = ""
    if($source -like "SUBSUBSTEP"){
        $text += "    * "
    } elseif($source -like "SUBSTEP"){
        $text += "  * "
    } elseif($source -like "STEP"){
        $text += "* "
    }

    $allColors = @("-Black","-DarkBlue","-DarkGreen","-DarkCyan","-DarkRed","-DarkMagenta","-DarkYellow","-Gray", "-DarkGray","-Blue","-Green","-Cyan","-Red","-Magenta","-Yellow","-White")
    $aliases = @{ "-Success" = "Green"; "-Highlight" = "Magenta"; "-Error" = "Red"; "-Warning" = "Yellow"; "-Info" = "Gray"; "-Normal" = "Gray"; "-Quiet" = "DarkGray"; }

    foreach($t in $arguments) {
        if ($t -eq "-nonewline") {
            #$text += ""
        } elseif ($t -eq "-foreground" -or $t -eq "-normal") {
            #$text += ""
        } elseif ($allColors -contains $t -or $aliases.Keys -contains $t) {
            #$text += ""
        } else {
            $text += "$t "
        }
    }

    return $text
}

function Suspend-LogTranscript {
    param(
        $block
    )
    $global:gw_log.suspended = $true;
    &$block
    $global:gw_log.suspended = $false;
}

function Start-LogTranscript {
    param (
        [string] $filePath
    )

    $global:gw_log.transcriptActive = $true
    $global:gw_log.transcriptStartTime = Get-Date -format "dd.MM.yyyy HH:mm:ss"
    $global:gw_log.transcriptPath = $filePath
    Write-LogHeader $filePath
}

function Stop-LogTranscript {
    $global:gw_log.transcriptActive = $false
}
function Clear-Log {
    $global:gw_log.startTime = Get-Date -format "dd.MM.yyyy HH:mm:ss"
    $global:gw_log.entries = @();
}

function Get-LogStartTime {
    return $global:gw_log.startTime
}
function Get-LogSeverity {
    $entries = $global:gw_log.entries
    $severity = -1

    $entries | ForEach-Object {
        $current = [int]$_.Severity
        if($current -gt $severity) {
            $severity = $current
        }
    }

    return $severity
}

function Get-LogStatus {
    $severity = Get-LogSeverity

    $status = "None"
    if ($severity -eq 0) {
        $status = "Success"
    } elseif ($severity -eq 1) {
        $status = "Warning"
    } elseif ($severity -gt 1) {
        $status = "Error"
    }
    return $status
}

Export-ModuleMember -Function *
