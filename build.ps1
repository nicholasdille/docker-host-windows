[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Name
    ,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
    ,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $IsoPath
    ,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $EditionIndex
    ,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $UpdatePath
    ,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $MountPath
    ,
    [Parameter()]
    [ValidateSet('CE', 'EE')]
    [string]
    $DockerEdition = 'CE'
    ,
    [Parameter()]
    [ValidateSet('stable', 'edge', 'testing')]
    [string]
    $DockerChannel = 'stable'
    ,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $DockerVersion
)

#$IsoPath = "$PSScriptRoot\en_windows_server_version_1709_x64_dvd_100090904.iso"
#$EditionIndex = 2
#$Name = 'Server1709'

#$IsoPath = "$PSScriptRoot\14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_EN-US.ISO"
#$EditionIndex = 3
#$Name = 'ws16eval'

$BaseImagePath = "$Path\$Name.vhdx"
$PatchedImagePath = "$Path\$Name-patch.vhdx"
$DockerImagePath = "$Path\$Name-docker.vhdx"
$MergedImagePath = "$Path\$Name-final.vhdx"
$DiffImagePath = "$Path\$Name-diff.vhdx"

if (-not (Test-Path -Path .\Convert-WindowsImage.ps1)) {
    Write-Error 'Please obtain Convert-WindowsImage.ps1 from ISO of Windows Server 2016 and place in save directory.'
    return
}
. .\Convert-WindowsImage.ps1
. "$PSScriptRoot\functions.ps1"

if (-not $DockerVersion) {
    $DockerVersion = Get-DockerVersion -Edition $DockerEdition -Channel $DockerChannel
}
"https://download.docker.com/win/static/$DockerChannel/x86_64/docker-$DockerVersion-$($DockerEdition.ToLower()).zip" | Set-Content -Path "$PSScriptRoot\c\docker_url.txt"

if (-not (Test-Path -Path $BaseImagePath)) {
    $IsoPath = Get-Item -Path $IsoPath
    if (-not (Test-Path -Path $IsoPath)) {
        Write-Warning 'Specified ISO does not exist'
        return
    }

    $DriveLetter = Mount-Image -Path $IsoPath
    if (-not $DriveLetter) {
        Write-Warning 'Unable to determine drive letter'
        return
    }
    if (-not $EditionIndex) {
        Write-Warning 'EditionIndex not specified'
        dism /Get-WimInfo /WimFile:"$($DriveLetter):\sources\install.wim"
        return
    }
    Convert-WindowsImage -SourcePath "$($DriveLetter):\sources\install.wim" -Edition $EditionIndex -VHDPath $BaseImagePath -SizeBytes 128GB -VHDFormat VHDX -DiskLayout UEFI
    Dismount-DiskImage -ImagePath $IsoPath
}

if (-not $UpdatePath) {
    $null = New-VHD -Path $PatchedImagePath -ParentPath $BaseImagePath -Differencing -ErrorAction Stop
}
if (-not (Test-Path -Path $PatchedImagePath)) {
    $null = New-VHD -Path $PatchedImagePath -ParentPath $BaseImagePath -Differencing -ErrorAction Stop
    $PatchedImagePath = Get-Item -Path $PatchedImagePath

    $Data = dism /Get-ImageInfo /ImageFile:$PatchedImagePath /Index:1
    $Line = $Data | Where-Object { $_ -like 'Version : *' }
    if ($Line -match '10.0.(.+)$') {
        $Build = $Matches[1]
    }
    if (-not $Build) {
        Write-Warning 'Unable to determine build version'
        return
    }

    $Files = Get-ChildItem -Path $UpdatePath | Select-Object -ExpandProperty FullName
    $UpdateDefinition = Get-UpdateDefinition -Build $Build
    $LatestUpdate = Find-Update -UpdateDefinition $UpdateDefinition -Files $Files

    if ($LatestUpdate) {
        Mount-ImageUsingDism -ImagePath $PatchedImagePath -MountPath $MountPath
        if (Test-ImageUsingDism -ImagePath $PatchedImagePath) {
            Add-UpdateUsingDism -MountPath $MountPath -UpdatePath $LatestUpdate
            $Files | Where-Object { $_ -ne $LatestUpdate } | ForEach-Object {
                Add-UpdateUsingDism -MountPath $MountPath -UpdatePath $_
            }
            Unmount-ImageUsingDism -MountPath $MountPath

        } else {
            Write-Warning 'Unable to mount for patching'
            return
        }
    }
}

if (-not (Test-Path -Path $DockerImagePath)) {
    $null = New-VHD -Path $DockerImagePath -ParentPath $PatchedImagePath -Differencing -ErrorAction Stop
    $DockerImagePath = Get-Item -Path $DockerImagePath

    # TODO add admin password from parameter

    Mount-ImageUsingDism -ImagePath $DockerImagePath -MountPath $MountPath
    if (Test-ImageUsingDism -ImagePath $DockerImagePath) {
        Add-FeatureUsingDism -MountPath $MountPath -FeatureName 'Containers'
        Copy-Item -Path "$PSScriptRoot\c\*" -Destination $MountPath -Recurse -Force
        Unmount-ImageUsingDism -MountPath $MountPath
    }
}

if (-not (Test-Path -Path $MergedImagePath)) {
    Convert-VHD -Path $DockerImagePath -DestinationPath $MergedImagePath -VHDType Dynamic -ErrorAction Stop
}

if (-not (Test-Path -Path $DiffImagePath)) {
    $null = New-VHD -Path $DiffImagePath -ParentPath $MergedImagePath -Differencing -ErrorAction Stop

    Get-VM -Name test | Get-VMHardDiskDrive | Remove-VMHardDiskDrive
    $HardDrive = Get-VM -Name test | Add-VMHardDiskDrive -Path $DiffImagePath -Passthru

    Set-VMFirmware -VMName test -FirstBootDevice $HardDrive
}