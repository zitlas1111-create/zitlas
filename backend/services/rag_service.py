"""
ZITLAS — RAG Service (Production)
Retrieval-Augmented Generation pipeline for the fitness knowledge base.

Knowledge base:
  backend/weight_loss/wl1.pdf        — Strength, conditioning, exercise, mobility, recovery
  backend/weight_loss/wl2.pdf        — Weight loss, nutrition, meal plans, recipes, FAQs
  backend/Muscle_Gain/mg1.pdf        — Muscle gain, hypertrophy, progressive overload
  backend/Muscle_Gain/mg2.pdf        — Muscle gain nutrition, supplementation, programming
  backend/general fitness/gf1.pdf    — General fitness, exercise DB, 207 exercises, 20 modules
  backend/general fitness/gf1b.pdf   — General fitness extension, modules 21-25, coaching rules
  backend/general fitness/gf2.pdf    — Nutrition Knowledge Base: macros, meal plans, Indian diets
  backend/transformation/tf1.pdf     — Body transformation: six pack, lean physique, recomposition

Pipeline:
  load_documents()
    └─ extract_pdf_text()        per PDF, page-by-page
  chunk_documents()              overlapping character windows + page attribution
  create_embeddings()            all-MiniLM-L6-v2 (sentence-transformers)
  build_faiss_index()            IndexFlatIP (cosine similarity), persisted to disk
  ──── Server is now ready ────
  search_knowledge(query)        FAISS top-k retrieval
  retrieve_context(query)        format chunks for LLM injection
  build_rag_prompt(...)          structured system+user prompt with context + profile
"""

import hashlib
import json
import logging
import pickle
import time
from pathlib import Path
from typing import Any

import numpy as np

# kb_manager is imported at module level because search_knowledge() delegates to it.
# kb_manager.py does NOT import rag_service at module level (only lazily inside
# _load_kb), so there is no circular import.
from services.kb_manager import kb_manager, get_embedding_model as _kb_get_embedding_model

# ── Logger ─────────────────────────────────────────────────────────────────────
logger = logging.getLogger("zitlas.rag")
if not logger.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(
        logging.Formatter(
            "%(asctime)s  [RAG]  %(levelname)-8s  %(message)s",
            datefmt="%H:%M:%S",
        )
    )
    logger.addHandler(_h)
    logger.setLevel(logging.INFO)
    logger.propagate = False

# ── Paths ─────────────────────────────────────────────────────────────────────
_BACKEND_DIR = Path(__file__).parent.parent

PDF_DIR_WEIGHT_LOSS     = _BACKEND_DIR / "weight_loss"
PDF_DIR_MUSCLE_GAIN     = _BACKEND_DIR / "Muscle_Gain"
PDF_DIR_GENERAL_FITNESS = _BACKEND_DIR / "general fitness"
PDF_DIR_TRANSFORMATION  = _BACKEND_DIR / "transformation"
VECTOR_STORE            = _BACKEND_DIR / "vector_store"

PDF_DIR   = PDF_DIR_WEIGHT_LOSS  # legacy alias

_INDEX_PATH  = VECTOR_STORE / "faiss.index"
_META_PATH   = VECTOR_STORE / "chunks_metadata.pkl"
_HASH_PATH   = VECTOR_STORE / "pdf_hashes.json"

# All PDFs indexed together; goal-based filtering is applied at retrieval time
PDF_SOURCES = [
    (PDF_DIR_WEIGHT_LOSS,     "wl1.pdf"),
    (PDF_DIR_WEIGHT_LOSS,     "wl2.pdf"),
    (PDF_DIR_MUSCLE_GAIN,     "mg1.pdf"),
    (PDF_DIR_MUSCLE_GAIN,     "mg2.pdf"),
    (PDF_DIR_GENERAL_FITNESS, "gf1.pdf"),
    (PDF_DIR_GENERAL_FITNESS, "gf1b.pdf"),
    (PDF_DIR_GENERAL_FITNESS, "gf2.pdf"),   # Nutrition Knowledge Base
    (PDF_DIR_TRANSFORMATION,  "tf1.pdf"),   # Transformation: six pack, lean physique, recomposition
]
PDF_FILES = ["wl1.pdf", "wl2.pdf"]  # legacy alias

# Per-PDF source alias and content category — attached to every chunk at index time.
# source  : short identifier used in logs, prompts, and API responses
# category: semantic grouping used by classify_query() for source boosting
_PDF_METADATA: dict[str, dict[str, str]] = {
    "gf1.pdf":  {"source": "gf1",  "category": "training"},
    "gf1b.pdf": {"source": "gf1b", "category": "coaching_rules"},
    "gf2.pdf":  {"source": "gf2",  "category": "nutrition"},
    "mg1.pdf":  {"source": "mg1",  "category": "training"},
    "mg2.pdf":  {"source": "mg2",  "category": "nutrition"},
    "wl1.pdf":  {"source": "wl1",  "category": "training"},
    "wl2.pdf":  {"source": "wl2",  "category": "nutrition"},
    "tf1.pdf":  {"source": "tf1",  "category": "transformation"},
}

# Score boosts applied on top of cosine similarity per query category.
# Values tuned so a preferred-source chunk wins a tie but a high-scoring
# off-category chunk still surfaces (no hard filter).
_CATEGORY_BOOST: dict[str, dict[str, float]] = {
    "training":        {"gf1.pdf": 0.12, "mg1.pdf": 0.08, "wl1.pdf": 0.06},
    "nutrition":       {"gf2.pdf": 0.12, "wl2.pdf": 0.08, "mg2.pdf": 0.06},
    "coaching_rules":  {"gf1b.pdf": 0.15},
    # Mixed queries (e.g. "I keep skipping workouts") have coaching overlap —
    # give gf1b a nudge so behavioral content surfaces alongside training content.
    "mixed":           {"gf1b.pdf": 0.10},
    # Transformation queries (abs, lean physique, recomp) always prefer tf1.pdf
    "transformation":  {"tf1.pdf": 0.18},
}

# ── Chunking config ────────────────────────────────────────────────────────────
CHUNK_SIZE    = 900    # characters per chunk  ≈ 225 LLM tokens
CHUNK_OVERLAP = 175    # character overlap between consecutive chunks
MIN_CHUNK_LEN = 80     # fragments shorter than this are discarded

# ── Retrieval config ───────────────────────────────────────────────────────────
DEFAULT_TOP_K = 5
MIN_SCORE     = 0.20   # cosine similarity floor — below this is noise

# ── Runtime state ─────────────────────────────────────────────────────────────
# _faiss_index and _chunks are kept as stubs for backward compatibility but are
# no longer populated.  All FAISS state lives inside kb_manager._cache.
# _is_ready is set to True immediately in initialize() — the system is ready
# to serve requests as soon as the server starts; KBs load lazily on demand.
_faiss_index        = None
_chunks: list[dict] = []
_is_ready           = False


# ════════════════════════════════════════════════════════════════════════════════
# RAG SYSTEM PROMPT
# ════════════════════════════════════════════════════════════════════════════════

TRANSFORMATION_SYSTEM_PROMPT = """You are the ZITLAS Transformation Coach.

Your job is to help users achieve:
- Six Pack Abs
- Lean Physique
- Body Recomposition
- Aesthetic Physique
- Complete Body Transformation Goals

Core rules:
- Answer using ONLY the retrieved transformation research context (tf1.pdf).
- Never pull information from weight loss, muscle gain, or general fitness knowledge bases unless explicitly configured.
- Provide structured answers with:
  1. Explanation
  2. Action Steps
  3. Common Mistakes
  4. Progress Expectations
  5. Practical Advice
- Personalize every response using the user's profile data.
- Use clear, motivating, practical language.
- Reference Indian foods and lifestyle where relevant.
- Be results-focused and specific — no vague advice.

Platform: ZITLAS — AI-powered transformation platform for Indian users aged 16-40."""

RAG_SYSTEM_PROMPT = """You are Zino, an AI fitness and weight-loss nutrition assistant for ZITLAS.

Core rules:
- Answer questions using ONLY the retrieved research context when possible.
- If the context does not contain enough information, say: \
"I don't have specific research on this, but based on general principles..."
- Never fabricate statistics, studies, or numbers not present in the context.
- Personalize every response using the user's profile data \
(weight, height, goal, occupation, budget, etc.).
- Use clear, friendly, everyday language — no medical jargon.
- Reference Indian foods and the Indian lifestyle where relevant.
- Be encouraging and positive — never judgmental about weight or food choices.
- Focus on sustainable fat loss: mild calorie deficit + high protein + movement.

Platform: ZITLAS — AI-powered weight-loss and nutrition platform for Indian users aged 16-40."""


# ════════════════════════════════════════════════════════════════════════════════
# PRIVATE HELPERS
# ════════════════════════════════════════════════════════════════════════════════

def _file_md5(path: Path) -> str:
    """Return MD5 hex-digest of a file for change detection."""
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def _get_embed_model():
    """
    Return the shared embedding model.
    The singleton is managed by kb_manager so only one instance ever exists,
    whether the caller is search_knowledge() or kb_manager._load_kb().
    """
    return _kb_get_embedding_model()


def _current_hashes() -> dict[str, str]:
    return {
        fname: _file_md5(pdf_dir / fname)
        for pdf_dir, fname in PDF_SOURCES
        if (pdf_dir / fname).exists()
    }


def _saved_hashes() -> dict[str, str]:
    if not _HASH_PATH.exists():
        return {}
    with open(_HASH_PATH) as f:
        return json.load(f)


def _write_hashes(hashes: dict[str, str]) -> None:
    VECTOR_STORE.mkdir(parents=True, exist_ok=True)
    with open(_HASH_PATH, "w") as f:
        json.dump(hashes, f, indent=2)


def _pdfs_changed() -> bool:
    return _current_hashes() != _saved_hashes()


# ════════════════════════════════════════════════════════════════════════════════
# QUERY CLASSIFICATION
# ════════════════════════════════════════════════════════════════════════════════

_TRAINING_KW = {
    "workout", "exercise", "training", "fitness", "sets", "reps", "gym", "lift",
    "squat", "deadlift", "bench", "press", "pull", "push", "cardio", "strength",
    "muscle", "build", "bulk", "program", "routine", "split", "upper body",
    "lower body", "full body", "compound", "isolation", "warm up", "cool down",
    "stretch", "flexibility", "mobility", "hypertrophy", "overload", "progressive",
    "beginner workout", "home workout",
}

_NUTRITION_KW = {
    "diet", "food", "meal", "eat", "nutrition", "protein", "carb", "fat",
    "calorie", "breakfast", "lunch", "dinner", "snack", "recipe", "ingredient",
    "vegetarian", "vegan", "supplement", "vitamin", "mineral", "hydration",
    "water", "drink", "macro", "micro", "nutrient", "high protein",
    "weight loss diet", "bulk diet", "indian food", "indian diet",
}

_COACHING_KW = {
    # Core behavioral / motivational terms
    "motivation", "motivated", "unmotivated", "demotivated",
    "consistency", "consistent", "inconsistent",
    "habit", "habits", "habit building", "habit formation", "building habits",
    "adherence", "discipline", "accountability",
    "mindset", "mental", "psychology", "coaching psychology",
    # Dropout / struggle signals
    "skip", "skipping", "skipped", "missing", "missing workout", "missed workout",
    "quit", "quitting", "give up", "dropout", "burnout", "burnt out",
    "not progressing", "plateau", "stuck", "progress",
    # Behavioral patterns
    "staying consistent", "stay consistent", "routine building", "routine formation",
    "recovery behavior", "coach", "advice",
    # Query phrasings
    "should i", "how should", "when should", "how to stay",
    "low energy", "tired", "low motivation",
    "improve", "form check", "technique", "recovering",
}


def _kw_score(keywords: set[str], query: str) -> int:
    """
    Count how many keywords appear in query.
    Single-word keywords use word-boundary matching to avoid false substring
    hits (e.g. 'eat' inside 'create').  Multi-word phrases use plain substring.
    """
    import re
    total = 0
    for kw in keywords:
        if " " in kw:
            total += 1 if kw in query else 0
        else:
            total += 1 if re.search(r"\b" + re.escape(kw) + r"\b", query) else 0
    return total


def classify_query(query: str) -> str:
    """
    Classify a user query into one of four content categories.

    Returns one of: "training" | "nutrition" | "coaching_rules" | "mixed"

    Used by search_knowledge() to apply source boosting when no explicit
    goal filter is provided.
    """
    q = query.lower()

    t = _kw_score(_TRAINING_KW,  q)
    n = _kw_score(_NUTRITION_KW, q)
    c = _kw_score(_COACHING_KW,  q)

    if t == 0 and n == 0 and c == 0:
        return "mixed"

    # Single clear winner
    if t > n and t > c:
        return "training"
    if n > t and n > c:
        return "nutrition"
    if c > t and c > n:
        return "coaching_rules"

    # Tie or multiple strong signals → mixed
    return "mixed"


# ════════════════════════════════════════════════════════════════════════════════
# DOCUMENT INGESTION
# ════════════════════════════════════════════════════════════════════════════════

def extract_pdf_text(pdf_path: Path) -> dict:
    """
    Extract text from a single PDF, page by page.

    Args:
        pdf_path: Absolute path to the PDF file.

    Returns:
        {
            "source_pdf":   "wl1.pdf",
            "total_pages":  int,
            "total_chars":  int,
            "pages": [
                {"page_number": 1, "text": "..."},
                {"page_number": 2, "text": "..."},
                ...           (empty pages are omitted)
            ]
        }
    """
    import fitz  # PyMuPDF

    source_pdf  = pdf_path.name
    doc         = fitz.open(str(pdf_path))
    total_pages = doc.page_count
    pages       = []
    total_chars = 0

    for i in range(total_pages):
        text = doc[i].get_text().strip()
        if text:
            pages.append({"page_number": i + 1, "text": text})
            total_chars += len(text)

    doc.close()
    logger.info(
        f"PDF Loaded: {source_pdf}  |  "
        f"{total_pages} pages total, {len(pages)} non-empty, "
        f"{total_chars:,} chars"
    )
    return {
        "source_pdf":  source_pdf,
        "total_pages": total_pages,
        "total_chars": total_chars,
        "pages":       pages,
    }


def load_documents() -> list[dict]:
    """
    Load and extract text from all configured PDFs.

    Returns:
        List of document dicts, one per PDF (output of extract_pdf_text).
        Missing PDFs are skipped with a warning.
    """
    logger.info(f"Loading {len(PDF_SOURCES)} PDF(s) from multiple directories")
    documents: list[dict] = []

    for pdf_dir, fname in PDF_SOURCES:
        path = pdf_dir / fname
        if not path.exists():
            logger.warning(f"PDF not found — skipping: {path}")
            continue
        doc = extract_pdf_text(path)
        if fname in {"gf1.pdf", "gf1b.pdf", "gf2.pdf"}:
            print(f"[GENERAL_FITNESS]\nIndexed: {fname}")
        if fname == "tf1.pdf":
            print(f"[TRANSFORMATION]\nIndexed: {fname}")
        documents.append(doc)

    total_chars = sum(d["total_chars"] for d in documents)
    logger.info(
        f"Load complete — {len(documents)} PDF(s), {total_chars:,} total chars"
    )
    return documents


# ════════════════════════════════════════════════════════════════════════════════
# CHUNKING
# ════════════════════════════════════════════════════════════════════════════════

def chunk_documents(documents: list[dict]) -> list[dict]:
    """
    Split all documents into overlapping character chunks with page attribution.

    Strategy:
    - Concatenate all pages into one character stream per document,
      recording each page's start/end byte offset.
    - Slide a window of CHUNK_SIZE chars with CHUNK_OVERLAP step.
    - Attribute each chunk to the page whose text contains the chunk midpoint.

    Returns:
        List of {text, source_pdf, page_number, chunk_id}.
    """
    all_chunks: list[dict] = []

    for doc in documents:
        source_pdf = doc["source_pdf"]
        pages      = doc["pages"]

        if not pages:
            logger.warning(f"No usable pages in {source_pdf} — skipping")
            continue

        # Build a single character stream for the document and track page boundaries
        full_text:  str              = ""
        page_spans: list[tuple]      = []   # (page_number, start_char, end_char)

        for page_info in pages:
            start = len(full_text)
            full_text += page_info["text"] + "\n\n"
            page_spans.append((page_info["page_number"], start, len(full_text)))

        def _page_at(char_pos: int) -> int:
            """Return the page number that owns char_pos (O(n) linear scan)."""
            for page_num, start, end in page_spans:
                if start <= char_pos < end:
                    return page_num
            return page_spans[-1][0]

        # Slide the window
        seq = 0
        pos = 0
        while pos < len(full_text):
            end   = min(pos + CHUNK_SIZE, len(full_text))
            piece = full_text[pos:end].strip()

            if len(piece) >= MIN_CHUNK_LEN:
                mid_page = _page_at(pos + (end - pos) // 2)
                _meta = _PDF_METADATA.get(
                    source_pdf,
                    {"source": source_pdf.replace(".pdf", ""), "category": "general"},
                )
                all_chunks.append({
                    "text":        piece,
                    "source_pdf":  source_pdf,
                    "source":      _meta["source"],
                    "category":    _meta["category"],
                    "page_number": mid_page,
                    "chunk_id":    f"{source_pdf}_{seq:05d}",
                })
                seq += 1

            pos += CHUNK_SIZE - CHUNK_OVERLAP

    logger.info(
        f"Chunks Created: {len(all_chunks)} chunks  "
        f"(size={CHUNK_SIZE} chars, overlap={CHUNK_OVERLAP} chars)  "
        f"across {len(documents)} PDF(s)"
    )
    # Per-source breakdown
    from collections import Counter
    src_counts = Counter(c["source_pdf"] for c in all_chunks)
    for src, count in sorted(src_counts.items()):
        logger.info(f"  Chunks from {src}: {count}")
    return all_chunks


# ════════════════════════════════════════════════════════════════════════════════
# EMBEDDINGS
# ════════════════════════════════════════════════════════════════════════════════

def create_embeddings(chunks: list[dict]) -> np.ndarray:
    """
    Generate sentence embeddings for all chunks.

    Model: all-MiniLM-L6-v2 (384-dim).
    Chosen for: fast inference, high retrieval quality, small footprint.

    Returns:
        float32 numpy array of shape (n_chunks, 384).
    """
    model = _get_embed_model()
    texts = [c["text"] for c in chunks]

    logger.info(f"Generating embeddings for {len(texts)} chunks  (batch_size=32) ...")
    t0     = time.time()
    embeds = model.encode(
        texts,
        convert_to_numpy=True,
        show_progress_bar=False,
        batch_size=32,
    )
    embeds = embeds.astype("float32")
    logger.info(
        f"Embeddings Generated: shape={embeds.shape}  "
        f"dim={embeds.shape[1]}  time={time.time() - t0:.1f}s"
    )
    return embeds


# ════════════════════════════════════════════════════════════════════════════════
# FAISS INDEX
# ════════════════════════════════════════════════════════════════════════════════

def build_faiss_index(embeddings: np.ndarray) -> Any:
    """
    L2-normalize embeddings, build an IndexFlatIP, and persist it to disk.

    IndexFlatIP over L2-normalized vectors == cosine similarity search.
    Exact search (no approximation) — appropriate for dataset sizes < 100k vectors.

    Saves:
        vector_store/faiss.index
        vector_store/pdf_hashes.json  (written separately by initialize())

    Returns:
        The FAISS index object.
    """
    import faiss

    VECTOR_STORE.mkdir(parents=True, exist_ok=True)

    vecs = embeddings.copy()
    faiss.normalize_L2(vecs)                          # in-place L2 normalization

    index = faiss.IndexFlatIP(vecs.shape[1])
    index.add(vecs)

    faiss.write_index(index, str(_INDEX_PATH))
    logger.info(
        f"FAISS index built and saved  |  "
        f"{index.ntotal} vectors  dim={vecs.shape[1]}  → {_INDEX_PATH}"
    )
    return index


def load_faiss_index() -> tuple[Any, list[dict]] | None:
    """
    Load FAISS index + chunk metadata from disk.

    Returns (index, chunks) if the cache is valid and PDFs are unchanged.
    Returns None if the cache is missing or any PDF has changed (triggers rebuild).
    """
    import faiss

    if not _INDEX_PATH.exists() or not _META_PATH.exists():
        logger.info("Vector store not found — will build from scratch")
        return None

    if _pdfs_changed():
        logger.info("PDF content changed (hash mismatch) — rebuilding FAISS index")
        return None

    index = faiss.read_index(str(_INDEX_PATH))
    with open(_META_PATH, "rb") as f:
        chunks = pickle.load(f)

    logger.info(
        f"FAISS Loaded: {index.ntotal} vectors, "
        f"{len(chunks)} chunks from {_INDEX_PATH}"
    )
    return index, chunks


def _save_metadata(chunks: list[dict]) -> None:
    VECTOR_STORE.mkdir(parents=True, exist_ok=True)
    with open(_META_PATH, "wb") as f:
        pickle.dump(chunks, f)
    logger.info(f"Chunk metadata saved — {len(chunks)} chunks → {_META_PATH}")


# ════════════════════════════════════════════════════════════════════════════════
# STARTUP
# ════════════════════════════════════════════════════════════════════════════════

def initialize() -> None:
    """
    Called once at server startup via asyncio.to_thread() in main.py lifespan.

    LAZY LOADING MODE — this function no longer loads any FAISS index.
    It only sets _is_ready=True so health checks pass immediately.

    Each goal's KB is loaded on the first request that needs it by kb_manager:
      weight_loss     → loads on first /api/assessment/generate-plan?goal=weight_loss
      muscle_gain     → loads on first muscle-gain request
      general_fitness → loads on first general-fitness request
      transformation  → loads on first transformation request

    Startup memory impact: ~0 MB for indexes (only FastAPI + logger + env vars).
    """
    global _is_ready

    logger.info("=" * 60)
    logger.info("ZITLAS RAG — lazy loading mode active")
    logger.info("No FAISS index loaded at startup.")
    logger.info("Each goal KB loads on first request (cached to disk afterward).")
    logger.info("=" * 60)

    _is_ready = True


# ════════════════════════════════════════════════════════════════════════════════
# SEARCH
# ════════════════════════════════════════════════════════════════════════════════

def search_knowledge(
    query: str,
    top_k: int = DEFAULT_TOP_K,
    goal: str | None = None,
) -> list[dict]:
    """
    Semantic search over per-goal FAISS knowledge base(s).

    With lazy loading, the first call for a given goal triggers a disk load
    (~1-2s from cache) or a PDF build (~30-60s on first ever run).
    Subsequent calls for the same goal return from the in-memory cache.

    Args:
        query:  Natural-language question.
        top_k:  Maximum results to return (default: 5).
        goal:   Fitness goal. One of:
                  "weight_loss" | "muscle_gain" | "general_fitness" | "transformation"
                  None → search all 4 goal KBs and return the best combined results.

    Returns:
        List of chunk dicts sorted by cosine score (descending):
            {text, source_pdf, source, category, page_number, chunk_id, score}
        Chunks below MIN_SCORE (0.20) are excluded.  Returns [] on error.
    """
    import faiss as _faiss

    _VALID_GOALS = ("weight_loss", "muscle_gain", "general_fitness", "transformation")

    model = _get_embed_model()
    q_vec = model.encode([query], convert_to_numpy=True).astype("float32")
    _faiss.normalize_L2(q_vec)

    # Query classification drives source boosting (only for goalless queries).
    query_category: str | None = None
    if not goal:
        query_category = classify_query(query)
        logger.info(f"Query category: {query_category}")

    # Which goal KBs to search.
    # goal-specific: one KB (fast, memory-efficient).
    # goalless: all four KBs merged (used by /api/rag/query and /api/ai/chat).
    goals_to_search = (goal,) if (goal and goal in _VALID_GOALS) else _VALID_GOALS

    all_candidates: list[dict] = []

    for g in goals_to_search:
        # get_kb() loads the KB lazily on first call, returns from cache otherwise.
        try:
            kb = kb_manager.get_kb(g)
        except Exception as exc:
            logger.error(f"Failed to load {g} KB — skipping: {exc}")
            continue

        # Expand candidate pool so boosting has room to re-rank.
        # coaching_rules: gf1b is a small file — needs a deeper scan.
        # general_fitness: 3 sources compete — widen pool.
        if query_category == "coaching_rules":
            search_k = top_k * 5
        elif query_category:
            search_k = top_k * 3
        elif g == "general_fitness":
            search_k = top_k * 3
        else:
            search_k = top_k

        # Guard: never ask FAISS for more vectors than it has.
        search_k = min(search_k, kb.faiss_index.ntotal)
        if search_k == 0:
            continue

        scores, idxs = kb.faiss_index.search(q_vec, search_k)

        for score, idx in zip(scores[0], idxs[0]):
            if idx < 0:
                continue
            score_f = float(score)
            if score_f < MIN_SCORE:
                continue
            chunk = kb.chunks[idx]

            # Source boosting — nudges preferred-category chunks upward without
            # hard-filtering off-category chunks that score highly.
            if query_category:
                boost = _CATEGORY_BOOST.get(query_category, {}).get(chunk["source_pdf"], 0.0)
                score_f = min(1.0, score_f + boost)
            elif g == "general_fitness" and chunk["source_pdf"] == "gf1b.pdf":
                # gf1b (coaching rules) is small — nudge so it surfaces alongside gf1/gf2.
                score_f = min(1.0, score_f + 0.08)

            # Terminal per-goal logging (preserved from original behaviour).
            if g == "muscle_gain":
                print(f"[MUSCLE_GAIN RAG]\nRetrieved Source: {chunk['source_pdf']}")
            elif g == "general_fitness":
                print(f"[GENERAL_FITNESS RAG]\nRetrieved Source: {chunk['source_pdf']}")
            elif g == "transformation":
                print(
                    f"[TRANSFORMATION RAG]\nRetrieved Source: {chunk['source_pdf']}"
                    f"  Page {chunk['page_number']}"
                    f"  category={chunk.get('category', '?')}"
                )

            logger.info(
                f"Search Score: {score_f:.4f}  |  "
                f"Retrieved Source: {chunk['source_pdf']} Page {chunk['page_number']}  |  "
                f"chunk_id={chunk['chunk_id']}  category={chunk.get('category', '?')}"
            )
            all_candidates.append({
                "text":        chunk["text"],
                "source_pdf":  chunk["source_pdf"],
                "source":      chunk.get("source", chunk["source_pdf"].replace(".pdf", "")),
                "category":    chunk.get("category", "general"),
                "page_number": chunk["page_number"],
                "chunk_id":    chunk["chunk_id"],
                "score":       score_f,
            })

    # Global re-sort and trim after merging across all searched KBs.
    all_candidates.sort(key=lambda x: x["score"], reverse=True)
    results = all_candidates[:top_k]

    logger.info(
        f"Retrieved {len(results)} chunk(s) above threshold  "
        f"(top_k={top_k}, min_score={MIN_SCORE}, "
        f"category={query_category or 'goal-filtered'})"
    )
    return results


# ════════════════════════════════════════════════════════════════════════════════
# CONTEXT BUILDER  (used by /api/ai/chat)
# ════════════════════════════════════════════════════════════════════════════════

def retrieve_context(
    query: str,
    top_k: int = DEFAULT_TOP_K,
    goal: str | None = None,
) -> tuple[str, list[dict]]:
    """
    Retrieve relevant chunks and format them for direct LLM context injection.
    Used by the existing /api/ai/chat endpoint.

    Args:
        goal: Optional fitness goal filter ("muscle_gain" | "weight_loss" | None).
              Passed through to search_knowledge() for source filtering.

    Returns:
        context_block: str   — labelled context block ready to prepend to the user message
        source_refs:   list  — [{chunk_id, source_pdf, page_number, score}, ...]
    """
    if goal == "muscle_gain":
        print(f"[GOAL] muscle_gain")
        print("[RAG]\nusing mg1.pdf + mg2.pdf")
    elif goal == "weight_loss":
        print(f"[GOAL] weight_loss")
        print("[RAG]\nusing wl1.pdf + wl2.pdf")
    elif goal == "general_fitness":
        print(f"[GOAL] general_fitness")
        print("[RAG]\nusing gf1.pdf + gf1b.pdf + gf2.pdf")
    elif goal == "transformation":
        print(f"[GOAL] transformation")
        print("[RAG]\nusing tf1.pdf")
    chunks = search_knowledge(query, top_k, goal=goal)
    if not chunks:
        return "", []

    parts = []
    for i, c in enumerate(chunks, 1):
        parts.append(
            f"[Reference {i} — {c['source_pdf']} Page {c['page_number']} "
            f"| relevance: {c['score']:.3f}]\n{c['text']}"
        )

    context_block = "\n\n---\n\n".join(parts)
    source_refs   = [
        {
            "chunk_id":    c["chunk_id"],
            "source_pdf":  c["source_pdf"],
            "page_number": c["page_number"],
            "score":       round(c["score"], 4),
        }
        for c in chunks
    ]
    return context_block, source_refs


# ════════════════════════════════════════════════════════════════════════════════
# PROMPT BUILDER  (used by /api/rag/query)
# ════════════════════════════════════════════════════════════════════════════════

_PROFILE_LABELS: dict[str, str] = {
    "current_weight":     "Current Weight",
    "goal_weight":        "Goal Weight",
    "height":             "Height",
    "age":                "Age",
    "gender":             "Gender",
    "activity_level":     "Activity Level",
    "diet_preference":    "Diet Preference",
    "workout_preference": "Workout Preference",
    "budget":             "Budget",
    "occupation":         "Occupation",
    "living_situation":   "Living Situation",
}


def build_rag_prompt(
    question: str,
    retrieved_chunks: list[dict],
    user_data: dict | None = None,
) -> dict[str, str]:
    """
    Assemble the full structured RAG prompt.

    Prompt layout (user message):
        CONTEXT
          [Reference 1 — wl2.pdf | Page 45 | Relevance: 0.876]
          <chunk text>
          ---
          [Reference 2 — ...]
          ...

        USER DATA
          Current Weight: 95 kg
          Goal Weight: 75 kg
          ...

        QUESTION
          <user's question>

    Args:
        question:          The user's raw question string.
        retrieved_chunks:  Output of search_knowledge() — list of chunk dicts with score.
        user_data:         Optional user profile dict for personalization.

    Returns:
        {"system": str, "user": str}
        Pass these directly to groq_service.chat(user_message=..., system_override=...).
    """
    sections: list[str] = []

    # ── CONTEXT ────────────────────────────────────────────────────────────────
    if retrieved_chunks:
        ctx_lines = ["CONTEXT (weight-loss and fitness research knowledge base):"]
        for i, c in enumerate(retrieved_chunks, 1):
            ctx_lines.append(
                f"\n[Reference {i} — {c['source_pdf']} | "
                f"Page {c['page_number']} | "
                f"Relevance: {c['score']:.3f}]\n"
                f"{c['text']}"
            )
        sections.append("\n".join(ctx_lines))
    else:
        sections.append(
            "CONTEXT: No specific research was retrieved for this query. "
            "Answer from general fitness and nutrition principles."
        )

    # ── USER DATA ──────────────────────────────────────────────────────────────
    if user_data:
        profile_lines = ["USER DATA:"]

        # Standard labelled fields first
        for key, label in _PROFILE_LABELS.items():
            val = user_data.get(key)
            if val is not None and str(val).strip():
                profile_lines.append(f"  {label}: {val}")

        # Any extra fields the caller passes
        known = set(_PROFILE_LABELS)
        for key, val in user_data.items():
            if key not in known and val is not None and str(val).strip():
                profile_lines.append(f"  {key.replace('_', ' ').title()}: {val}")

        if len(profile_lines) > 1:          # only include section if there's data
            sections.append("\n".join(profile_lines))

    # ── QUESTION ───────────────────────────────────────────────────────────────
    sections.append(f"QUESTION:\n{question}")

    return {
        "system": RAG_SYSTEM_PROMPT,
        "user":   "\n\n---\n\n".join(sections),
    }


def build_transformation_prompt(
    question: str,
    retrieved_chunks: list[dict],
    user_data: dict | None = None,
) -> dict[str, str]:
    """
    Transformation-specific RAG prompt builder.

    Uses TRANSFORMATION_SYSTEM_PROMPT so the LLM stays in the transformation
    knowledge base (tf1.pdf) and never crosses into weight-loss or muscle-gain
    context unless explicitly re-configured.

    Identical structure to build_rag_prompt() but with the transformation system prompt.
    """
    sections: list[str] = []

    # ── CONTEXT ────────────────────────────────────────────────────────────────
    if retrieved_chunks:
        ctx_lines = ["CONTEXT (transformation research knowledge base — tf1.pdf):"]
        for i, c in enumerate(retrieved_chunks, 1):
            ctx_lines.append(
                f"\n[Reference {i} — {c['source_pdf']} | "
                f"Page {c['page_number']} | "
                f"Relevance: {c['score']:.3f} | "
                f"category={c.get('category', 'transformation')}]\n"
                f"{c['text']}"
            )
        sections.append("\n".join(ctx_lines))
    else:
        sections.append(
            "CONTEXT: No specific transformation research was retrieved for this query. "
            "Answer from general body transformation and recomposition principles."
        )

    # ── USER DATA ──────────────────────────────────────────────────────────────
    if user_data:
        profile_lines = ["USER DATA:"]
        for key, label in _PROFILE_LABELS.items():
            val = user_data.get(key)
            if val is not None and str(val).strip():
                profile_lines.append(f"  {label}: {val}")
        known = set(_PROFILE_LABELS)
        for key, val in user_data.items():
            if key not in known and val is not None and str(val).strip():
                profile_lines.append(f"  {key.replace('_', ' ').title()}: {val}")
        if len(profile_lines) > 1:
            sections.append("\n".join(profile_lines))

    # ── QUESTION ───────────────────────────────────────────────────────────────
    sections.append(f"QUESTION:\n{question}")

    return {
        "system": TRANSFORMATION_SYSTEM_PROMPT,
        "user":   "\n\n---\n\n".join(sections),
    }
