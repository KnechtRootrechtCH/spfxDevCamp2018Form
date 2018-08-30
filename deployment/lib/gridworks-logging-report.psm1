# -----------------------------------------------------------------------------
# Author: roland.oechslin@garaio.com
# -----------------------------------------------------------------------------

function Set-UploadDocuments {
    Param(
            [ValidateScript({If(Test-Path $_){$true}else{Throw "Invalid path given: $_"}})] 
            $LocalFolderLocation,
            [String] 
            $siteUrl,
            [String]
            $documentLibraryName,
            [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection]
            $Connection
    )
    Process{
           
            $path = $LocalFolderLocation.TrimEnd('\')
    
            Write-Host "Provided Site :"$siteUrl -ForegroundColor Green
            Write-Host "Provided Path :"$path -ForegroundColor Green
            Write-Host "Provided Document Library name :"$documentLibraryName -ForegroundColor Green
    
              try{
    
                    $file = Get-ChildItem -Path $path -Recurse
                    $i = 0;
                    Write-Host "Uploading documents to Site.." -ForegroundColor Cyan
                    (dir $path -Recurse) | %{
                        try{
                            $i++
                            if($_.GetType().Name -eq "FileInfo"){
                              $SPFolderName =  $documentLibraryName + $_.DirectoryName.Substring($path.Length);
                              $status = "Uploading Files :'" + $_.Name + "' to Location :" + $SPFolderName
                              Write-Progress -activity "Uploading Documents.." -status $status -PercentComplete (($i / $file.length)  * 100)
                              $te = Add-PnPFile -Path $_.FullName -Folder $SPFolderName -Connection $Connection
                             }          
                            }
                        catch{
                        }
                     }
                }
                catch{
                 Write-Host $_.Exception.Message -ForegroundColor Red
                }
    
      }
}


function Write-LogToSharepointOnline {
    param (
        [Parameter(Mandatory=$true)]
        [string] $listUrl,
        [string] $siteUrl,
        [string] $documentLibraryName,
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $connection,        
        [string] $folder = "Log",
        [string] $format = "html",
        [string] $fileName = "",
        [bool] $dateFolder = $true
    )

    Suspend-LogTranscript {

        Write-Step "Generating log content"

        $logFolder = "$deployment_dir\logs"

        Set-UploadDocuments -LocalFolderLocation $logFolder -siteUrl $siteUrl -documentLibraryName $documentLibraryName -Connection $connection
    }
}

function Write-LogToFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )

    Suspend-LogTranscript {
        Write-Step "Writing $($messages.Count) lines to log file '$filePath'"
        Write-LogHeader $filePath
        $lines = Get-LogLines
        $lines | Out-File -Append -filepath $filePath
        Write-Step "Done"
    }
}

function Write-LogToCsv {
    param (
        [Parameter(Mandatory=$true)]
        [string] $filePath
    )

    Suspend-LogTranscript {
        $messages = $global:gw_log.entries
        $messages | ForEach-Object {
            $_.Message = $_.Message -replace ';',':' -replace '"',"'"
        }

        Write-Step "Writing $($messages.Count) rows to csv file '$filePath'"
        $messages | Select-Object Timestamp, Source, Message | Export-Csv $filePath -Delimiter ";" -Encoding "Unicode" -NoTypeInformation
        Write-Step "Done"
    }
}
function Write-LogToHtml {
    param (
        [Parameter(Mandatory=$true)]
        [string] $filePath,
        [string] $applicationTitle,
        [string] $applicationSubTitle,
        [string] $title,
        [int] $startIndex = 0,
        [int] $endIndex = -1
    )

    Suspend-LogTranscript {
        Write-Step "Generating html log content"
        $content = Format-HtmlLogContent $applicationTitle $applicationSubTitle $title $startIndex $endIndex

        Write-Step "Writing report to file '$filePath'"
        $content | Out-File -filepath $filePath
    }
}

function Get-LogLines {
    $messages = $global:gw_log.entries
    $lines = @()
    $messages | ForEach-Object {
        lines += $_.Log
    }
    return lines;
}

function Get-LogIndex {
    return $global:gw_log.entries.Count
}

function Format-HtmlLogContent {
    param (
        [string] $applicationTitle = "InstallTool",
        [string] $applicationSubTitle = $environment,
        [string] $title,
        [int] $startIndex = 0,
        [int] $endIndex = -1
    )

    if([string]::IsNullOrEmpty($title)){
        $title = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
    }

    $entries = $global:gw_log.entries

    if($endIndex -lt 0){
        $endIndex = $entries.Count
    }

    $rows = @()

    Write-SubStep "Formating $($entries.Count) log messages as html"
    for ($i = $startIndex; $i -lt $endIndex; $i++) {
        $entry = $entries[$i]
        $rows += Format-LogEntryAsHtml $entry
    }

    Write-SubStep "Loading template"
    $content = Get-HtmlTaskReportTemplate

    Write-SubStep "Filling content into template"
    $content = $content.Replace("[Content]", $rows)
    $content = $content.Replace("[ApplicationTitle]", $applicationTitle)
    $content = $content.Replace("[PortalSubtitle]", $applicationSubTitle)
    $content = $content.Replace("[Title]", $title)

    $content = $content.Replace("[StartTime]", $global:gw_log.startTime)
    $now = Get-Date -format "dd.MM.yyyy HH:mm:ss"
    $content = $content.Replace("[EndTime]", $now)
    $content = $content.Replace("[CurrentServer]", $environment)

    return $content
}

function Format-LogEntryAsHtml {
    param (
        [Parameter(Mandatory=$true)]
        [object] $logEntry
    )

    $message = Format-LogMessageAsHtml $logEntry
    $action = Get-LogMessageAction $logEntry
    $rowClass = Get-LogMessageRowClass $logEntry
    $time = $logEntry.Timestamp.ToString()
    $source = $logEntry.Source.ToLower()

    $row = "
    <tr class=""main $rowClass"">
        <td class=""action"">$action</td>
        <td class=""time"">$time</td>
        <td class=""source"">$source</td>
        <td class=""message""><pre class=""mono"">$message</pre></td>
    </tr>";

    return $row
}

function Format-LogMessageAsHtml {
    param (
        [Parameter(Mandatory=$true)]
        [object] $logEntry
    )

    $allColors = @("-Black","-DarkBlue","-DarkGreen","-DarkCyan","-DarkRed","-DarkMagenta","-DarkYellow","-Gray", "-DarkGray","-Blue","-Green","-Cyan","-Red","-Magenta","-Yellow","-White")
    $aliases = @{ "-Success" = "Green"; "-Highlight" = "Magenta"; "-Error" = "Red"; "-Warning" = "Yellow"; "-Info" = "Gray"; "-Normal" = "Gray"; "-Quiet" = "DarkGray"; }

    $text = ""
    $sofar = ""
    $color = $aliases["-Normal"].TrimStart("-")

    if($logEntry.Source -like "SUBSUBSTEP"){
        $text += "<font color=""blue"">      * </font>"
    } elseif($logEntry.Source -like "SUBSTEP"){
        $text += "<font color=""blue"">    * </font>"
    } elseif($logEntry.Source -like "STEP"){
        $text += "<font color=""blue"">* </font>"
    } elseif($logEntry.Source -like "SUCCESS"){
        $color = "Green"
    }

    foreach($t in $logEntry.Arguments) {
        if ($t -eq "-nonewline") {
            #$text += ""
        } elseif ($t -eq "-foreground" -or $t -eq "-normal") {
            if (-not ([string]::IsNullOrEmpty($sofar))) {
                $text += "<font color=""$color"">$sofar</font>"
            }
            $color = $aliases["-Normal"].TrimStart("-")
            $sofar = ""

        } elseif ($allColors -contains $t -or $aliases.Keys -contains $t) {
            if ($sofar) {
                $text += "<font color=""$color"">$sofar</font>"
            }

            if ($aliases.Keys -contains $t) {
                $color = $aliases[$t].TrimStart("-")
            } else {
                $color = $t.substring(1).TrimStart("-")
            }

            if ($color -eq "Normal") {
                $color = $aliases["-Normal"].TrimStart("-")
            }
            $sofar = ""

        } else {
            $sofar += "$t "
        }
    }

    # last bit done special
    $text += "<font color=""$color"">$sofar</font>"

    return $text;
}

function Get-LogMessageAction {
    param (
        [Parameter(Mandatory=$true)]
        [object] $logEntry
    )

    $rowClassMapping = @{
        "UPDATED" = "updated";
        "ADDED" = "added";
        "DELETED" = "deleted";
        "SUCCESS" = "success";
    }

    $source = $logEntry.Source
    $rowClass = $rowClassMapping[$source]
    return $rowClass
}

function Get-LogMessageRowClass {
    param (
        [Parameter(Mandatory=$true)]
        [object] $logEntry
    )

    $rowClassMapping = @{
        "STEP" = "information";
        "SUBSTEP" = "information";
        "SUBSUBSTEP" = "information";
        "COLOR" = "information";
        "DEBUG" = "verbose";
        "INFO" = "information";
        "WARNING" = "warning";
        "ERROR" = "error";
        "SUCCESS" = "information";
        "TIMER-START" = "information";
        "TIMER-END" = "information";
        "UPDATED" = "updated";
        "ADDED" = "added";
        "DELETED" = "deleted";
    }

    $source = $logEntry.Source
    $rowClass = $rowClassMapping[$source]
    if ([string]::IsNullOrEmpty($rowClass)) {
        $rowClass = "information"
    }
    return $rowClass
}

function Get-HtmlTaskReportTemplate {
    $templatePath = "$lib_dir\Templates\TaskReport.html"
    $templateContent = Get-Content $templatePath
    return $templateContent
}

Export-ModuleMember -Function *
