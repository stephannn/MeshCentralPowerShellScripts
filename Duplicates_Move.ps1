# Get Script location
if ($PSScriptRoot.Length -eq 0) {
    $Scriptlocation = (get-location).path
} else {
    $Scriptlocation = $PSScriptRoot
}

$configPath = Join-Path ($Scriptlocation) "config.xml"
if((Test-Path $configPath) -eq $false){
	Write-Host "Config file config.xml not found"
	#exit 1
    throw "Config file config.xml not found"
}

$config = [xml](Get-Content -Path $configPath -Encoding UTF8)

Import-Module "$Scriptlocation\MeshCentralModule.psd1"

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

$groupNameExpected = "Duplicates"

$Global:LogFilePath = "$Scriptlocation\Duplicates_Move.log"

Write-Log -Component "Initial Setup" -LogText "Setting connection"

Set-ConnectionDetails -serverUrl "$($serverProtocol)://$meshServer/control.ashx" -username $username -password $password

$MCDeviceDetails = Get-MeshCentralData -action getDeviceDetails
$MCMeshesResult = Get-MeshCentralData -action meshes
$MCNodesResult = Get-MeshCentralData -action nodes

if($MCNodesResult -and $MCMeshesResult){
	$LinqJoinedData = [System.Linq.Enumerable]::GroupJoin(
		$MCNodesResult,
		$MCMeshesResult,
		[System.Func[Object,string]] {param ($x);$x.DeviceGroupID.ToUpper()},
		[System.Func[Object,string]]{param ($Y);$y.GroupID.ToUpper()},
		[System.Func[System.Object, [Collections.Generic.IEnumerable[System.Object]], System.Object]]{
			param ($LeftJoin,$RightJoinEnum);
			$RightJoin = [System.Linq.Enumerable]::SingleOrDefault($RightJoinEnum)
			#$LeftJoin = [System.Linq.Enumerable]::SingleOrDefault($y)
			New-Object -TypeName PSObject -Property @{
				MCDeviceID = $LeftJoin.DeviceID;
				MCDeviceName = $LeftJoin.DeviceName;
				MCDeviceGroupID = $LeftJoin.DeviceGroupID;
				MCGroupName = $RightJoin.GroupName;
			}
		}
	)

	$OutputArrayMCNodeMesh = [System.Linq.Enumerable]::ToArray($LinqJoinedData)

}

if($MCDeviceDetails -and $OutputArrayMCNodeMesh) {

	$LinqJoinedData = [System.Linq.Enumerable]::GroupJoin(
		$OutputArrayMCNodeMesh,
		$MCDeviceDetails,
		[System.Func[Object,string]] {param ($x);$x.MCDeviceID.ToUpper()},
		[System.Func[Object,string]]{param ($Y);$y.DeviceID.ToUpper()},
		[System.Func[System.Object, [Collections.Generic.IEnumerable[System.Object]], System.Object]]{
			param ($LeftJoin,$RightJoinEnum);
			$RightJoin = [System.Linq.Enumerable]::SingleOrDefault($RightJoinEnum)
			#$LeftJoin = [System.Linq.Enumerable]::SingleOrDefault($y)
			New-Object -TypeName PSObject -Property @{
				MCDeviceID = $LeftJoin.MCDeviceID;
				MCDeviceName = $LeftJoin.MCDeviceName;
				MCDeviceGroupID = $LeftJoin.MCDeviceGroupID;
				MCDeviceGroupName = $LeftJoin.MCGroupName;
				MCDeviceSerialNumber = $RightJoin.SerialNumber;
				MCDeviceLastConnectTime = $RightJoin.LastConnectTime;
			}
		}
	)
	$OutputArrayMCNodeDetailMesh = [System.Linq.Enumerable]::ToArray($LinqJoinedData)
}

$deviceGroup = $MCMeshesResult | Where-Object { $_.GroupName -eq $groupNameExpected}

# Duplicates
if($OutputArrayMCNodeDetailMesh){
	($OutputArrayMCNodeDetailMesh | Group-Object MCDeviceSerialNumber | Where-Object {$_.Count -gt 1} | Select Group) | ForEach-Object {
        $_.Group | Where-Object { $_.MCDeviceGroupID -ne $deviceGroup.GroupID } | Sort-Object MCDeviceLastConnectTime | Select-Object -SkipLast 1 | ForEach-Object {
            if($null -ne $_.MCDeviceID -and $null -ne $deviceGroup.GroupID -and $_.MCDeviceGroupID -ne $deviceGroup.GroupID ){
			    Write-Host "Moving Device: $($_.MCDeviceName) ($( $_.MCDeviceID)) from group: $($_.MCDeviceGroupName) ($($_.MCDeviceGroupID)) to: $($deviceGroup.GroupName) ($($deviceGroup.GroupID))"
			    Write-Log -Component $Component -LogText "Moving Device: $($_.MCDeviceName) ($( $_.MCDeviceID)) from group: $($_.MCDeviceGroupName) ($($_.MCDeviceGroupID)) to: $($deviceGroup.GroupName) ($($deviceGroup.GroupID))"
			
			    Set-MeshCentralData -action changeDeviceMesh -requestData @{nodeids=@($_.MCDeviceID); meshid=$deviceGroup.GroupID }
		    }
        }

    }
}

#Remove-Module MeshCentralModule