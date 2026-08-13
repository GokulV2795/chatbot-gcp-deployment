from typing import Literal

from pydantic import BaseModel, Field

Role = Literal["system", "user", "assistant"]


class ChatMessage(BaseModel):
    role: Role
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(..., min_length=1)
    model: str | None = None
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)
    # OpenRouter checks affordability against this ceiling up front, not actual usage —
    # leaving it unset lets it default to the model's max (e.g. 64000), which fails
    # accounts without a large credit balance even for a one-word reply.
    max_tokens: int = Field(default=1024, ge=1, le=8192)


class HealthResponse(BaseModel):
    status: Literal["ok"]
