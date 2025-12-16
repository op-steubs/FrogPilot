# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**FrogPilot** is a community-driven fork of openpilot that extends the autonomous driving system with experimental features, personalization options, and advanced driving controls. It follows a modular, process-based architecture built on message-passing (Cap'n Proto) with SCons as the build system.

## Build Commands

### Building the Project
```bash
# Full parallel build (uses all CPU cores)
scons -j$(nproc)

# Build UI only
scons -j8 selfdrive/ui/
# or
cd selfdrive/ui/ && scons -u -j8

# Update dependencies after pulling
git submodule update --init --recursive
tools/ubuntu_setup.sh
```

### Testing
```bash
# Run all tests
pytest .

# Run tests for specific module
cd selfdrive/monitoring && pytest .

# Run linter (pre-commit hooks)
pre-commit run --all
```

### Python Environment
- **Required Python Version**: 3.11.4 (specified in `.python-version`)

## Device Connection

SSH into the comma device:
```bash
ssh -i ~/.ssh/id_ed25519 comma@10.7.7.133
```

- **Hostname**: comma-2a7e1e2
- **User**: comma
- **IP**: 10.7.7.133
- **Port**: 22
- **Key**: ~/.ssh/id_ed25519

### Development Workflow Script

Use `scripts/fp-dev.sh` for the recommended development workflow:

```bash
# Push current branch to GitHub
./scripts/fp-dev.sh push

# Build current branch on device (handles libyuv, params cleanup automatically)
./scripts/fp-dev.sh build

# Switch device to your dev branch and reboot
./scripts/fp-dev.sh test

# Switch device back to safe branch (FrogPilot-Staging)
./scripts/fp-dev.sh safe

# Check status of local and device
./scripts/fp-dev.sh status
```

### Manual Device Deployment
To manually checkout a branch on the comma device:
```bash
cd /data/openpilot
git fetch origin <branch-name>
git checkout -b <branch-name> FETCH_HEAD
scons -j$(nproc)
```

Note: The device's git config doesn't create remote tracking branches automatically, so use `FETCH_HEAD` instead of `origin/<branch-name>` when creating a local branch.

### Build Troubleshooting

**libyuv missing (`cannot find -lyuv`)**: The libyuv submodule may be corrupted. Fix:
```bash
cd /data/openpilot/third_party/libyuv
rm -rf libyuv
./build.sh
```

**UnknownKeyName error for new params**: The params_pyx.so wasn't rebuilt. Clean and rebuild:
```bash
cd /data/openpilot
rm -f common/params_pyx.so common/params_pyx.o common/params_pyx.cpp
PATH=/usr/local/pyenv/versions/3.11.4/bin:$PATH scons --cache-disable -j4 common/params_pyx.so
```

**Full build fails**: Tinygrad models need ONNX files downloaded at runtime. Build only specific targets:
```bash
PATH=/usr/local/pyenv/versions/3.11.4/bin:$PATH scons --cache-disable -j4 common/params_pyx.so selfdrive/ui/ui
```

## Architecture Overview

### Core Directory Structure
- **`frogpilot/`** - FrogPilot-specific features and enhancements
  - `controls/` - Advanced driving control logic (Conditional Experimental Mode, Speed Limit Controller, etc.)
  - `assets/` - Model manager, theme manager, and static resources
  - `navigation/` - Map services and speed limit detection
  - `system/` - System services (statistics, tracking, UI server)
  - `ui/` - Qt-based UI extensions
- **`selfdrive/`** - Core openpilot self-driving logic (upstream base)
  - `car/` - Vehicle interface definitions for 300+ cars
  - `controls/` - Main control algorithms (`controlsd.py`, `plannerd.py`)
  - `modeld/` - ML model processing
- **`system/`** - System services (camera, sensors, logging, hardware abstraction)
- **`cereal/`** - Message definitions using Cap'n Proto (`log.capnp`, `custom.capnp`)
- **`panda/`** - Vehicle communication layer (CAN/OBD interface)
- **`opendbc/`** - Database of vehicle configurations

### Key Components

#### FrogPilot Process (`frogpilot_process.py`)
Central coordinator that handles:
- Model management (downloading, updating, switching models)
- Theme management (downloading, applying themes)
- Automatic openpilot updates
- Map updates
- Statistics and error reporting

Publishes `frogpilotPlan` and subscribes to core topics (`carState`, `controlsState`, `modelV2`, etc.)

#### FrogPilot Planner (`frogpilot/controls/frogpilot_planner.py`)
Advanced driving logic layer with these subcomponents:
- **ConditionalExperimentalMode** - Auto-switches between Chill and Experimental modes based on conditions (curves, stopped leads, low speed)
- **FrogPilotAcceleration** - Custom acceleration profiles
- **FrogPilotFollowing** - Advanced following distance logic
- **FrogPilotVCruise** - Custom cruise control behaviors
- **WeatherChecker** - Adjusts behavior based on weather

#### Model System
Two inference engines available:
- **Classic Model** (`classic_modeld/`) - Runs supercombo model with THNEED/ONNX/GPU runtimes
- **Tinygrad Model** (`tinygrad_modeld/`) - Alternative inference using tinygrad framework

Models are managed by `frogpilot/assets/model_manager.py` which downloads from FrogPilot-Resources repository.

#### Speed Limit Controller (`frogpilot/controls/lib/speed_limit_controller.py`)
Detects speed limits from multiple sources:
- OpenStreetMap offline maps
- Mapbox online data
- Vehicle dashboard (if supported)
- Falls back to Experimental Mode estimation if unavailable

### Message-Oriented Architecture

**Communication**: msgq (message queue) with Cap'n Proto serialization for fast IPC between processes.

**Key Message Topics:**
- Core inputs: `carState`, `carControl`, `controlsState`, `deviceState`, `radarState`, `modelV2`
- FrogPilot custom: `frogpilotPlan`, `frogpilotCarState`, `frogpilotControlsState`, `frogpilotNavigation`, `frogpilotOnroadEvents`
- Model outputs: `modelV2`, `frogpilotModelV2`, `liveParameters`

**Control Loop Rate**: Model processes at ~30Hz (DT_MDL = 0.033s)

### Parameter Management System

Three-tier parameter storage:
```python
params = Params()                          # Persistent (/data/params) - survives reboots
params_cache = Params("/cache/params")     # Semi-persistent - shared between components
params_memory = Params("/dev/shm/params")  # RAM-based - ultra-fast, volatile
```

### Configuration

**Main Config File**: `frogpilot/common/frogpilot_variables.py` (88KB)
- Default parameters for all FrogPilot features
- Model metadata paths
- Device-specific settings
- Feature flags and constants

**Driving Personalities**: Four adjustable profiles (Traffic, Aggressive, Standard, Relaxed) that control following distance, acceleration, and braking style.

## Branch Strategy

| Branch | Install URL | Description | For |
|--------|-------------|-------------|-----|
| **FrogPilot** | frogpilot.download | Main release branch | Everyone |
| **FrogPilot-Staging** | staging.frogpilot.download | Beta features | Early adopters |
| **FrogPilot-Testing** | testing.frogpilot.download | Alpha/bleeding-edge | Advanced testers |
| **FrogPilot-Development** | N/A | Active development - unstable | FrogPilot developers only |
| **MAKE-PRS-HERE** | N/A | Pull request workspace | Contributors |

**Important**: All pull requests MUST target the `MAKE-PRS-HERE` branch. PRs to other branches will be auto-closed.

## Development Workflow

### Pull Requests
PRs should:
1. Target `MAKE-PRS-HERE` branch (enforced by GitHub Actions)
2. Pass automated CI checks (`.github/workflows/`)
3. Include clear description and verification
4. Follow openpilot's priorities: safety, stability, quality, features (in that order)

### Code Style
- Run `pre-commit run --all` before committing
- Use descriptive variable names
- Follow existing patterns in the codebase

### GitHub Actions Build Workflow
**File**: `.github/workflows/compile_frogpilot.yaml`
- Builds for C3 and C3X devices (self-hosted runners)
- Optional translation updates using OpenAI API
- Removes test files and SCons artifacts before deployment
- Force-pushes to release branches (FrogPilot, FrogPilot-Staging, FrogPilot-Testing, or custom)

## Common Patterns

### Feature Flags
Controlled via parameter keys like:
- `DoToggleReset` - Reset to defaults
- `UpdateTinygrad` - Model engine update
- `FlashPanda` - Vehicle interface firmware
- `IssueReported` - Error reporting webhook

### Adding New Parameters
When adding a new parameter/toggle, it must be added to **both** files:
1. **`frogpilot/common/frogpilot_variables.py`** - Parameter definition and default value
2. **`common/params.cc`** - Params whitelist (or you'll get `UnknownKeyName` error)

### Steering Wheel Button Customization
Buttons can be mapped to these functions:
- 0: NOTHING
- 1: PERSONALITY_PROFILE (switch driving personality)
- 2: FORCE_COAST
- 3: PAUSE_LATERAL
- 4: PAUSE_LONGITUDINAL
- 5: EXPERIMENTAL_MODE
- 6: TRAFFIC_MODE

### UI System
**Framework**: Qt-based (C++/Python hybrid)
- Real-time driving screen with customizable themes
- Offroad settings interface
- Screen recorder using OpenMAX codec

## Important Files

| File | Purpose | Size |
|------|---------|------|
| `frogpilot/common/frogpilot_variables.py` | Master configuration file | 88KB |
| `frogpilot/assets/model_manager.py` | Model downloads and updates | 23KB |
| `frogpilot/assets/theme_manager.py` | Theme customization system | 27KB |
| `selfdrive/controls/controlsd.py` | Main control daemon | 45KB |
| `cereal/log.capnp` | Message definitions | - |

## Safety Philosophy

From openpilot upstream:
- **Safety first**: All development prioritizes safety above features
- **Stability**: System must be reliable and predictable
- **Quality**: Well-tested code with clear verification
- **Features**: Last priority - openpilot is considered feature-complete

FrogPilot extends this with experimental features while maintaining the safety-first approach. Always stay attentive when testing new features.

## Community

- **Discord**: https://discord.frogpilot.download
- **Wiki**: https://frogpilot.wiki.gg/
- Bug reports: `#bug-reports` channel
- Feature requests: `#feature-requests` channel

## Key Dependencies

- **cereal**: Cap'n Proto messaging
- **msgq**: High-speed message queue
- **panda**: CAN/OBD vehicle communication
- **opendbc**: Vehicle configuration database
- **tinygrad**: ML inference framework
- **Qt5**: UI framework
- **OpenCV**: Computer vision
