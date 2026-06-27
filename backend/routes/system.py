"""
ZITLAS — System Routes

GET /api/system/kb-status   — Knowledge base lazy-loading cache status
"""

from typing import Any

from fastapi import APIRouter

from services.kb_manager import kb_manager

router = APIRouter()


@router.get("/kb-status")
async def kb_status() -> dict[str, Any]:
    """
    Knowledge base cache status.

    Shows which per-goal FAISS indexes are currently held in RAM,
    how many chunks each contains, and the LRU cache limit.

    Response shape:
        {
            "loaded_kbs":      ["weight_loss", "general_fitness"],
            "cache_size":      2,
            "memory_optimized": true
        }

    loaded_kbs is empty at startup; it grows as users trigger goal-specific
    requests.  Old entries are evicted (LRU) when cache_size would exceed
    the configured maximum.
    """
    stats = kb_manager.get_cache_stats()
    return {
        "loaded_kbs":      stats["loaded_kbs"],
        "cache_size":      stats["cache_size"],
        "memory_optimized": True,
    }
