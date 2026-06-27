"""
ZITLAS — Per-Goal FAISS Index Pre-builder

Converts the existing unified vector_store/faiss.index into four per-goal
sub-indexes that kb_manager.py expects.  Run this ONCE before deploying.

The unified index already has all vectors in order; we just extract the rows
that belong to each goal's PDF set using the chunk metadata as a guide.

Usage (from backend/ directory):
    python prebuild_indexes.py

Output:
    vector_store/weight_loss/    faiss.index + chunks_metadata.pkl + pdf_hashes.json
    vector_store/muscle_gain/    faiss.index + chunks_metadata.pkl + pdf_hashes.json
    vector_store/general_fitness/ faiss.index + chunks_metadata.pkl + pdf_hashes.json
    vector_store/transformation/  faiss.index + chunks_metadata.pkl + pdf_hashes.json

Time: ~5 seconds (no re-embedding needed — reuses existing vectors).
"""

import hashlib
import json
import pickle
import time
from pathlib import Path

import faiss
import numpy as np

# ── Paths ─────────────────────────────────────────────────────────────────────
BACKEND_DIR  = Path(__file__).parent
VECTOR_STORE = BACKEND_DIR / "vector_store"
UNIFIED_IDX  = VECTOR_STORE / "faiss.index"
UNIFIED_META = VECTOR_STORE / "chunks_metadata.pkl"

# ── Goal → PDF mapping (mirrors kb_manager._KB_PDF_SOURCES) ──────────────────
GOAL_PDFS: dict[str, list[tuple[Path, str]]] = {
    "weight_loss": [
        (BACKEND_DIR / "weight_loss",    "wl1.pdf"),
        (BACKEND_DIR / "weight_loss",    "wl2.pdf"),
    ],
    "muscle_gain": [
        (BACKEND_DIR / "Muscle_Gain",    "mg1.pdf"),
        (BACKEND_DIR / "Muscle_Gain",    "mg2.pdf"),
    ],
    "general_fitness": [
        (BACKEND_DIR / "general fitness", "gf1.pdf"),
        (BACKEND_DIR / "general fitness", "gf1b.pdf"),
        (BACKEND_DIR / "general fitness", "gf2.pdf"),
    ],
    "transformation": [
        (BACKEND_DIR / "transformation",  "tf1.pdf"),
    ],
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def _md5(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def _write_hashes(goal: str, out_dir: Path) -> None:
    hashes: dict[str, str] = {}
    for pdf_dir, fname in GOAL_PDFS[goal]:
        p = pdf_dir / fname
        if p.exists():
            hashes[fname] = _md5(p)
    with open(out_dir / "pdf_hashes.json", "w") as f:
        json.dump(hashes, f, indent=2)


# ── Sanity checks ─────────────────────────────────────────────────────────────

def _check_prerequisites() -> None:
    if not UNIFIED_IDX.exists():
        raise FileNotFoundError(
            f"Unified FAISS index not found: {UNIFIED_IDX}\n"
            "Run the original rag_service.initialize() at least once first."
        )
    if not UNIFIED_META.exists():
        raise FileNotFoundError(f"Unified metadata not found: {UNIFIED_META}")
    print(f"[OK] Unified index : {UNIFIED_IDX}  ({UNIFIED_IDX.stat().st_size / 1e6:.1f} MB)")
    print(f"[OK] Unified metadata: {UNIFIED_META}  ({UNIFIED_META.stat().st_size / 1e6:.1f} MB)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    t_start = time.time()
    print("=" * 60)
    print("ZITLAS — Per-Goal Index Pre-builder")
    print("=" * 60)

    _check_prerequisites()

    # Load unified resources.
    print("\nLoading unified index...")
    unified_index = faiss.read_index(str(UNIFIED_IDX))
    n_total = unified_index.ntotal
    dim     = unified_index.d
    print(f"  {n_total} vectors  dim={dim}")

    print("Loading unified chunk metadata...")
    with open(UNIFIED_META, "rb") as f:
        all_chunks: list[dict] = pickle.load(f)
    print(f"  {len(all_chunks)} chunks")

    if len(all_chunks) != n_total:
        raise ValueError(
            f"Mismatch: FAISS has {n_total} vectors but metadata has {len(all_chunks)} chunks. "
            "The index and metadata must be in sync."
        )

    # Reconstruct the full vector matrix from FAISS.
    # IndexFlatIP stores vectors in insertion order, matching the chunk list order.
    print("Extracting all vectors from FAISS index...")
    all_vectors = np.zeros((n_total, dim), dtype="float32")
    unified_index.reconstruct_n(0, n_total, all_vectors)
    print(f"  Extracted {all_vectors.shape}")

    # Build one sub-index per goal.
    print()
    results: list[dict] = []
    for goal, pdf_pairs in GOAL_PDFS.items():
        t0   = time.time()
        pdfs = {fname for _, fname in pdf_pairs}

        # Find the chunk indices that belong to this goal.
        goal_indices = [
            i for i, c in enumerate(all_chunks)
            if c["source_pdf"] in pdfs
        ]

        if not goal_indices:
            print(f"[WARN] {goal}: no chunks found for PDFs {pdfs} — skipping")
            continue

        goal_chunks  = [all_chunks[i] for i in goal_indices]
        goal_vectors = all_vectors[goal_indices]   # shape (k, dim) — already L2-normalised

        # Build IndexFlatIP.  Vectors are already L2-normalised from the original build.
        sub_index = faiss.IndexFlatIP(dim)
        sub_index.add(goal_vectors)

        # Write to disk.
        out_dir = VECTOR_STORE / goal
        out_dir.mkdir(parents=True, exist_ok=True)
        faiss.write_index(sub_index, str(out_dir / "faiss.index"))
        with open(out_dir / "chunks_metadata.pkl", "wb") as f:
            pickle.dump(goal_chunks, f)
        _write_hashes(goal, out_dir)

        elapsed = time.time() - t0
        size_mb = (out_dir / "faiss.index").stat().st_size / 1e6
        print(
            f"[OK] {goal:<20} {len(goal_chunks):>5} chunks  "
            f"FAISS={size_mb:.2f} MB  ({elapsed:.2f}s)"
        )
        results.append({"goal": goal, "chunks": len(goal_chunks), "faiss_mb": size_mb})

    # Verify totals.
    total_chunks = sum(r["chunks"] for r in results)
    print()
    print(f"Total chunks across all goals: {total_chunks} / {len(all_chunks)} in unified")
    if total_chunks != len(all_chunks):
        missing = len(all_chunks) - total_chunks
        print(f"[WARN] {missing} chunks not assigned to any goal (unexpected source_pdf values).")

    print()
    print(f"Done in {time.time() - t_start:.1f}s")
    print("Per-goal indexes are ready. kb_manager will load from disk on first request.")
    print("=" * 60)


if __name__ == "__main__":
    main()
