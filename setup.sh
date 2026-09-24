#!/usr/bin/env bash
# ==============================================================================
# llm-stack: Automated Setup & Bootstrap Script
# ==============================================================================

set -e

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Dynamically locate root script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

LITELLM_DIR="${SCRIPT_DIR}/Litellm"
LIBRECHAT_DIR="${SCRIPT_DIR}/LibreChat"
MODEL_DIR="${SCRIPT_DIR}/granite-model"

echo -e "${BLUE}====================================================================${NC}"
echo -e "${BLUE}   llm-stack: Automated Environment Setup & Dependency Bootstrap    ${NC}"
echo -e "${BLUE}====================================================================${NC}"

# 1. Prerequisite Checks
echo -e "\n${YELLOW}[1/6] Verifying System Prerequisites...${NC}"

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not installed. Please install Docker before running setup.${NC}"
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker Compose (v2) is not installed. Please install docker-compose-plugin.${NC}"
    exit 1
fi

# Ensure Docker daemon is reachable
if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker daemon is not running. Attempting to start service...${NC}"
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl start docker || true
    elif command -v service >/dev/null 2>&1; then
        sudo service docker start || true
    fi
    sleep 3
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Unable to connect to Docker daemon. Please ensure Docker is running.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ Docker and Docker Compose v2 verified.${NC}"

# 2. Shared Network Creation
echo -e "\n${YELLOW}[2/6] Configuring Docker Network...${NC}"
if ! docker network inspect llm-network >/dev/null 2>&1; then
    docker network create llm-network
    echo -e "${GREEN}✓ Created bridge network 'llm-network'.${NC}"
else
    echo -e "${GREEN}✓ Network 'llm-network' already exists.${NC}"
fi

# 3. Environment & Cryptographic Secrets Generation
echo -e "\n${YELLOW}[3/6] Initializing Environment Variables & Security Tokens...${NC}"

generate_hex() {
    local bytes="$1"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$bytes"
    else
        head -c "$bytes" /dev/urandom | xxd -p | tr -d '\n'
    fi
}

# Generate unique internal secrets
LITELLM_MASTER_KEY="sk-$(generate_hex 16)"
LITELLM_SALT_KEY="$(generate_hex 16)"
JWT_SECRET="$(generate_hex 32)"
JWT_REFRESH_SECRET="$(generate_hex 32)"
CREDS_KEY="$(generate_hex 16)"
CREDS_IV="$(generate_hex 8)"
MEILI_MASTER_KEY="$(generate_hex 16)"
ADMIN_PANEL_SECRET="$(generate_hex 32)"

# Setup LiteLLM .env
if [ ! -f "${LITELLM_DIR}/.env" ]; then
    echo "Creating Litellm/.env from template..."
    cp "${LITELLM_DIR}/.env.example" "${LITELLM_DIR}/.env"
    sed -i "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}|" "${LITELLM_DIR}/.env"
    sed -i "s|^LITELLM_SALT_KEY=.*|LITELLM_SALT_KEY=${LITELLM_SALT_KEY}|" "${LITELLM_DIR}/.env"
    echo -e "${GREEN}✓ Created Litellm/.env with secure master credentials.${NC}"
else
    echo -e "${GREEN}✓ Litellm/.env already exists (preserving existing keys).${NC}"
    EXISTING_MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' "${LITELLM_DIR}/.env" | cut -d= -f2)
    if [ -n "$EXISTING_MASTER_KEY" ]; then
        LITELLM_MASTER_KEY="$EXISTING_MASTER_KEY"
    fi
fi

# Setup LiteLLM config
if [ ! -f "${LITELLM_DIR}/litellm_config.yaml" ]; then
    echo "Creating Litellm/litellm_config.yaml from example..."
    cp "${LITELLM_DIR}/litellm_config.example.yaml" "${LITELLM_DIR}/litellm_config.yaml"
    echo -e "${GREEN}✓ Created Litellm/litellm_config.yaml.${NC}"
fi

# Setup LibreChat .env
if [ ! -f "${LIBRECHAT_DIR}/.env" ]; then
    echo "Creating LibreChat/.env from template..."
    cp "${LIBRECHAT_DIR}/.env.example" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^JWT_REFRESH_SECRET=.*|JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}|" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^CREDS_KEY=.*|CREDS_KEY=${CREDS_KEY}|" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^CREDS_IV=.*|CREDS_IV=${CREDS_IV}|" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^MEILI_MASTER_KEY=.*|MEILI_MASTER_KEY=${MEILI_MASTER_KEY}|" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^ADMIN_PANEL_SESSION_SECRET=.*|ADMIN_PANEL_SESSION_SECRET=${ADMIN_PANEL_SECRET}|" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^LITELLM_API_KEY=.*|LITELLM_API_KEY=${LITELLM_MASTER_KEY}|" "${LIBRECHAT_DIR}/.env"
    sed -i "s|^RAG_OPENAI_API_KEY=.*|RAG_OPENAI_API_KEY=${LITELLM_MASTER_KEY}|" "${LIBRECHAT_DIR}/.env"
    echo -e "${GREEN}✓ Created LibreChat/.env with synchronized tokens.${NC}"
else
    echo -e "${GREEN}✓ LibreChat/.env already exists (preserving existing settings).${NC}"
fi

# Ensure runtime directories exist
mkdir -p "${LIBRECHAT_DIR}/images" "${LIBRECHAT_DIR}/uploads" "${LIBRECHAT_DIR}/logs" "${LIBRECHAT_DIR}/skill" "${LIBRECHAT_DIR}/data-node" "${LIBRECHAT_DIR}/meili_data_v1.35.1"

# 4. IBM Granite Model Weights
echo -e "\n${YELLOW}[4/6] Checking Local Embedding Model Weights...${NC}"
if [ -f "${MODEL_DIR}/model.safetensors" ] && [ -s "${MODEL_DIR}/model.safetensors" ]; then
    echo -e "${GREEN}✓ Local IBM Granite embedding weights present in granite-model/.${NC}"
else
    echo -e "${YELLOW}Local weights not detected. Launching automated model download...${NC}"
    bash "${SCRIPT_DIR}/download-model.sh"
fi

# 5. Build Granite Embedding Service Image
echo -e "\n${YELLOW}[5/6] Building Local Granite Embedding Container Image...${NC}"
(cd "${LITELLM_DIR}" && docker compose build granite_embedding)
echo -e "${GREEN}✓ Granite embedding image successfully built.${NC}"

# 6. Install Global CLI Command (Optional)
echo -e "\n${YELLOW}[6/6] Registering 'llm-stack' CLI command...${NC}"
chmod +x "${SCRIPT_DIR}/llm-stack.sh" "${SCRIPT_DIR}/download-model.sh"
if [ -w /usr/local/bin ]; then
    ln -sf "${SCRIPT_DIR}/llm-stack.sh" /usr/local/bin/llm-stack
    echo -e "${GREEN}✓ Symlinked 'llm-stack' to /usr/local/bin/llm-stack.${NC}"
elif command -v sudo >/dev/null 2>&1; then
    sudo ln -sf "${SCRIPT_DIR}/llm-stack.sh" /usr/local/bin/llm-stack 2>/dev/null && \
        echo -e "${GREEN}✓ Symlinked 'llm-stack' to /usr/local/bin/llm-stack (via sudo).${NC}" || \
        echo -e "${YELLOW}Notice: Could not symlink to /usr/local/bin. You can use ./llm-stack.sh directly.${NC}"
else
    echo -e "${YELLOW}Notice: Run './llm-stack.sh' from this directory.${NC}"
fi

echo -e "\n${BLUE}====================================================================${NC}"
echo -e "${GREEN}${BOLD}✓ Environment Bootstrap Completed Successfully!${NC}"
echo -e "${BLUE}====================================================================${NC}"
echo -e "${YELLOW}${BOLD}POST-SETUP EXERCISES REQUIRED BEFORE FIRST START:${NC}"
echo -e "  ${BOLD}1. Configure API Keys:${NC}"
echo -e "     Edit: ${BOLD}${LITELLM_DIR}/.env${NC}"
echo -e "     Add your provider key (e.g., OPENROUTER_API_KEY=sk-or-v1-...)"
echo -e ""
echo -e "  ${BOLD}2. Select Models & Effort Tiers:${NC}"
echo -e "     Edit: ${BOLD}${LITELLM_DIR}/litellm_config.yaml${NC}"
echo -e "     Review or adjust the model pools for Tier 1 (Economy), Tier 2 (Workhorse), and Tier 3 (SOTA)."
echo -e ""
echo -e "  ${BOLD}3. (Optional) Set Server Domain for Intranet:${NC}"
echo -e "     Edit: ${BOLD}${LIBRECHAT_DIR}/.env${NC}"
echo -e "     Update DOMAIN_CLIENT and DOMAIN_SERVER to your server's IP or DNS name."
echo -e ""
echo -e "  ${BOLD}4. Launch the AI Stack:${NC}"
echo -e "     Run: ${BOLD}llm-stack start${NC}  (or ${BOLD}./llm-stack.sh start${NC})"
echo -e "${BLUE}====================================================================${NC}\n"
