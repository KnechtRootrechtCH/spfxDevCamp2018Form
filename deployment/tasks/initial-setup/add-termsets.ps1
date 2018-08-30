
$adminUrl = $apps.default.admin_url

Connect-PnPOnline -Url $adminUrl -Credentials $apps.default.credential | Out-Null

Write-Step "creating termsets for $($apps.default.tenant)"
Apply-PnPProvisioningTemplate -Path (Resolve-Path $pwd\files\gridworksconfig\termstore\termsets.xml) -Parameters @{"TermGroupName"="$($apps.default.tenant)"}

Disconnect-PnPOnline
