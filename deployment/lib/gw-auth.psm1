# -----------------------------------------------------------------------------
# Author: stefan.kestenholz@garaio.com
# -----------------------------------------------------------------------------

function Get-PnPCredentials([string]$userName, [string]$password) {
   if ([string]::IsNullOrEmpty($password)) {
      $securePassword = Read-Host -Prompt "Enter the password" -AsSecureString
   } else {
      $securePassword = $Password | ConvertTo-SecureString -AsPlainText -Force
   }
   return New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($userName, $securePassword)
}

function Test-GwCommands {

    param(
        [Parameter(Mandatory = $false, Position = 1)]
        [switch]$SkipPowerShellInstall = $false    
    )    

    # Check if PnP PowerShell is installed
    if (!$SkipPowershellInstall) {
        Write-Step "Verifying where the Pnp Powershell Commandlets are installed ..."
        $modules = Get-Module -Name SharePointPnPPowerShellOnline -ListAvailable
        if ($modules -eq $null) {
            Write-Step "Pnp Powershell Commandlets are not installed..."
            # Not installed.
            Install-Module -Name SharePointPnPPowerShellOnline -Scope CurrentUser -Force
            Import-Module -Name SharePointPnPPowerShellOnline -DisableNameChecking

            Write-SubStep "The console might have to be restarted for the modules to work."
            Exit-Installer
        }
    }

}

function Connect-GwUrl {
    param(
        [string] $url,
        $app = $apps.default,
        [switch] $quiet = $false
    )

    if (-not $quiet) {
        Write-Step "Connecting to '$url' ..." -nonewline
    }

    try {

        if (-not $app.credential) {
            $username = $app.administrator
            $app.credential = Get-Credential -Message "Supply password" -UserName $username

            $filename = $($apps.default.credentialtenantfile)
            $tenant_admin_path = "$env_dir\$environment"
            
            if (!(Test-Path $tenant_admin_path )) {
                Exit-Failure "Failed to find environment init file in $tenant_admin_path!"
            }
            
            $fullpath = "$tenant_admin_path\$filename"

            $app.credential | Export-clixml $($fullpath)
        }

        Connect-PnPOnline -Url $url -Credentials $app.credential | Out-Null
        $web = Get-PnPWeb
        if (-not $quiet) {
            Write-Step "Connected to '$($web.Title)'" -Success "OK!"
        }
    } catch {
        Exit-Failure "$_"
    }
}

function Connect-GwStoredStoredCredentialUrl {
    param(
        [string] $url,
        $app = $apps.default,
        [switch] $quiet = $false
    )

    if (-not $quiet) {
        Write-Step "Connecting to '$url' ..." -nonewline
    }

    try {

        # $url = $app.url
        $username = $app.administrator
        
        $credential = Get-PnPStoredCredential -Name $url
    
        if (-not $credential) {
            Add-PnPStoredCredential -Name $url -Username $username
            Write-Step "Save password to Credential Manager!"
        }

        Connect-PnPOnline -Url $url

        $web = Get-PnPWeb
        if (-not $quiet) {
            Write-Step "Connected to '$($web.Title)'" -Success "OK!"
        }

    } catch {
        Exit-Failure "$_"
    }
}

function Connect-GwCurrentEnvironment {
    $url = $apps.default.url
    Connect-GwUrl $url
}

function Connect-GwStoredCurrentEnvironment {

    $url = $apps.default.url
    Connect-GwStoredStoredCredentialUrl $url

}

Export-ModuleMember -Function *