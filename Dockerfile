FROM nikolaik/python-nodejs:python3.12-nodejs22-bookworm

ENV NODE_ENV=production

ARG TIGRISFS_VERSION=1.2.1
ARG CLOUDFLARED_DEB_URL=https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb

# Install system dependencies + tigrisfs/cloudflared/opencode, then clean cache
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \ 
      fuse \ 
      ca-certificates \ 
      curl; \ 
    \ 
    curl -fsSL "https://github.com/tigrisdata/tigrisfs/releases/download/v0.3.1/tigrisfs_0.3.1_linux_amd64.deb" -o /tmp/tigrisfs.deb; \ 
    dpkg -i /tmp/tigrisfs.deb; \ 
    rm -f /tmp/tigrisfs.deb; \ 
    \ 
    curl -fsSL "${CLOUDFLARED_DEB_URL}" -o /tmp/cloudflared.deb; \ 
    dpkg -i /tmp/cloudflared.deb; \ 
    rm -f /tmp/cloudflared.deb; \ 
    \ 
    curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path; \ 
    mv /root/.opencode/bin/opencode /usr/local/bin/opencode; \ 
    \ 
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Copy preset config
COPY config /opt/config-init

# Create startup script
RUN install -m 755 /dev/stdin /entrypoint.sh <<'EOF'\n#!/bin/bash\nset -e\n\nMOUNT_POINT="/root/s3"\nWORKSPACE_DIR="$MOUNT_POINT/workspace"\nXDG_DIR="$MOUNT_POINT/.opencode"\nGLOBAL_CONFIG_DIR="$XDG_DIR/config/opencode"\nCONFIG_INIT_DIR="/opt/config-init/opencode"\n\n# Initialize workspace and XDG environment variables
setup_workspace() {\n    mkdir -p "$WORKSPACE_DIR/project" "$GLOBAL_CONFIG_DIR" "$XDG_DIR"/{data,state}\n    export XDG_CONFIG_HOME="$XDG_DIR/config"\n    export XDG_DATA_HOME="$XDG_DIR/data"\n    export XDG_STATE_HOME="$XDG_DIR/state"\n    PROJECT_DIR="$WORKSPACE_DIR/project"\n\n    # Copy config files only if they not exist\n    for file in opencode.json AGENTS.md; do\n        if [ ! -f "$GLOBAL_CONFIG_DIR/$file" ]; then\n            cp "$CONFIG_INIT_DIR/$file" "$GLOBAL_CONFIG_DIR/" 2>/dev/null && echo "[INFO] Initialized $file" || true\n        fi\n    done\n}\n\n# Ensure mount point is a clean directory
reset_mountpoint() {\n    mountpoint -q "$MOUNT_POINT" 2>/dev/null && fusermount -u "$MOUNT_POINT" 2>/dev/null || true\n    rm -rf "$MOUNT_POINT"\n    mkdir -p "$MOUNT_POINT"\n}\n\nreset_mountpoint\n\nif [ -z "$S3_ENDPOINT" ] || [ -z "$S3_BUCKET" ] || [ -z "$S3_ACCESS_KEY_ID" ] || [ -z "$S3_SECRET_ACCESS_KEY" ]; then\n    echo "[WARN] Incomplete S3 config, using local directory mode"\nelse\n    echo "[INFO] Mounting S3: ${S3_BUCKET} -> ${MOUNT_POINT}"\n\n    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"\n    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"\n    export AWS_REGION="${S3_REGION:-auto}"\n    export AWS_S3_PATH_STYLE="${S3_PATH_STYLE:-false}"\n\n    /usr/bin/tigrisfs --endpoint "$S3_ENDPOINT" ${TIGRISFS_ARGS:-} -f "${S3_BUCKET}${S3_PREFIX:+:$S3_PREFIX}" "$MOUNT_POINT" &\n    sleep 3\n\n    if ! mountpoint -q "$MOUNT_POINT"; then\n        echo "[ERROR] S3 mount failed"\n        exit 1\n    fi\n    echo "[OK] S3 mounted successfully"\nfi\n\nsetup_workspace\n\ncleanup() {\n    echo "[INFO] Shutting down..."\n    if [ -n "$OPENCODE_PID" ]; then\n        kill -TERM "$OPENCODE_PID" 2>/dev/null\n        wait "$OPENCODE_PID" 2>/dev/null\n    fi\n    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then\n        fusermount -u "$MOUNT_POINT" 2>/dev/null || true\n    fi\n    exit 0\n}\ntrap cleanup SIGTERM SIGINT\n\necho "[INFO] Starting OpenCode..."\ncd "$PROJECT_DIR"\nopencode web --port 2633 --hostname 0.0.0.0 &\nOPENCODE_PID=$!\nwait $OPENCODE_PID\nEOF

WORKDIR /root/s3/workspace
EXPOSE 2633

CMD ["/entrypoint.sh"]