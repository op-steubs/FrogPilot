#!/bin/bash
#
# FrogPilot Development Workflow Script
# Safe development workflow - never bricks your device!
#
# LOCAL BUILD WORKFLOW (Fast - build on Mac, deploy to device):
#   ./scripts/fp-dev.sh compile   - Build ARM64 binaries locally in Docker
#   ./scripts/fp-dev.sh deploy    - Sync built code to device
#   ./scripts/fp-dev.sh test      - Switch device to your dev branch
#
# REMOTE BUILD WORKFLOW (Original - build on device):
#   ./scripts/fp-dev.sh push      - Push current branch to GitHub
#   ./scripts/fp-dev.sh build     - Build current branch on device
#   ./scripts/fp-dev.sh test      - Switch device to your dev branch
#
# OTHER COMMANDS:
#   ./scripts/fp-dev.sh status    - Show device and local status
#   ./scripts/fp-dev.sh safe      - Switch device back to FrogPilot-Staging
#   ./scripts/fp-dev.sh logs      - Show recent device logs
#   ./scripts/fp-dev.sh docker    - Build/rebuild the Docker image
#

set -e

# Configuration
DEVICE_IP="10.7.7.133"
DEVICE_USER="comma"
SAFE_BRANCH="FrogPilot-Staging"
SSH_KEY="~/.ssh/id_ed25519"
REPO_PATH="/data/openpilot"
DOCKER_IMAGE="frogpilot-arm64"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

    # Checkout the dev branch (device doesn't create remote tracking branches)
    print_status "Checking out ${LOCAL_BRANCH}..."
    ssh_cmd "cd ${REPO_PATH} && git checkout ${LOCAL_BRANCH} 2>/dev/null || git checkout -b ${LOCAL_BRANCH} FETCH_HEAD"
    ssh_cmd "cd ${REPO_PATH} && git reset --hard FETCH_HEAD"

    # Build libyuv if it doesn't exist (first build or corrupted submodule)
    LIBYUV_CHECK=$(ssh_cmd "test -f ${REPO_PATH}/third_party/libyuv/larch64/lib/libyuv.a && echo 'exists' || echo 'missing'")
    if [ "$LIBYUV_CHECK" = "missing" ]; then
        print_status "Building libyuv (first time setup)..."
        # Remove potentially corrupted libyuv submodule and let build.sh clone fresh
        ssh_cmd "cd ${REPO_PATH}/third_party/libyuv && rm -rf libyuv && ./build.sh"
        print_success "libyuv built successfully"
    fi

    # Build with cache disabled - target specific components
    # Full build fails because tinygrad models need ONNX files downloaded at runtime
    SCONS_PREFIX="PATH=/usr/local/pyenv/versions/3.11.4/bin:\$PATH"
    SCONS_CMD="${SCONS_PREFIX} scons --cache-disable -j4"

    # Clean params_pyx artifacts to ensure fresh build (avoids UnknownKeyName errors)
    print_status "Cleaning params module for fresh build..."
    ssh_cmd "cd ${REPO_PATH} && rm -f common/params_pyx.so common/params_pyx.o common/params_pyx.cpp"

    print_status "Building UI (this may take a few minutes)..."
    BUILD_CMD="cd ${REPO_PATH} && ${SCONS_CMD} common/params_pyx.so selfdrive/ui/ui"

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

cmd_docker() {
    print_status "Building Docker image for ARM64 cross-compilation..."
    print_warning "This may take 10-15 minutes on first build"
    echo ""

    cd "$PROJECT_ROOT"
    if docker build --platform linux/arm64 -t "$DOCKER_IMAGE" -f Dockerfile.arm64 . ; then
        print_success "Docker image '$DOCKER_IMAGE' built successfully!"
        echo ""
        echo "Image size: $(docker images $DOCKER_IMAGE --format '{{.Size}}')"
    else
        print_error "Docker build failed!"
        exit 1
    fi
}

cmd_compile() {
    print_status "Compiling FrogPilot in Docker (ARM64)..."
    echo ""

    # Check if Docker image exists
    if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
        print_warning "Docker image not found. Building it first..."
        cmd_docker
    fi

    cd "$PROJECT_ROOT"

    # Build libyuv if it doesn't exist (first compile only)
    if [ ! -f "third_party/libyuv/larch64/lib/libyuv.a" ]; then
        print_status "Building libyuv for ARM64 (first time only)..."
        docker run --platform linux/arm64 --rm \
            -v "$PROJECT_ROOT":/home/batman/openpilot \
            "$DOCKER_IMAGE" \
            bash -c "cd /home/batman/openpilot/third_party/libyuv && ./build.sh"
        if [ -f "third_party/libyuv/larch64/lib/libyuv.a" ]; then
            print_success "libyuv built successfully"
        else
            print_error "Failed to build libyuv"
            exit 1
        fi
    fi

    # Compile EGL stubs for linking (device driver provides real implementations)
    if [ ! -f "third_party/linux/lib/libegl_stubs.a" ]; then
        print_status "Compiling EGL stubs..."
        docker run --platform linux/arm64 --rm \
            -v "$PROJECT_ROOT":/home/batman/openpilot \
            "$DOCKER_IMAGE" \
            bash -c "cd /home/batman/openpilot/third_party/linux && \
                     gcc -c -fPIC -I/usr/include egl_stubs.c -o lib/egl_stubs.o && \
                     ar rcs lib/libegl_stubs.a lib/egl_stubs.o"
        if [ -f "third_party/linux/lib/libegl_stubs.a" ]; then
            print_success "EGL stubs compiled"
        fi
    fi

    # Default to building UI and params if no target specified
    BUILD_TARGET="${2:-common/params_pyx.so selfdrive/ui/ui}"

    print_status "Build target: $BUILD_TARGET"
    print_status "Starting Docker build..."
    echo ""

    if docker run --platform linux/arm64 --rm \
        -v "$PROJECT_ROOT":/home/batman/openpilot \
        "$DOCKER_IMAGE" \
        bash -c "sudo mkdir -p /data/scons_cache && sudo chown -R batman:batman /data/scons_cache && rm -f /data/scons_cache/*.lock 2>/dev/null; cd /home/batman/openpilot && python3 -m SCons -j8 --cache-disable $BUILD_TARGET" ; then
        echo ""
        print_success "Build completed successfully!"
        echo ""
        echo "Built binaries are ARM64 Linux - compatible with comma device"
        echo "Next step: ./scripts/fp-dev.sh deploy"
    else
        echo ""
        print_error "Build failed!"
        exit 1
    fi
}

cmd_deploy() {
    check_device

    LOCAL_BRANCH=$(git branch --show-current)
    print_status "Deploying built code to device..."
    print_warning "This syncs your local build to the device"
    echo ""

    # Create/update the branch on device
    print_status "Setting up branch '$LOCAL_BRANCH' on device..."
    ssh_cmd "cd ${REPO_PATH} && git fetch origin ${LOCAL_BRANCH} 2>/dev/null || true"
    ssh_cmd "cd ${REPO_PATH} && git checkout ${LOCAL_BRANCH} 2>/dev/null || git checkout -b ${LOCAL_BRANCH}"

    # Rsync the built files to device
    # Exclude git, large model files, and Mac-specific files
    print_status "Syncing files to device (this may take a minute)..."

    rsync -avz --progress \
        --exclude='.git' \
        --exclude='*.onnx' \
        --exclude='*.thneed' \
        --exclude='*.dlc' \
        --exclude='.DS_Store' \
        --exclude='__pycache__' \
        --exclude='.mypy_cache' \
        --exclude='.pytest_cache' \
        --exclude='node_modules' \
        --exclude='.venv' \
        --exclude='*.pyc' \
        -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
        "$PROJECT_ROOT/" \
        "${DEVICE_USER}@${DEVICE_IP}:${REPO_PATH}/"

    print_success "Deploy completed!"
    echo ""
    echo "To test your changes, run: ./scripts/fp-dev.sh test"
    echo "To stay safe, run: ./scripts/fp-dev.sh safe"
}

cmd_shell() {
    print_status "Opening shell in Docker container..."
    cd "$PROJECT_ROOT"

    # Check if Docker image exists
    if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
        print_warning "Docker image not found. Building it first..."
        cmd_docker
    fi

    docker run --platform linux/arm64 -it --rm \
        -v "$PROJECT_ROOT":/home/batman/openpilot \
        "$DOCKER_IMAGE" \
        bash
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
    docker)
        cmd_docker
        ;;
    compile)
        cmd_compile "$@"
        ;;
    deploy)
        cmd_deploy
        ;;
    shell)
        cmd_shell
        ;;
    *)
        echo "FrogPilot Development Workflow"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo -e "${BLUE}=== LOCAL BUILD (Fast - recommended) ===${NC}"
        echo "  compile [target] - Build ARM64 binaries locally in Docker"
        echo "  deploy           - Rsync built code to device"
        echo "  test             - Switch device to your dev branch"
        echo "  shell            - Open interactive shell in Docker"
        echo "  docker           - Build/rebuild the Docker image"
        echo ""
        echo -e "${BLUE}=== REMOTE BUILD (Original) ===${NC}"
        echo "  push    - Push current branch to GitHub"
        echo "  build   - Build current branch on device"
        echo "  test    - Switch device to your dev branch"
        echo ""
        echo -e "${BLUE}=== OTHER ===${NC}"
        echo "  status  - Show device and local git status"
        echo "  safe    - Switch device back to FrogPilot-Staging"
        echo "  logs    - Show recent device error logs"
        echo ""
        echo -e "${GREEN}Fast local workflow:${NC}"
        echo "  1. Make code changes on your Mac"
        echo "  2. ./scripts/fp-dev.sh compile"
        echo "  3. ./scripts/fp-dev.sh deploy"
        echo "  4. ./scripts/fp-dev.sh test"
        echo ""
        echo -e "${YELLOW}If anything goes wrong:${NC}"
        echo "  ./scripts/fp-dev.sh safe"
        ;;
esac
