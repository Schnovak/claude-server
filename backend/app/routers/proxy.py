"""
Proxy router for forwarding requests to localhost ports on the server.
This allows the frontend to access dev servers started by Claude.
"""
import httpx
from fastapi import APIRouter, Depends, Request, Response, HTTPException, Query
from fastapi.responses import StreamingResponse
from typing import Optional

from ..services.auth import get_current_user, get_current_user_optional, AuthService
from ..models import User

router = APIRouter(prefix="/proxy", tags=["proxy"])

# Allowed port range for proxying (security measure)
ALLOWED_PORTS = range(3000, 10000)

# Timeout for proxy requests
PROXY_TIMEOUT = 30.0


@router.api_route(
    "/{port:int}/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]
)
async def proxy_request(
    port: int,
    path: str,
    request: Request,
    token: Optional[str] = Query(None, description="Auth token for iframe/browser access"),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """
    Proxy requests to localhost:{port}/{path} on the server.

    This allows the frontend to access dev servers started by Claude,
    since 'localhost' in the browser refers to the user's machine, not the server.
    """
    # Handle token-based auth for iframe/browser access
    user_id = None
    if current_user:
        user_id = current_user.id
    elif token:
        payload = AuthService.decode_token(token)
        if payload:
            user_id = payload.get("sub")

    if not user_id:
        raise HTTPException(
            status_code=401,
            detail="Authentication required"
        )

    # Security: only allow certain ports
    if port not in ALLOWED_PORTS:
        raise HTTPException(
            status_code=403,
            detail=f"Port {port} not allowed. Allowed range: {ALLOWED_PORTS.start}-{ALLOWED_PORTS.stop-1}"
        )

    # Build target URL
    target_url = f"http://localhost:{port}/{path}"
    if request.query_params:
        target_url += f"?{request.query_params}"

    # Get request body if present
    body = await request.body() if request.method in ["POST", "PUT", "PATCH"] else None

    # Forward headers (excluding hop-by-hop headers)
    headers = {}
    skip_headers = {"host", "connection", "keep-alive", "transfer-encoding", "upgrade"}
    for key, value in request.headers.items():
        if key.lower() not in skip_headers:
            headers[key] = value

    try:
        async with httpx.AsyncClient(timeout=PROXY_TIMEOUT) as client:
            response = await client.request(
                method=request.method,
                url=target_url,
                headers=headers,
                content=body,
                follow_redirects=True,
            )

            # Build response headers (excluding hop-by-hop headers)
            response_headers = {}
            for key, value in response.headers.items():
                if key.lower() not in skip_headers:
                    response_headers[key] = value

            return Response(
                content=response.content,
                status_code=response.status_code,
                headers=response_headers,
                media_type=response.headers.get("content-type"),
            )

    except httpx.ConnectError:
        raise HTTPException(
            status_code=502,
            detail=f"Cannot connect to localhost:{port}. Is the server running?"
        )
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=504,
            detail=f"Request to localhost:{port} timed out"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Proxy error: {str(e)}"
        )
