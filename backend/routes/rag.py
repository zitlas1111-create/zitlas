"""
ZITLAS — RAG Routes

POST /api/rag/query   — RAG-powered AI nutrition query with full source attribution
GET  /api/rag/status  — RAG service health and index statistics
"""

import asyncio
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from services import groq_service, rag_service

router = APIRouter()


# ══════════════════════════════════════════════════════════════════════════════
# REQUEST / RESPONSE MODELS
# ══════════════════════════════════════════════════════════════════════════════

class UserData(BaseModel):
    """Optional user profile for response personalization."""
    current_weight:     str | None = None   # e.g. "95 kg"
    goal_weight:        str | None = None   # e.g. "75 kg"
    height:             str | None = None   # e.g. "175 cm"
    age:                int | None = None
    gender:             str | None = None   # male / female / other
    activity_level:     str | None = None   # sedentary / light / moderate / active
    diet_preference:    str | None = None   # vegetarian / non-vegetarian / vegan
    workout_preference: str | None = None   # home / gym / walking / none
    budget:             str | None = None   # e.g. "₹150/day"
    occupation:         str | None = None   # hostel student / college student / office worker
    living_situation:   str | None = None   # hostel / home / pg / office

    class Config:
        extra = "allow"    # accept any additional keys the caller passes


class RAGQueryRequest(BaseModel):
    question: str  = Field(..., min_length=1, max_length=2000, description="User's question")
    user_data: UserData | None = Field(default=None, description="User profile for personalization")
    top_k: int     = Field(default=5, ge=1, le=10, description="Max chunks to retrieve (1-10)")
    goal: str | None = Field(
        default=None,
        description="Fitness goal filter: weight_loss | muscle_gain | general_fitness | transformation. "
                    "Restricts search to the matching KB (recommended on free-tier deployments)."
    )


class RAGSource(BaseModel):
    source_pdf:  str
    page_number: int
    chunk_id:    str
    score:       float


class RAGQueryResponse(BaseModel):
    answer:           str
    sources:          list[RAGSource]
    model:            str
    tokens_used:      int
    chunks_retrieved: int


# ══════════════════════════════════════════════════════════════════════════════
# POST /api/rag/query
# ══════════════════════════════════════════════════════════════════════════════

@router.post("/query", response_model=RAGQueryResponse)
async def rag_query(body: RAGQueryRequest) -> RAGQueryResponse:
    """
    RAG-powered AI nutrition endpoint with full source attribution.

    Pipeline:
        User Question
            ↓
        Semantic Search (FAISS)
            ↓
        Top-K Relevant Chunks
            ↓
        build_rag_prompt() — context + user profile + question
            ↓
        LLM (Groq → Gemini → OpenRouter)
            ↓
        Answer + Source References

    Source references include PDF name, page number, and relevance score.
    """
    print("\n" + "=" * 60)
    print("RAG QUERY")
    print(f"  question : {body.question[:120]!r}")
    print(f"  top_k    : {body.top_k}")
    print(f"  user_data: {'yes' if body.user_data else 'no'}")
    print("=" * 60)

    # 1. Semantic search — run in thread pool so the event loop is never blocked.
    #    Pass goal so search_knowledge() uses a single KB instead of all four,
    #    which avoids OOM on free-tier deployments (512 MB limit).
    print(f"[RAG QUERY] goal={body.goal!r}  question={body.question[:80]!r}")
    chunks = await asyncio.to_thread(
        rag_service.search_knowledge, body.question, body.top_k, body.goal
    )
    print(f"[RAG QUERY] Retrieved {len(chunks)} chunk(s)")

    # 2. Build structured prompt
    user_data_dict = body.user_data.model_dump(exclude_none=True) if body.user_data else None
    prompt = rag_service.build_rag_prompt(
        question=body.question,
        retrieved_chunks=chunks,
        user_data=user_data_dict,
    )

    # 3. Call LLM
    try:
        result = await groq_service.chat(
            user_message=prompt["user"],
            system_override=prompt["system"],
            max_tokens=1024,
        )
    except EnvironmentError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM provider error: {str(e)}")

    # 4. Build source list
    sources = [
        RAGSource(
            source_pdf=c["source_pdf"],
            page_number=c["page_number"],
            chunk_id=c["chunk_id"],
            score=round(c["score"], 4),
        )
        for c in chunks
    ]

    print(
        f"[RAG QUERY] Done — model={result['model']}  "
        f"tokens={result['tokens_used']}  sources={len(sources)}"
    )

    return RAGQueryResponse(
        answer=result["reply"],
        sources=sources,
        model=result["model"],
        tokens_used=result["tokens_used"],
        chunks_retrieved=len(chunks),
    )


# ══════════════════════════════════════════════════════════════════════════════
# GET /api/rag/status
# ══════════════════════════════════════════════════════════════════════════════

@router.get("/status")
async def rag_status() -> dict[str, Any]:
    """
    RAG service health check.

    With lazy loading active, chunks_indexed reflects only currently-loaded KBs.
    Use GET /api/system/kb-status for full cache details.
    """
    from services.kb_manager import kb_manager, MAX_LOADED_KBS

    stats = kb_manager.get_cache_stats()

    # Count chunks per source PDF across all currently-loaded KBs.
    source_counts: dict[str, int] = {}
    total_chunks = 0
    with kb_manager._global_lock:
        for kb in kb_manager._cache.values():
            for c in kb.chunks:
                source_counts[c["source_pdf"]] = source_counts.get(c["source_pdf"], 0) + 1
            total_chunks += len(kb.chunks)

    return {
        "ready":          rag_service._is_ready,
        "lazy_loading":   True,
        "chunks_indexed": total_chunks,       # only loaded KBs; grows on first requests
        "chunks_per_pdf": source_counts,
        "loaded_kbs":     stats["loaded_kbs"],
        "cache_size":     stats["cache_size"],
        "max_loaded_kbs": MAX_LOADED_KBS,
        "vector_store":   str(rag_service.VECTOR_STORE),
        "chunk_size":     rag_service.CHUNK_SIZE,
        "chunk_overlap":  rag_service.CHUNK_OVERLAP,
        "min_score":      rag_service.MIN_SCORE,
        "default_top_k":  rag_service.DEFAULT_TOP_K,
    }
