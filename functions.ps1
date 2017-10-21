function Get-DockerVersion {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('CE', 'EE')]
        [string]
        $Edition = 'CE'
        ,
        [Parameter()]
        [ValidateSet('stable', 'edge', 'testing')]
        [string]
        $Channel = 'stable'
    )

    try {
        $Content = Invoke-WebRequest -UseBasicParsing -Uri "https://download.docker.com/win/static/$Channel/x86_64/" | Select-Object -ExpandProperty Content
    } catch {
        throw 'Failed to download list of Docker versions'
    }

    $StartIndex = 0
    $Index = $Content.IndexOf('href="docker-', $StartIndex)
    while ($Index -gt -1) {
        $EndIndex = $Content.IndexOf("-$($Edition.ToLower()).zip", $Index)
        $Version = $Content.substring($Index + 6 + 7, ($EndIndex + 2 - 7 - 7) - ($Index + 1))
        $StartIndex = $Index + 1
        $Index = $Content.IndexOf('href="docker-', $StartIndex)
    }

    $Version
}

function Mount-Image {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    $MountInfo = Mount-DiskImage -ImagePath $Path -PassThru
    $MountInfo | Get-Volume | Select-Object -ExpandProperty DriveLetter
}

function Get-UpdateDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Build
    )

    try {
        Invoke-RestMethod -Uri 'https://support.microsoft.com/app/content/api/content/asset/en-us/4000816' | Select-Object -ExpandProperty links | Where-Object { $_.text -like "*OS Build $Build.*" } | Sort-Object -Property id -Descending
    } catch {
        throw 'Unable to download update definitions from Microsoft'
    }
}

function Find-Update {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject[]]
        $UpdateDefinition
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Files
    )

    $LatestUpdate = ''
    foreach ($Update in $UpdateDefinition) {
        $kbId = $Update.articleId
        $LatestUpdate = $Files | Where-Object { $_ -like "*-kb$kbId-*" }

        if ($LatestUpdate) {
            break
        }
    }

    $LatestUpdate
}

function Test-ImageUsingDism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ImagePath
    )

    [bool](dism /Get-MountedImageInfo | Select-String -SimpleMatch "$ImagePath")
}

function Mount-ImageUsingDism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ImagePath
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $MountPath
    )

    dism /Mount-Image /ImageFile:$ImagePath /Index:1 /MountDir:$MountPath
}

function Add-UpdateUsingDism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $MountPath
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $UpdatePath
    )

    dism /Image:$MountPath /Add-Package /PackagePath:$UpdatePath
}

function Add-FeatureUsingDism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $MountPath
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FeatureName
    )

    dism /Image:$MountPath /Enable-Feature /FeatureName:$FeatureName
}

function Unmount-ImageUsingDism {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $MountPath
    )

    dism /Unmount-Image /MountDir:$MountPath /Commit
}