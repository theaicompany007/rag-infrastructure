#!/bin/bash
# Infrastructure Management Script
# Manages RAG Service, ChromaDB, Redis, and Ngrok
# Location: /home/postgres/rag-infrastructure/manage-infra.sh
#
# Usage:
#   ./manage-infra.sh [start|stop|restart|rebuild|rebuild-rag|purge|status|...]
#
# Commands:
#   start          - Start infrastructure services (RAG/ChromaDB/Redis)
#   stop           - Stop infrastructure services
#   restart        - Restart infrastructure services
#   rebuild        - Rebuild and restart all services
#   rebuild-rag    - Rebuild and restart RAG service only
#   purge          - Stop and remove containers, networks (keeps volumes)
#   status         - Show status of infrastructure services
#   enable-ngrok   - Enable ngrok service (systemd)
#   disable-ngrok  - Disable ngrok service (systemd)
#   ngrok-status   - Check ngrok service status and active tunnels
#
# Notes:
#   - Infrastructure must start BEFORE other projects (revenue/web/vani depend on it)
#   - This project creates the shared-infra-network that other projects connect to
#   - Celery Worker and Celery Beat run in VANI project (not here)
#   - Purge only affects infrastructure project, not other projects
#   - Ngrok runs as a systemd service on the host (not in Docker) to expose services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="infra"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Infrastructure Management (RAG/ChromaDB/Redis/Ngrok)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${RED}❌ Error: $COMPOSE_FILE not found in $(pwd)${NC}"
        exit 1
    fi
}

cmd_start() {
    print_header
    echo -e "${YELLOW}🚀 Starting infrastructure services...${NC}"
    echo ""
    
    check_compose_file
    
    # Create .env file if it doesn't exist (for build args)
    if [ ! -f .env ]; then
        echo -e "${YELLOW}⚠️  .env file not found. Creating from .env.local...${NC}"
        if [ -f .env.local ]; then
            # Extract build args from .env.local
            grep -E "^(SUPABASE_URL|NEXT_PUBLIC_SUPABASE_URL|NEXT_PUBLIC_SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY)=" .env.local > .env 2>/dev/null || true
        fi
    fi
    
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    echo ""
    echo -e "${GREEN}✅ Infrastructure services started!${NC}"
    echo ""
    echo -e "${CYAN}Services:${NC}"
    echo "  - RAG Service: http://localhost:8001"
    echo "  - ChromaDB: http://localhost:8000"
    echo "  - Redis: localhost:6379"
    echo ""
    echo -e "${YELLOW}💡 Note: Other projects (revenue/web/vani) can now connect via shared-infra-network${NC}"
    echo -e "${YELLOW}💡 Note: Celery Worker and Celery Beat run in VANI project${NC}"
}

cmd_stop() {
    print_header
    echo -e "${YELLOW}🛑 Stopping infrastructure services...${NC}"
    echo ""
    
    check_compose_file
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" stop
    
    echo ""
    echo -e "${GREEN}✅ Infrastructure services stopped${NC}"
    echo -e "${YELLOW}⚠️  Note: Other projects may be affected if they depend on these services${NC}"
}

cmd_restart() {
    print_header
    echo -e "${YELLOW}🔄 Restarting infrastructure services...${NC}"
    echo ""
    
    check_compose_file
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" restart
    
    echo ""
    echo -e "${GREEN}✅ Infrastructure services restarted${NC}"
}

cmd_rebuild() {
    print_header
    echo -e "${YELLOW}🔨 Rebuilding and restarting infrastructure services...${NC}"
    echo ""
    
    check_compose_file
    
    # Create .env file if needed
    if [ ! -f .env ]; then
        if [ -f .env.local ]; then
            grep -E "^(SUPABASE_URL|NEXT_PUBLIC_SUPABASE_URL|NEXT_PUBLIC_SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY)=" .env.local > .env 2>/dev/null || true
        fi
    fi
    
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d --build
    
    echo ""
    echo -e "${GREEN}✅ Infrastructure services rebuilt and started${NC}"
}

cmd_rebuild_rag() {
    print_header
    echo -e "${YELLOW}🔨 Rebuilding and restarting RAG service only...${NC}"
    echo ""
    
    check_compose_file
    
    if [ ! -f .env ]; then
        if [ -f .env.local ]; then
            grep -E "^(SUPABASE_URL|NEXT_PUBLIC_SUPABASE_URL|NEXT_PUBLIC_SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY)=" .env.local > .env 2>/dev/null || true
        fi
    fi
    
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" build rag-service && \
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d rag-service
    
    echo ""
    echo -e "${GREEN}✅ RAG service rebuilt and started${NC}"
}

cmd_purge() {
    print_header
    echo -e "${RED}🗑️  Purging infrastructure services...${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  This will:${NC}"
    echo "  - Stop all infrastructure containers"
    echo "  - Remove infrastructure containers"
    echo "  - Remove infrastructure networks"
    echo "  - Keep volumes (data preserved)"
    echo ""
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}Cancelled${NC}"
        exit 0
    fi
    
    check_compose_file
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    
    echo ""
    echo -e "${GREEN}✅ Infrastructure services purged${NC}"
    echo -e "${YELLOW}⚠️  Note: Volumes preserved. Other projects may need to restart.${NC}"
}

cmd_status() {
    print_header
    echo -e "${CYAN}📊 Infrastructure Services Status${NC}"
    echo ""
    
    check_compose_file
    
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" ps
    
    echo ""
    echo -e "${CYAN}Network Status:${NC}"
    if docker network ls | grep -q "shared-infra-network"; then
        echo -e "${GREEN}✅ shared-infra-network exists${NC}"
        docker network inspect shared-infra-network --format '  Containers: {{len .Containers}}' 2>/dev/null || echo "  (no containers connected)"
    else
        echo -e "${YELLOW}⚠️  shared-infra-network not found (start services to create it)${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Service Containers:${NC}"
    for service in rag-service chroma redis; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            echo -e "${GREEN}✅ ${service} is running${NC}"
        else
            echo -e "${YELLOW}⚠️  ${service} is not running${NC}"
        fi
    done
    
    echo ""
    echo -e "${CYAN}Ngrok Service (Host):${NC}"
    # Check for multiple possible ngrok service names
    ngrok_services=$(systemctl list-units --type=service 2>/dev/null | grep -i ngrok | awk '{print $1}' || true)
    if [ -n "$ngrok_services" ]; then
        echo "$ngrok_services" | while read svc; do
            if systemctl is-active "$svc" &>/dev/null 2>&1; then
                status="RUNNING"
                color="${GREEN}"
            elif systemctl is-enabled "$svc" &>/dev/null 2>&1; then
                status="ENABLED (not running)"
                color="${YELLOW}"
            else
                status="DISABLED"
                color="${YELLOW}"
            fi
            echo -e "${color}  ${svc}: ${status}${NC}"
        done
    else
        echo -e "${YELLOW}  No ngrok systemd service found${NC}"
    fi
    
    # Check for running ngrok processes
    if pgrep -f "ngrok" > /dev/null 2>&1; then
        echo -e "${GREEN}  Ngrok process(es) running:${NC}"
        ps aux | grep -E "[n]grok" | grep -v grep | head -3 | while read line; do
            echo "    $line"
        done
    fi
    
    # Check ngrok API if accessible
    if command -v curl > /dev/null 2>&1; then
        if curl -s http://localhost:4040/api/tunnels > /dev/null 2>&1; then
            echo -e "${GREEN}  Ngrok API accessible at http://localhost:4040${NC}"
            tunnels=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"[^"]*"' | head -3)
            if [ -n "$tunnels" ]; then
                echo -e "${CYAN}  Active tunnels:${NC}"
                curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"[^"]*"' | head -3 | while read url; do
                    clean_url=$(echo "$url" | cut -d'"' -f4)
                    echo "    - $clean_url"
                done
            fi
        fi
    fi
}

cmd_enable_ngrok() {
    print_header
    echo -e "${YELLOW}✅ Enabling ngrok service...${NC}"
    echo ""
    echo -e "${CYAN}⚠️  NOTE: Ngrok is for DEVELOPMENT ONLY${NC}"
    echo -e "${CYAN}   Production should use load balancer URLs${NC}"
    echo -e "${CYAN}   Set ENABLE_NGROK=false in .env.local for production${NC}"
    echo ""
    
    # Check if ngrok is installed
    if ! command -v ngrok &> /dev/null; then
        echo -e "${RED}❌ Ngrok is not installed${NC}"
        echo -e "${YELLOW}💡 Install ngrok: https://ngrok.com/download${NC}"
        echo -e "${YELLOW}💡 Or: sudo apt-get install ngrok${NC}"
        exit 1
    fi
    
    # Find existing ngrok service or create one
    NGROK_SERVICE=""
    for service in onlyne-ngrok.service vani-ngrok.service ngrok-vani.service infra-ngrok.service; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            NGROK_SERVICE="$service"
            break
        fi
    done
    
    if [ -z "$NGROK_SERVICE" ]; then
        echo -e "${YELLOW}⚠️  No ngrok systemd service found${NC}"
        echo -e "${CYAN}Creating infrastructure ngrok service...${NC}"
        
        # Check if we have a local service file template
        if [ -f "infra-ngrok.service" ]; then
            echo -e "${CYAN}Using local infra-ngrok.service template...${NC}"
            sudo cp infra-ngrok.service /etc/systemd/system/infra-ngrok.service
            sudo systemctl daemon-reload
            NGROK_SERVICE="infra-ngrok.service"
            echo -e "${GREEN}✅ Created ${NGROK_SERVICE}${NC}"
        elif [ -f "../vani/deployment/vani-ngrok.service" ]; then
            echo -e "${CYAN}Using VANI ngrok service as template...${NC}"
            sudo cp ../vani/deployment/vani-ngrok.service /etc/systemd/system/infra-ngrok.service
            # Modify for infrastructure
            sudo sed -i 's/VANI/Infrastructure/g' /etc/systemd/system/infra-ngrok.service
            sudo sed -i 's/vani/infra/g' /etc/systemd/system/infra-ngrok.service
            sudo systemctl daemon-reload
            NGROK_SERVICE="infra-ngrok.service"
            echo -e "${GREEN}✅ Created ${NGROK_SERVICE}${NC}"
        else
            echo -e "${YELLOW}⚠️  Service file template not found${NC}"
            echo -e "${CYAN}You can create it manually or use existing service${NC}"
            echo ""
            echo -e "${CYAN}Existing ngrok services:${NC}"
            systemctl list-units --type=service 2>/dev/null | grep -i ngrok || echo "  (none found)"
            echo ""
            read -p "Enter service name to enable (or press Enter to skip): " NGROK_SERVICE
            if [ -z "$NGROK_SERVICE" ]; then
                echo -e "${YELLOW}⚠️  Skipping service creation - ngrok can run as process${NC}"
                exit 0
            fi
        fi
    fi
    
    if [ -n "$NGROK_SERVICE" ]; then
        # Check if ngrok config exists
        if [ ! -f ~/.config/ngrok/ngrok.yml ] && [ ! -f /home/postgres/.config/ngrok/ngrok.yml ]; then
            echo -e "${YELLOW}⚠️  Ngrok config not found${NC}"
            echo -e "${CYAN}You may need to configure ngrok:${NC}"
            echo "  1. Set authtoken: ngrok config add-authtoken YOUR_TOKEN"
            echo "  2. Create config: ~/.config/ngrok/ngrok.yml"
        fi
        
        sudo systemctl enable "$NGROK_SERVICE"
        echo -e "${GREEN}✅ Ngrok service enabled (will start on boot)${NC}"
        
        # Optionally start it now
        if systemctl is-active "$NGROK_SERVICE" &>/dev/null; then
            echo -e "${GREEN}✅ Ngrok service is already running${NC}"
        else
            read -p "Start ngrok service now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo systemctl start "$NGROK_SERVICE"
                sleep 2
                if systemctl is-active "$NGROK_SERVICE" &>/dev/null; then
                    echo -e "${GREEN}✅ Ngrok service started${NC}"
                else
                    echo -e "${RED}❌ Failed to start ngrok service${NC}"
                    echo -e "${CYAN}Check logs: sudo journalctl -u $NGROK_SERVICE -n 50${NC}"
                fi
            fi
        fi
    fi
}

cmd_disable_ngrok() {
    print_header
    echo -e "${YELLOW}🛑 Disabling ngrok service...${NC}"
    echo ""
    
    # Stop all possible ngrok services
    stopped_any=false
    for service in onlyne-ngrok.service vani-ngrok.service ngrok-vani.service infra-ngrok.service; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            if systemctl is-active "$service" &>/dev/null; then
                echo -e "${CYAN}Stopping ${service}...${NC}"
                sudo systemctl stop "$service"
                echo -e "${GREEN}✅ Stopped ${service}${NC}"
                stopped_any=true
            fi
            sudo systemctl disable "$service" 2>/dev/null || true
            echo -e "${GREEN}✅ Disabled ${service} (will not start on boot)${NC}"
        fi
    done
    
    if [ "$stopped_any" = false ]; then
        echo -e "${YELLOW}⚠️  No ngrok systemd services found or running${NC}"
    fi
    
    # Also check for running ngrok processes
    if pgrep -f "ngrok" > /dev/null 2>&1; then
        echo ""
        echo -e "${CYAN}Found running ngrok processes:${NC}"
        ps aux | grep -E "[n]grok" | grep -v grep | head -3
        read -p "Stop all ngrok processes? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pkill -f ngrok
            sleep 2
            if ! pgrep -f "ngrok" > /dev/null 2>&1; then
                echo -e "${GREEN}✅ All ngrok processes stopped${NC}"
            else
                echo -e "${YELLOW}⚠️  Some ngrok processes may still be running${NC}"
                echo -e "${CYAN}Check manually: ps aux | grep ngrok${NC}"
            fi
        fi
    fi
}

cmd_ngrok_status() {
    print_header
    echo -e "${CYAN}📊 Ngrok Service Status${NC}"
    echo ""
    
    # Check systemd services
    echo -e "${CYAN}Systemd Services:${NC}"
    ngrok_services=$(systemctl list-units --type=service 2>/dev/null | grep -i ngrok | awk '{print $1}' || true)
    if [ -n "$ngrok_services" ]; then
        echo "$ngrok_services" | while read svc; do
            if systemctl is-active "$svc" &>/dev/null 2>&1; then
                status="RUNNING"
                color="${GREEN}"
            elif systemctl is-enabled "$svc" &>/dev/null 2>&1; then
                status="ENABLED (not running)"
                color="${YELLOW}"
            else
                status="DISABLED"
                color="${YELLOW}"
            fi
            echo -e "${color}  ${svc}: ${status}${NC}"
            if systemctl is-active "$svc" &>/dev/null 2>&1; then
                systemctl status "$svc" --no-pager -l | head -10
            fi
        done
    else
        echo -e "${YELLOW}  No ngrok systemd services found${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Running Processes:${NC}"
    if pgrep -f "ngrok" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Ngrok process(es) found:${NC}"
        ps aux | grep -E "[n]grok" | grep -v grep | while read line; do
            echo "  $line"
        done
    else
        echo -e "${YELLOW}  No ngrok processes running${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Ngrok API:${NC}"
    if command -v curl > /dev/null 2>&1; then
        if curl -s http://localhost:4040/api/tunnels > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Ngrok API accessible at http://localhost:4040${NC}"
            echo ""
            echo -e "${CYAN}Active Tunnels:${NC}"
            tunnels_json=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null)
            if echo "$tunnels_json" | grep -q '"tunnels"'; then
                echo "$tunnels_json" | grep -o '"public_url":"[^"]*"' | while read url; do
                    clean_url=$(echo "$url" | cut -d'"' -f4)
                    # Get tunnel config
                    addr=$(echo "$tunnels_json" | grep -A 5 "$clean_url" | grep -o '"addr":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
                    echo -e "${GREEN}  - ${clean_url} → ${addr}${NC}"
                done
            else
                echo -e "${YELLOW}  No active tunnels found${NC}"
            fi
        else
            echo -e "${YELLOW}  Ngrok API not accessible (ngrok may not be running)${NC}"
        fi
    else
        echo -e "${YELLOW}  curl not available - cannot check API${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Ngrok Configuration:${NC}"
    if [ -f ~/.config/ngrok/ngrok.yml ]; then
        echo -e "${GREEN}✅ Config found: ~/.config/ngrok/ngrok.yml${NC}"
        if grep -q "authtoken" ~/.config/ngrok/ngrok.yml 2>/dev/null; then
            echo -e "${GREEN}  Authtoken configured${NC}"
        else
            echo -e "${YELLOW}  Authtoken not found in config${NC}"
        fi
        if grep -q "tunnels:" ~/.config/ngrok/ngrok.yml 2>/dev/null; then
            echo -e "${GREEN}  Tunnel configuration found${NC}"
            grep -A 10 "tunnels:" ~/.config/ngrok/ngrok.yml | head -15
        else
            echo -e "${YELLOW}  No tunnel configuration found${NC}"
        fi
    elif [ -f /home/postgres/.config/ngrok/ngrok.yml ]; then
        echo -e "${GREEN}✅ Config found: /home/postgres/.config/ngrok/ngrok.yml${NC}"
    else
        echo -e "${YELLOW}  Config not found${NC}"
        echo -e "${CYAN}  Expected: ~/.config/ngrok/ngrok.yml${NC}"
    fi
}

cmd_fix_redis_misconf() {
    print_header
    echo -e "${YELLOW}🔧 Fixing Redis MISCONF (cannot persist to disk)...${NC}"
    echo ""
    
    if ! docker ps --format "{{.Names}}" | grep -q "^redis$"; then
        echo -e "${RED}❌ Redis container is not running${NC}"
        echo -e "${YELLOW}💡 Start infrastructure first: ./manage-infra.sh start${NC}"
        exit 1
    fi
    
    echo "Running: docker exec redis redis-cli CONFIG SET stop-writes-on-bgsave-error no"
    if docker exec redis redis-cli CONFIG SET stop-writes-on-bgsave-error no 2>/dev/null; then
        echo ""
        echo -e "${GREEN}✅ Redis MISCONF fix applied${NC}"
        echo "   Redis will now accept writes even if RDB snapshot fails."
        echo "   To verify: docker exec redis redis-cli set test 1 && docker exec redis redis-cli del test"
    else
        echo -e "${RED}❌ Failed to apply fix${NC}"
        echo "   Check: docker logs redis"
        echo "   Or fix disk permissions: docker exec redis ls -la /data"
        exit 1
    fi
}

# Main command dispatcher
case "${1:-}" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    rebuild)
        cmd_rebuild
        ;;
    rebuild-rag)
        cmd_rebuild_rag
        ;;
    purge)
        cmd_purge
        ;;
    status)
        cmd_status
        ;;
    enable-ngrok)
        cmd_enable_ngrok
        ;;
    disable-ngrok)
        cmd_disable_ngrok
        ;;
    ngrok-status)
        cmd_ngrok_status
        ;;
    fix-redis-misconf)
        cmd_fix_redis_misconf
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|rebuild|rebuild-rag|purge|status|enable-ngrok|disable-ngrok|ngrok-status|fix-redis-misconf}"
        echo ""
        echo "Commands:"
        echo "  start             - Start infrastructure services (Docker)"
        echo "  stop              - Stop infrastructure services (Docker)"
        echo "  restart           - Restart infrastructure services (Docker)"
        echo "  rebuild           - Rebuild and restart all services (Docker)"
        echo "  rebuild-rag       - Rebuild and restart RAG service only (Docker)"
        echo "  purge             - Stop and remove containers/networks (keeps volumes)"
        echo "  status            - Show status of all services (Docker + Ngrok)"
        echo "  enable-ngrok      - Enable ngrok service (systemd)"
        echo "  disable-ngrok     - Disable ngrok service (systemd)"
        echo "  ngrok-status      - Check ngrok service status and active tunnels"
        echo "  fix-redis-misconf - Fix Redis MISCONF (cannot persist to disk) error"
        echo ""
        echo "Note: Celery Worker and Celery Beat run in VANI project (not here)"
        exit 1
        ;;
esac

