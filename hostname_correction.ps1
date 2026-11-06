# Get Script location
if ($PSScriptRoot.Length -eq 0) {
    $Scriptlocation = (get-location).path
} else {
    $Scriptlocation = $PSScriptRoot
}

Import-Module "$Scriptlocation\MeshCentralModule.psd1"

[string]$Global:LogFilePath = $(Join-Path -Path $Scriptlocation -ChildPath 'MeshCentral_Hostname_Correction.log')

[string]$Component = "Config"
$configPath = Join-Path ($Scriptlocation) "Config.xml"
if((Test-Path $configPath) -eq $false){
	Write-Log -Component $Component -LogText "Config file config.xml not found in: $configPath" -Type Error
	Exit 1
    #throw "Config file config.xml not found"
}

$config = [xml](Get-Content -Path $configPath -Encoding UTF8)

## missing
## check if server is reachable
## check if username password are correct

$global:authHeader = $null
$global:serverUrl = $null

$username = $config.config.username
$password = $config.config.password
$meshServer = $config.config.meshServer
$serverProtocol = $config.config.serverProtocol

if([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($password) -or [string]::IsNullOrEmpty($meshServer) -or [string]::IsNullOrEmpty($serverProtocol)){
    throw "Config file incomplete"
}

$Component = "MeshCentral"

Write-Log -Component "Initial Setup" -LogText "Setting connection"

Set-ConnectionDetails -serverUrl "$($serverProtocol)://$meshServer/control.ashx" -username $username -password $password

$MCDeviceDetails = Get-MeshCentralData -action getDeviceDetails

$MCDeviceDetails | Where-Object {$_.MeshName -ne $_.DeviceName} | ForEach-Object {
    Write-Host "Renaming MeshName from: $($_.MeshName) to $($_.DeviceName)"
    Write-Log -Component $Component -LogText "Renaming MeshName from: $($_.MeshName) to ($( $_.DeviceName))"

    Set-MeshCentralData -action changedevice -requestData @{id="$($_.DeviceId)"; name=$_.DeviceName.Trim()}
}

Remove-Module MeshCentralModule

Write-Log -Component $Component -LogText "Finishing MeshCentral Hostname correction"