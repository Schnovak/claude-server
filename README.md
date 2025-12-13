# Claude Server

A self-hosted platform for running Claude Code with complete user isolation and security.

## Features

- **Multi-user support** - Each user gets isolated workspace
- **Sandboxed execution** - Claude CLI runs in firejail/Docker for security
- **Project management** - Create, manage, and organize coding projects
- **Claude Chat** - Chat with Claude about your code
- **Job runner** - Run builds, tests, and custom commands
- **Git integration** - Built-in git operations
- **API key per user** - Each user configures their own Anthropic API key

## Quick Start

```bash
git clone https://github.com/Schnovak/claude-server.git
cd claude-server
./server.sh
```

That's it. The script handles everything:
- First run: Guides through setup
- Every run: Shows menu to start services

## Requirements

**Required:**
- Python 3.10+
- Node.js 18+ (for Claude CLI)

**Optional:**
- Docker (for production deployment)
- Flutter (for frontend development)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Frontend                           │
│                 (Flutter Web App)                       │
└─────────────────────┬───────────────────────────────────┘
                      │ HTTP/REST
┌─────────────────────▼───────────────────────────────────┐
│                      Backend                            │
│                  (FastAPI + Python)                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ Auth        │  │ Projects    │  │ Claude      │     │
│  │ Service     │  │ Service     │  │ Service     │     │
│  └─────────────┘  └─────────────┘  └──────┬──────┘     │
└───────────────────────────────────────────┼─────────────┘
                                            │ Sandboxed
┌───────────────────────────────────────────▼─────────────┐
│                    Claude CLI                           │
│               (firejail isolation)                      │
└─────────────────────────────────────────────────────────┘
```

## Security

### User Isolation
- Each user has separate workspace: `users/{user_id}/workspace/`
- Database queries always filter by owner
- Path traversal attacks blocked

### Claude CLI Sandboxing
- **Development**: Optional (set `REQUIRE_SANDBOX=false`)
- **Production**: Enforced via firejail or Docker
- Claude can only access user's workspace, nothing else

### API Keys
- Stored per-user with `600` permissions
- Never shared between users
- Each user brings their own Anthropic API key

## Usage

### Starting the Server

```bash
./server.sh
```

Menu options:
1. **Start Backend Server** - API on http://localhost:8000
2. **Start Backend + Frontend** - Full dev environment
3. **Deploy with Docker** - Production deployment

### First Time Setup

1. Run `./server.sh`
2. Script auto-detects first run and guides through setup
3. Creates config, database, and installs dependencies
4. Select option 1 to start backend

### Adding Your API Key

1. Start the server
2. Open http://localhost:8000 (or frontend URL)
3. Register/Login
4. Go to Settings → Claude
5. Enter your Anthropic API key

## Configuration

Edit `config/.env`:

```env
# Server
HOST=0.0.0.0
PORT=8000
DEBUG=false

# Security (change in production!)
SECRET_KEY=your-secret-key

# Claude
CLAUDE_BINARY=claude
DEFAULT_MODEL=claude-sonnet-4-20250514

# Sandbox (true for production)
REQUIRE_SANDBOX=false
```

## Production Deployment

### With Docker (Recommended)

```bash
./server.sh
# Select option 3: Deploy with Docker
# Select option 1: Start services
```

Services:
- Frontend: http://localhost (nginx)
- Backend: http://localhost:8000 (API)

### Manual

1. Install firejail: `sudo apt install firejail`
2. Set `REQUIRE_SANDBOX=true` in config
3. Run behind reverse proxy (nginx/caddy)
4. Use proper SSL certificates

## API Documentation

Once running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Project Structure

```
claude-server/
├── server.sh           # Main entry point
├── docker-compose.yml  # Production deployment
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── models/
│   │   ├── routers/
│   │   ├── services/
│   │   └── schemas/
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   ├── providers/
│   │   └── models/
│   ├── pubspec.yaml
│   └── Dockerfile
├── config/
│   └── .env
├── data/               # Database & logs
└── users/              # User workspaces
```

## License

MIT
