# settings
Set-Variable -scope global -name apps @{}

$apps.default = @{
    "url" = "";
    "admin_url" = "";
    "credentialtenantfile" = "tenantadmin.xml";
    "credential" = $credential;
};





