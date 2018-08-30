# -----------------------------------------------------------------------------
# Author: roland.oechslin@garaio.com
# Order: 10
# Description: Script for deployment package to sitecollection appcatalog (-Scope Site)
# -----------------------------------------------------------------------------

Param(
    [Parameter(Mandatory = $false, Position = 1)]
    [switch]$Build,

    [Parameter(Mandatory = $false, Position = 2)]
    [switch]$SkipSolutionDeployment = $false
)

Write-Info "Provisioning solution..."

$zipFile = "sp-fx-dev-camp-2018.sppkg"
$solutionName = "sp-fx-dev-camp-2018"
$solutionTitle = "sp-fx-dev-camp-2018-client-side-solution"
$appstoreurl = "$($apps.default.url)"


Write-Step "Connect to App Store $($appstoreurl )... " -nonewline
$connection = Connect-PnPOnline -Url $appstoreurl  -Credentials $apps.default.credential -ReturnConnection

if($connection -ne $null){

    Write-Success "OK!"

    if ($SkipSolutionDeployment -ne $true) {

        Set-Location $PSScriptRoot\..\..\..\..\


        # Temporary until schema change is present
        $existingApp = Get-PnPApp -Identity $solutionTitle -ErrorAction SilentlyContinue
        if ($existingApp -ne $null) {
            Write-Step "Remove solution $($existingApp.Title)... " -nonewline
            Remove-PnPApp -Identity $existingApp
            Write-Success "OK!"
        }

        # TODO: Fix when ATM API is ready
        # Apply-PnPProvisioningTemplate -Path "$content_dir\solutions\solution.xml" -Connection $connection
        # Update-AppIfPresent -AppName $solutionTitle -Connection $connection

        # TODO: Remove when ATM API is ready
        $packageConfig = Get-Content -Raw -Path (".\config\package-solution.json") | ConvertFrom-Json
        $packagePath = Join-Path (".\sharepoint\") $packageConfig.paths.zippedPackage -Resolve
        $skipFeatureDeployment = $packageConfig.solution.skipFeatureDeployment

        Write-Step "Uploading the $($packageConfig.paths.zippedPackage) on the AppCatalog... " -nonewline

        # Adding and publishing the App package
        If ($skipFeatureDeployment -ne $true) {
            Write-Step "Uploading the $($packageConfig.paths.zippedPackage) on the AppCatalog with skipFeatureDeployment = false... " -nonewline
            $temp = Add-PnPApp -Scope Site -Path $packagePath -Publish -Overwrite
        }
        Else {
            Write-Step "Uploading the $($packageConfig.paths.zippedPackage) on the AppCatalog with skipFeatureDeployment = true... " -nonewline
            $temp = Add-PnPApp -Scope Site -Path $packagePath -SkipFeatureDeployment -Publish -Overwrite -Verbose
        }

        Write-Success "OK!"
    }

    Set-Location $PSScriptRoot\deployment
}


