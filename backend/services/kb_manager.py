"""
ZITLAS — Knowledge Base Manager
Lazy loading, LRU caching, and thread-safe per-goal FAISS knowledge bases.

Memory model:
  Startup allocates NOTHING for FAISS — zero index loaded.
  On the first request for goal X, only that goal's PDFs are loaded.
  MAX_LOADED_KBS controls how many goal KBs live in RAM simultaneously;
  the least-recently-used is evicted when the limit is exceeded.

Supported goals / disk layout:
  weight_loss      → vector_store/weight_loss/   (wl1.pdf + wl2.pdf)
  muscle_gain      → vector_store/muscle_gain/   (mg1.pdf + mg2.pdf)
  general_fitness  → vector_store/general_fitness/ (gf1.pdf + gf1b.pdf + gf2.pdf)
  transformation   → vector_store/transformation/ (tf1.pdf)

Usage:
    from services.kb_manager import kb_manager
    kb = kb_manager.get_kb("weight_loss")
    # kb.faiss_index  — loaded FAISS IndexFlatIP
    # kb.chunks       — list of chunk dicts with text/source_pdf/page_number etc.
"""

import gc
import hashlib
import json
import logging
import pickle
import threading
import time
from pathlib import Path
from typing import Any

# ── Logger ─────────────────────────────────────────────────────────────────────
logger = logging.getLogger("zitlas.kb_manager")
if not logger.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(
        logging.Formatter(
            "%(asctime)s  [KB]   %(levelname)-8s  %(message)s",
            datefmt="%H:%M:%S",
        )
    )
    logger.addHandler(_h)
    logger.setLevel(logging.INFO)
    logger.propagate = False

# ── Paths ──────────────────────────────────────────────────────────────────────
_BACKEND_DIR = Path(__file__).parent.parent
VECTOR_STORE = _BACKEND_DIR / "vector_store"

# ── Per-goal PDF sources ───────────────────────────────────────────────────────
# Each key maps to the PDFs that compose that goal's knowledge base.
# These paths mirror rag_service.PDF_SOURCES but are partitioned by goal.
_KB_PDF_SOURCES: dict[str, list[tuple[Path, str]]] = {
    "weight_loss": [
        (_BACKEND_DIR / "weight_loss",    "wl1.pdf"),
        (_BACKEND_DIR / "weight_loss",    "wl2.pdf"),
    ],
    "muscle_gain": [
        (_BACKEND_DIR / "Muscle_Gain",    "mg1.pdf"),
        (_BACKEND_DIR / "Muscle_Gain",    "mg2.pdf"),
    ],
    "general_fitness": [
        (_BACKEND_DIR / "general fitness", "gf1.pdf"),
        (_BACKEND_DIR / "general fitness", "gf1b.pdf"),
        (_BACKEND_DIR / "general fitness", "gf2.pdf"),
    ],
    "transformation": [
        (_BACKEND_DIR / "transformation",  "tf1.pdf"),
    ],
}

_KB_DISPLAY: dict[str, str] = {
    "weight_loss":    "Weight Loss",
    "muscle_gain":    "Muscle Gain",
    "general_fitness": "General Fitness",
    "transformation": "Transformation",
}

# Maximum number of goal KBs held in RAM simultaneously.
# When exceeded, the least-recently-used KB is evicted.
# Tuned for Render Free Tier (512 MB): 2 KBs + embedding model fits comfortably.
MAX_LOADED_KBS: int = 2

# ── Shared embedding model singleton ──────────────────────────────────────────
# One SentenceTransformer instance for the entire process.
# Double-checked locking ensures it is loaded exactly once even under concurrent
# requests at startup.
_embedding_model = None
_model_lock = threading.Lock()


def get_embedding_model():
    """
    Return the shared all-MiniLM-L6-v2 SentenceTransformer instance.
    Loads the model on first call; cached for the process lifetime.
    Thread-safe via double-checked locking — never loaded twice.
    """
    global _embedding_model
    if _embedding_model is None:
        with _model_lock:
            if _embedding_model is None:          # second check inside the lock
                from sentence_transformers import SentenceTransformer
                logger.info("Loading embedding model: all-MiniLM-L6-v2 ...")
                t0 = time.time()
                _embedding_model = SentenceTransformer("all-MiniLM-L6-v2")
                logger.info(f"Embedding model ready  ({time.time() - t0:.1f}s)")
    return _embedding_model


# ── KB container ──────────────────────────────────────────────────────────────

class KnowledgeBase:
    """
    Holds one goal's in-memory FAISS index, chunk metadata, and LRU timestamp.
    Immutable after construction; only last_used is written (via touch()).
    """
    __slots__ = ("name", "faiss_index", "chunks", "last_used")

    def __init__(self, name: str, faiss_index: Any, chunks: list[dict]):
        self.name        = name
        self.faiss_index = faiss_index          # faiss.IndexFlatIP
        self.chunks      = chunks               # list of chunk dicts
        self.last_used   = time.time()

    def touch(self) -> None:
        """Update the LRU timestamp to now."""
        self.last_used = time.time()


# ── Manager ───────────────────────────────────────────────────────────────────

class KnowledgeBaseManager:
    """
    Thread-safe lazy-loading manager for per-goal FAISS knowledge bases.

    Concurrency design:
    - _global_lock  : guards reads/writes to _cache (held only briefly).
    - _kb_locks[g]  : one lock per goal, serialises building/loading that KB.
                      Means two threads requesting the same KB simultaneously
                      will have one load it while the other waits, then both
                      return from the cache.  Different goals load in parallel.

    LRU eviction:
    - Checked after every cache insertion (inside _global_lock).
    - The KB that was least recently accessed is removed when the cache exceeds
      MAX_LOADED_KBS.  The KB just inserted is never the eviction target.
    """

    def __init__(self):
        self._cache: dict[str, KnowledgeBase] = {}
        self._global_lock = threading.Lock()
        # One lock per goal prevents double-loading the same KB.
        self._kb_locks: dict[str, threading.Lock] = {
            g: threading.Lock() for g in _KB_PDF_SOURCES
        }

    # ── Public API ─────────────────────────────────────────────────────────────

    def get_kb(self, goal_type: str) -> KnowledgeBase:
        """
        Return the KnowledgeBase for the given goal, loading it if necessary.

        Args:
            goal_type: One of "weight_loss" | "muscle_gain" |
                       "general_fitness" | "transformation".

        Returns:
            KnowledgeBase with a ready FAISS index and chunk list.

        Raises:
            ValueError: Unknown goal_type.
            RuntimeError: No PDFs found for the goal.
        """
        if goal_type not in _KB_PDF_SOURCES:
            raise ValueError(
                f"Unknown goal type: {goal_type!r}. "
                f"Valid values: {sorted(_KB_PDF_SOURCES)}"
            )

        display = _KB_DISPLAY[goal_type]

        # ── Fast path: cache hit (brief lock) ─────────────────────────────────
        with self._global_lock:
            if goal_type in self._cache:
                self._cache[goal_type].touch()
                logger.info(f"Using cached {display} KB.")
                return self._cache[goal_type]

        # ── Slow path: load the KB (per-goal lock, not global lock) ───────────
        with self._kb_locks[goal_type]:
            # Re-check after acquiring the per-KB lock: another thread may have
            # already loaded this KB while we were waiting.
            with self._global_lock:
                if goal_type in self._cache:
                    self._cache[goal_type].touch()
                    logger.info(f"Using cached {display} KB.")
                    return self._cache[goal_type]

            # Load from disk or build from PDFs.
            # The global lock is NOT held during I/O so other KBs can load concurrently.
            logger.info(f"Loading {display} KB...")
            kb = self._load_kb(goal_type)

            # Insert into cache and apply LRU eviction if needed.
            with self._global_lock:
                self._cache[goal_type] = kb
                self._evict_if_needed(exclude=goal_type)

            logger.info(f"{display} KB loaded successfully.")
            return kb

    def unload_kb(self, kb_name: str) -> None:
        """
        Manually remove a KB from the in-memory cache.
        The next request for this KB will reload it from disk.
        """
        display = _KB_DISPLAY.get(kb_name, kb_name)
        with self._global_lock:
            if kb_name in self._cache:
                del self._cache[kb_name]
                logger.info(f"Unloaded {display} KB from cache.")
            else:
                logger.warning(f"KB {kb_name!r} was not in cache — nothing to unload.")

    def get_model(self):
        """Return the shared embedding model (lazy-loaded on first call)."""
        return get_embedding_model()

    def get_cache_stats(self) -> dict:
        """
        Snapshot of the current cache state.  Safe to call from any thread.
        """
        with self._global_lock:
            loaded = list(self._cache.keys())
            details = {
                name: {
                    "chunks":    len(kb.chunks),
                    "vectors":   kb.faiss_index.ntotal,
                    "last_used": kb.last_used,
                }
                for name, kb in self._cache.items()
            }
        return {
            "loaded_kbs":     loaded,
            "cache_size":     len(loaded),
            "max_loaded_kbs": MAX_LOADED_KBS,
            "memory_optimized": True,
            "kb_details":     details,
        }

    # ── Private helpers ────────────────────────────────────────────────────────

    def _load_kb(self, goal_type: str) -> KnowledgeBase:
        """
        Load a KB from disk cache, or build it from PDFs and persist to disk.
        Called with the per-goal lock held; the global lock is NOT held.

        Disk layout per goal:
            vector_store/<goal_type>/faiss.index
            vector_store/<goal_type>/chunks_metadata.pkl
            vector_store/<goal_type>/pdf_hashes.json
        """
        import faiss

        display   = _KB_DISPLAY[goal_type]
        store_dir = VECTOR_STORE / goal_type
        idx_path  = store_dir / "faiss.index"
        meta_path = store_dir / "chunks_metadata.pkl"
        hash_path = store_dir / "pdf_hashes.json"
        t0        = time.time()

        # ── Try disk cache ──────────────────────────────────────────────────────
        if idx_path.exists() and meta_path.exists():
            if not self._pdfs_changed(goal_type, hash_path):
                index = faiss.read_index(str(idx_path))
                with open(meta_path, "rb") as fh:
                    chunks = pickle.load(fh)
                        try:
                    import psutil as _psutil
                    _rss = _psutil.Process().memory_info().rss / 1024 / 1024
                    logger.info(
                        f"{display} KB loaded from disk  ({time.time() - t0:.1f}s)"
                        f"  — {index.ntotal} vectors, {len(chunks)} chunks"
                        f"  | RAM: {_rss:.1f} MB"
                    )
                except Exception:
                    logger.info(
                        f"{display} KB loaded from disk  ({time.time() - t0:.1f}s)"
                        f"  — {index.ntotal} vectors, {len(chunks)} chunks"
                    )
                return KnowledgeBase(goal_type, index, chunks)
            logger.info(f"{display} KB: PDF content changed — rebuilding index")

        # ── Build from PDFs ─────────────────────────────────────────────────────
        # rag_service is imported here (not at module level) to avoid a circular
        # import: rag_service imports kb_manager at the top, so kb_manager must
        # not import rag_service at the top.
        logger.info(f"Building {display} KB from PDFs ...")
        from services import rag_service as _rs

        documents: list[dict] = []
        for pdf_dir, fname in _KB_PDF_SOURCES[goal_type]:
            path = pdf_dir / fname
            if path.exists():
                documents.append(_rs.extract_pdf_text(path))
            else:
                logger.warning(f"PDF not found — skipping: {path}")

        if not documents:
            raise RuntimeError(
                f"No PDFs found for {display} KB. "
                f"Searched: {[str(d / f) for d, f in _KB_PDF_SOURCES[goal_type]]}"
            )

        chunks = _rs.chunk_documents(documents)

        # Generate embeddings using the shared singleton.
        model  = get_embedding_model()
        texts  = [c["text"] for c in chunks]
        logger.info(f"Generating embeddings for {len(texts)} chunks  (batch_size=32) ...")
        t1 = time.time()
        import numpy as np
        embeds = model.encode(
            texts,
            convert_to_numpy=True,
            show_progress_bar=False,
            batch_size=32,
        ).astype("float32")
        logger.info(f"Embeddings ready  ({time.time() - t1:.1f}s)")

        # Build FAISS IndexFlatIP over L2-normalised vectors (= cosine similarity).
        vecs = embeds.copy()
        faiss.normalize_L2(vecs)
        index = faiss.IndexFlatIP(vecs.shape[1])
        index.add(vecs)

        # Persist to disk so subsequent restarts load from cache (<2s).
        store_dir.mkdir(parents=True, exist_ok=True)
        faiss.write_index(index, str(idx_path))
        with open(meta_path, "wb") as fh:
            pickle.dump(chunks, fh)
        self._write_hashes(goal_type, hash_path)

        try:
            import psutil as _psutil
            _rss = _psutil.Process().memory_info().rss / 1024 / 1024
            logger.info(
                f"{display} KB built and saved  ({time.time() - t0:.1f}s)"
                f"  — {index.ntotal} vectors, {len(chunks)} chunks"
                f"  | RAM: {_rss:.1f} MB"
            )
        except Exception:
            logger.info(
                f"{display} KB built and saved  ({time.time() - t0:.1f}s)"
                f"  — {index.ntotal} vectors, {len(chunks)} chunks"
            )
        return KnowledgeBase(goal_type, index, chunks)

    def _pdfs_changed(self, goal_type: str, hash_path: Path) -> bool:
        """
        True if any PDF for this goal has been modified since the index was built.
        Uses MD5 hashes stored alongside each per-goal index.

        If no PDFs exist on disk (e.g. Render deployment where only the pre-built
        vector_store/ is committed, not the source PDFs), the pre-built index is
        trusted as-is — returning False skips the rebuild.
        """
        if not hash_path.exists():
            return True
        with open(hash_path) as fh:
            saved: dict[str, str] = json.load(fh)
        current: dict[str, str] = {}
        for pdf_dir, fname in _KB_PDF_SOURCES[goal_type]:
            p = pdf_dir / fname
            if p.exists():
                h = hashlib.md5()
                with open(p, "rb") as fh:
                    for block in iter(lambda: fh.read(65536), b""):
                        h.update(block)
                current[fname] = h.hexdigest()
        # No PDFs present at all → trust the committed pre-built index.
        if not current:
            logger.info(
                f"No source PDFs found for {goal_type} — "
                "trusting pre-built index (deployment mode)"
            )
            return False
        # Only compare hashes for PDFs that are actually present on disk.
        return any(current.get(k) != saved.get(k) for k in current)

    def _write_hashes(self, goal_type: str, hash_path: Path) -> None:
        """Persist current PDF MD5 hashes for this goal to disk."""
        hashes: dict[str, str] = {}
        for pdf_dir, fname in _KB_PDF_SOURCES[goal_type]:
            p = pdf_dir / fname
            if p.exists():
                h = hashlib.md5()
                with open(p, "rb") as fh:
                    for block in iter(lambda: fh.read(65536), b""):
                        h.update(block)
                hashes[fname] = h.hexdigest()
        with open(hash_path, "w") as fh:
            json.dump(hashes, fh, indent=2)

    def _evict_if_needed(self, exclude: str | None = None) -> None:
        """
        Remove the least-recently-used KB when the cache exceeds MAX_LOADED_KBS.
        Must be called with _global_lock held.
        The 'exclude' KB (the one just inserted) is never chosen for eviction.
        """
        while len(self._cache) > MAX_LOADED_KBS:
            candidates = [n for n in self._cache if n != exclude]
            if not candidates:
                break
            lru = min(candidates, key=lambda n: self._cache[n].last_used)
            del self._cache[lru]
            gc.collect()  # release FAISS index + chunk list memory immediately
            try:
                import psutil as _psutil
                _rss = _psutil.Process().memory_info().rss / 1024 / 1024
                logger.info(
                    f"LRU evicted {_KB_DISPLAY.get(lru, lru)} KB "
                    f"(limit={MAX_LOADED_KBS})  | RAM after gc: {_rss:.1f} MB"
                )
            except Exception:
                logger.info(
                    f"LRU evicted {_KB_DISPLAY.get(lru, lru)} KB "
                    f"(limit={MAX_LOADED_KBS})"
                )


# ── Module-level singleton ────────────────────────────────────────────────────
# Import this in other modules:   from services.kb_manager import kb_manager
kb_manager = KnowledgeBaseManager()
