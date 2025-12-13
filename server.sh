#!/bin/bash
# Don't use set -e, we handle errors explicitly

# ============================================
#         Claude Server Manager
# ============================================
# Single entry point for setup and running

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# State file to track setup completion
SETUP_DONE_FILE="$PROJECT_ROOT/.setup_complete"

clear
echo -e "${CYAN}"
echo "   ╔═══════════════════════════════════════╗"
echo "   ║        Claude Server Manager          ║"
echo "   ╚═══════════════════════════════════════╝"
echo -e "${NC}"

# ============================================
# Helper Functions
# ============================================

print_step() { echo -e "\n${BLUE}▶ $1${NC}"; }
print_ok() { echo -e "  ${GREEN}✓${NC} $1"; }
print_warn() { echo -e "  ${YELLOW}!${NC} $1"; }
print_err() { echo -e "  ${RED}✗${NC} $1"; }

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

wait_for_key() {
    echo ""
    read -p "  Press Enter to continue..."
}

# ============================================
# Setup Check
# ============================================

run_setup() {
    print_step "Checking requirements..."
    
    MISSING=""
    
    # Python
    if check_command python3; then
        print_ok "Python 3 installed"
    else
        print_err "Python 3 not found"
        MISSING="$MISSING python3"
    fi
    
    # Docker (optional but recommended)
    if check_command docker; then
        print_ok "Docker installed"
        HAS_DOCKER=true
    else
        print_warn "Docker not found (optional, for production)"
        HAS_DOCKER=false
    fi
    
    # Flutter (optional)
    if check_command flutter; then
        print_ok "Flutter installed"
        HAS_FLUTTER=true
    else
        print_warn "Flutter not found (optional, for frontend dev)"
        HAS_FLUTTER=false
    fi
    
    # Claude CLI
    if check_command claude; then
        print_ok "Claude CLI installed"
    else
        print_warn "Claude CLI not found"
        echo -e "       Install: ${CYAN}npm install -g @anthropic-ai/claude-code${NC}"
    fi
    
    if [ -n "$MISSING" ]; then
        echo ""
        print_err "Missing required:$MISSING"
        echo "  Please install and run this script again."
        exit 1
    fi
    
    # Create directories
    print_step "Creating directories..."
    mkdir -p "$PROJECT_ROOT/data/artifacts"
    mkdir -p "$PROJECT_ROOT/data/logs/jobs"
    mkdir -p "$PROJECT_ROOT/users"
    mkdir -p "$PROJECT_ROOT/config"
    print_ok "Directories created"
    
    # Setup backend
    print_step "Setting up backend..."
    cd "$PROJECT_ROOT/backend"
    
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        print_ok "Virtual environment created"
    fi
    
    source venv/bin/activate
    pip install --upgrade pip -q 2>/dev/null
    pip install -r requirements.txt -q 2>/dev/null
    print_ok "Dependencies installed"
    
    # Generate .env if needed
    if [ ! -f "$PROJECT_ROOT/config/.env" ]; then
        print_step "Generating configuration..."
        
        SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
        
        cat > "$PROJECT_ROOT/config/.env" << ENVFILE
# Claude Server Configuration
# Generated on $(date)

# Server
HOST=0.0.0.0
PORT=8000
DEBUG=false

# Security - DO NOT SHARE THIS KEY
SECRET_KEY=$SECRET

# Database
DATABASE_URL=sqlite+aiosqlite:///$PROJECT_ROOT/data/dev_platform.db

# Paths
USERS_PATH=$PROJECT_ROOT/users
DATA_PATH=$PROJECT_ROOT/data
LOGS_PATH=$PROJECT_ROOT/data/logs

# Claude
CLAUDE_BINARY=claude
DEFAULT_MODEL=claude-sonnet-4-20250514

# Sandbox (set true when firejail/docker available)
REQUIRE_SANDBOX=false
ENVFILE
        print_ok "Configuration generated"
    else
        print_ok "Configuration exists"
    fi
    
    # Initialize database
    print_step "Initializing database..."
    python3 << 'PYINIT'
import asyncio
import sys
sys.path.insert(0, '.')
from app.database import engine, Base
from app.models import *

async def init():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

asyncio.run(init())
PYINIT
    print_ok "Database ready"
    
    deactivate
    cd "$PROJECT_ROOT"
    
    # Setup frontend if Flutter available
    if [ "$HAS_FLUTTER" = true ]; then
        print_step "Setting up frontend..."
        cd "$PROJECT_ROOT/frontend"
        if flutter config --enable-web > /dev/null 2>&1 && flutter pub get > /dev/null 2>&1; then
            print_ok "Frontend ready"
        else
            print_warn "Frontend setup had issues (may still work)"
        fi
        cd "$PROJECT_ROOT"
    fi
    
    # Mark setup complete
    date > "$SETUP_DONE_FILE"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}         Setup Complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
}

# ============================================
# Main Menu
# ============================================

show_menu() {
    echo ""
    echo -e "${BOLD}What would you like to do?${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) Start Backend Server"
    echo -e "  ${CYAN}2${NC}) Start Backend + Frontend (Development)"
    if check_command docker; then
        echo -e "  ${CYAN}3${NC}) Deploy with Docker (Production)"
    fi
    echo ""
    echo -e "  ${CYAN}s${NC}) Re-run Setup"
    echo -e "  ${CYAN}c${NC}) Edit Configuration"
    echo -e "  ${CYAN}q${NC}) Quit"
    echo ""
}

start_backend() {
    echo ""
    print_step "Starting backend server..."
    echo ""
    echo -e "  ${GREEN}API:${NC}  http://localhost:8000"
    echo -e "  ${GREEN}Docs:${NC} http://localhost:8000/docs"
    echo ""
    echo -e "  ${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""
    
    cd "$PROJECT_ROOT/backend"
    source venv/bin/activate
    python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
}

start_dev() {
    if ! check_command flutter; then
        print_err "Flutter not installed. Use option 1 for backend only."
        return
    fi
    
    echo ""
    print_step "Starting development servers..."
    echo ""
    echo -e "  ${GREEN}Backend:${NC}  http://localhost:8000"
    echo -e "  ${GREEN}Frontend:${NC} Will open in Chrome"
    echo ""
    
    # Start backend in background
    cd "$PROJECT_ROOT/backend"
    source venv/bin/activate
    python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 &
    BACKEND_PID=$!
    
    sleep 2
    
    # Start frontend
    cd "$PROJECT_ROOT/frontend"
    flutter run -d chrome
    
    # Cleanup
    kill $BACKEND_PID 2>/dev/null
}

deploy_docker() {
    echo ""
    print_step "Deploying with Docker..."
    
    cd "$PROJECT_ROOT"
    
    # Check for docker compose
    if docker compose version &> /dev/null; then
        COMPOSE="docker compose"
    elif check_command docker-compose; then
        COMPOSE="docker-compose"
    else
        print_err "Docker Compose not found"
        return
    fi
    
    echo ""
    echo -e "  ${CYAN}1${NC}) Start services"
    echo -e "  ${CYAN}2${NC}) Stop services"
    echo -e "  ${CYAN}3${NC}) View logs"
    echo -e "  ${CYAN}4${NC}) Rebuild & restart"
    echo -e "  ${CYAN}b${NC}) Back"
    echo ""
    read -p "  Select: " docker_choice
    
    case $docker_choice in
        1)
            $COMPOSE up -d --build
            echo ""
            echo -e "  ${GREEN}Services started!${NC}"
            echo -e "  Frontend: http://localhost"
            echo -e "  Backend:  http://localhost:8000"
            ;;
        2)
            $COMPOSE down
            print_ok "Services stopped"
            ;;
        3)
            $COMPOSE logs -f
            ;;
        4)
            $COMPOSE down
            $COMPOSE up -d --build
            print_ok "Services rebuilt and started"
            ;;
    esac
}

edit_config() {
    CONFIG_FILE="$PROJECT_ROOT/config/.env"
    
    if check_command nano; then
        nano "$CONFIG_FILE"
    elif check_command vim; then
        vim "$CONFIG_FILE"
    elif check_command vi; then
        vi "$CONFIG_FILE"
    else
        echo ""
        echo "  Config file: $CONFIG_FILE"
        echo ""
        cat "$CONFIG_FILE"
    fi
}

# ============================================
# Main
# ============================================

# Check if setup needed
if [ ! -f "$SETUP_DONE_FILE" ]; then
    echo -e "${YELLOW}First time setup required.${NC}"
    wait_for_key
    run_setup
    wait_for_key
fi

# Main loop
while true; do
    clear
    echo -e "${CYAN}"
    echo "   ╔═══════════════════════════════════════╗"
    echo "   ║        Claude Server Manager          ║"
    echo "   ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Show status
    echo -e "  ${BOLD}Status:${NC}"
    if [ -f "$SETUP_DONE_FILE" ]; then
        echo -e "  ${GREEN}●${NC} Setup complete"
    else
        echo -e "  ${RED}●${NC} Setup required"
    fi
    
    # Check if backend running
    if curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
        echo -e "  ${GREEN}●${NC} Backend running"
    else
        echo -e "  ${YELLOW}●${NC} Backend stopped"
    fi
    
    show_menu
    read -p "  Select: " choice
    
    case $choice in
        1) start_backend ;;
        2) start_dev ;;
        3) deploy_docker ;;
        s|S) run_setup; wait_for_key ;;
        c|C) edit_config ;;
        q|Q) echo ""; exit 0 ;;
        *) print_warn "Invalid option" ;;
    esac
done
