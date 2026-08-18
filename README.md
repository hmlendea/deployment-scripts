[![Donate](https://img.shields.io/badge/-%E2%99%A5%20Donate-%23ff69b4)](https://hmlendea.go.ro/funding)
[![License](https://img.shields.io/github/license/hmlendea/deployment-scripts)](https://github.com/hmlendea/deployment-scripts/blob/master/LICENSE)

# Deployment Scripts

Deployment-oriented shell scripts for Linux environments. The repository includes MonoGame SDK installers for Ubuntu virtual machines, Raspberry Pi service deployment helpers that retrieve GitHub release artefacts, and .NET release packaging scripts for multiple target runtime generations.

## 📑 Table of Contents

- [Capabilities](#-capabilities)
- [Use Cases](#-use-cases)
- [Usage](#-usage)
  - [Examples](#examples)
- [Command Reference](#️-command-reference)
- [Known Limitations](#️-known-limitations)
- [System Requirements](#️-system-requirements)
- [Installation](#-installation)
  - [Installation From Source](#installation-from-source)
- [Configuration](#️-configuration)
  - [Configuration Files](#configuration-files)
  - [Settings](#settings)
- [Compatibility](#-compatibility)
- [Project Structure](#️-project-structure)
  - [Directories](#directories)
- [Deployment](#-deployment)
- [Contributing](#-contributing)
- [Project Engagement](#-project-engagement)
- [License](#-license)

## ✨ Capabilities

- Install MonoGame SDK dependencies, native libraries, fonts, and tooling on Ubuntu-based virtual machines.
- Package self-contained .NET release artefacts for Linux, macOS, and Windows from a local solution or project directory.
- Retrieve the latest GitHub release for a service, unpack the appropriate asset for the host architecture, and launch it locally.
- Generate and register `systemd` unit files for deployed services on Raspberry Pi or other Linux hosts.
- Apply post-deployment `appsettings*.json` substitutions for .NET and ASP.NET Core applications.

## 🎯 Use Cases

- **MonoGame environment provisioning:** Prepare an Ubuntu VM for building or running MonoGame applications.
- **.NET release packaging:** Produce versioned release archives or binaries for multiple runtimes from a local repository.
- **Service deployment:** Install or update a GitHub-hosted application release on a Raspberry Pi and expose it through `systemd`.

## 🚀 Usage

```bash
# Package a .NET release from the current solution or project directory
bash ./release/dotnet/10.0.sh 1.2.3

# Install or update the latest release of a GitHub-hosted service
cd raspberry-pi
bash ./start-service.sh owner/repository

# Register the deployed service with systemd
sudo bash ./install-service.sh repository
```

### Examples

```bash
# Install MonoGame 3.8.x into the current working directory
cd monogame
bash ./install-monogame.sh 3.8.1.303

# Install the legacy MonoGame 3.6 SDK workflow
bash ./install-monogame-3.6.sh

# Deploy an ASP.NET Core release that should listen on port 8080
cd ../raspberry-pi
bash ./start-service.sh owner/web-service 8080
sudo bash ./install-service.sh web-service 8080
```

## ⌨️ Command Reference

| Command | Description |
|---------|-------------|
| `bash ./monogame/install-monogame.sh <monogame-version>` | Downloads and installs the specified MonoGame SDK release together with required Ubuntu dependencies. |
| `bash ./monogame/install-monogame-3.6.sh` | Runs the legacy MonoGame 3.6 installation workflow. |
| `bash ./raspberry-pi/start-service.sh <repository-or-owner/repository> [port] [args...]` | Downloads the latest compatible GitHub release asset, prepares the service directory, optionally patches `appsettings*.json`, and launches the application. |
| `sudo bash ./raspberry-pi/install-service.sh <service-name> [args...]` | Creates or refreshes a `systemd` unit that executes `start-service.sh` for the named service. |
| `bash ./release/dotnet/<dotnet-version>.sh <version>` | Publishes a self-contained .NET release for the runtime identifiers encoded in the selected script. |

## ⚠️ Known Limitations

- The MonoGame installation scripts are tailored to Ubuntu-style environments and depend on `apt-get`, `sudo`, `wget`, `unzip`, and `make`.
- The deployment workflow expects GitHub releases tagged as `v<version>` and Linux assets whose names either match `<repository>_<version>_<platform>.zip` or contain Linux and architecture markers.
- `monogame/install-monogame.sh` currently does not handle font file paths containing spaces.
- The .NET release scripts assume the current repository contains a `.sln`, `.slnx`, or `.csproj` layout that can be resolved automatically.

## 🖥️ System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Operating system | Linux | Ubuntu for MonoGame tasks; Raspberry Pi OS or another `systemd`-based Linux distribution for service deployment |
| Shell environment | Bash | Bash with `sudo` access |
| Core utilities | `git`, `curl`, `wget`, `unzip`, `zip`, `jq`, `find`, `sed`, `awk` | Current distribution packages |
| .NET SDK | Matching SDK for the selected release script and target project | Current supported SDK that matches the application being packaged |

## 📦 Installation

### Installation From Source

```bash
git clone https://github.com/hmlendea/deployment-scripts.git
cd deployment-scripts
chmod +x monogame/*.sh raspberry-pi/*.sh release/dotnet/*.sh
```

## ⚙️ Configuration

The Raspberry Pi deployment scripts read a small local configuration file and, for .NET services, can optionally apply post-deployment settings substitutions from a CSV file stored in the deployment root directory.

### Configuration Files

| File | Scope | Purpose |
|------|-------|---------|
| `raspberry-pi/config.conf` | Host-local | Declares the deployment root directory and default GitHub credentials used for release discovery and downloads. |
| `<DeploymentRootDirectory>/appsettings.csv` | Deployment root | Defines optional substitutions that are applied to `appsettings*.json` files after a service package is unpacked. |

### Settings

The subsequent settings are recognised:
| Section | Key | Type | Default | Required | Description |
|---------|-----|------|---------|----------|-------------|
| — | `DeploymentRootDirectory` | `string` | `—` | Yes | Root directory under which deployed services, temporary files, and generated launchers are stored. |
| — | `GitHubUsername` | `string` | `—` | Yes | Default GitHub owner used when `start-service.sh` is invoked with only a repository name. |
| — | `GitHubAccessToken` | `string` | `empty` | No | Optional token used for authenticated GitHub API requests and asset downloads. |

## 🧩 Compatibility

| Component | Supported Versions | Notes |
|-----------|--------------------|-------|
| MonoGame installer workflow | MonoGame 3.6 and later script-driven releases | The repository contains a dedicated legacy script for 3.6 and a parameterised installer for later versions. |
| .NET release packaging scripts | 2.2, 3.1, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 | Each script targets a specific packaging workflow and publishes for multiple runtime identifiers. |
| Deployment host architectures | `x86_64`, `aarch64`, `arm` | `start-service.sh` selects `linux-x64`, `linux-arm64`, or `linux-arm` assets based on the detected CPU architecture. |

## 🗂️ Project Structure

The repository is organised by deployment scenario rather than by programming language or application.

### Directories

| Directory | Purpose |
|-----------|---------|
| `monogame/` | Ubuntu-oriented MonoGame SDK installation scripts, including a legacy MonoGame 3.6 workflow. |
| `raspberry-pi/` | Service deployment and `systemd` registration scripts for Raspberry Pi and similar Linux hosts. |
| `release/dotnet/` | Version-specific .NET release packaging scripts for generating self-contained artefacts. |

## 🚢 Deployment

The deployment workflow is intended for Linux hosts that retrieve published GitHub release artefacts and execute them as services.

1. Create `raspberry-pi/config.conf` with at least `DeploymentRootDirectory` and `GitHubUsername`.
2. Optionally create `<DeploymentRootDirectory>/appsettings.csv` if deployed .NET applications require post-deployment configuration substitution.
3. Run `bash ./raspberry-pi/start-service.sh owner/repository [port]` to download the latest compatible artefact, unpack it, and generate a launcher.
4. Run `sudo bash ./raspberry-pi/install-service.sh <service-name> [args...]` to register or refresh the corresponding `systemd` service.

## 🤝 Contributing

You are welcome to submit any suggestion, feedback, or modification to this project.

When doing so, please:
- Maintain cross-platform compatibility
- Submit focused pull requests that conform to the existing code style
- Maintain your branch synchronised with `master`
- Revise the documentation when functionality changes
- Raise a new [issue](https://github.com/hmlendea/deployment-scripts/issues) for problems or suggestions

## 💝 Project Engagement

Discovered a problem or have a suggestion? [Open an issue](https://github.com/hmlendea/deployment-scripts/issues)!

If you find this project useful, consider [funding it](https://hmlendea.go.ro/funding) or starring ⭐️ it on GitHub!

[![Donate](https://raw.githubusercontent.com/hmlendea/readme-assets/master/donate_generic.png)](https://hmlendea.go.ro/funding)

## 📄 License

This project is being distributed under the `GNU General Public License v3.0`.
See [LICENSE](./LICENSE) for further information.
