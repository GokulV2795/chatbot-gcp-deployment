import json

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.core.security import verify_shared_secret
from app.models.schemas import ChatRequest
from app.services.openrouter import OpenRouterError, stream_chat_completion

router = APIRouter(tags=["chat"], dependencies=[Depends(verify_shared_secret)])


@router.post("/chat")
async def chat(request: ChatRequest) -> StreamingResponse:
    async def event_stream():
        try:
            async for token in stream_chat_completion(
                messages=request.messages,
                model=request.model,
                temperature=request.temperature,
                max_tokens=request.max_tokens,
            ):
                # JSON-encode so multi-line tokens (e.g. code blocks) stay a single SSE data field.
                yield f"data: {json.dumps(token)}\n\n"
        except OpenRouterError as exc:
            yield f"event: error\ndata: {json.dumps(exc.detail)}\n\n"
        finally:
            yield "event: done\ndata: [DONE]\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
