import type { ChatMessage } from "./types";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/api";
const SHARED_SECRET = process.env.NEXT_PUBLIC_APP_SHARED_SECRET ?? "";

interface StreamChatOptions {
  messages: ChatMessage[];
  signal?: AbortSignal;
  onToken: (token: string) => void;
}

/**
 * Parses the backend's SSE stream, which frames each event as:
 *   data: "<json-encoded token>"\n\n
 *   event: error\ndata: "<message>"\n\n
 *   event: done\ndata: [DONE]\n\n
 */
export async function streamChat({ messages, signal, onToken }: StreamChatOptions): Promise<void> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (SHARED_SECRET) {
    headers.Authorization = `Bearer ${SHARED_SECRET}`;
  }

  const response = await fetch(`${API_BASE_URL}/chat`, {
    method: "POST",
    headers,
    body: JSON.stringify({ messages }),
    signal,
  });

  if (!response.ok || !response.body) {
    const text = await response.text().catch(() => response.statusText);
    throw new Error(`Chat request failed (${response.status}): ${text}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const events = buffer.split("\n\n");
    buffer = events.pop() ?? "";

    for (const rawEvent of events) {
      const lines = rawEvent.split("\n");
      let eventType = "message";
      let data = "";

      for (const line of lines) {
        if (line.startsWith("event:")) eventType = line.slice("event:".length).trim();
        else if (line.startsWith("data:")) data = line.slice("data:".length).trim();
      }

      if (eventType === "error") {
        throw new Error(JSON.parse(data));
      }
      if (eventType === "done") {
        return;
      }
      if (data) {
        onToken(JSON.parse(data));
      }
    }
  }
}
