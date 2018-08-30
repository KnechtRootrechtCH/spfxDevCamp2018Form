# -----------------------------------------------------------------------------
# Author: ro@garaio.com
# Order: 10
# -----------------------------------------------------------------------------


$adminUrl = $apps.default.admin_url

Connect-PnPOnline -Url $adminUrl -Credentials $apps.default.credential | Out-Null

Write-Step "export termsets for $($apps.default.tenant)"

$termsetsFile = (Resolve-Path $pwd\files\gridworksconfig\termstore\termsets-test.xml)
Export-PnPTermGroupToXml -Identity "cloud67" -FullTemplate -Out $termsetsFile -Force


Disconnect-PnPOnline
