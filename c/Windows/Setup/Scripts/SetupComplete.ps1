$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

#region Download and install Docker EE
Write-Verbose 'Download Docker EE'
New-Item -Path "$env:ProgramFiles\Docker" -ItemType Directory
$DockerUrl = Get-Content -Path c:\docker_url.txt
Invoke-WebRequest -UseBasicparsing -Outfile "$env:ProgramFiles\Docker\docker.zip" -Uri $DockerUrl
Expand-Archive -Path "$env:ProgramFiles\Docker\docker.zip" -DestinationPath "$env:ProgramFiles"
Remove-Item -Path "$env:ProgramFiles\Docker\docker.zip"
$env:path += ";$env:ProgramFiles\docker"
& dockerd.exe --register-service
$CurrentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("PATH", "$env:ProgramFiles\Docker" + $CurrentPath, [EnvironmentVariableTarget]::Machine)
#endregion

#region Start docker
Write-Verbose 'Start docker'
Start-Service -Name docker
#endregion

#region Pull base images
Write-Verbose 'Pull base images'
& docker pull microsoft/nanoserver:1709
#endregion