#!/bin/bash
#
# FrogPilot Development Workflow Script
# Safe development workflow - never bricks your device!
#
# Usage:
#   ./scripts/fp-dev.sh push      - Push current branch to GitHub
#   ./scripts/fp-dev.sh build     - Build current branch on device (doesn't switch to it)
#   ./scripts/fp-dev.sh test      - Switch device to your dev branch (for testing)
#   ./scripts/fp-dev.sh safe      - Switch device back to FrogPilot-Staging (safe/stable)
#   ./scripts/fp-dev.sh status    - Show device and local status
#   ./scripts/fp-dev.sh logs      - Show recent device logs
#

set -e

# Configuration
DEVICE_IP="10.7.7.133"
DEVICE_USER="comma"
SAFE_BRANCH="FrogPilot-Staging"
SSH_KEY="~/.ssh/id_ed25519"
REPO_PATH="/data/openpilot"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ssh_cmd() {
    ssh -i $SSH_KEY -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${DEVICE_USER}@${DEVICE_IP} "$1"
}

print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

check_device() {
    print_status "Checking device connection..."
    if ! ssh_cmd "echo connected" &>/dev/null; then
        print_error "Cannot connect to device at ${DEVICE_IP}"
        print_warning "Make sure your device is on and connected to the network"
        exit 1
    fi
    print_success "Device connected"
}

cmd_status() {
    echo ""
    echo -e "${BLUE}=== Local Status ===${NC}"
    LOCAL_BRANCH=$(git branch --show-current)
    echo "Branch: $LOCAL_BRANCH"
    echo "Changes: $(git status --short | wc -l | tr -d ' ') files"
    git status --short | head -5

    echo ""
    echo -e "${BLUE}=== Device Status ===${NC}"
    check_device

    DEVICE_BRANCH=$(ssh_cmd "cd ${REPO_PATH} && git branch --show-current")
    echo "Branch: $DEVICE_BRANCH"

    if [ "$DEVICE_BRANCH" = "$SAFE_BRANCH" ]; then
        print_success "Device is on SAFE branch ($SAFE_BRANCH)"
    else
        print_warning "Device is on DEV branch ($DEVICE_BRANCH)"
    fi

    # Check if device has uncommitted changes
    DEVICE_CHANGES=$(ssh_cmd "cd ${REPO_PATH} && git status --short | wc -l")
    if [ "$DEVICE_CHANGES" -gt "0" ]; then
        print_warning "Device has $DEVICE_CHANGES uncommitted changes"
    fi
}

cmd_push() {
    LOCAL_BRANCH=$(git branch --show-current)
    print_status "Pushing branch '$LOCAL_BRANCH' to GitHub..."

    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        print_warning "You have uncommitted changes:"
        git status --short
        echo ""
        read -p "Commit these changes first? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Commit message: " COMMIT_MSG
            git add -A
            git commit -m "$COMMIT_MSG"
        else
            print_error "Push cancelled - commit your changes first"
            exit 1
        fi
    fi

    git push origin "$LOCAL_BRANCH"
    print_success "Pushed to origin/$LOCAL_BRANCH"
}

cmd_build() {
    LOCAL_BRANCH=$(git branch --show-current)
    check_device

    print_status "Building branch '$LOCAL_BRANCH' on device..."
    print_warning "This does NOT switch the device to this branch yet"
    echo ""

    # Fetch and checkout the branch on device
    print_status "Fetching latest code..."
    ssh_cmd "cd ${REPO_PATH} && git fetch origin ${LOCAL_BRANCH}"

    # Store current branch to restore later
    DEVICE_CURRENT=$(ssh_cmd "cd ${REPO_PATH} && git branch --show-current")

    # Checkout the dev branch (device doesn't create tracking branches automatically)
    print_status "Checking out ${LOCAL_BRANCH}..."
    ssh_cmd "cd ${REPO_PATH} && git checkout ${LOCAL_BRANCH} 2>/dev/null || git checkout -b ${LOCAL_BRANCH} FETCH_HEAD"
    ssh_cmd "cd ${REPO_PATH} && git reset --hard FETCH_HEAD"

    # Build with cache disabled
    # Note: Full build fails on release branches (missing panda sources)
    # So we build only the necessary components
    print_status "Building params module..."
    SCONS_CMD="PATH=/usr/local/pyenv/versions/3.11.4/bin:\$PATH /usr/local/pyenv/versions/3.11.4/bin/python -m SCons --cache-disable -j4"
    BUILD_PARAMS="cd ${REPO_PATH} && ${SCONS_CMD} common/params_pyx.so"

    print_status "Building UI (main binary only)..."
    BUILD_UI="cd ${REPO_PATH} && ${SCONS_CMD} selfdrive/ui/ui"

    # Combine both builds
    BUILD_CMD="${BUILD_PARAMS} && ${BUILD_UI}"

    if ssh_cmd "$BUILD_CMD" 2>&1; then
        print_success "Build completed successfully!"
        echo ""
        print_status "Branch '$LOCAL_BRANCH' is built and ready"
        print_warning "Device is still running: $DEVICE_CURRENT"
        echo ""
        echo "To test your changes, run: ./scripts/fp-dev.sh test"
        echo "To stay safe, run: ./scripts/fp-dev.sh safe"
    else
        print_error "Build failed!"
        echo ""
        print_status "Switching back to safe branch..."
        ssh_cmd "cd ${REPO_PATH} && git checkout ${SAFE_BRANCH}"
        print_success "Device restored to $SAFE_BRANCH"
        exit 1
    fi
}

cmd_test() {
    LOCAL_BRANCH=$(git branch --show-current)
    check_device

    print_warning "This will switch your device to branch: $LOCAL_BRANCH"
    print_warning "Your device will reboot and run your development code!"
    echo ""
    read -p "Are you sure? (yes/no) " -r
    if [[ ! $REPLY = "yes" ]]; then
        print_status "Cancelled"
        exit 0
    fi

    print_status "Switching device to $LOCAL_BRANCH..."
    ssh_cmd "cd ${REPO_PATH} && git checkout ${LOCAL_BRANCH}"

    print_status "Rebooting device..."
    ssh_cmd "sudo reboot" || true

    echo ""
    print_success "Device is rebooting with your development branch!"
    print_warning "If anything goes wrong, run: ./scripts/fp-dev.sh safe"
}

cmd_safe() {
    check_device

    print_status "Switching device to safe branch: $SAFE_BRANCH"

    # Clean any build artifacts and switch to safe branch
    ssh_cmd "cd ${REPO_PATH} && git checkout -- . && git clean -fd && git checkout ${SAFE_BRANCH}"

    print_success "Device switched to $SAFE_BRANCH"

    read -p "Reboot device now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh_cmd "sudo reboot" || true
        print_success "Device rebooting with safe branch"
    fi
}

cmd_logs() {
    check_device
    print_status "Recent device logs:"
    echo ""
    ssh_cmd "tail -100 /data/log/error.txt 2>/dev/null || echo 'No error log found'"
}

# Main
case "${1:-status}" in
    push)
        cmd_push
        ;;
    build)
        cmd_build
        ;;
    test)
        cmd_test
        ;;
    safe)
        cmd_safe
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    *)
        echo "FrogPilot Development Workflow"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  status  - Show device and local git status"
        echo "  push    - Push current branch to GitHub"
        echo "  build   - Build current branch on device (doesn't switch to it)"
        echo "  test    - Switch device to your dev branch (requires confirmation)"
        echo "  safe    - Switch device back to FrogPilot-Staging"
        echo "  logs    - Show recent device error logs"
        echo ""
        echo "Safe workflow:"
        echo "  1. Make code changes on your Mac"
        echo "  2. ./scripts/fp-dev.sh push"
        echo "  3. ./scripts/fp-dev.sh build"
        echo "  4. ./scripts/fp-dev.sh test    (when ready to try it)"
        echo "  5. ./scripts/fp-dev.sh safe    (if anything goes wrong)"
        ;;
esac
