# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------

$loadedAssemblies = @{}

function Import-AssemblyFromGac( $name ) {
    try {
        if ($loadedAssemblies.ContainsKey( $name )) {
            Write-Debug "Assembly" -Highlight $name -Normal "already loaded..."
            return
        }
        Write-Step -nonewline "Loading assembly" -Highlight $name
        $loadedAssemblies[$name] = [System.Reflection.Assembly]::LoadWithPartialName($name)
        Write-Success "OK!"
    } catch {
        Write-Error "Failed to load -> $_"
    }
}

function Invoke-WithCulture(
        [System.Globalization.CultureInfo] $culture = (throw "USAGE: Invoke-WithCulture -Culture culture -Script {…}"),
        [ScriptBlock] $script = (throw "USAGE: Invoke-WithCulture -Culture culture -Script {…}")) {
    $OldCulture = [Threading.Thread]::CurrentThread.CurrentCulture
    $OldUICulture = [Threading.Thread]::CurrentThread.CurrentUICulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture = $culture
        [Threading.Thread]::CurrentThread.CurrentUICulture = $culture
        Invoke-Command $script
    }
    finally {
        [Threading.Thread]::CurrentThread.CurrentCulture = $OldCulture
        [Threading.Thread]::CurrentThread.CurrentUICulture = $OldUICulture
    }
}

function Import-Assembly( $path ) {
    $location = Get-Location

    if (!(Test-Path $path)) {
        Write-Error "Assembly not found at path: $path"
        return
    }

    $parent = Split-Path -parent $path
    $name = Split-Path -leaf $path

    Write-Step -nonewline "Loading assembly" -Highlight $name
    try {
        Set-Location $parent
        $result = [System.Reflection.Assembly]::LoadFrom( $path )
        Pop-Location
        Write-Success "OK!"
    } catch {
        $error = Get-ErrorRecord
        Write-Error "Failed to load -> $error"
        throw

    } finally {
        Set-Location $location
    }
}

function Format-HashTable ( $hash ) {
    return ($hash.Keys | foreach { "$_='$($hash[$_])" }) -join ", "
}

function New-WebApplication {
    param(
        $app
    )

    Import-Module Webadministration

    $url = $app.url
    if (-not $url) {
        Write-Error ("App {0} does not define an url!" -f (Format-HashTable $app))
        return
    }

    if ($app.ssl) {
        $url = "https://$($app.name)"
    } else {
        $url = "http://$($app.name)"
    }

    Write-Info "`nProcessing web application $url ..."

    # check whether app settings define explicit removal of existing
    # web application in for the New-WebApplication cmdlet.
    $wa = Get-SPWebApplication $url -ErrorAction SilentlyContinue
    $exists = $wa -ne $null
    if ($exists) {
        Write-Step "Web application $url exists"
        switch ($app.setup.app_exists) {
            "delete" {
                if (Get-Confirmation "Deleting existing web application $url, are you sure?") {
                    Remove-SPWebApplication $app.url -DeleteIISSite -RemoveContentDatabases -confirm:$false
                    $exists = $false
                }
            }
            "skip" {
            }
            default {
            }
        }
    }

    # configuration setting 'app_pool' is required.
    if (-not $app.app_pool) {
        Write-Step -Error "Configuration 'app_pool' is required!"
        return
    }

    # check whether app pool exists - if not, it is created later.
    $app.app_pool_exists = @( Get-Item "IIS:\AppPools\*" |? { $_.Name -eq $app.app_pool } ).Count -gt 0

    # configuration setting 'app_pool_user' is required.
    if (-not $app.app_pool_user) {
        Write-Step -Error "Configuration 'app_pool_user' is required!"
        return
    }

    # verifying application pool user.
    $app.app_pool_account = Get-SPManagedAccount $app.app_pool_user -ErrorAction SilentlyContinue
    if (-not $app.app_pool_account) {
        Write-Step -Error "Service account" -Highlight $app.app_pool_user -Normal "does not exist!"
        return
    }

    $accounts = @(Get-WmiObject -Class Win32_UserAccount) |% { "$($_.Domain)\$($_.Name)".ToLower() }

    # verify configured super user account exists.
    $superuser = "$($app.portal_super_user)".toLower()
    if (-not @($accounts |? { $_.Equals($superuser) })) {
        Write-Step -Error "Configured portal super user" -Highlight $superuser -Normal "does not exist!"
        return
    }

    # verify configured super user account exists.
    $superreader = "$($app.portal_super_reader)".ToLower()
    if (-not @($accounts |? { $_.Equals($superreader) })) {
        Write-Step -Error "Configured portal super reader" -Highlight $superreader -Normal "does not exist!"
        return
    }

    if (-not $exists) {
        Write-Step "Creating web application $url ..."

        if ($app.useclaims) {
            Write-SubStep "With claims authentication ..."
            $ap = New-SPAuthenticationProvider

            if ($app.app_pool_exists) {
                Write-SubStep "Application pool" -Highlight $app.app_pool -Normal "exists ..."
                $wa = New-SPWebApplication -Name $app.name -Port $app.port -HostHeader $app.hostheader -URL $url -SecureSocketsLayer:$app.ssl -ApplicationPool $app.app_pool -DatabaseName $app.content_db -AuthenticationProvider $ap
            } else {
                Write-SubStep "Application pool" -Highlight $app.app_pool -Normal "does not exist, will be created implicitly ..."
                $wa = New-SPWebApplication -Name $app.name -Port $app.port -HostHeader $app.hostheader -URL $url -SecureSocketsLayer:$app.ssl -ApplicationPool $app.app_pool -ApplicationPoolAccount $app.app_pool_account -DatabaseName $app.content_db -AuthenticationProvider $ap
            }

        } else {
            Write-SubStep "With default authentication ..."
            if ($app.app_pool_exists) {
                Write-SubStep "Application pool" -Highlight $app.app_pool -Normal "exists ..."
                $wa = New-SPWebApplication -Name $app.name -Port $app.port -HostHeader $app.hostheader -URL $url -SecureSocketsLayer:$app.ssl -ApplicationPool $app.app_pool -DatabaseName $app.content_db
            } else {
                Write-SubStep "Application pool" -Highlight $app.app_pool -Normal "does not exist, will be created implicitly ..."
                $wa = New-SPWebApplication -Name $app.name -Port $app.port -HostHeader $app.hostheader -URL $url -SecureSocketsLayer:$app.ssl -ApplicationPool $app.app_pool -ApplicationPoolAccount $app.app_pool_account -DatabaseName $app.content_db
            }
        }

        $wa = Get-SPWebApplication $url
        if ($wa -eq $null) {
            Write-Error "Web application was not created correctly!"
            return
        }
    }

    # check whether super user account needs to be set
    $existing = $wa.Properties["portalsuperuseraccount"]
    if ($existing -ne $superuser) {
        if ($wa.UseClaimsAuthentication -and -not $superuser.StartsWith("i:0#.w|")) {
            $superuser = "i:0#.w|" + $superuser
        }
        Write-SubStep "Configuring" -Highlight $superuser -Normal "as portal super user account"

        $wa.Properties["portalsuperuseraccount"] = $superuser
        $fullPolicy = $wa.Policies.Add($superuser, "Portal Super User Account")
        $fullPolicy.PolicyRoleBindings.Add($wa.PolicyRoles.GetSpecialRole([Microsoft.SharePoint.Administration.SPPolicyRoleType]::FullControl)) | Out-Null
        $wa.Update()
    }

    # check whether super reader account needs to be set
    $existing = $wa.Properties["portalsuperreaderaccount"]
    if ($existing -ne $superreader) {
        if ($wa.UseClaimsAuthentication -and -not $superreader.StartsWith("i:0#.w|")) {
            $superreader = "i:0#.w|" + $superreader
        }
        Write-SubStep "Configuring" -Highlight $superreader -Normal "as portal super reader account"

        $wa.Properties["portalsuperreaderaccount"] = $superreader
        $readPolicy = $wa.Policies.Add($superreader, "Portal Super Reader Account")
        $readPolicy.PolicyRoleBindings.Add($wa.PolicyRoles.GetSpecialRole([Microsoft.SharePoint.Administration.SPPolicyRoleType]::FullRead)) | Out-Null
        $wa.Update()
    }

    # TODO: this is only needed for development environments
    Write-SubStep "Configuring ping on app pool" -Highlight $app.app_pool -Normal "..."
    $pool = Get-Item "IIS:\AppPools\$($app.app_pool)"
    $pool.ProcessModel.pingingEnabled = $false
    $pool | Set-Item
}

function Set-ManagedPath($app, $relativeUrl, $explicit = $false) {
    if (-not $app) {
        Write-Error "Required parameter 'app' is missing!"
        return
    }
    if ($app -is [String]) {
        $url = $app
    }  else {
        $url = $app.url
        if (-not $url) {
            Write-Error "Provided app does not define an url!"
            return
        }
    }

    $explicitLog = ""
    if ($explicit) {
        $explicitLog = " explicit"
    }

    Write-Step "Configuring$($explicitLog) managed path $($url)/$($relativeUrl) ... " -nonewline

    $path = Get-SPManagedPath $relativeUrl -WebApplication $url -ErrorAction:SilentlyContinue
    $exists = $path -ne $null
    if ($exists) {
        Write-Success "OK!"
    } else {
        $result = New-SPManagedPath  -RelativeUrl $relativeUrl -WebApplication $webapp -Explicit:$explicit
        $exists = $result -ne $null
        if ($exists) {
            Write-Success "OK!"
        } else {
            Write-Error $result
        }
    }
}

function Remove-ItemsFromRecycleBin {
    param(
        $url
    )

    Write-Step "Removing items from $url recycle bin ..."
    try {
        $site = New-Object Microsoft.SharePoint.SPSite $url
        Write-Step "Deleting recycle bin"
        for ($i=0;$i -lt $site.allwebs.count; $i++) {
            $subweb = $site.allwebs[$i]
            if ($subweb.recyclebin.count -gt 0) {
                Write-SubStep $subweb.url "...deleting" $subweb.recyclebin.count "item(s).";
                $subweb.recyclebin.deleteall();
            }
            $subweb.Dispose()
        }

        if ($site.recyclebin.count -gt 0) {
            Write-SubStep $site.url "...deleting" $site.recyclebin.count "item(s).";
            $site.recyclebin.deleteall();
        }
    } finally  {
        if ($site) {
            $site.Dispose()
        }
    }
}

function Remove-List {
    param(
        $url
    )

    Write-Step "Deleting list $url ..."
    $site = New-Object Microsoft.SharePoint.SPSite $url
    $web = $site.OpenWeb()

    try {
        $list = $web.GetList( $url )
    } catch {}

    if ($list) {
        try {
            if (-not $list.AllowDeletion) {
                Write-SubStep "Setting AllowDeletion:=true"
                $list.AllowDeletion = $true
                $list.Update()
            }
            if ($list) {
                Write-SubStep "List exists, deleting" -nonewline
                $list.Delete()
                Write-Success "OK!"
            } else {
                Write-SubStep "List does not exist"
            }
        } catch {
            Write-Error $_
        }
    }

    if ($web) {
        $web.Dispose()
    }
    if ($site) {
        $site.Dispose()
    }
}

function Remove-WebApplication {
    param (
        $app
    )

    $url = $app.url
    if (-not $url) {
        Write-Error ("App {0} does not define an url!" -f (Format-HashTable $app))
        return
    }

    $wa = Get-SPWebApplication $app.url -ErrorAction SilentlyContinue
    if (-not $wa) {
        Write-Step "Web application $($app.url) does not exist..."
    } else {
        Write-Step "Removing web application $($app.url) ..."
        Remove-SPWebApplication $app.url -DeleteIISSite -RemoveContentDatabases #-confirm:$false
    }
}

function Enable-AnonymousAccess {
    param (
        $app
    )

    $wa = Get-SPWebApplication $app.url

    $wa.IisSettings.Keys | ForEach-Object {
        if (-not $wa.IisSettings[$_].AllowAnonymous) {
            Write-Debug "Setting anonymous state on " -Highlight $app.url -Normal "..."
            $wa.IisSettings[$_].AllowAnonymous = $true
            $wa.Update()
            $wa.ProvisionGlobally();
        }
    }

    ( Get-SPWebApplication $app.url | Get-SPSite | Get-SPWeb -Limit All | Where {$_ -ne $null -and $_.HasUniqueRoleAssignments -eq $true } ) | ForEach-Object {
        $web = $_
        Write-Debug "Setting anonymous state on $($web.url) ..."
        $web.AnonymousState = [Microsoft.SharePoint.SPWeb+WebAnonymousState]::On
        $web.Update();
    }

    Write-Success "OK."
}

function New-Web( $webUrl, $name, $provisioningTemplate, $siteTemplate = "") {

    if ((Get-SPWeb $webUrl -ErrorAction SilentlyContinue) -ne $null) {
        Write-Host "Web '$name' already exists" -f yellow
        return

    }
    Write-Color "Create Web" -Highlight $name
    $web = New-SPWeb -Url $webUrl -Language 1031 -Name $name -Template $siteTemplate
    #beatg $web.ApplyWebTemplate( $siteTemplate )

    $web.AddProperty("gwpr_templateid", $provisioningTemplate)
    $web.Update()
    $web.Dispose()
}

function Remove-Web( $url ) {
    Write-Step "Delete SPWeb '$url'"
    try {
        $web = Get-SPWeb $url

        $subwebs = $web.GetSubwebsForCurrentUser()
        foreach($subweb in $subwebs) {
            Remove-Web $subweb.Url
        }

        $web = Remove-SPWeb $url -confirm:$false

    } catch {
        Write-Error $_
    }
}

function Remove-Site( $url ) {
    Write-Step "Deleting site collection '$url'"
    try {
        Remove-SPSite $url -confirm:$false
    } catch {
        Write-Error $_
    }
}

function Remove-AllSites( $url ) {
    $sites = Get-SPSite -limit all | Where-Object {$_.Url -like "$url/*"}

    foreach ($site in $sites) {
        Write-Step "Deleting site '$($site.Url)'"
        try {
            Remove-SPSite $site -confirm:$false
        } catch {
            Write-Error $_
        }
    }
}

function Start-ApplyProvisioningFeature( $url, $outputUrl = $true ) {
    try {
        $identity = "GridSoft_GridWorks_Provisioning_ApplyProvisioning"
        Write-Step "Activating feature" -Highlight $identity -Normal "..."
        if ($outputUrl) {
            Write-SubStep "on url: $url"
        }
        Enable-SPFeature -identity $identity -Url $url -confirm:$false -force | Out-Null
    } catch {
        Write-Error $_
    }
}

function Start-ProvisioningActivities {
    param(
        $app,
        $relativePath,
        [switch] $confirm = $false
    )

    $relativePath = $relativePath.Replace("/", "\").Trim("\");
    if ($relativePath.StartsWith("config:")) {
        $relativePath = $relativePath.replace("config:", "")
    }

    if ($confirm  -and -not (Get-Confirmation "Execute activities from '$relativePath' ?")) {
        return
    }

    Write-Step "Executing activities from $relativePath ..."
    $web = Get-SPWeb $app.url
    $configFolder = $app.lists["GridWorksConfig"].folder
    $filePath = "$($configFolder)\$($relativePath)"

    $content = Get-Content $filePath -Encoding UTF8
    $content = Start-ReplaceConfigVars $app $content

    [xml]$xml = $content
    $activitites = $xml.selectNodes("//Activity")
    Write-SubStep "File has $($activitites.Count) activities ..."

    $mode = [GridSoft.GridWorks.Provisioning.Activities.ActivityMode]::Execute
    try {
        $report = [GridSoft.GridWorks.Provisioning.Activities.ActivityRuntime]::Execute($web, $content, $mode)
    } catch {
        $error = ((Get-ErrorRecord $_) -split "`n") -join "`n    "
        Write-Error "Failed to execute activities:`n    error: $error"
    }

    $report.Sections | foreach {

        Write-SubStep $_.Title -NoNewLine
        $result = $_.SectionResult
        $s = ""
        $_.Progress | foreach {
            $s += "`n    $_";
        }

        if ($result -eq "Success") {
            Write-Color -Success " -> Success"
        } elseif ($result -eq "Warning") {
            Write-Color -Warning " -> Warning"
        } elseif ($result -eq "Error") {
            Write-Color -Error " -> Error"
        } else {
            Write-Color -DarkGray " -> $result"
        }

        if ($result -eq "Warning") {
            Write-Color -Warning $s
        } elseif ($result -eq "Error") {
            Write-Color -Error $s
        } else {
            Write-Debug $s
        }
    }

    $web.Dispose()
    Write-Host ""
}

function Add-File($webUrl, $folderUrl, $filename, $filePath) {
    $absoluteFolderUrl = $folderUrl
    if (-not $folderUrl.StartsWith("http")) {
        $absoluteFolderUrl = $webUrl + $folderUrl
    }

    try {
        Write-Host "Add file '$filename' to '$absoluteFolderUrl'" -f Magenta
        $web = Get-SPWeb $webUrl

        $folder = $web.GetFolder( $folderUrl )
        $file = Get-ChildItem $filePath
        $f = $folder.Files.Add($filename, $file.OpenRead(), $false) #overwrite=false

    } catch {
        Write-Error $_
    }
}

function Add-RemoteEventReceiver($web, $listUrl, $type, $syncType = "Synchronous") {
    $name = $listUrl.Substring($listUrl.LastIndexOf('/') + 1) +  "_" + $type + "_RER"

    Write-Step "Adding remote event receiver $name"

    $list = $web.GetList($web.Url + $listUrl)
    Write-SubStep "List: $listUrl"

    $existing = $list.EventReceivers | ? {$_.Name -eq $name}
    if ($existing -ne $null) {
        Write-SubStep "Removing existing receiver" -nonewline
        $existing.Delete()
        Write-Success "OK!"
    }

    $url = $apps.remote.url.Trim('/') + "/WebServices/ListItemEventReceiver.svc";
    Write-SubStep "App: $url"

    $def = $list.EventReceivers.Add()
    $def.Type = $type
    $def.Name = $name
    $def.Url = $url
    $def.Synchronization = $syncType
    $def.Update()

    Write-SubStep "Receiver added" -nonewline
    Write-Success "OK!"
    Write-Host
}

Export-ModuleMember -Function *
