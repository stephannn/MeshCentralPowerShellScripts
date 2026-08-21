# MeshCentralPowerShellScripts
PowerShell Scripts for MeshCentral

The script _meshcentral_duplicates.ps1_ moves devices with the same serial number into the mesh Duplicates. To remove duplicates instead of moving change the code: 

_Set-MeshCentralData -action changeDeviceMesh -requestData @{nodeids=@($_.MCDeviceID); meshid=$deviceGroup.GroupID }_

to:

_Remove-MeshCentralData -action removedevices -requestData @{nodeids=@($_.MCDeviceID); meshid=$deviceGroup.GroupID }_

The Config.xml contains required information to connect to the MeshCentral server.
