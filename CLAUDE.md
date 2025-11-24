# CLAUDE.md - AI Assistant Guide for FrogPilot

**Last Updated:** November 24, 2025
**Repository:** FrogPilot - Advanced openpilot Fork
**Version:** 0.9.7+

---

## Table of Contents

1. [Overview](#overview)
2. [Repository Structure](#repository-structure)
3. [Architecture & Key Concepts](#architecture--key-concepts)
4. [Development Workflows](#development-workflows)
5. [Code Conventions](#code-conventions)
6. [Testing & Quality](#testing--quality)
7. [Common Tasks](#common-tasks)
8. [FrogPilot-Specific Features](#frogpilot-specific-features)
9. [Safety & Best Practices](#safety--best-practices)
10. [Troubleshooting](#troubleshooting)

---

## Overview

### What is FrogPilot?

**FrogPilot** is a community-driven fork of comma.ai's openpilot that provides bleeding-edge autonomous driving features. It's built on a distributed process architecture where 40+ independent daemons communicate via Cap'n Proto messages to control vehicle steering, acceleration, and braking.

### Key Facts for AI Assistants

- **Primary Languages:** Python (1,444 files), C++ (794 files)
- **Build System:** SCons (Python-based)
- **Message Passing:** Cereal (Cap'n Proto over shared memory)
- **Target Hardware:** comma 3/3X devices (aarch64 Linux)
- **Control Loop:** 100Hz main control, 20Hz vision models
- **Supported Vehicles:** 275+ cars across 16 manufacturers

### Repository Location

```
/home/user/FrogPilot/
```

All paths in this document are relative to this root directory.

---

## Repository Structure

### Top-Level Organization

```
FrogPilot/
├── selfdrive/          # Core openpilot functionality
│   ├── car/            # Per-manufacturer car interfaces (Toyota, Honda, etc.)
│   ├── controls/       # Main control loop (controlsd, plannerd, radard)
│   ├── modeld/         # Vision model inference
│   ├── locationd/      # Localization, calibration, parameter estimation
│   ├── navd/           # Navigation and routing
│   ├── monitoring/     # Driver monitoring
│   ├── pandad/         # Panda hardware interface
│   └── ui/             # Qt-based user interface (C++)
│
├── frogpilot/          # FrogPilot-specific enhancements
│   ├── controls/       # Enhanced control features (AOL, CEM, personalities)
│   ├── navigation/     # Map management (mapd)
│   ├── system/         # System utilities (speed_limit_filler, the_pond)
│   ├── assets/         # Model/theme managers
│   ├── ui/             # FrogPilot UI extensions
│   ├── classic_modeld/ # ONNX model support
│   ├── tinygrad_modeld/# Tinygrad model support
│   └── common/         # FrogPilot variables and utilities
│
├── system/             # System-level services
│   ├── camerad/        # Camera capture (C++)
│   ├── loggerd/        # Data logging and encoding (C++)
│   ├── sensord/        # IMU/sensor collection (C++)
│   ├── manager/        # Process lifecycle management
│   ├── hardware/       # Hardware abstraction layer
│   ├── athena/         # Cloud connectivity
│   ├── ubloxd/         # GPS daemon (u-blox)
│   └── qcomgpsd/       # GPS daemon (Qualcomm)
│
├── cereal/             # Message schemas (Cap'n Proto)
│   ├── log.capnp       # Main logging schema
│   ├── car.capnp       # Car interface schema
│   ├── custom.capnp    # FrogPilot custom messages
│   └── services.py     # Service definitions
│
├── common/             # Shared utilities
├── panda/              # CAN bus hardware interface
├── opendbc/            # CAN message database
├── third_party/        # External dependencies
├── tools/              # Development tools
└── docs/               # Documentation

Key Symlinks:
- msgq -> msgq_repo/msgq
- rednose -> rednose_repo/rednose
- tinygrad -> tinygrad_repo/tinygrad
```

### Critical Files by Function

#### System Bootstrap
- `launch_openpilot.sh` - Entry point
- `launch_chffrplus.sh` - Main launcher
- `launch_env.sh` - Environment configuration
- `system/manager/manager.py` - Process orchestrator
- `system/manager/process_config.py` - Process definitions (40+ daemons)

#### Control System
- `selfdrive/controls/controlsd.py` - Main control loop (100Hz)
- `selfdrive/controls/plannerd.py` - Motion planning
- `selfdrive/controls/radard.py` - Object detection/tracking
- `selfdrive/controls/lib/latcontrol*.py` - Lateral (steering) control
- `selfdrive/controls/lib/longcontrol.py` - Longitudinal (speed) control

#### Configuration & Parameters
- `frogpilot/common/frogpilot_variables.py` - **90+ FrogPilot parameters**
- `common/params.py` - Parameter storage system
- `system/version.py` - Version management

#### Car Integration
- `selfdrive/car/*/interface.py` - Car-specific interfaces
- `selfdrive/car/*/carstate.py` - CAN message parsing
- `selfdrive/car/*/carcontroller.py` - Control signal generation
- `selfdrive/car/*/values.py` - Car constants and limits

#### User Interface
- `selfdrive/ui/ui.cc` - Main UI application (C++)
- `selfdrive/ui/qt/offroad/settings.cc` - Settings screen
- `frogpilot/ui/qt/offroad/frogpilot_settings.cc` - FrogPilot settings

#### FrogPilot Features
- `frogpilot/frogpilot_process.py` - FrogPilot main daemon
- `frogpilot/controls/lib/conditional_experimental_mode.py` - CEM
- `frogpilot/controls/lib/frogpilot_following.py` - Driving personalities
- `frogpilot/system/speed_limit_filler.py` - Speed limit controller
- `frogpilot/assets/theme_manager.py` - Theme system
- `frogpilot/assets/model_manager.py` - Model selection

---

## Architecture & Key Concepts

### Process-Based Architecture

FrogPilot uses a **distributed process model** where independent daemons communicate via messages:

```python
# Process lifecycle managed by system/manager/manager.py
# Each process defined in system/manager/process_config.py

procs = [
    # Always running
    PythonProcess("pandad", "selfdrive.pandad.pandad", always_run),
    NativeProcess("ui", "selfdrive/ui", ["./ui"], always_run),
    PythonProcess("deleter", "system.loggerd.deleter", always_run),

    # Onroad only (while driving)
    PythonProcess("controlsd", "selfdrive.controls.controlsd", only_onroad),
    PythonProcess("plannerd", "selfdrive.controls.plannerd", only_onroad),
    PythonProcess("radard", "selfdrive.controls.radard", only_onroad),
    NativeProcess("modeld", "selfdrive/modeld", ["./modeld"], only_onroad),

    # FrogPilot-specific
    PythonProcess("frogpilot_process", "frogpilot.frogpilot_process", always_run),
    PythonProcess("speed_limit_filler", "frogpilot.system.speed_limit_filler", run_speed_limit_filler),
    # ... 30+ more processes
]
```

### Message Passing with Cereal

All inter-process communication uses **Cereal** (Cap'n Proto):

```python
# Typical daemon pattern
from cereal import messaging

def main():
    # Subscribe to messages
    sm = messaging.SubMaster(['carState', 'modelV2', 'radarState'])

    # Publish messages
    pm = messaging.PubMaster(['carControl'])

    while True:
        sm.update()  # Receive new messages

        # Process logic
        car_state = sm['carState']
        result = compute(car_state)

        # Send result
        msg = messaging.new_message('carControl')
        msg.carControl.enabled = True
        pm.send('carControl', msg)
```

**Key Message Types** (defined in `cereal/*.capnp`):
- `carState` - Vehicle state (speed, steering angle, gear, etc.)
- `carControl` - Control commands (steering, throttle, brake)
- `modelV2` - Vision model outputs (path, lanes, objects)
- `radarState` - Radar/object tracking
- `liveCalibration` - Camera calibration
- `frogpilotPlan` - FrogPilot planning extensions (custom.capnp)
- `frogpilotCarState` - FrogPilot state extensions (custom.capnp)

### Parameter System

Configuration is stored in three locations:

```python
from openpilot.common.params import Params

# Persistent storage (/data/params)
params = Params()

# Cache directory (/cache/params)
params_cache = Params("/cache/params")

# RAM only - lost on reboot (/dev/shm/params)
params_memory = Params("/dev/shm/params")

# Usage
value = params.get("ParameterName")  # Returns bytes
bool_value = params.get_bool("BoolParameter")
params.put("ParameterName", "new_value")
params.put_bool("BoolParameter", True)
```

**FrogPilot Parameters** (`frogpilot/common/frogpilot_variables.py`):
- `AlwaysOnLateral` - Always-on steering assist
- `ConditionalExperimentalMode` - Smart mode switching
- `LongitudinalPersonality` - Driving personality (0=Traffic, 1=Aggressive, 2=Standard, 3=Relaxed)
- `SpeedLimitController` - Enable speed limit control
- `ModelSelector` - Choose driving model
- 85+ more parameters...

### Control Loop Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   Main Control Loop (100Hz)                  │
│                   (controlsd.py)                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
    ┌─────────────┐    ┌──────────┐    ┌────────────────┐
    │   Camera    │───▶│ Vision   │───▶│    Planning    │
    │  (20Hz)     │    │ Model    │    │  (plannerd)    │
    └─────────────┘    │(modeld)  │    └────────────────┘
                       └──────────┘            │
                              │                │
                              ▼                ▼
    ┌─────────────┐    ┌──────────────────────────────┐
    │  CAN Bus    │───▶│    Control Algorithm         │
    │ (carstate)  │    │  Lateral + Longitudinal      │
    └─────────────┐    └──────────────────────────────┘
          │                        │
          │                        ▼
          │              ┌──────────────────┐
          │              │   Car Controller │
          └─────────────▶│   CAN Output     │
                         └──────────────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │   Vehicle CAN    │
                         │ (steering/brake) │
                         └──────────────────┘
```

### Car Interface Pattern

Each manufacturer has a standardized interface:

```python
# selfdrive/car/toyota/interface.py (example)
class CarInterface(CarInterfaceBase):
    @staticmethod
    def get_pid_accel_limits(CP, current_speed, cruise_speed):
        return ActuatorLimits(accel_min=-3.5, accel_max=2.0)

    def update(self, c, can_strings):
        # Parse CAN messages
        ret = self.CS.update(self.cp, self.cp_cam)

        # Update state
        ret.steeringAngleDeg = self.CS.angle_steers
        ret.vEgo = self.CS.out.vEgo

        return ret

    def apply(self, c):
        # Generate control CAN messages
        can_sends = self.CC.update(c, self.CS)
        return can_sends
```

---

## Development Workflows

### Initial Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/FrogAi/FrogPilot
cd FrogPilot

# Install dependencies (Ubuntu)
./tools/ubuntu_setup.sh

# Build all components
scons -j$(nproc)
```

### Branch Strategy

| Branch | URL | Purpose | Use When |
|--------|-----|---------|----------|
| `FrogPilot` | frogpilot.download | Stable release | Production use |
| `FrogPilot-Staging` | staging.frogpilot.download | Beta testing | Early adopters |
| `FrogPilot-Testing` | testing.frogpilot.download | Alpha/bleeding-edge | Advanced testing |
| `FrogPilot-Development` | ❌ Don't use | Active development | **Developers only** |
| `MAKE-PRS-HERE` | ❌ Don't use | PR workspace | Contributors |

**Important:** Always work on feature branches based on `MAKE-PRS-HERE` when contributing.

### Building Components

```bash
# Full build
scons -j$(nproc)

# Build specific component
scons -j8 selfdrive/ui/         # UI only
scons -j8 selfdrive/modeld/     # Model daemon
scons -j8 selfdrive/controls/   # Control system

# Rebuild from component directory
cd selfdrive/ui && scons -u -j8

# Clean build
scons -c
```

### Running Tests

```bash
# All tests
pytest .

# Specific module
pytest selfdrive/monitoring/

# With verbose output
pytest -v selfdrive/controls/

# Run linters (must be installed first)
# Install: pip install ruff mypy cppcheck
ruff check .
mypy .
cppcheck --enable=all selfdrive/
```

### Code Quality Checks

Pre-commit hooks should run automatically if installed:

```bash
# Install hooks
pip install pre-commit
pre-commit install

# Run manually
pre-commit run --all-files

# Run specific hook
pre-commit run ruff --all-files
```

**Linting Standards:**
- **Python:** Ruff (line length: 160), MyType (strict)
- **C++:** cppcheck, cpplint (line length: 240)
- **General:** codespell, check-ast, check-yaml

### Git Workflow for PRs

```bash
# Create feature branch from MAKE-PRS-HERE
git checkout MAKE-PRS-HERE
git pull origin MAKE-PRS-HERE
git checkout -b feature/my-new-feature

# Make changes and test
# ... edit files ...
scons -j$(nproc)
pytest .

# Commit with clear message
git add .
git commit -m "Add: Description of feature

- Detailed change 1
- Detailed change 2

Fixes #issue_number"

# Push to remote
git push origin feature/my-new-feature

# Create PR via GitHub to MAKE-PRS-HERE branch
```

---

## Code Conventions

### File Naming

- **Python files:** `snake_case.py` (e.g., `frogpilot_process.py`)
- **C++ files:** `snake_case.cc/.h` (e.g., `frogpilot_settings.cc`)
- **Class files:** Match class name (e.g., `CarInterface` → `interface.py`)

### Naming Conventions

**Python:**
```python
# Functions: snake_case
def get_frogpilot_toggles():
    pass

# Classes: PascalCase
class FrogPilotPlanner:
    pass

# Constants: UPPER_SNAKE_CASE
DT_MDL = 0.083  # 12Hz

# Private: _leading_underscore
def _internal_helper():
    pass

# Module-level: descriptive names
frogpilot_default_params = {}
```

**C++:**
```cpp
// Classes: PascalCase
class FrogPilotSettings : public QWidget {};

// Functions: camelCase
void updateSettings() {}

// Variables: snake_case
int max_speed = 100;

// Constants: kPascalCase
const int kDefaultSpeed = 50;

// Member variables: snake_case with trailing _
class Foo {
  int member_var_;
};
```

**Parameters (Params system):**
```python
# PascalCase for parameter names
params.put("AlwaysOnLateral", "1")
params.put_bool("ConditionalExperimentalMode", True)
params.put("LongitudinalPersonality", "2")
```

**Messages (Cereal):**
```python
# CamelCase for message types
msg = messaging.new_message('carControl')
msg.carControl.enabled = True

# FrogPilot messages: frogpilot prefix + CamelCase
msg = messaging.new_message('frogpilotPlan')
msg.frogpilotPlan.trafficModeActive = True
```

### Code Structure Patterns

**Daemon Entry Point:**
```python
#!/usr/bin/env python3
import time
from cereal import messaging
from openpilot.common.params import Params
from openpilot.common.realtime import Ratekeeper

def main():
    # Initialize
    params = Params()
    sm = messaging.SubMaster(['inputMessages'])
    pm = messaging.PubMaster(['outputMessages'])
    rk = Ratekeeper(20, None)  # 20Hz

    # Main loop
    while True:
        sm.update()

        # Process logic
        result = process(sm['inputMessages'])

        # Publish result
        msg = messaging.new_message('outputMessages')
        msg.outputMessages.value = result
        pm.send('outputMessages', msg)

        rk.keep_time()

if __name__ == "__main__":
    main()
```

**Parameter Toggle Check:**
```python
from openpilot.common.params import Params

def check_feature():
    params = Params()

    # Boolean parameter
    if params.get_bool("FeatureEnabled"):
        do_something()

    # String/numeric parameter
    value = params.get("NumericParameter")
    if value:
        threshold = int(value)
```

**Car Interface Addition:**
```python
# selfdrive/car/manufacturer/interface.py
from openpilot.selfdrive.car import CarInterfaceBase

class CarInterface(CarInterfaceBase):
    @staticmethod
    def _get_params(ret, candidate, fingerprint, car_fw, disable_openpilot_long, experimental_long):
        ret.carName = "manufacturer"
        ret.safetyConfigs = [get_safety_config(car.CarParams.SafetyModel.manufacturer)]

        # Set limits
        ret.steerLimitTimer = 0.4
        ret.steerActuatorDelay = 0.1

        return ret
```

### Import Organization

```python
# Standard library
import os
import sys
import time

# Third-party
import numpy as np

# openpilot common
from openpilot.common.params import Params
from openpilot.common.realtime import Ratekeeper

# Cereal
from cereal import messaging, car

# Local imports
from openpilot.selfdrive.controls.lib.events import Events
from openpilot.frogpilot.common.frogpilot_variables import get_frogpilot_toggles
```

### Type Hints (Python 3.11+)

```python
from typing import Optional
from cereal import car, log

def process_car_state(
    cs: car.CarState,
    enabled: bool,
    speed_limit: Optional[float] = None
) -> tuple[float, bool]:
    """Process car state and return target speed and status.

    Args:
        cs: Current car state
        enabled: Whether openpilot is enabled
        speed_limit: Optional speed limit in m/s

    Returns:
        Tuple of (target_speed, success_status)
    """
    target_speed = speed_limit if speed_limit else cs.vEgo
    return target_speed, enabled
```

---

## Testing & Quality

### Testing Framework

FrogPilot uses **pytest** for testing:

```bash
# Run all tests
pytest .

# Run specific test file
pytest selfdrive/monitoring/test_monitoring.py

# Run with coverage
pytest --cov=selfdrive/controls/

# Run with verbose output
pytest -v -s
```

### Writing Tests

```python
# test_feature.py
import pytest
from cereal import log, car
from openpilot.selfdrive.controls.lib.feature import process_feature

def test_feature_basic():
    """Test basic feature functionality."""
    # Setup
    msg = log.Event.new_message()
    msg.valid = True

    # Execute
    result = process_feature(msg)

    # Assert
    assert result.enabled
    assert result.value > 0

def test_feature_disabled():
    """Test feature when disabled."""
    msg = log.Event.new_message()
    msg.valid = False

    result = process_feature(msg)

    assert not result.enabled

@pytest.mark.parametrize("speed,expected", [
    (0, 0),
    (10, 10),
    (30, 25),
])
def test_speed_limiting(speed, expected):
    """Test speed limiting with various inputs."""
    result = limit_speed(speed)
    assert result == expected
```

### Continuous Integration

GitHub Actions workflows (`.github/workflows/`):

- **`compile_frogpilot.yaml`** - Main compilation on self-hosted runners
- **`review_pull_request.yaml`** - PR validation
- **`update_release_branch.yaml`** - Release management

### Linting Configuration

**Ruff (Python):**
```python
# Line length: 160 characters
# Target: Python 3.11+
# Selected rules: E, F, W, PIE, C4, ISC, RUF100, A
# Ignored: W292, E741, E402, C408, ISC003
```

**cppcheck (C++):**
```bash
cppcheck --enable=all --suppress=unusedFunction selfdrive/
```

**cpplint (C++ style):**
```bash
cpplint --linelength=240 --filter=-legal/copyright selfdrive/ui/*.cc
```

---

## Common Tasks

### Adding a New FrogPilot Feature

1. **Define Parameter** in `frogpilot/common/frogpilot_variables.py`:

```python
frogpilot_default_params: dict[str, ParamInfo] = {
    # ... existing params ...

    "MyNewFeature": ParamInfo(
        default="0",
        allowed_types=bool,
        description="Enable my new feature",
        static=False,
    ),
}
```

2. **Add to Toggles** in same file:

```python
class FrogPilotToggles:
    def __init__(self):
        # ... existing toggles ...
        self.my_new_feature = params.get_bool("MyNewFeature")
```

3. **Implement Feature Logic** in `frogpilot/controls/lib/my_new_feature.py`:

```python
from openpilot.common.params import Params

class MyNewFeature:
    def __init__(self):
        self.params = Params()
        self.enabled = False

    def update(self, car_state, frogpilot_toggles):
        if not frogpilot_toggles.my_new_feature:
            return None

        # Feature logic
        result = self.process(car_state)
        return result
```

4. **Add UI Settings** in `frogpilot/ui/qt/offroad/frogpilot_settings.cc`:

```cpp
// Add to appropriate settings panel
QList<ParamControl*> FrogPilotSettingsPanel::createFeatureToggles() {
  QList<ParamControl*> toggles;

  toggles.append(new ParamControl(
    "MyNewFeature",
    "My New Feature",
    "Description of what this feature does and how to use it.",
    "../assets/icons/icon_feature.png",
    this
  ));

  return toggles;
}
```

5. **Integrate in Control Loop** (`selfdrive/controls/controlsd.py` or FrogPilot process):

```python
from openpilot.frogpilot.controls.lib.my_new_feature import MyNewFeature

# In __init__
self.my_feature = MyNewFeature()

# In update loop
feature_result = self.my_feature.update(car_state, self.frogpilot_toggles)
```

### Adding a New Car

1. **Identify Manufacturer** - Add to or create in `selfdrive/car/manufacturer/`

2. **Create Fingerprint** in `values.py`:

```python
CAR.NEW_MODEL_2024 = "NEW MANUFACTURER MODEL 2024"

FINGERPRINTS = {
    CAR.NEW_MODEL_2024: [{
        # CAN IDs seen on bus 0
        0x123: 8,  # Steering angle
        0x456: 8,  # Speed
        # ... more CAN IDs
    }],
}
```

3. **Implement Interface** in `interface.py`:

```python
class CarInterface(CarInterfaceBase):
    @staticmethod
    def _get_params(ret, candidate, fingerprint, car_fw, disable_openpilot_long, experimental_long):
        ret.carName = "manufacturer"
        ret.safetyConfigs = [get_safety_config(car.CarParams.SafetyModel.manufacturer)]

        if candidate == CAR.NEW_MODEL_2024:
            ret.wheelbase = 2.7
            ret.steerRatio = 15.5
            ret.mass = 1700
            # ... more parameters

        return ret
```

4. **Implement CarState** in `carstate.py`:

```python
def update(self, cp, cp_cam):
    ret = car.CarState.new_message()

    # Parse CAN messages
    ret.vEgo = cp.vl["SPEED"]["SPEED"] * CV.KPH_TO_MS
    ret.steeringAngleDeg = cp.vl["STEERING"]["ANGLE"]
    ret.gas = cp.vl["PEDALS"]["GAS"]

    return ret
```

5. **Implement CarController** in `carcontroller.py`:

```python
def update(self, CC, CS):
    can_sends = []

    # Generate steering command
    if CC.enabled:
        steer_cmd = self.calculate_steer(CC.steeringTorque)
        can_sends.append(make_can_msg(0x123, steer_cmd))

    return can_sends
```

### Modifying UI

**Python UI Changes** (rarely needed):

Most UI is C++, but Python can be used for simple additions in `selfdrive/ui/qt/python/`.

**C++ UI Changes:**

1. **Modify Existing Screen** in `selfdrive/ui/qt/`:

```cpp
// In offroad/settings.cc (example)
void SettingsWindow::addNewSetting() {
  QWidget *widget = new QWidget(this);
  QVBoxLayout *layout = new QVBoxLayout(widget);

  layout->addWidget(new ParamControl(
    "ParameterName",
    "Display Name",
    "Description text",
    "../assets/icons/icon.png",
    this
  ));

  main_layout->addWidget(widget);
}
```

2. **Add FrogPilot UI** in `frogpilot/ui/qt/offroad/`:

FrogPilot UI extensions follow the same pattern as core UI but live in the frogpilot directory.

3. **Rebuild UI:**

```bash
cd selfdrive/ui
scons -u -j8
```

### Working with Models

**Downloading Models:**

Models are managed by `frogpilot/assets/model_manager.py`. They're stored in `/data/models/`.

**Selecting Model:**

```python
# Via parameters
params.put("ModelSelector", "model_name")

# Via UI - FrogPilot Settings → Model Selection
```

**Adding New Model:**

1. Place model files in `/data/models/model_name/`
2. Update `model_manager.py` model list
3. Add UI entry in `frogpilot/ui/qt/offroad/model_settings.cc`

### Adding Custom Themes

**Theme Structure:**
```
/data/themes/theme_name/
├── colors.json          # Color scheme
├── icons/               # Icon pack
│   └── icon_*.png
├── sounds/              # Sound pack
│   └── sound_*.wav
└── theme.json           # Theme metadata
```

**colors.json Example:**
```json
{
  "primary": "#FF6B00",
  "secondary": "#00A86B",
  "background": "#1A1A1A",
  "text": "#FFFFFF",
  "accent": "#FFD700"
}
```

**Theme Manager** handles installation/activation in `frogpilot/assets/theme_manager.py`.

---

## FrogPilot-Specific Features

### Always On Lateral (AOL)

**Location:** Integrated in lateral control (`selfdrive/controls/lib/latcontrol_*`)

**Purpose:** Maintains steering assist even when accelerator/brake pressed

**Key Logic:**
- Prevents lateral disengagement on pedal press
- Controlled via `AlwaysOnLateral` parameter
- Respects safety limits

### Conditional Experimental Mode (CEM)

**Location:** `frogpilot/controls/lib/conditional_experimental_mode.py`

**Purpose:** Automatically switches between Chill and Experimental modes

**Triggers:**
- Approaching curves (high curvature)
- Slower lead vehicles (significant speed delta)
- Below configured speed threshold
- Predicted stops (traffic lights, stop signs)

**Configuration:**
```python
params.put_bool("ConditionalExperimentalMode", True)
params.put("CEMSpeed", "40")  # mph/kph based on units
```

### Driving Personalities

**Location:** `frogpilot/controls/lib/frogpilot_following.py`

**Profiles:**
- **0 = Traffic:** Minimize gaps, quick responses
- **1 = Aggressive:** Tight following, fast acceleration
- **2 = Standard:** Balanced behavior (default)
- **3 = Relaxed:** Larger gaps, gentle acceleration

**Configuration:**
```python
params.put("LongitudinalPersonality", "2")  # 0-3

# Each profile has tunable parameters
params.put("TrafficFollow", "1.0")  # Following distance multiplier
params.put("TrafficJerkAcceleration", "0.5")
params.put("TrafficJerkDeceleration", "0.5")
```

**Switch via UI:** Use following distance button on steering wheel

### Speed Limit Controller (SLC)

**Location:** `frogpilot/system/speed_limit_filler.py`

**Data Sources:**
1. OpenStreetMap (offline) - `/data/media/0/osm/`
2. Mapbox API (online)
3. Vehicle dashboard (if supported)

**Configuration:**
```python
params.put_bool("SpeedLimitController", True)

# Offset per speed range (mph or kph)
params.put("Offset1", "5")   # 0-34 mph
params.put("Offset2", "10")  # 35-54 mph
params.put("Offset3", "15")  # 55-64 mph
params.put("Offset4", "20")  # 65+ mph
```

**Map Management:**
- Download via FrogPilot Settings → Navigation
- Auto-update scheduling available
- Maps stored in `/data/media/0/osm/`

### Advanced Vehicle Control

**Acceleration Enhancements:**
- **Location:** `frogpilot/controls/lib/frogpilot_acceleration.py`
- Neural network feedforward for smoother response
- Human-like acceleration profiles

**Curve Speed Control:**
- **Location:** `frogpilot/controls/lib/curve_speed_controller.py`
- Automatically slow for curves
- Uses vision model curvature prediction

**Increased Steering Torque:**
- Select vehicles only (Toyota, Honda)
- Requires safety validation
- Configurable limits per vehicle

### Theme System

**Location:** `frogpilot/assets/theme_manager.py`

**Components:**
- Color schemes (JSON)
- Icon packs (PNG sprites)
- Sound packs (WAV files)
- Turn signal animations
- Steering wheel icons

**Holiday Themes:**
- 13 seasonal themes in `frogpilot/assets/holiday_themes/`
- Auto-activate based on date
- Custom theme creation via Theme Maker

**Random Events:**
- Mario Kart-style effects
- Rainbow path visualization
- Fun animations while driving

### Model Selection

**Location:** `frogpilot/assets/model_manager.py`

**Supported Backends:**
1. **Standard (modeld)** - Default openpilot ONNX
2. **Classic (classic_modeld)** - Legacy ONNX models
3. **Tinygrad (tinygrad_modeld)** - Alternative ML framework

**Configuration:**
```python
params.put("ModelSelector", "classic")  # "standard", "classic", "tinygrad"
```

**Model Files:**
- Stored in `/data/models/`
- Auto-download on selection
- Multiple models can coexist

### Custom Messaging (Cereal)

**Location:** `cereal/custom.capnp`

**FrogPilot Message Types:**
```capnp
struct FrogPilotCarControl {
  alwaysOnLateral @0 :Bool;
  trafficModeActive @1 :Bool;
}

struct FrogPilotCarState {
  buttonPress @0 :ButtonPress;

  enum ButtonPress {
    none @0;
    gapAdjustCruise @1;
    lkas @2;
  }
}

struct FrogPilotPlan {
  adjustedCruise @0 :Float32;
  conditionalExperimentalActive @1 :Bool;
  desiredFollowDistance @2 :Float32;
  safeObstacleDistance @3 :Float32;
  vtscControllingCurve @4 :Bool;
}
```

**Usage:**
```python
msg = messaging.new_message('frogpilotPlan')
msg.frogpilotPlan.conditionalExperimentalActive = True
msg.frogpilotPlan.adjustedCruise = 25.0
pm.send('frogpilotPlan', msg)
```

---

## Safety & Best Practices

### Safety-Critical Code

**⚠️ These areas require EXTREME caution:**

1. **Control Limits** (`selfdrive/car/*/values.py`)
   - Steering torque limits
   - Acceleration/braking limits
   - Safety configurations

2. **Car Controllers** (`selfdrive/car/*/carcontroller.py`)
   - CAN message generation
   - Actuator commands
   - Safety overrides

3. **Safety Models** (Panda firmware)
   - Hardware-level safety enforcement
   - Cannot be modified via software alone

**Golden Rule:** When modifying control code:
- ✅ Test in simulation first
- ✅ Start with conservative limits
- ✅ Validate on test track before public roads
- ✅ Review safety implications thoroughly
- ❌ Never disable safety checks
- ❌ Never exceed manufacturer-specified limits
- ❌ Never bypass hardware safety model

### Code Review Checklist

Before submitting PRs:

- [ ] Code follows naming conventions
- [ ] Type hints added (Python)
- [ ] Docstrings for public functions
- [ ] Tests written and passing
- [ ] Linters pass (ruff, mypy, cppcheck)
- [ ] No hardcoded paths (use relative paths)
- [ ] Parameters use Params() system
- [ ] No blocking calls in control loops
- [ ] No infinite loops without rate limiting
- [ ] Error handling for edge cases
- [ ] No security vulnerabilities (SQL injection, XSS, etc.)
- [ ] No credentials in code (use environment variables)

### Performance Considerations

**Control Loop (100Hz):**
- Keep compute under 10ms per cycle
- Avoid allocations in hot path
- Use numpy for vectorized operations
- Profile with `cProfile` if slow

**Vision Models (20Hz):**
- Models run on dedicated process
- GPU acceleration when available
- Memory-mapped for efficiency

**Message Passing:**
- Cereal uses zero-copy shared memory
- Minimal serialization overhead
- Don't block on message sends

**Parameter Access:**
- Cache frequently accessed params
- Use `Params` object per process
- Avoid repeated file I/O

### Debugging Tips

**Log Viewing:**
```bash
# System logs
journalctl -u comma -f

# Cloud logs (if athena enabled)
# View at https://useradmin.comma.ai

# Process-specific logs
tail -f /data/logs/controlsd.log
```

**Live Parameter Viewing:**
```python
from openpilot.common.params import Params
params = Params()

# View all params
for key in params.all_keys():
    print(f"{key}: {params.get(key)}")
```

**CAN Message Sniffing:**
```bash
# Via pandad
cd /data/openpilot && python -c "
from cereal import messaging
sm = messaging.SubMaster(['can'])
while True:
    sm.update()
    print(sm['can'])
"
```

**UI Debug Mode:**
```python
# Enable developer UI
params.put_bool("IsMetric", False)  # Shows developer sidebar
```

### Common Pitfalls

1. **Forgetting Submodules:**
   ```bash
   # Always update submodules after pull
   git submodule update --init --recursive
   ```

2. **Wrong Python Version:**
   ```bash
   # FrogPilot requires Python 3.11+
   python3 --version
   ```

3. **Not Rebuilding After Changes:**
   ```bash
   # Always rebuild after modifying C++/Cython
   scons -j$(nproc)
   ```

4. **Parameter Type Mismatch:**
   ```python
   # Wrong
   params.put("BoolParam", True)  # ❌ put expects string

   # Right
   params.put_bool("BoolParam", True)  # ✅
   ```

5. **Blocking Control Loop:**
   ```python
   # Wrong - blocks control loop
   def update(self):
       time.sleep(1)  # ❌

   # Right - use RateKeeper
   def update(self):
       # Fast processing
       self.rk.keep_time()  # ✅
   ```

6. **Hardcoded Paths:**
   ```python
   # Wrong
   path = "/home/user/FrogPilot/data"  # ❌

   # Right
   from pathlib import Path
   path = Path(__file__).parent / "data"  # ✅
   ```

---

## Troubleshooting

### Build Failures

**Issue:** `scons: *** No SConstruct file found.`
```bash
# Solution: Run from repo root
cd /home/user/FrogPilot
scons -j$(nproc)
```

**Issue:** `fatal error: 'Qt/QtWidgets' file not found`
```bash
# Solution: Install Qt dependencies
sudo apt-get install qtbase5-dev qttools5-dev
```

**Issue:** Submodule errors
```bash
# Solution: Update submodules
git submodule update --init --recursive

# If still failing, try clean checkout
git submodule foreach --recursive git clean -xfd
git submodule update --init --recursive
```

### Runtime Errors

**Issue:** Process crashes immediately
```bash
# Check manager logs
journalctl -u comma -n 100

# Check specific process
tail -f /data/logs/process_name.log
```

**Issue:** Parameter not found
```python
# Check if parameter exists
from openpilot.common.params import Params
params = Params()
value = params.get("ParameterName")
if value is None:
    # Parameter doesn't exist, set default
    params.put("ParameterName", "default_value")
```

**Issue:** CAN communication failure
```bash
# Check panda connection
cd panda/python
python -c "from panda import Panda; print(Panda.list())"

# Should show connected pandas
```

### Git Issues

**Issue:** Push fails with 403
```bash
# Ensure branch starts with 'claude/' and ends with session ID
git branch --show-current
# Should be: claude/claude-md-micvu41yi1ot9eja-01BpXX7FRyoAb1SKSvWu4F6F

# If network error, retry with exponential backoff
git push -u origin branch_name
sleep 2 && git push -u origin branch_name
sleep 4 && git push -u origin branch_name
```

**Issue:** Merge conflicts
```bash
# View conflicts
git status

# Resolve manually, then:
git add .
git commit
```

### Performance Issues

**Issue:** Control loop running slow
```bash
# Profile with cProfile
python -m cProfile -o output.prof selfdrive/controls/controlsd.py

# Analyze results
python -c "import pstats; p = pstats.Stats('output.prof'); p.sort_stats('cumulative'); p.print_stats(20)"
```

**Issue:** High CPU usage
```bash
# Check process CPU
top -p $(pgrep -f "process_name")

# If specific process is high:
# - Check for infinite loops
# - Profile as above
# - Optimize hot path
```

### Getting Help

1. **Documentation:**
   - FrogPilot Wiki: https://frogpilot.wiki.gg/
   - openpilot Docs: https://docs.comma.ai

2. **Community:**
   - FrogPilot Discord: https://discord.frogpilot.download
   - Bug Reports: #bug-reports channel
   - Feature Requests: #feature-requests channel

3. **Code Search:**
   - Use GitHub search for examples
   - Search DeepWiki: https://deepwiki.com/FrogAi/FrogPilot

---

## Quick Reference

### Essential Commands

```bash
# Build
scons -j$(nproc)                    # Full build
scons -j8 selfdrive/ui/            # Component build
scons -c                            # Clean

# Test
pytest .                            # All tests
pytest -v selfdrive/               # Verbose
pytest --cov=.                      # With coverage

# Lint
ruff check .                        # Python linting
mypy .                              # Type checking
cppcheck selfdrive/                # C++ static analysis

# Git
git submodule update --init --recursive
git pull origin branch_name
git push -u origin branch_name
```

### Key Directories

```
selfdrive/car/          # Car interfaces
selfdrive/controls/     # Control loop
selfdrive/ui/           # UI (C++)
frogpilot/controls/     # FrogPilot control features
frogpilot/ui/           # FrogPilot UI
frogpilot/common/       # FrogPilot config
cereal/                 # Message schemas
system/manager/         # Process management
```

### Important Files

```
system/manager/process_config.py              # Process definitions
frogpilot/common/frogpilot_variables.py       # FrogPilot parameters
selfdrive/controls/controlsd.py               # Main control loop
cereal/log.capnp                              # Core messages
cereal/custom.capnp                           # FrogPilot messages
common/params.py                              # Parameter system
```

### Parameter Examples

```python
from openpilot.common.params import Params
params = Params()

# Boolean
params.put_bool("FeatureName", True)
enabled = params.get_bool("FeatureName")

# String
params.put("StringParam", "value")
value = params.get("StringParam")

# Numeric (stored as string)
params.put("NumericParam", str(42))
num = int(params.get("NumericParam"))
```

### Message Examples

```python
from cereal import messaging

# Subscribe
sm = messaging.SubMaster(['carState', 'modelV2'])
sm.update()
speed = sm['carState'].vEgo

# Publish
pm = messaging.PubMaster(['carControl'])
msg = messaging.new_message('carControl')
msg.carControl.enabled = True
pm.send('carControl', msg)
```

---

## Conclusion

This guide covers the essential information for AI assistants working with FrogPilot. Key takeaways:

1. **Architecture:** Distributed processes communicating via Cereal messages
2. **Safety First:** Always validate changes in safe environments
3. **Follow Conventions:** Consistent naming and structure throughout
4. **Test Thoroughly:** Use pytest and linters before committing
5. **FrogPilot Features:** Modular, parameter-driven enhancements
6. **Community:** Active Discord for support and collaboration

When in doubt:
- Read existing code for examples
- Check parameter definitions in `frogpilot_variables.py`
- Review process flow in `process_config.py`
- Test incrementally with small changes
- Ask in Discord for clarification

**Happy coding! 🐸**

---

*This document is maintained by the FrogPilot community. Last updated: November 24, 2025*

*For updates to this guide, please submit PRs to the MAKE-PRS-HERE branch.*
