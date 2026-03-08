#!/bin/bash
set -e

# ============================================================
# Fiberus Docker Entrypoint
# ============================================================
# - Ensures .fiberus_config.xml exists for the current user
# - Checks host kernel version for io_uring compatibility
# - Checks whether io_uring syscalls are blocked by seccomp
# - Auto-registers warp10 if mounted at /opt/warp10
# ============================================================

# ---- Ensure .fiberus_config.xml exists for current user ----
# When running as non-root, $HOME won't have the config from the build stage.
FIBERUS_CONFIG="$HOME/.fiberus_config.xml"
if [ ! -f "$FIBERUS_CONFIG" ]; then
    cat > "$FIBERUS_CONFIG" <<'EOF'
<xml>
    <section id="vars">
        <set name="FIBERUS_COMPILE_CACHE" value="/opt/fiberus-cache" />
    </section>
</xml>
EOF
fi

# ---- Kernel version check for io_uring ----
KERNEL_VERSION=$(uname -r | cut -d. -f1-2)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)

if [ "$KERNEL_MAJOR" -lt 5 ] || { [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -lt 10 ]; }; then
    echo "WARNING: Host kernel $KERNEL_VERSION detected."
    echo "         Fiberus requires Linux >= 5.10 for io_uring support."
    echo "         Some features may not work correctly."
    echo ""
fi

# ---- memlock ulimit check for io_uring registered buffers ----
# io_uring buffer registration pins memory in kernel space. The fiberus runtime
# registers 1024 x 128KB = 128MB per worker thread. Docker's default memlock
# limit (64KB) is far too low, causing io_uring_register_buffers to fail.
MEMLOCK_SOFT=$(ulimit -l 2>/dev/null)
if [ "$MEMLOCK_SOFT" != "unlimited" ] 2>/dev/null && [ "${MEMLOCK_SOFT:-0}" -lt 524288 ] 2>/dev/null; then
    echo "WARNING: memlock ulimit is ${MEMLOCK_SOFT}KB (need >=512MB or unlimited)."
    echo "         io_uring buffer registration will fail without sufficient memlock."
    echo "         Run with: --ulimit memlock=-1:-1"
    echo ""
fi

# ---- io_uring seccomp check ----
# Attempt a basic io_uring_setup syscall. If blocked by Docker's default
# seccomp profile, warn the user to run with --security-opt seccomp=unconfined.
if command -v python3 &>/dev/null; then
    if ! python3 -c "
import ctypes, ctypes.util, sys
libc = ctypes.CDLL(ctypes.util.find_library('c'), use_errno=True)
# io_uring_setup syscall number on x86_64 = 425
ret = libc.syscall(425, 1, ctypes.c_void_p(0))
errno = ctypes.get_errno()
# EFAULT (14) or EINVAL (22) = syscall available (just bad args, that's fine)
# EPERM  (1)  or ENOSYS (38) = blocked by seccomp or kernel
if errno in (1, 38):
    sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
        echo "WARNING: io_uring syscalls appear to be blocked by seccomp."
        echo "         Run the container with: --security-opt seccomp=unconfined"
        echo ""
    fi
fi

exec "$@"
