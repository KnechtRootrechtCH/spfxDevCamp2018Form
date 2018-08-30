# Save Template
Write-Output "Saving the template to XML file"

# $templateSolutionFile = "C:\Projects\prive-0365\deployment\tasks\dev\setup-provisioning\solution_temnplate.xml";
# Get-PnPProvisioningTemplate -Out $templateSolutionFile -PersistBrandingFiles -PersistPublishingFiles


# 1) Get-PnPProvisioningTemplate -Handlers Lists -Out c:\temp\siterequests-list.xml -Force
# 2) Remove all ListInstances except siterequests list

# $templateSiteRequestFile = "C:\Projects\prive-0365\deployment\tasks\dev\setup-provisioning\siterequests_template.xml";
# Get-PnPProvisioningTemplate -Out $templateSiteRequestFile -Handlers Lists -Force

$demo = $apps.default.url + "/sites/dev-d6"


Write-Step "Connecting to $($demo)..." -nonewline

Connect-PnPOnline -Url $demo -Credentials $apps.default.credential | Out-Null

Write-Success "OK!"

$templateInformationFile = "C:\Projects\prive-0365\deployment\tasks\dev\setup-provisioning\information_template-new1.xml";
Get-PnPProvisioningTemplate -Out $templateInformationFile -Handlers Lists -Force

Disconnect-PnPOnline
