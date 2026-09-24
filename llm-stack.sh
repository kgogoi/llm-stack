#!/usr/bin/env bash
# ==============================================================================
# Master Control Script for llm-stack (Litellm + LibreChat + SearXNG)
# ==============================================================================

set -e

# Dynamically resolve directory where this script lives, even through symlinks
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

LITELLM_DIR="${SCRIPT_DIR}/Litellm"
LIBRECHAT_DIR="${SCRIPT_DIR}/LibreChat"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

ensure_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker daemon is not responsive. Starting Docker service...${NC}"
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl start docker 2>/dev/null || systemctl start docker 2>/dev/null || true
        elif command -v service >/dev/null 2>&1; then
            sudo service docker start 2>/dev/null || service docker start 2>/dev/null || true
        fi
        for i in $(seq 1 15); do
            if docker info >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
    fi
    sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
    
    # Ensure external network exists
    docker network create llm-network >/dev/null 2>&1 || true
}

check_env() {
    if [ ! -f "${LITELLM_DIR}/.env" ] || [ ! -f "${LIBRECHAT_DIR}/.env" ]; then
        echo -e "${YELLOW}Warning: Environment files not found. Running setup.sh to initialize...${NC}"
        bash "${SCRIPT_DIR}/setup.sh"
    fi
}

start_stack() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}  Starting llm-stack (Litellm & LibreChat)           ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    ensure_docker
    check_env

    echo -e "\n${GREEN}[1/2] Launching LiteLLM Stack (Granite + LiteLLM + DB)...${NC}"
    (cd "$LITELLM_DIR" && docker compose up -d)

    echo -e "\n${GREEN}[2/2] Launching LibreChat Stack (LibreChat + SearXNG + RAG + Mongo + Meili)...${NC}"
    (cd "$LIBRECHAT_DIR" && docker compose up -d)

    echo -e "\n${GREEN}✓ All services initiated successfully!${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "  ${YELLOW}LibreChat Web UI:${NC}    http://localhost:3080"
    echo -e "  ${YELLOW}Admin Panel:${NC}         http://localhost:3000"
    echo -e "  ${YELLOW}LiteLLM Proxy:${NC}       http://localhost:4000"
    echo -e "  ${YELLOW}Granite Embedding:${NC}   http://localhost:8080"
    echo -e "${BLUE}=====================================================${NC}\n"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

stop_stack() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker is not running. Nothing to stop.${NC}"
        return 0
    fi
    echo -e "${YELLOW}Stopping all services...${NC}"
    (cd "$LIBRECHAT_DIR" && docker compose down) || true
    (cd "$LITELLM_DIR" && docker compose down) || true
    echo -e "${GREEN}✓ All services stopped cleanly.${NC}"
}

status_stack() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker daemon is not running.${NC}"
        return 0
    fi
    echo -e "${BLUE}=== Current Container Status ===${NC}"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

logs_stack() {
    service_name="${2:-LibreChat}"
    echo -e "${BLUE}Streaming logs for: $service_name (Press Ctrl+C to exit)...${NC}"
    docker logs -f "$service_name"
}

backup_stack() {
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="${BACKUP_DIR}/llm-stack-backup-${TIMESTAMP}.tar.gz"
    echo -e "${YELLOW}Creating snapshot backup to: ${BACKUP_FILE}...${NC}"

    TMP_DUMP=$(mktemp -d)
    
    # 1. Export MongoDB if running
    if docker ps -q -f name=chat-mongodb | grep -q .; then
        echo "Dumping MongoDB databases..."
        docker exec chat-mongodb mongodump --out /tmp/mongodump 2>/dev/null || true
        docker cp chat-mongodb:/tmp/mongodump "${TMP_DUMP}/mongodb" 2>/dev/null || true
        docker exec chat-mongodb rm -rf /tmp/mongodump 2>/dev/null || true
    fi

    # 2. Export LiteLLM Postgres if running
    if docker ps -q -f name=litellm_db | grep -q .; then
        echo "Dumping LiteLLM PostgreSQL database..."
        docker exec -t litellm_db pg_dumpall -c -U litellm > "${TMP_DUMP}/litellm_db.sql" 2>/dev/null || true
    fi

    # 3. Copy configuration files
    mkdir -p "${TMP_DUMP}/configs"
    cp "${LITELLM_DIR}/litellm_config.yaml" "${TMP_DUMP}/configs/" 2>/dev/null || true
    cp "${LITELLM_DIR}/.env" "${TMP_DUMP}/configs/litellm.env" 2>/dev/null || true
    cp "${LIBRECHAT_DIR}/librechat.yaml" "${TMP_DUMP}/configs/" 2>/dev/null || true
    cp "${LIBRECHAT_DIR}/.env" "${TMP_DUMP}/configs/librechat.env" 2>/dev/null || true

    # Create tarball
    tar -czf "$BACKUP_FILE" -C "$TMP_DUMP" .
    rm -rf "$TMP_DUMP"
    echo -e "${GREEN}✓ Backup created successfully: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))${NC}"
}

check_stack() {
    echo -e "${BLUE}=== Checking AI Stack Configuration ===${NC}"
    
    # Check LiteLLM keys
    if [ -f "${LITELLM_DIR}/.env" ]; then
        if grep -q '^OPENROUTER_API_KEY=sk-' "${LITELLM_DIR}/.env"; then
            echo -e "${GREEN}✓ OPENROUTER_API_KEY is configured in Litellm/.env${NC}"
        else
            echo -e "${YELLOW}! OPENROUTER_API_KEY is not yet set in Litellm/.env (required for cloud model routing)${NC}"
        fi
    else
        echo -e "${RED}✗ Litellm/.env is missing. Run ./setup.sh${NC}"
    fi

    # Check Granite model
    if [ -f "${SCRIPT_DIR}/granite-model/model.safetensors" ]; then
        echo -e "${GREEN}✓ Local IBM Granite embedding weights present ($(du -h "${SCRIPT_DIR}/granite-model/model.safetensors" | cut -f1))${NC}"
    else
        echo -e "${RED}✗ IBM Granite embedding model weights missing in granite-model/. Run ./download-model.sh${NC}"
    fi

    # Check network
    if docker network inspect llm-network >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker network 'llm-network' is ready${NC}"
    else
        echo -e "${YELLOW}! Docker network 'llm-network' does not exist (will be created automatically)${NC}"
    fi
}

case "$1" in
    start|up)
        start_stack
        ;;
    stop|down)
        stop_stack
        ;;
    restart)
        stop_stack
        sleep 2
        start_stack
        ;;
    status|ps)
        status_stack
        ;;
    logs)
        logs_stack "$@"
        ;;
    backup)
        backup_stack
        ;;
    check)
        check_stack
        ;;
    *)
        echo "Usage: llm-stack {start|stop|restart|status|logs [container_name]|backup|check}"
        echo ""
        echo "Commands:"
        echo "  start   - Start both LiteLLM and LibreChat stacks"
        echo "  stop    - Stop all containers across both stacks"
        echo "  restart - Restart all services"
        echo "  status  - Show status of all containers"
        echo "  logs    - View live logs (default: LibreChat, or specify container name)"
        echo "  backup  - Snapshot databases and configuration to backups/"
        echo "  check   - Validate environment and configuration completeness"
        exit 1
        ;;
esac
