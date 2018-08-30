# tenant name
$apps.default.tenant = "gw365dev"

# Configure shortname only !!!
$adminshortname = ($env:UserName).SubString(0,($env:UserName).IndexOf('0'))

$apps.default.administrator = "$($adminshortname)@gw365dev.onmicrosoft.com"
$sitename = "$($adminshortname)app"

# tenant url's
$apps.default.url = "https://$($apps.default.tenant).sharepoint.com/sites/$($sitename)"
$apps.default.admin_url = "https://$($apps.default.tenant)-admin.sharepoint.com"

$tenantAdminPath = "$env_dir\$environment\" + $apps.default.credentialtenantfile

$credentialFile = Import-Clixml $($tenantAdminPath)
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentialFile.UserName, $credentialFile.Password
$apps.default.credential = $credential
