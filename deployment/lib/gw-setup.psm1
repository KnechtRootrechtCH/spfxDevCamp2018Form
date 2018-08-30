# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------

function Get-UserCustomActions {
    $context = Get-PnPContext
    $customActions = $context.Site.UserCustomActions
    $context.Load($customActions)
    $context.ExecuteQuery()

    return $customActions;
}

function Remove-GwJavaScriptLink {
    param(
        [string] $name
    )

    $context = Get-PnPContext
    $actions = Get-UserCustomActions

    $matches = $actions
    if ($name) {
        $matches = $matches | Where-Object { $_.Name -eq $name }
    }

    $matches | ForEach-Object {
        $name = $_.Name
        Write-SubStep "Removing user custom action" -Highlight $name -Normal "..."

        $context = $_.Context
        $_.DeleteObject()
        $context.ExecuteQuery()
    }
}

function Add-GwJavaScriptLink {
    param(
        [string] $name,
        [string] $url,
        [string] $scope,
        [int] $sequence
    )

    $context = Get-PnPContext
    if ($context.Url.Contains(".sharepoint.com")) {
    } else {
        $i = $url.replace("%20", " ").ToLower().indexOf("style library")
        $url = "~SiteCollection/" + $url.substring($i)
    }

    Write-SubStep "Adding user custom action" -Highlight $name -normal "url" -Highlight $url -normal "..."
    $action = $context.Site.UserCustomActions.Add();
    $action.Location = "ScriptLink"
    $action.ScriptSrc = $url
    $action.Name = $name
    $action.Sequence = $Sequence

    $action.Update()
    $context.ExecuteQuery()
}

function Import-Styles {
     param (
        $app,
        $folder = $null,
        $listRelativeUrl = $null,
        $checkout = $false,
        $exclude = "",
        $include = "",
        $includeNewerThan = $null
    )

    Write-Step "Import-Styles"
    try {
        $ctx = Get-PnPContext
        $web = Get-PnPWeb
        $webUrl = $web.Url

        $assetsVersion = Get-ConfigVar $app "AssetsVersion"

        if (-not $localFolder) {
            $localFolder = "$content_dir/Style Library"
        }

        $localFolder = $localFolder.Replace("\", "/")
        $localFolderRelative = $localFolder.Replace("$content_dir".Replace("\", "/"), "");
        Write-Step "Checking local folder" -Highlight $localFolderRelative -Normal "..."
        if (-not (Test-Path $localFolder)) {
            Write-Error "Folder '$localFolder' does not exist."
            return
        }

        $basePath = $localFolder.Trim("/")
        if (-not $listRelativeUrl) {
            $listRelativeUrl = "Style Library/"
        }

        $list = Get-PnpList $listRelativeUrl
        $forceCheckout = $list.ForceCheckout -eq $true
        Write-Step "List has ForceCheckout" -Highlight $forceCheckout.ToString() -Normal "..."
        if ($forceCheckout) {
            Write-Step "Disabling" -Highlight "ForceCheckout" -Normal "on list..."
            $list.ForceCheckout = $false
            $list.Update()
            $list.Context.ExecuteQuery();
        }

        $hashExists = (Get-PnPField -List $list | Where-Object { $_.InternalName -eq "gwHash" }).Count
        if (-not $hashExists) {
            $field = Add-PnPField -list $list -InternalName "gwHash" -Type "Note" -DisplayName "Hash" -AddToDefaultView
        }

        $existingHashes = @{}
        $listItems = $list.GetItems([Microsoft.SharePoint.Client.CamlQuery]::CreateAllItemsQuery())
        $ctx.load($listItems)
        $ctx.executeQuery()
        foreach ($listItem in $listItems) {
            $id = $listItem.ID
            $url = $listItem["FileRef"]
            $index = $url.indexOf($assetsVersion) + $assetsVersion.length
            $url = $url.substring($index);
            $hash = $listItem["gwHash"]
            #Write-Host "$id - $url - $hash"
            if ($hash) {
                $existingHashes[$url] = $hash
            }
        }

        $listRootFolderServerRelativeUrl = "$($web.ServerRelativeUrl)/$($listRelativeUrl)"
        Write-Step "Importing" -Highlight $localFolderRelative -Normal "to" -Highlight "$listRootFolderServerRelativeUrl" -Normal "..."

        $files = @( Get-ChildItem $localFolder -recurse | Where-Object { !($_.PSIsContainer) })
        $files = $files | Sort-Object FullName
        $count = $files.Count

        Write-SubStep "Found" -Highlight $count -Normal "files ..."

        if ($exclude -ne "") {
            # $exclude = "$exclude".replace("\", "/")
            Write-SubStep "Applying exclude filter" -Highlight $exclude -Normal "..."
            $files = $files | Where-Object { $_.FullName.Replace("\", "/") -notmatch $exclude }
            Write-SubStep "New count is" -Highlight ($files.Count) -Normal "files (Removed: $($count-$files.Count)) ..."
        }

        if ($include -ne "") {
            # $include = "$include".replace("\", "/")
            Write-SubStep "Applying include filter" -Highlight $include -Normal "..."

            $files = $files | Where-Object { $_.FullName.Replace("\", "/") -match $include }
            Write-SubStep "New count is" -Highlight ($files.Count) -Normal "files (Removed: $($count-$files.Count)) ..."
        }

        if ($includeNewerThan -ne $null) {
            [DateTime]$filter = $includeNewerThan
            $timeFormat = "HH:mm:ss.fff tt";

            Write-SubStep "Applying include newer than" -Highlight $filter.ToString($timeFormat) -Normal "..."
            $files = $files | Where-Object {
                $filename = $_.FullName.Replace("\", "/").replace($basePath, ".")
                $modified = $_.LastWriteTime.ToLocalTime()
                $timespan = New-TimeSpan $modified $filter

                # files newer than 500ms are included.
                $diff = [long] $timespan.TotalMilliseconds
                $changed = $diff -lt 100
                #Write-Host "$($filename.PadRight(120, ' ')) $($modified.ToString($timeFormat)) $($diff)ms -> $changed"
                return $changed
            }
            Write-SubStep "New count is" -Highlight ($files.Count) -Normal "files (Removed: $($count-$files.Count))..."
        }

        $ordered = New-Object "System.Collections.ArrayList";
        $files | ForEach-Object {
            $file = $_

            $fileType = "";
            $fileExtension = $file.Extension.Trim('.')

            if (@("less", "css") -contains $fileExtension) {
                $fileType = "style";
                $order = 1;
            } elseif (@("ts", "js") -contains $fileExtension) {
                $fileType = "script";
                $order = 0;
            } elseif (@("map") -contains $fileExtension) {
                $fileType = "sourcemap";
                $order = 2;
            } elseif (@("html", "aspx") -contains $fileExtension) {
                $fileType = "template";
                $order = 3;
            } elseif (@("png", "jpg", "gif", "ico") -contains $fileExtension) {
                $fileType = "image";
                $order = 4;
            } elseif (@("xml", "txt") -contains $fileExtension) {
                $fileType = "text";
                $order = 5;
            } elseif (@("eot", "woff", "woff2", "ttf", "otf", "svg") -contains $fileExtension) {
                $fileType = "webfont";
                $order = 6;
            } else {
                Write-SubStep -Warning "skipping file" -Highlight "$targetName" -Normal ", Extension" -Highlight "$fileExtension" -Normal "..." -Success "OK!"
            }

            $ordered.Add(@{
                "File" = $file;
                "Order" = $order;
                "FileType" = $fileType;
            }) | Out-Null;
        }

        $ordered | Sort-Object { $_.Order } | ForEach-Object {
            $file = $_.File
            $fileType = $_.FileType

            $fileName = $file.Name
            $fileExtension = $file.Extension.Trim('.')

            $targetName = $file.FullName.Replace("\", "/")
            $targetName = $targetName.Replace($basePath, "")
            $targetName = $targetName.Trim("/")
            $targetRelativePath = $targetName.Replace("GridWorks/", "/")

            $folderName = $targetName.Replace($file.Name, "").Trim("/")
            $folderName = $listRelativeUrl + $folderName
            $folderName = $folderName.replace("/GridWorks/", "/$assetsVersion/").replace("/GridWorks", "/$assetsVersion")

            # attempt to read the content of the file
            while ($true) {
                try {
                    $content = [System.IO.File]::ReadAllText($file.FullName)
                    break;
                } catch {
                    Write-SubSubStep "Cannot read $($file.FullName), Retrying..."
                    Start-Sleep -Seconds 1
                }
            }

            Write-SubStep "processing $fileType" -Highlight "$targetRelativePath" -normal "..." -nonewline

            $after = $before = $content
            $after = Start-ReplaceConfigVars $app $after

            if (@("aspx", "html") -contains $fileExtension) {
                $after = Start-ReplaceHtmlEntities $after
            }

            if ($before -cne $after) {
                # create temp file, but retain original name for add-spofile
                $tempFile = [System.IO.Path]::GetTempFileName() | Get-Item
                $tempFileActual = "$($tempFile.Directory)\$fileName"

                # retry if file is locked.
                while ($true) {
                    try {
                        [System.IO.File]::WriteAllText($tempFileActual, $after)
                        break;
                    } catch {
                        Write-SubSubStep "Cannot write $($tempFileActual), Retrying..."
                        Start-Sleep -Seconds 1
                    }
                }

                $file = Get-Item $tempFileActual
            }

            $existingHash = $existingHashes[$targetRelativePath]
            $newHash = Get-FileHash $file.FullName -Algorithm SHA256
            $newHash = $newHash.Hash

            if ($existingHash -eq $newHash) {
                Write-Color -DarkGray "skipping file, hash matched..." -Yellow "OK!"
            } else {
                Write-Color -DarkGray "uploading file ..." -nonewline
                $result = Add-PnPFile -Folder $folderName -Path $file.FullName -Checkout -CheckinComment "GW" -Publish -PublishComment "GW" -Values @{ gwHash = $newHash }
                Write-Success "OK!"
            }
        }
    } finally {
    }

    Write-Host
}

function Import-Config {
   param (
       $app,
       $folder = $null,
       $listRelativeUrl = $null,
       $checkout = $false,
       $exclude = "",
       $include = ""
   )

   Write-Step "Import-Config"
   throw "Migrate to pnp cmdlet"

   try {
       $ctx = Get-PnPContext
       $web = Get-PnPWeb

       # check local directory specified by 'folder'
       if (-not $folder) {
           $folder = "$content_dir/GridWorksConfig/"
       }
       if (-not (Test-Path $folder)) {
           Write-Error "Folder '$folder' does not exist!"
           return
       }
       $basePath = $folder.Replace("\", "/").Trim("/")

       # check sharepoint list specified by 'listRelativeUrl'
       if (-not $listRelativeUrl) {
           $listRelativeUrl = "/GridWorksConfig"
       }
       $remoteFolder = $web.GetFolder($listRelativeUrl)
       if (-not $remoteFolder.Exists) {
           Write-Error "SPFolder '$listRelativeUrl' does not exist on web url '$url'!"
           return
       }

       Write-Step "Importing" -Highlight $basePath -Normal "to" -Highlight "$($url)$($listRelativeUrl)" -Normal "..."
       $files = @( Get-ChildItem $folder -recurse | where { $_.Extension.Contains(".") })

       Write-SubStep "Found" -Highlight $files.Count -Normal "files ..."
       if ($exclude -ne "") {
           $exclude = "$exclude".replace("/", "\")
           $files = $files | where { $_.FullName -notmatch $exclude }
           Write-SubStep "Exclude filter" -Highlight $exclude -Normal "applied, matching" -Highlight $files.Count -Normal " ..."
       }
       if ($include -ne "") {
           $include = "$include".replace("/", "\")
           $files = $files | where { $_.FullName -match $include }
           Write-SubStep "Include filter" -Highlight $include -Normal "applied, matching" -Highlight $files.Count -Normal " ..."
       }

       $files | ForEach-Object {
           $file = $_

           $targetName = $file.FullName.Replace("\", "/")
           $targetName = $targetName.Replace($basePath, "")
           $targetName = $targetName.Trim("/")
           Write-SubStep "adding file" -Highlight "$targetName" -Normal "..."

           if ($file.Extension -eq ".xml") {
               $content = [System.IO.File]::ReadAllText($file.FullName)
               $content = Start-ReplaceConfigVars $app $content
               $content = [System.Text.Encoding]::UTF8.GetBytes($content)
           } else {
               $content = [System.IO.File]::ReadAllBytes($file.FullName)
           }

           Add-FileToFolder $file $content $remoteFolder $targetName $checkout
       }
   } finally {
   }

   Write-Host
}

function Get-GwThemeIfNotSet {
    [CmdletBinding()]

    Param (
        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection]$Connection
    )

    Process {
        
        $adminTheme = $apps.default.theme
        $currentTheme = Get-PnPPropertyBag -Key "ThemePrimary" -Connection $Connection

        write-host "adminTheme: $($adminTheme)"
        write-host "currentTheme: $($currentTheme)"

        write-host "Get-PnPTenantTheme:"

        Get-PnPTenantTheme -Connection $connection
    }
}

function Set-GwThemeIfNotSet {
    [CmdletBinding()]

    Param (
        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection]$Connection,
        [Parameter(Mandatory = $true)]
        [string] $ThemeName        
    )

    Process {

        $palette = @{
            "themePrimary" = "#b1cb35";
            "themeLighterAlt" = "#fafbf1";
            "themeLighter" = "#f1f6db";
            "themeLight" = "#dee9a7";
            "themeTertiary" = "#c6d967";
            "themeSecondary" = "#b6ce3e";
            "themeDarkAlt" = "#a2b92f";
            "themeDark" = "#738321";
            "themeDarker" = "#63711d";
            "neutralLighterAlt" = "#ececec";
            "neutralLighter" = "#e8e8e8";
            "neutralLight" = "#dedede";
            "neutralQuaternaryAlt" = "#cfcfcf";
            "neutralQuaternary" = "#c6c6c6";
            "neutralTertiaryAlt" = "#bebebe";
            "neutralTertiary" = "#bfbfbf";
            "neutralSecondary" = "#909090";
            "neutralPrimaryAlt" = "#727272";
            "neutralPrimary" = "#6a6a6a";
            "neutralDark" = "#454545";
            "black" = "#3b3b3b";
            "white" = "#f2f2f2";
            "primaryBackground" = "#f2f2f2";
            "primaryText" = "#6a6a6a";
            "bodyBackground" = "#f2f2f2";
            "bodyText" = "#6a6a6a";
            "disabledBackground" = "#e8e8e8";
            "disabledText" = "#bebebe";
        }
        
        $currentTheme = Get-PnPPropertyBag -Key "ThemePrimary" -Connection $Connection

        # deserialize theme in variable
        if($palette.themePrimary -ne $currentTheme)
        {
            # The theme 'seems' to not be set. This check is flawed and based only on the primary theme color for now
            Add-PnPTenantTheme -Identity $ThemeName -Overwrite -Palette $palette -IsInverted $false -Connection $Connection
            Set-PnPWebTheme -Theme $ThemeName -Connection $Connection
            Write-Step "Custom Theme '$($currentTheme)' set"
        } else {
            Write-Step "Custom Theme '$($currentTheme)' already set"
        }
    }
}

function Update-AppIfPresent {
    [CmdletBinding()]

    Param(
        [Parameter(Mandatory = $true)]
        [String] $AppName,

        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $Connection
    )

    Process {
        $app = Get-PnPApp -Identity $AppName -Connection $Connection -ErrorAction SilentlyContinue
        if($app -ne $null)
        {
            if($app.InstalledVersion)
            {
                Write-Host "Updating solution in site" -ForegroundColor Yellow
                # Uninstall from Site
                Update-PnPApp -Identity $app.Id
                # Wait for the app to be uninstall
                # $installedVersion = Get-PnPApp -Identity $AppName -Connection $Connection | Select-Object -ExpandProperty InstalledVersion
                # while($installedVersion.Major -ne $null)
                # {
                #     Write-Host "." -ForegroundColor Yellow -NoNewLine
                #     Start-Sleep -Seconds 5
                #     $installedVersion = Get-PnPApp -Identity $AppName -Connection $Connection | Select-Object -ExpandProperty InstalledVersion
                # }
                # Write-Host " Done." -ForegroundColor Green
            }
            # Write-Host "Removing solution from appcatalog... " -ForegroundColor Yellow -NoNewline
            # Remove-PnPApp -Identity $app.Id -Connection $Connection
            # Write-Host " Done." -ForegroundColor Green
        }
    }
}

function Get-GwImformationFieldValues {

    param(
        $siteData,
        $prefix
    )

    $valuesList = @{}

    if (![string]::IsNullOrEmpty($siteData.name)) {
        $valuesList.Add("Title", $siteData.name)
    }
    if (![string]::IsNullOrEmpty($siteData.description)) {
        $valuesList.Add("gwSiteDescription", $siteData.description)
    }
    if (![string]::IsNullOrEmpty($siteData.shortname)) {
        $valuesList.Add("gwShortName", $siteData.shortname)
    }
    if (![string]::IsNullOrEmpty($siteData.language)) {
        $valuesList.Add("gwLanguage", $siteData.language)
    }
    if (![string]::IsNullOrEmpty($siteData.sitetype)) {
        $valuesList.Add("gwSiteType", $siteData.sitetype)
    }
    if (![string]::IsNullOrEmpty($siteData.sitetemplateid)) {
        $valuesList.Add("gwSiteTemplateId", $siteData.sitetemplateid)
    }
    if (![string]::IsNullOrEmpty($siteData.siteprovisioningstatus)) {
        $valuesList.Add("gwSiteProvisionStatus", $siteData.siteprovisioningstatus)
    }
    if (![string]::IsNullOrEmpty($siteData.owner)) {
        $valuesList.Add("gwSiteOwner", $siteData.owner)
    }
    if (![string]::IsNullOrEmpty($siteData.member)) {
        $valuesList.Add("gwSiteMember", $siteData.member)
    }
    if ($siteData.siteispublic -eq $true) {
        $valuesList.Add("gwPrivate", $true)
    } else {
        $valuesList.Add("gwPrivate", $false)
    }
    if ($siteData.noexternalsharing -eq $true) {
        $valuesList.Add("gwNoExternalSharing", $true)
    } else {
        $valuesList.Add("gwNoExternalSharing", $false)
    }
    if (![string]::IsNullOrEmpty($siteData.url)) {
        $informationUrl = "/sites/$($prefix)$($siteData.shortname.ToLower())"
        $valuesList.Add("gwWebUrl", "$($informationUrl), $($siteData.name)")
    }
    if (![string]::IsNullOrEmpty($siteData.organisation)) {
        $valuesList.Add("gwArea", $siteData.organisation)
    }
    if (![string]::IsNullOrEmpty($siteData.sitestatus)) {
        $valuesList.Add("gwSiteStatus", $siteData.sitestatus)
    }
    if (![string]::IsNullOrEmpty($siteData.projectstart)) {
        $valuesList.Add("gwProjectStart", $siteData.projectstart)
    }
    if (![string]::IsNullOrEmpty($siteData.projectend)) {
        $valuesList.Add("gwProjectEnd", $siteData.projectend)
    }
    if (![string]::IsNullOrEmpty($siteData.projectlead)) {
        $valuesList.Add("gwProjectLead", $siteData.projectlead)
    }
    if (![string]::IsNullOrEmpty($siteData.pspelement)) {
        $valuesList.Add("gwPSPElement", $siteData.pspelement)
    }
    if (![string]::IsNullOrEmpty($siteData.projectsize)) {
        $valuesList.Add("gwProjectSize", $siteData.projectsize)
    }
    if (![string]::IsNullOrEmpty($siteData.projectdomain)) {
        $valuesList.Add("gwProjectDomain", $siteData.projectdomain)
    }
    if (![string]::IsNullOrEmpty($siteData.projecttype)) {
        $valuesList.Add("gwProjectType", $siteData.projecttype)
    }
    if ($site.digitalactivity -ne $null -And $siteData.digitalactivity.count -gt 0 ) {
        $valuesList.Add("gwDigitalActivity", $siteData.digitalactivity)
    }
    if (![string]::IsNullOrEmpty($siteData.projectphase)) {
        $valuesList.Add("gwProjectPhase", $siteData.projectphase)
    }
    if (![string]::IsNullOrEmpty($siteData.projectprio)) {
        $valuesList.Add("gwProjectPrio", $siteData.projectprio)
    }
    if (![string]::IsNullOrEmpty($siteData.siteclassification)) {
        $valuesList.Add("gwSiteClassification", $siteData.siteclassification)
    }

    return $valuesList
}


function Get-GwInformationItemFieldValues {

    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.SharePoint.Client.ListItem] $ListItem,
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $Connection        
    )

    $valuesList = @{}

    if (![string]::IsNullOrEmpty($ListItem["Title"])) {
        $valuesList.Add("Title", $ListItem["Title"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwSiteDescription"])) {
        $valuesList.Add("gwSiteDescription", $ListItem["gwSiteDescription"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwShortName"])) {
        $valuesList.Add("gwShortName", $ListItem["gwShortName"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwLanguage"])) {
        $valuesList.Add("gwLanguage", $ListItem["gwLanguage"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwSiteType"])) {
        $valuesList.Add("gwSiteType", $ListItem["gwSiteType"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwSiteTemplateId"])) {
        $valuesList.Add("gwSiteTemplateId", $ListItem["gwSiteTemplateId"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwSiteProvisionStatus"])) {
        $valuesList.Add("gwSiteProvisionStatus", $ListItem["gwSiteProvisionStatus"])
    }
    if ($ListItem["gwPrivate"] -eq $true) {
        $valuesList.Add("gwPrivate", $true)
    } else {
        $valuesList.Add("gwPrivate", $false)
    }
    if ($ListItem["gwNoExternalSharing"] -eq $true) {
        $valuesList.Add("gwNoExternalSharing", $true)
    } else {
        $valuesList.Add("gwNoExternalSharing", $false)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwWebUrl"])) {
        $valuesList.Add("gwWebUrl", "$($ListItem["gwWebUrl"].url), $($ListItem["gwWebUrl"].description)")
    }
    if (![string]::IsNullOrEmpty($ListItem["gwArea"])) {
        $valuesList.Add("gwArea", $ListItem["gwArea"].TermGuid)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwSiteStatus"])) {
        $valuesList.Add("gwSiteStatus", $ListItem["gwSiteStatus"].TermGuid)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwProjectStart"])) {
        $valuesList.Add("gwProjectStart", $ListItem["gwProjectStart"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwProjectEnd"])) {
        $valuesList.Add("gwProjectEnd", $ListItem["gwProjectEnd"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwPSPElement"])) {
        $valuesList.Add("gwPSPElement", $ListItem["gwPSPElement"].TermGuid)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwProjectSize"])) {
        $valuesList.Add("gwProjectSize", $ListItem["gwProjectSize"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwProjectDomain"])) {
        $valuesList.Add("gwProjectDomain", $ListItem["gwProjectDomain"].TermGuid)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwProjectType"])) {
        $valuesList.Add("gwProjectType", $ListItem["gwProjectType"].TermGuid)
    }
    if ($ListItem["gwDigitalActivity"] -ne $null -And $ListItem["gwDigitalActivity"].count -gt 0 ) {
        $valuesList.Add("gwDigitalActivity", $ListItem["gwDigitalActivity"].TermGuid)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwProjectPhase"])) {
        $valuesList.Add("gwProjectPhase", $ListItem["gwProjectPhase"].TermGuid)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwProjectPrio"])) {
        $valuesList.Add("gwProjectPrio", $ListItem["gwProjectPrio"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwSiteClassification"])) {
        $valuesList.Add("gwSiteClassification", $ListItem["gwSiteClassification"])
    }

    return $valuesList
}
function Set-GwInformationItem {

    param(
        [Parameter(Mandatory = $true)]
        [String] $SiteUrl,
        [Parameter(Mandatory = $true)]
        [Microsoft.SharePoint.Client.ListItem] $ListItem,
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $Connection        
    )

    # get source
    $siteRequestList = Get-PnPList -Connection $Connection -Identity Lists/SiteRequests
    $requestitem = Get-PnPListItem -Connection $Connection -List $siteRequestList -Id $ListItem.Id


    Write-Step "Connect to Child Site '$($SiteUrl)'..." -nonewline
    $connectionNew = Connect-PnPOnline -Url $SiteUrl -Credentials $apps.default.credential -ReturnConnection

    if ($connectionNew -ne $null) {

        Write-Success "OK!"

        # get target
        $listInfo = Get-PnPList -Connection $connectionNew -Identity Lists/Information

        if ($listInfo -ne $null) {

            Write-Step "Add listitem to $($listInfo.Title)..." -nonewline
            $parentCTId = Get-GWParentContentTypeId -ContentTypeId $requestitem["ContentTypeId"]
            $fieldValues = Get-GwInformationItemFieldValues -ListItem $requestitem -Connection $Connection
            $informationItem = Add-PnPListItem -List $listInfo -ContentType $parentCTId -Values $fieldValues -Connection $connectionNew          
            Write-Success "OK"

            Write-Verbose $($fieldValues | ConvertTo-Json)

            # Update Userfields
            if($informationItem) {

                $gwSiteOwner = $requestitem["gwSiteOwner"].Email
                if($gwSiteOwner){
        
                    $updateSiteOwner = @{"gwSiteOwner"="$($gwSiteOwner)"}
                
                    if ($informationItem -ne $null) {
                        Write-Step ($updateSiteOwner | ConvertTo-Json)

                        Write-Step "Update infoitem[$($informationItem.id)] : [gwSiteOwner=$($gwSiteOwner)]..." -nonewline
                        $updateInfoItem = Set-PnPListItem -Connection $connectionNew -List $listInfo -Identity $informationItem.id -Values $updateSiteOwner
                        Write-Success "OK"
                    }
                }            

                $gwSiteMember = $requestitem["gwSiteMember"].Email
                if($gwSiteMember){
        
                    $updateSiteMember = @{"gwSiteMember"="$($gwSiteMember)"}
                
                    if ($informationItem -ne $null) {
                        Write-Verbose ($updateSiteMember | ConvertTo-Json)

                        Write-Step "Update infoitem[$($informationItem.id)] : [gwSiteMember=$($gwSiteMember)]..." -nonewline
                        $updateInfoItem = Set-PnPListItem -Connection $connectionNew -List $listInfo -Identity $informationItem.id -Values $updateSiteMember
                        Write-Success "OK"
                    }
                }
                
                $gwProjectLead = $requestitem["gwProjectLead"].Email
                if($gwProjectLead){
        
                    $updateProjectLead = @{"gwProjectLead"="$($gwProjectLead)"}
                
                    if ($informationItem -ne $null) {
                        Write-Verbose ($updateProjectLead | ConvertTo-Json)

                        Write-Step "Update infoitem[$($informationItem.id)] : [gwProjectLead=$($gwProjectLead)]..." -nonewline
                        $updateInfoItem = Set-PnPListItem -Connection $connectionNew -List $listInfo -Identity $informationItem.id -Values $updateProjectLead
                        Write-Success "OK"
                    }
                }                  

            }
        }

    } else {
        Write-Error $_
        throw "Error while connectiong to sitecollection $($SiteUrl)!"
    }
}
function Get-GWParentContentTypeId {

    param(
        [Parameter(Mandatory = $true)]
        [String] $ContentTypeId
    )

    $workCT = "0x0100AD911DC115B64D77B477D5B723182C5000612C16B71623493C8A1F257BCBF6C9D7"
    $pptCT = "0x0100AD911DC115B64D77B477D5B723182C5000EB1C61F7B5BF4DFDAE9526D917CEF0AB"

    $foundCT = ""

    if ($ContentTypeId -match $workCT) {
        $foundCT = $workCT
        Write-SubStep "Arbeitsgruppe-Information"
    } elseif ($ContentTypeId -match $pptCT) {
        $foundCT = $pptCT
        Write-SubStep "PPM-Projekt"
    } else {
        $foundCT = $workCT
        Write-Error "Parent content type not found, default content type is set!"
    }

    return $foundCT
} 

function Get-GwSiteAliasSimple() {

    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.SharePoint.Client.ListItem] $ListItem,
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $Connection        
    )

    Write-Step "Generating site alias..."

    if (![string]::IsNullOrEmpty($ListItem["gwSiteTemplateId"])) {

        $siteTemplateId = $ListItem["gwSiteTemplateId"]
        $requestTypeShortName = $siteTemplateId.Substring(0,3)
        Write-SubStep "Template Type is $($requestTypeShortName): '$($siteTemplateId)'"

    } else {
        Write-Warning "gwSiteTemplateId not found"
    }

    $siteAlias = ""

    # ensure naming conventions
    # get request type (first 3 letter of gwSiteTemplateId name is used for site prefix, e.g. P-, K-, G-)
    switch ($requestTypeShortName) {
        "org" { $siteAlias = [string]::Format("{0}-{1}", "g", $ListItem["gwShortName"]); break }
        "ppm" { $siteAlias = [string]::Format("{0}-{1}", "p", $ListItem["gwShortName"]); break}
        default { 
            Write-Warning "No first letter mapping parameter for Shortname found. Default value is set."
            $siteAlias = [string]::Format("{0}", $ListItem["gwShortName"]); break
        }

    }

    if ($ListItem["gwNoExternalSharing"] -eq $true) {
        $siteAlias += "-EXT"
    } 

    if (![string]::IsNullOrEmpty($apps.default.prefix)) {
        $siteAlias = $apps.default.prefix + $siteAlias
    }

    $siteAlias = $siteAlias.Replace(' ','-') #no spaces allowed
    Write-SubStep "SiteAlias is: $($siteAlias)"

    return $siteAlias 
}

function Get-GwRequestSiteAlias {

    param(
        [Parameter(Mandatory = $true)]
        [String] $SiteTemplateId,
        [Parameter(Mandatory = $true)]
        [String] $AliasName,
        [bool] $NoExternalSharing = $false,
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $Connection        
    )

    Write-SubStep "Generating site alias..."

    if (![string]::IsNullOrEmpty($SiteTemplateId)) {
        $requestTypeShortName = $SiteTemplateId.Substring(0,3)
        Write-SubSubStep "Template Type is $($requestTypeShortName): '$($SiteTemplateId)'"

    } else {
        Write-Warning "SiteTemplateId not found"
    }

    $siteAlias = ""

    # ensure naming conventions
    # get request type (first 3 letter of gwSiteTemplateId name is used for site prefix, e.g. P-, K-, G-)
    switch ($requestTypeShortName) {
        "org" { $siteAlias = [string]::Format("{0}-{1}", "g", $AliasName); break }
        "ppm" { $siteAlias = [string]::Format("{0}-{1}", "p", $AliasName); break}
        default { 
            Write-Warning "No first letter mapping parameter for Shortname found. Default value is set."
            $siteAlias = [string]::Format("{0}", $AliasName); break
        }

    }

    if ($NoExternalSharing -eq $true) {
        $siteAlias += "-EXT"
    } 

    if (![string]::IsNullOrEmpty($apps.default.prefix)) {
        $siteAlias = $apps.default.prefix + $siteAlias
    }

    $siteAlias = $siteAlias.Replace(' ','-') #no spaces allowed
    Write-SubSubStep "SiteAlias is: $($siteAlias)"

    return $siteAlias 
}

function Set-GwRequestItemWebUrl {  
 
    param(
        [Parameter(Mandatory = $true)]
        [String] $listName,
        [Parameter(Mandatory = $true)]
        [String] $id,
        [Parameter(Mandatory = $true)]
        [String] $siteUrl,
        [Parameter(Mandatory = $true)]
        [String] $title,
        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $connection        
    )

    try {

        $list = "/Lists/" + $listName 
        $updateValues = @{
            "gwWebUrl" ="$($siteUrl), $($title)";
            "gwSiteProvisionStatus"="Provisioned"
        }

        $updateRequestItem = Set-PnPListItem -Connection $connection -List $list -Identity $id -Values $updateValues
        Write-Step "Update item[$($id)] : [gwWebUrl=$($siteUrl); title=$($title)]"
    }
    catch {
        Write-Error $_
    }

}

function Set-GwRequestQueueItemWebUrl {  
 
    param(
        [Parameter(Mandatory = $true)]
        [String] $listName,
        [Parameter(Mandatory = $true)]
        [String] $id,
        [Parameter(Mandatory = $true)]
        [String] $siteUrl,
        [Parameter(Mandatory = $true)]
        [String] $title,
        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $connection        
    )

    try {

        $updateValues = @{
            "gwRequestWebUrl" ="$($siteUrl), $($title)";
            "gwRequestProvisionStatus"="Provisioned"
        }

        $updateRequestItem = Set-PnPListItem -Connection $connection -List $listName -Identity $id -Values $updateValues
        Write-Step "Update item[$($id)] : [gwRequestWebUrl=$($siteUrl); title=$($title)]"
    }
    catch {
        Write-Error $_
    }

}

function Set-GwRequestItemStatus {  
 
    param(
        [Parameter(Mandatory = $true)]
        [String] $listName,
        [Parameter(Mandatory = $true)]
        [String] $requestItemId,
        [Parameter(Mandatory = $true)]
        [String] $statusType,
        [Parameter(Mandatory = $true)]
        [String] $statusMessage,
        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $connection        
    )

    try {

        $list = "/Lists/" + $listName 
        $updateRequestItem = Get-PnPListItem -Connection $connection -List $list -Id $requestItemId -Fields "Id","GUID","Title","gwprStatus","gwSiteProvisionStatus"
        $updateRequestItem = Set-PnPListItem -Connection $connection -List $list -Identity $updateRequestItem.Id -Values @{"gwprStatus" = "$($statusMessage)"; "gwSiteProvisionStatus" = "$($statusType)"}
        Write-Step "Request item status set to [statusType=$($statusType); statusMessage=$($statusMessage)]"
    }
    catch {
        Write-Error $_
    }

}

function Set-GwRequestQueueItemStatus {  
 
    param(
        [Parameter(Mandatory = $true)]
        [String] $listName,
        [Parameter(Mandatory = $true)]
        [String] $requestItemId,
        [Parameter(Mandatory = $true)]
        [String] $statusType,
        [Parameter(Mandatory = $true)]
        [String] $statusMessage,
        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $connection        
    )

    try {

        $updateRequestItem = Get-PnPListItem -Connection $connection -List $listName -Id $requestItemId -Fields "Id","GUID","Title","gwRequestProvisioningMessage","gwRequestProvisionStatus"
        $updateRequestItem = Set-PnPListItem -Connection $connection -List $listName -Identity $updateRequestItem.Id -Values @{"gwRequestProvisioningMessage" = "$($statusMessage)"; "gwRequestProvisionStatus" = "$($statusType)"}
        Write-Step "Request item status set to [statusType=$($statusType); statusMessage=$($statusMessage)]"
    }
    catch {
        Write-Error $_
    }

}

function Get-GwIsAliasValid {  
 
    param(
        [Parameter(Mandatory = $true)]
        [String] $listName,
        [Parameter(Mandatory = $true)]
        [String] $requestItemId,
        [Parameter(Mandatory = $true)]
        [String] $siteAlias,
        [Parameter(Mandatory = $true)]
        [String] $statusType,
        [Parameter(Mandatory = $true)]
        [String] $statusMessage,
        [Parameter(Mandatory = $true)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $connection        
    )

    try {
        if (Test-PnPOffice365GroupAliasIsUsed -Connection $connection -Alias $siteAlias) {
            Write-Warning "Alias is used [$($siteAlias)]"
            Set-GwRequestItemStatus -listName $listName -requestItemId $requestItemId -statusType "Failed" -statusMessage "Alias is used '$($siteAlias)'" -Connection $connection
        } else {
            return $true
        }
    } catch {
        return $false
    }

}

function Get-GwUserEmailValue {  
 
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.SharePoint.Client.ListItem] $listItem,
        [Parameter(Mandatory = $true)]
        [String] $fieldStaticName,
        [Parameter(Mandatory = $false)]
        [String[]] $defaultValue
    )

    try {

        [string]$userEmail = ""
        $userEmail = $listItem[$($fieldStaticName)].Email
        
        if ([string]::IsNullOrEmpty($listItem[$($fieldStaticName)].Email)) {
            $users = $defaultValue
        } else {
            $users = @($userEmail) 
        }

        return $users
    }
    catch {
        Write-Error $_
    }

}

function Get-GwRequestDescriptionValue {  
 
    param(
        [Parameter(Mandatory = $true)]
        [string] $description,
        [Parameter(Mandatory = $true)]
        [string] $defaultValue
    )

    if (![string]::IsNullOrEmpty($description)) {
        $returnDescriptionValue = $description
    } else {
        $returnDescriptionValue = $defaultValue
    }

    return $returnDescriptionValue

}

function Get-GwSiteDescriptionValue {  
 
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.SharePoint.Client.ListItem] $listItem,
        [Parameter(Mandatory = $true)]
        [String] $defaultValue
    )

    if ($listItem["gwSiteDescription"]){
        $description = $listItem["gwSiteDescription"]
    } else
    {
        $description = $defaultValue
    }

    return $description

}
function Set-GwSiteClassification {

    Param(
        [Parameter(Mandatory = $true)]
        [String] $siteUrl,
        [Parameter(Mandatory = $true)]
        [bool] $isPrivate = $false,
        [Parameter(Mandatory = $true)]
        [bool] $externalSharing = $false
    )    

    Write-Step "Add Classification"

    # set public / private and classify accordingly
    $siteClassification = "intern"
    
    Write-SubStep "Private : $($isPrivate)"
    
    if ($isPrivate -eq $true)
    {
        $siteClassification = "vertraulich"
    }

    # set external sharing and classify accordingly
    Write-SubStep "ExternalSharing : $($externalSharing)"

    if ($externalSharing -eq $true)
    {
        $siteClassification = "extern"
    }
    
    $connectionSubChild = Connect-PnPOnline -Url $siteUrl -Credentials $apps.default.credential -ReturnConnection

    # set site classification 
    $site = Get-PnPSite -Connection $connectionSubChild
    $accessToken = Get-PnPAccessToken
    [Microsoft.SharePoint.Client.SiteExtensions]::SetSiteClassification($site, $siteClassification, $accessToken)

    Write-Step "Site Classification : $($siteClassification)"
}

function Convert-GwInformationItemFields {

    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [Microsoft.SharePoint.Client.ListItem] $ListItem,

        [Parameter(Mandatory = $true, Position = 2)]
        [String] $TemplateConfigListName,
        
        [Parameter(Mandatory = $true, Position = 3)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $Connection        
    )


    # ====================================================================================================
    # Get TemplateId
    # ====================================================================================================

    # $filterFileDirRef = $ListItem["gwRequestSourceFileRef"]
    # $filterLanguage = $ListItem["gwRequestTemplateLanguage"]
    # $camlQueryTemplateId = "<View>
    # <Query>
    # <Where><And><Eq><FieldRef Name='gwTemplateLanguage' /><Value Type='Choice'>" + $filterLanguage + "</Value></Eq><Eq><FieldRef Name='gwTemplateRequestSource' /><Value Type='Text'>" + $filterFileDirRef + "</Value></Eq></And></Where>
    # <OrderBy><FieldRef Name='ID' Ascending='True' /></OrderBy>
    # </Query>
    # <QueryOptions />
    # </View>"

    # Write-SubStep "Filter DirRef: $($filterFileDirRef)"
    # Write-SubStep "Filter Language: $($filterLanguage)"

    # $itemsTemplateConfig = Get-PnPListItem -Connection $Connection -List $TemplateConfigListName -Query $camlQueryTemplateId

    # if ($itemsTemplateConfig.count -gt 0){

    #     $templateLanguage = $itemsTemplateConfig["gwTemplateLanguage"]
    #     Write-SubStep "TemplateLanguage found in config list : $($templateLanguage)"
    # }
    # else {
    #     Write-Error "TemplateLanguage not found in list : $($TemplateConfigListName)"
    # }

    # exit

    # ====================================================================================================
    # Convert Data
    # ====================================================================================================

    $valuesList = @{}

    if (![string]::IsNullOrEmpty($ListItem["Title"])) {
        $valuesList.Add("Title", $ListItem["Title"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestDescription"])) {
        $valuesList.Add("gwSiteDescription", $ListItem["gwRequestDescription"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestShortName"])) {
        $valuesList.Add("gwShortName", $ListItem["gwRequestShortName"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestTemplateLanguage"])) {
        $valuesList.Add("gwLanguage", $ListItem["gwRequestTemplateLanguage"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestBaseTemplate"])) {
        $valuesList.Add("gwSiteType", $ListItem["gwRequestBaseTemplate"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestTemplateId"])) {
        $valuesList.Add("gwSiteTemplateId", $ListItem["gwRequestTemplateId"])
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestProvisionStatus"])) {
        $valuesList.Add("gwSiteProvisionStatus", $ListItem["gwRequestProvisionStatus"])
    }
    if ($ListItem["gwRequestIsPrivate"] -eq $true) {
        $valuesList.Add("gwPrivate", $true)
    } else {
        $valuesList.Add("gwPrivate", $false)
    }
    if ($ListItem["gwRequestNoExternalSharing"] -eq $true) {
        $valuesList.Add("gwNoExternalSharing", $true)
    } else {
        $valuesList.Add("gwNoExternalSharing", $false)
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestWebUrl"])) {
        $valuesList.Add("gwWebUrl", "$($ListItem["gwRequestWebUrl"].url), $($ListItem["gwRequestWebUrl"].description)")
    }
    if (![string]::IsNullOrEmpty($ListItem["gwRequestSiteClassification"])) {
        $valuesList.Add("gwSiteClassification", $ListItem["gwRequestSiteClassification"])
    }

    # if ($ListItem["gwRequestSiteOwner"] -ne $null) {

    #     $owners = @()
    #     $ownersList = $ListItem["gwRequestSiteOwner"]
    #     foreach ($owner in $ownersList) {
    #         $owners += $owner.Email
    #     }

    #     $valuesList.Add("gwSiteOwner", @($owners))
    # }

    # if ($ListItem["gwRequestSiteMember"] -ne $null) {

    #     $members = @()
    #     $membersList = $ListItem["gwRequestSiteMember"]
    #     foreach ($member in $membersList) {
    #         $members += $member.Email
    #     }

    #     $valuesList.Add("gwSiteOwner", @($members))
    # }

    # if (![string]::IsNullOrEmpty($ListItem["gwArea"])) {
    #     $valuesList.Add("gwArea", $ListItem["gwArea"].TermGuid)
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwSiteStatus"])) {
    #     $valuesList.Add("gwSiteStatus", $ListItem["gwSiteStatus"].TermGuid)
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwProjectStart"])) {
    #     $valuesList.Add("gwProjectStart", $ListItem["gwProjectStart"])
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwProjectEnd"])) {
    #     $valuesList.Add("gwProjectEnd", $ListItem["gwProjectEnd"])
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwPSPElement"])) {
    #     $valuesList.Add("gwPSPElement", $ListItem["gwPSPElement"].TermGuid)
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwProjectSize"])) {
    #     $valuesList.Add("gwProjectSize", $ListItem["gwProjectSize"])
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwProjectDomain"])) {
    #     $valuesList.Add("gwProjectDomain", $ListItem["gwProjectDomain"].TermGuid)
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwProjectType"])) {
    #     $valuesList.Add("gwProjectType", $ListItem["gwProjectType"].TermGuid)
    # }
    # if ($ListItem["gwDigitalActivity"] -ne $null -And $ListItem["gwDigitalActivity"].count -gt 0 ) {
    #     $valuesList.Add("gwDigitalActivity", $ListItem["gwDigitalActivity"].TermGuid)
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwProjectPhase"])) {
    #     $valuesList.Add("gwProjectPhase", $ListItem["gwProjectPhase"].TermGuid)
    # }
    # if (![string]::IsNullOrEmpty($ListItem["gwProjectPrio"])) {
    #     $valuesList.Add("gwProjectPrio", $ListItem["gwProjectPrio"])
    # }

    return $valuesList
}

function Set-GwInformationRequestItem {

    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [String] $ListName,

        [Parameter(Mandatory = $true, Position = 2)]
        [String] $TemplateConfigListName,

        [Parameter(Mandatory = $true, Position = 3)]
        [String] $SiteUrl,

        [Parameter(Mandatory = $true, Position = 4)]
        [Microsoft.SharePoint.Client.ListItem] $ListItem,

        [Parameter(Mandatory = $true, Position = 5)]
        [SharePointPnP.PowerShell.Commands.Base.SPOnlineConnection] $Connection,
        
        [Parameter(Mandatory = $false, Position = 6)]
        [PSCredential]$Credentials = $apps.default.credential             
    )

    # get source
    $siteRequestList = Get-PnPList -Connection $Connection -Identity Lists/SiteRequestsQueue
    $requestitem = Get-PnPListItem -Connection $Connection -List $siteRequestList -Id $ListItem.Id


    Write-Step "Connect to Child Site '$($SiteUrl)'..." -nonewline
    $connectionNew = Connect-PnPOnline -Url $SiteUrl -Credentials $Credentials -ReturnConnection

    if ($connectionNew -ne $null) {

        Write-Success "OK!"

        # get target
        $listInfo = Get-PnPList -Connection $connectionNew -Identity Lists/Information

        if ($listInfo -ne $null) {

            Write-Step "Add listitem to $($listInfo.Title)..." -nonewline
            $parentCTId = "0x0100AD911DC115B64D77B477D5B723182C5000612C16B71623493C8A1F257BCBF6C9D7" # Get-GWParentContentTypeId -ContentTypeId $requestitem["ContentTypeId"]
            $fieldValues = Convert-GwInformationItemFields -ListItem $requestitem -TemplateConfigListName $TemplateConfigListName -Connection $Connection

            Write-Step $($fieldValues | ConvertTo-Json)

            $informationItem = Add-PnPListItem -List $listInfo -ContentType $parentCTId -Values $fieldValues -Connection $connectionNew          
            Write-Success "OK"

            # Update Userfields
            if($informationItem) {


                if ($requestitem["gwRequestSiteOwner"] -ne $null){
                    if (![string]::IsNullOrEmpty($requestitem["gwRequestSiteOwner"])) {

                        $owners = @()
                        $ownersList = $requestitem["gwRequestSiteOwner"]
                        foreach ($owner in $ownersList) {
                            $owners += $owner.Email
                        }
                        Write-Step $($owners | ConvertTo-Json)

                        $updateSiteOwner = @{"gwSiteOwner"= @($owners)}

                        Write-Step "Update SiteOwner..." -nonewline
                        $updateInfoItem = Set-PnPListItem -Connection $connectionNew -List $listInfo -Identity $informationItem.id -Values $updateSiteOwner
                        Write-Success "OK"

                    }  
                }
              
                if ($requestitem["gwRequestSiteMember"] -ne $null){
                    if (![string]::IsNullOrEmpty($requestitem["gwRequestSiteMember"])) {
            
                        $members = @()
                        $membersList = $requestitem["gwRequestSiteMember"]
                        foreach ($member in $membersList) {
                            $members += $member.Email
                        }
                        Write-Step $($members | ConvertTo-Json)
                
                        $updateSiteMember = @{"gwSiteMember"= @($members)}

                        Write-Step "Update SiteMember..." -nonewline
                        $updateInfoItem = Set-PnPListItem -Connection $connectionNew -List $listInfo -Identity $informationItem.id -Values $updateSiteMember
                        Write-Success "OK"
                    }    
                }
                
                # $gwProjectLead = $requestitem["gwProjectLead"].Email
                # if($gwProjectLead){
        
                #     $updateProjectLead = @{"gwProjectLead"="$($gwProjectLead)"}
                
                #     if ($informationItem -ne $null) {
                #         Write-Verbose ($updateProjectLead | ConvertTo-Json)

                #         Write-Step "Update infoitem[$($informationItem.id)] : [gwProjectLead=$($gwProjectLead)]..." -nonewline
                #         $updateInfoItem = Set-PnPListItem -Connection $connectionNew -List $listInfo -Identity $informationItem.id -Values $updateProjectLead
                #         Write-Success "OK"
                #     }
                # }                  

            }
        }

    } else {
        Write-Error $_
        throw "Error while connectiong to sitecollection $($SiteUrl)!"
    }
}


Export-ModuleMember -Function *
