# NodeManager

NodeManager is a PowerShell module to install, switch, and manage Node.js versions on Windows without administrator rights.

It is designed for company-managed laptops where MSI installers and system-wide writes are often blocked.

## Why this module exists

In many corporate environments:

- You cannot install Node.js with admin-only installers.
- You need multiple Node.js versions across projects.
- Global npm installs fail because the default prefix points to protected locations.

NodeManager solves this by:

- Installing Node.js from official zip archives.
- Managing per-user Node.js versions in a dedicated folder.
- Switching versions by updating user PATH.
- Configuring a per-version npm global prefix automatically.

## Features

- Install a specific Node.js version.
- Use exact versions, major versions, or latest LTS.
- Auto-detect a Node version by finding the first `.nvmrc` file under the current directory tree.
- Isolate global npm packages per Node version.
- Keep Node.js state in user scope (no admin required).

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Internet access to https://nodejs.org
- User permission to write to your profile directory (hopefully this is always true)

## Installation

### Option 1: From PowerShell Gallery

```powershell
Install-Module NodeManager -Scope CurrentUser
Import-Module NodeManager
```

### Option 2: From source

Clone this repository and copy the module folder to:

- Windows PowerShell: $HOME\Documents\WindowsPowerShell\Modules\NodeManager
- PowerShell 7: $HOME\Documents\PowerShell\Modules\NodeManager

Then run:

```powershell
Import-Module NodeManager -Force
```

## Optional configuration

By default, versions are stored in:

- `$env:USERPROFILE\node-versions`

To use another folder, set a global variable in your PowerShell profile before importing the module:

```powershell
$global:nodeVersionsDir = "C:\installs\nodejs"
Import-Module NodeManager
```

## Quick start

```powershell
# Install and use latest LTS
nodeuse lts

# Install and use latest patch for major 24
nodeuse 24

# Install and use exact version
nodeuse 24.16.0

# List installed versions
nls

# Remove a version
nrm 24.16.0
```

## Commands

### Main functions

- `Invoke-NodeAuto`: search .nvmrc and activate matching version
- `Get-NodeLatestLTS`: return latest LTS version
- `Get-NodeRoot`: return storage root folder
- `Get-NodeVersions`: list installed versions and active version
- `Install-NodeVersion`: download and install a version
- `Use-NodeVersion`: activate an installed version
- `Resolve-NodeVersion`: resolve lts or major to exact version
- `nodeuse`: install if needed, then activate
- `Remove-NodeVersion`: remove an installed version

### Aliases

- `nuse` -> nodeuse
- `ninst` -> Install-NodeVersion
- `nrm` -> Remove-NodeVersion
- `nls` -> Get-NodeVersions
- `node-auto` -> Invoke-NodeAuto

## How npm global packages are handled

For each active Node.js version, NodeManager ensures a dedicated npm global folder:

- `<NodeDir>\npm-global`

It then sets:

- `NPM_CONFIG_PREFIX` (User and current session)
- `npm config prefix --location=user`

This avoids writing to protected system folders and keeps globals isolated per version.

## Troubleshooting

### node is not recognized in a new terminal

Run:

```powershell
Import-Module NodeManager -Force
```

NodeManager synchronizes session `PATH` from the active user configuration on import.

### Version appears active in prompt but command is missing

Check where versions are stored:

```powershell
nls
```

Ensure your profile sets `nodeVersionsDir` before `Import-Module` if you use a custom directory.

## Publishing

This module is intended to be published on PowerShell Gallery.

Before publishing:

- Update ModuleVersion in NodeManager.psd1
- Update ReleaseNotes
- Ensure ProjectUri and LicenseUri are valid
- Run Test-ModuleManifest

Then publish:

```powershell
Publish-Module -Path . -Repository PSGallery -NuGetApiKey <YOUR_API_KEY>
```

## License

MIT. See LICENSE.
