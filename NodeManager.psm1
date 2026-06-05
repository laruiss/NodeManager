# =============================
# NodeManager Module
# =============================

<#
.SYNOPSIS
Lit un fichier .nvmrc et active la version Node correspondante.
#>
function Invoke-NodeAuto {
    $nvmrc = Get-ChildItem -Path (Get-Location) -Filter ".nvmrc" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($nvmrc) {
        $version = Get-Content $nvmrc.FullName
        Write-Host "Version détectée via .nvmrc : $version"
        nodeuse $version
    } else {
        Write-Host "Pas de .nvmrc trouvé."
    }
}

<#
.SYNOPSIS
Récupère la dernière version LTS de Node.js.
#>
function Get-NodeLatestLTS {
    Write-Host "Récupération de la dernière version LTS..."

    $data = Invoke-RestMethod https://nodejs.org/dist/index.json

    $lts = $data |
        Where-Object { $_.lts -ne $false } |
        Sort-Object { [version]($_.version -replace '^v','') } -Descending |
        Select-Object -First 1

    $version = $lts.version -replace '^v',''

    Write-Host "Dernière LTS détectée : v$version"
    return $version
}

<#
.SYNOPSIS
Retourne le dossier racine des versions Node installées.
#>
function Get-NodeRoot {
    if (Get-Variable -Name nodeVersionsDir -Scope Global -ErrorAction SilentlyContinue) {
        if ($nodeVersionsDir -and $nodeVersionsDir.Trim() -ne "") {
            return $nodeVersionsDir
        }
    }

    return "$env:USERPROFILE\node-versions"
}

<#
.SYNOPSIS
Liste les versions Node installées et indique la version active.
#>
function Get-NodeVersions {
    $root = Get-NodeRoot

    if (-not (Test-Path $root)) {
        Write-Host "Aucune version installée."
        return
    }

    $active = $env:NODE_ACTIVE_VERSION

    Get-ChildItem $root -Directory | ForEach-Object {
        $version = $_.Name -replace "^node-v", ""

        if ($version -eq $active) {
            Write-Host "* v$version (active)"
        } else {
            Write-Host "  v$version"
        }
    }
}

<#
.SYNOPSIS
Télécharge et installe une version de Node.js.

.PARAMETER Version
Version exacte de Node.js à installer.
#>
function Install-NodeVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    $root = Get-NodeRoot

    if (-not (Test-Path $root)) {
        New-Item -ItemType Directory -Path $root | Out-Null
    }

    $nodeDir = "$root\node-v$Version"
    $zipPath = "$root\node-v$Version.zip"
    $url = "https://nodejs.org/dist/v$Version/node-v$Version-win-x64.zip"

    if (Test-Path $nodeDir) {
        Write-Host "Node v$Version déjà installé."
        return
    }

    Write-Host "Téléchargement de Node.js v$Version..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    Expand-Archive -Path $zipPath -DestinationPath $root
    Remove-Item $zipPath

    Rename-Item -Path "$root\node-v$Version-win-x64" -NewName "node-v$Version"

    $npmGlobal = "$nodeDir\npm-global"
    New-Item -ItemType Directory -Path $npmGlobal | Out-Null

    $npmPs1 = "$nodeDir\npm.ps1"
    $npxPs1 = "$nodeDir\npx.ps1"
    if (Test-Path $npmPs1) { Unblock-File -Path $npmPs1 }
    if (Test-Path $npxPs1) { Unblock-File -Path $npxPs1 }

    Write-Host "Node v$Version installé."
}

<#
.SYNOPSIS
Active une version Node installée et isole son npm-global.

.PARAMETER Version
Version exacte de Node.js à activer.
#>
function Use-NodeVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    $root = Get-NodeRoot
    $target = "$root\node-v$Version"

    if (-not (Test-Path $target)) {
        Write-Host "Version non installée : $Version"
        return
    }

    $npmGlobal = "$target\npm-global"
    $defaultRoot = "$env:USERPROFILE\node-versions"
    $rootPrefix = ([System.IO.Path]::GetFullPath($root)).TrimEnd('\') + '\'
    $defaultRootPrefix = ([System.IO.Path]::GetFullPath($defaultRoot)).TrimEnd('\') + '\'

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    # Nettoie uniquement les anciennes entrées gérées par NodeManager dans le PATH utilisateur.
    $cleanUser = ($currentUserPath -split ";") | Where-Object {
        $entry = $_.Trim()
        $entry -ne "" -and
        -not $entry.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $entry.StartsWith($defaultRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $newUserParts = @($target, $npmGlobal, "$npmGlobal\bin") + $cleanUser
    $newUserPath = ($newUserParts | Select-Object -Unique) -join ";"

    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")

    # La session doit inclure User + Machine pour éviter de casser le prompt courant.
    $sessionParts = @($newUserPath)
    if ($machinePath) {
        $sessionParts += $machinePath
    }
    $env:Path = ((($sessionParts -join ";") -split ";") | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique) -join ";"

    [Environment]::SetEnvironmentVariable("NODE_ACTIVE_VERSION", $Version, "User")
    $env:NODE_ACTIVE_VERSION = $Version

    Set-NodeNpmGlobalPrefix -NodeDir $target

    Write-Host "Node v$Version activé ✅"
}

<#
.SYNOPSIS
Résout une version Node (exacte, major ou lts) en version exacte.

.PARAMETER InputVersion
Version demandée (ex: 24, 24.16.0, lts).
#>
function Resolve-NodeVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputVersion
    )

    $data = Invoke-RestMethod https://nodejs.org/dist/index.json

    if ($InputVersion -eq "lts") {
        return ($data | Where-Object { $_.lts } | Select-Object -First 1).version -replace "^v"
    }

    if ($InputVersion -match "^\d+$") {
        $filtered = $data | Where-Object { $_.version -match "^v$InputVersion\." }
        $latest = $filtered | Select-Object -First 1
        return $latest.version -replace "^v"
    }

    return $InputVersion
}

<#
.SYNOPSIS
Active une version Node locale ou l'installe si nécessaire.

.PARAMETER ShortVersion
Version courte, exacte ou alias lts.

.EXAMPLE
nodeuse 24.12.0
Installe la version exacte.

.EXAMPLE
nodeuse 24
Installe la dernière version de la version majeure 24.

.EXAMPLE
nodeuse lts
Installe la dernière version LTS.
#>
function nodeuse {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ShortVersion
    )

    $root = Get-NodeRoot

    if (-not (Test-Path $root)) {
        $resolved = Resolve-NodeVersion "lts"
        Install-NodeVersion $resolved
        Use-NodeVersion -Version "$resolved"
        return
    }

    $versions = Get-ChildItem $root -Directory |
        Where-Object { $_.Name -match "^node-v\d+\.\d+\.\d+$" } |
        Select-Object -ExpandProperty Name |
        ForEach-Object { $_ -replace "^node-v", "" }

    $match = $versions | Where-Object { $_ -like "$ShortVersion*" }

    if (-not $match) {
        $resolved = Resolve-NodeVersion $ShortVersion
        Install-NodeVersion $resolved
        Use-NodeVersion -Version "$resolved"
        return
    }

    $full = ($match | Select-Object -First 1)
    Use-NodeVersion -Version "$full"
}

<#
.SYNOPSIS
Supprime une version Node installÃ©e et nettoie le PATH utilisateur.

.PARAMETER Version
Version exacte de Node.js Ã  supprimer.
#>
function Remove-NodeVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    $root = Get-NodeRoot
    $target = "$root\node-v$Version"

    if (-not (Test-Path $target)) {
        Write-Host "Version non installÃ©e : $Version"
        return
    }

    Write-Host "Suppression de Node v$Version..."

    # Suppression du dossier
    Remove-Item -Recurse -Force $target

    # Nettoyage du PATH utilisateur
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $clean = ($current -split ";") | Where-Object {
        ($_ -ne "$target") -and ($_ -notlike "*node-v$Version\npm-global*")
    }
    [Environment]::SetEnvironmentVariable("Path", ($clean -join ";"), "User")

    Write-Host "Node v$Version supprimÃ© et PATH nettoyÃ©."
}

<#
.SYNOPSIS
Configure le prefix npm global pour la version Node active.
#>
function Set-NodeNpmGlobalPrefix {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NodeDir
    )

    $npmGlobal = "$NodeDir\npm-global"
    if (-not (Test-Path $npmGlobal)) {
        New-Item -ItemType Directory -Path $npmGlobal -Force | Out-Null
    }

    # Persiste et applique immédiatement le prefix npm global pour la session.
    [Environment]::SetEnvironmentVariable("NPM_CONFIG_PREFIX", $npmGlobal, "User")
    $env:NPM_CONFIG_PREFIX = $npmGlobal

    $npmCmd = "$NodeDir\npm.cmd"
    if (Test-Path $npmCmd) {
        try {
            & $npmCmd config set prefix "$npmGlobal" --location=user | Out-Null
        } catch {
            Write-Warning "Impossible de configurer npm prefix automatiquement via npm config."
        }
    }
}

<#
.SYNOPSIS
Resynchronise le PATH de la session à partir de NODE_ACTIVE_VERSION.
#>
function Sync-NodeSessionPath {
    $active = [Environment]::GetEnvironmentVariable("NODE_ACTIVE_VERSION", "User")
    if (-not $active -or $active.Trim() -eq "") {
        return
    }

    $root = Get-NodeRoot
    $defaultRoot = "$env:USERPROFILE\node-versions"
    $rootPrefix = ([System.IO.Path]::GetFullPath($root)).TrimEnd('\') + '\'
    $defaultRootPrefix = ([System.IO.Path]::GetFullPath($defaultRoot)).TrimEnd('\') + '\'
    $target = "$root\node-v$active"

    if (-not (Test-Path "$target\node.exe")) {
        return
    }

    $npmGlobal = "$target\npm-global"
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    $cleanSession = ($env:Path -split ";") | Where-Object {
        $entry = $_.Trim()
        $entry -ne "" -and
        -not $entry.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $entry.StartsWith($defaultRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $sessionParts = @($target, $npmGlobal, "$npmGlobal\bin") + $cleanSession
    if ($machinePath) {
        $sessionParts += ($machinePath -split ";")
    }

    $env:Path = ($sessionParts | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique) -join ";"
    $env:NODE_ACTIVE_VERSION = $active
    Set-NodeNpmGlobalPrefix -NodeDir $target
}

Set-Alias nuse nodeuse
Set-Alias ninst Install-NodeVersion
Set-Alias nrm Remove-NodeVersion
Set-Alias nls Get-NodeVersions
Set-Alias node-auto Invoke-NodeAuto

Sync-NodeSessionPath

Export-ModuleMember -Function * -Alias *
