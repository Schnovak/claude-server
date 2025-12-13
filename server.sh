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

# State files
SETUP_DONE_FILE="$PROJECT_ROOT/.setup_complete"
BACKEND_PID_FILE="$PROJECT_ROOT/.backend.pid"
BACKEND_LOG_FILE="$PROJECT_ROOT/data/logs/backend.log"

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

is_backend_running() {
    if [ -f "$BACKEND_PID_FILE" ]; then
        local pid=$(cat "$BACKEND_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

check_for_updates() {
    # Skip if not a git repo
    if [ ! -d "$PROJECT_ROOT/.git" ]; then
        return
    fi

    # Fetch latest (silently)
    git -C "$PROJECT_ROOT" fetch origin main --quiet 2>/dev/null || return

    # Check if behind
    LOCAL=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)
    REMOTE=$(git -C "$PROJECT_ROOT" rev-parse origin/main 2>/dev/null)

    if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
        echo ""
        echo -e "  ${YELLOW}╔═══════════════════════════════════════╗${NC}"
        echo -e "  ${YELLOW}║         Update Available!             ║${NC}"
        echo -e "  ${YELLOW}╚═══════════════════════════════════════╝${NC}"
        echo ""

        # Show what's new
        echo -e "  ${BOLD}Changes:${NC}"
        git -C "$PROJECT_ROOT" log --oneline HEAD..origin/main 2>/dev/null | head -5 | while read line; do
            echo -e "    ${CYAN}•${NC} $line"
        done
        echo ""

        read -p "  Update now? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            echo ""
            print_step "Updating..."

            # Stop backend if running
            if is_backend_running; then
                stop_backend
                print_ok "Backend stopped for update"
            fi

            # Pull updates
            if git -C "$PROJECT_ROOT" pull origin main --quiet; then
                print_ok "Updated successfully!"
                echo ""
                echo -e "  ${YELLOW}Restarting script...${NC}"
                sleep 1
                exec "$0" "$@"
            else
                print_err "Update failed. Try manually: git pull"
            fi
            wait_for_key
        fi
    fi
}

stop_backend() {
    if [ -f "$BACKEND_PID_FILE" ]; then
        local pid=$(cat "$BACKEND_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$BACKEND_PID_FILE"
    fi
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

    if is_backend_running; then
        echo -e "  ${CYAN}1${NC}) Stop Backend Server"
        echo -e "  ${CYAN}2${NC}) View Logs"
        echo -e "  ${CYAN}3${NC}) Restart Backend"
    else
        echo -e "  ${CYAN}1${NC}) Start Backend Server"
    fi

    if check_command flutter; then
        echo -e "  ${CYAN}f${NC}) Run Frontend (Flutter)"
    fi
    if check_command docker; then
        echo -e "  ${CYAN}d${NC}) Deploy with Docker (Production)"
    fi
    echo ""
    echo -e "  ${CYAN}s${NC}) Re-run Setup"
    echo -e "  ${CYAN}c${NC}) Edit Configuration"
    echo -e "  ${CYAN}q${NC}) Quit"
    echo ""
}

start_backend() {
    if is_backend_running; then
        print_warn "Backend already running"
        return
    fi

    echo ""
    print_step "Starting backend server..."

    # Ensure log directory exists
    mkdir -p "$(dirname "$BACKEND_LOG_FILE")"

    # Start in background
    cd "$PROJECT_ROOT/backend"
    source venv/bin/activate
    nohup python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > "$BACKEND_LOG_FILE" 2>&1 &
    echo $! > "$BACKEND_PID_FILE"

    sleep 2

    if is_backend_running; then
        echo ""
        print_ok "Backend started!"
        echo ""
        echo -e "  ${GREEN}API:${NC}  http://localhost:8000"
        echo -e "  ${GREEN}Docs:${NC} http://localhost:8000/docs"
        echo -e "  ${GREEN}Logs:${NC} $BACKEND_LOG_FILE"
    else
        print_err "Failed to start backend. Check logs:"
        echo ""
        tail -20 "$BACKEND_LOG_FILE"
    fi

    wait_for_key
}

view_logs() {
    if [ ! -f "$BACKEND_LOG_FILE" ]; then
        print_warn "No logs yet"
        wait_for_key
        return
    fi

    echo ""
    echo -e "  ${CYAN}1${NC}) View recent logs"
    echo -e "  ${CYAN}2${NC}) Follow live logs"
    echo -e "  ${CYAN}b${NC}) Back"
    echo ""
    read -p "  Select: " log_choice

    case $log_choice in
        1)
            echo ""
            echo -e "${BOLD}Recent Logs${NC} (press ${CYAN}q${NC} to go back)"
            echo -e "${CYAN}────────────────────────────────────────${NC}"
            if check_command less; then
                less +G "$BACKEND_LOG_FILE"
            else
                tail -50 "$BACKEND_LOG_FILE"
                wait_for_key
            fi
            ;;
        2)
            echo ""
            echo -e "${BOLD}Live Logs${NC} (press ${CYAN}Enter${NC} to stop)"
            echo -e "${CYAN}────────────────────────────────────────${NC}"
            # Run tail in background, wait for Enter to stop
            tail -f "$BACKEND_LOG_FILE" &
            TAIL_PID=$!
            read -r
            kill $TAIL_PID 2>/dev/null
            ;;
    esac
}

start_frontend() {
    if ! check_command flutter; then
        print_err "Flutter not installed."
        wait_for_key
        return
    fi

    if ! is_backend_running; then
        echo ""
        print_warn "Backend not running. Start it first?"
        read -p "  Start backend? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            start_backend
        fi
    fi

    clear
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}         Flutter Frontend${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}Backend:${NC}  http://localhost:8000"
    echo -e "  ${GREEN}Frontend:${NC} Will open in Chrome"
    echo ""
    echo -e "  ${YELLOW}Press 'q' then Enter in Flutter console to quit${NC}"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo ""

    cd "$PROJECT_ROOT/frontend"
    flutter run -d chrome 2>&1

    echo ""
    print_ok "Frontend stopped"
    wait_for_key
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

# Check for updates on startup
check_for_updates

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
    if is_backend_running; then
        echo -e "  ${GREEN}●${NC} Backend running (PID: $(cat "$BACKEND_PID_FILE"))"
    else
        echo -e "  ${YELLOW}●${NC} Backend stopped"
    fi

    show_menu
    read -p "  Select: " choice

    # Handle dynamic menu based on backend state
    if is_backend_running; then
        case $choice in
            1) stop_backend; print_ok "Backend stopped"; wait_for_key ;;
            2) view_logs ;;
            3) stop_backend; start_backend ;;
            f|F) start_frontend ;;
            d|D) deploy_docker; wait_for_key ;;
            s|S) run_setup; wait_for_key ;;
            c|C) edit_config ;;
            q|Q) echo ""; exit 0 ;;
            *) ;;
        esac
    else
        case $choice in
            1) start_backend ;;
            f|F) start_frontend ;;
            d|D) deploy_docker; wait_for_key ;;
            s|S) run_setup; wait_for_key ;;
            c|C) edit_config ;;
            q|Q) echo ""; exit 0 ;;
            *) ;;
        esac
    fi
done
