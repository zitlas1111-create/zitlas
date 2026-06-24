"""
ZITLAS — OpenRouter Service
3rd-fallback AI provider (Groq → Gemini → OpenRouter).
Uses the OpenAI-compatible REST API via the openai SDK.

Model priority (fastest / cheapest first):
  1. deepseek/deepseek-chat
  2. meta-llama/llama-3.3-70b-instruct
  3. qwen/qwen-3-32b
"""

import os
import traceback as _tb
from typing import Any

_BASE_URL = "https://openrouter.ai/api/v1"

_MODELS = [
    "deepseek/deepseek-chat",
    "meta-llama/llama-3.3-70b-instruct",
    "qwen/qwen-3-32b",
]


def _get_client():
    from openai import AsyncOpenAI
    api_key = os.getenv("OPENROUTER_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "OPENROUTER_API_KEY is not set. Add it to backend/.env."
        )
    return AsyncOpenAI(base_url=_BASE_URL, api_key=api_key)


async def generate(
    messages:    list[dict],
    max_tokens:  int   = 1024,
    temperature: float = 0.7,
    json_mode:   bool  = False,
) -> dict[str, Any]:
    """
    Call OpenRouter and return the same dict structure as groq_service.chat().
    Tries each model in _MODELS order until one succeeds.
    json_mode=True passes response_format json_object to the model.
    """
    client   = _get_client()
    last_err = None
    extra    = {"response_format": {"type": "json_object"}} if json_mode else {}

    for model in _MODELS:
        try:
            print(f"[OpenRouter] Trying {model} …")
            completion = await client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                **extra,
            )
            text   = completion.choices[0].message.content or ""
            usage  = completion.usage
            tokens = usage.total_tokens if usage else 0
            print(f"[OpenRouter] OK {model} (tokens={tokens})")
            preview = (text[:300] + "…") if len(text) > 300 else text
            print(f"[OpenRouter] Preview: {preview!r}")
            return {
                "reply":             text,
                "model":             f"openrouter/{model}",
                "tokens_used":       tokens,
                "prompt_tokens":     usage.prompt_tokens     if usage else 0,
                "completion_tokens": usage.completion_tokens if usage else 0,
            }
        except Exception as _e:
            last_err = _e
            print(f"[OpenRouter] {model} failed — {type(_e).__name__}: {_e}")
            print(_tb.format_exc())

    raise RuntimeError(
        f"All OpenRouter models failed. "
        f"Last error: {type(last_err).__name__}: {last_err}"
    ) from last_err
