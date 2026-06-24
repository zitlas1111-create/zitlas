"""
ZITLAS — Gemini 2.5 Flash Service
Fallback AI provider used when Groq hits rate limits or quota.
Mirrors the return format of groq_service.chat() exactly.
"""

import asyncio
import os
import traceback as _tb
from typing import Any

GEMINI_MODEL = "gemini-2.5-flash"


def _get_client():
    from google import genai  # lazy import — only needed when Groq fails
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "GEMINI_API_KEY is not set. Add it to backend/.env."
        )
    return genai.Client(api_key=api_key)


def _convert_messages(messages: list[dict]) -> tuple[str | None, list[dict]]:
    """
    Convert OpenAI-format messages → Gemini format.
    Returns (system_instruction | None, contents_list).
    """
    system_instruction: str | None = None
    contents: list[dict] = []

    for msg in messages:
        role    = msg.get("role", "user")
        content = msg.get("content", "")

        if role == "system":
            # Gemini takes system instructions separately
            system_instruction = content
        elif role == "user":
            contents.append({"role": "user",  "parts": [{"text": content}]})
        elif role in ("assistant", "model"):
            contents.append({"role": "model", "parts": [{"text": content}]})

    # Gemini requires contents to start with role=user
    if not contents:
        contents = [{"role": "user", "parts": [{"text": "Hello"}]}]
    elif contents[0]["role"] != "user":
        contents.insert(0, {"role": "user", "parts": [{"text": "(context)"}]})

    return system_instruction, contents


def _extract_text(response) -> str:
    """
    Safely extract text from a Gemini response.
    In google-genai 2.x, response.text raises ValueError when the response
    has no candidates or was blocked by safety filters.
    """
    # Try the convenience property first
    try:
        text = response.text
        if text is not None:
            return text
    except (ValueError, AttributeError) as e:
        print(f"[Gemini] response.text raised {type(e).__name__}: {e}")

    # Fallback: walk candidates → parts manually
    try:
        candidates = response.candidates or []
        if candidates:
            parts = candidates[0].content.parts or []
            if parts:
                return parts[0].text or ""
        print(f"[Gemini] No candidates in response. Finish reasons: "
              f"{[str(c.finish_reason) for c in (response.candidates or [])]}")
    except Exception as e:
        print(f"[Gemini] Failed to extract text from candidates: {e}")

    return ""


async def generate(
    messages:    list[dict],
    max_tokens:  int   = 1024,
    temperature: float = 0.7,
    json_mode:   bool  = False,  # kept for API compatibility; JSON mode is always on
) -> dict[str, Any]:
    """
    Call Gemini 2.5 Flash and return the same dict structure as groq_service.chat().
    Always uses response_mime_type="application/json" — Gemini returns valid JSON only.
    Runs the synchronous Gemini SDK call in a thread-pool executor so it
    doesn't block the FastAPI event loop.
    """
    from google.genai import types  # lazy import

    system_instruction, contents = _convert_messages(messages)

    print(f"[Gemini] Sending request — model={GEMINI_MODEL} "
          f"max_tokens={max_tokens} temperature={temperature} "
          f"has_system={'yes' if system_instruction else 'no'} "
          f"contents_turns={len(contents)}")

    client = _get_client()

    # Build config — pass system_instruction in the constructor so Pydantic
    # validates it immediately (setting it after construction can silently fail
    # in google-genai 2.x when the internal validator runs at send time).
    config_kwargs: dict = {
        "temperature":        temperature,
        "max_output_tokens":  max_tokens,
        "response_mime_type": "application/json",
    }
    if system_instruction:
        config_kwargs["system_instruction"] = system_instruction

    config = types.GenerateContentConfig(**config_kwargs)

    def _sync_call():
        try:
            resp = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=contents,
                config=config,
            )
            return resp
        except Exception as e:
            print(f"\n[Gemini] _sync_call EXCEPTION: {type(e).__name__}: {e}")
            print(_tb.format_exc())
            raise

    try:
        loop     = asyncio.get_event_loop()
        response = await loop.run_in_executor(None, _sync_call)
    except Exception as e:
        print(f"\n[Gemini] generate() caught exception: {type(e).__name__}: {e}")
        print(_tb.format_exc())
        raise

    text = _extract_text(response)

    # Print first 400 chars of the raw response so we can verify the JSON structure
    preview = (text[:400] + "…") if len(text) > 400 else text
    print(f"[Gemini] Raw response preview ({len(text)} chars):\n{preview}")

    # Extract token usage if available
    prompt_tokens     = 0
    completion_tokens = 0
    try:
        meta              = response.usage_metadata
        prompt_tokens     = meta.prompt_token_count     or 0
        completion_tokens = meta.candidates_token_count or 0
    except Exception:
        pass

    return {
        "reply":             text,
        "model":             GEMINI_MODEL,
        "tokens_used":       prompt_tokens + completion_tokens,
        "prompt_tokens":     prompt_tokens,
        "completion_tokens": completion_tokens,
    }
