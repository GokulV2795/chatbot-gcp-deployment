"use client";

import { useRef, type KeyboardEvent } from "react";

interface ChatInputProps {
  onSend: (text: string) => void;
  disabled: boolean;
}

export default function ChatInput({ onSend, disabled }: ChatInputProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const submit = () => {
    const value = textareaRef.current?.value.trim();
    if (!value || disabled) return;
    onSend(value);
    if (textareaRef.current) textareaRef.current.value = "";
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      submit();
    }
  };

  return (
    <div className="flex items-end gap-2 border-t border-neutral-200 p-4 dark:border-neutral-800">
      <textarea
        ref={textareaRef}
        rows={1}
        placeholder="Message the chatbot..."
        onKeyDown={handleKeyDown}
        disabled={disabled}
        className="max-h-40 flex-1 resize-none rounded-xl border border-neutral-300 bg-white px-3 py-2 text-sm outline-none focus:border-accent disabled:opacity-50 dark:border-neutral-700 dark:bg-neutral-800"
      />
      <button
        onClick={submit}
        disabled={disabled}
        className="rounded-xl bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover disabled:opacity-50"
      >
        Send
      </button>
    </div>
  );
}
