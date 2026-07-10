"""
ZITLAS — Workout Recommendation Engine (backend/services/workout_engine.py)

Loads backend/workout/zitlas_kb_records.jsonl ONCE at import time (393
records: exercises, warm-ups, mobility drills, stretches, cool-downs,
breathing techniques, meditations, yoga poses, chronic-condition guidance,
acute recovery-condition guidance, and lifestyle/women/senior/disability/kids
profiles) and serves every workout-generation feature from it. The PDF
(ZITLAS_Phase1_Knowledge_Base.pdf) is the human-readable version of the same
content — the JSONL is the only thing this engine reads at request time.

Mirrors the exact architecture proven out in services/food_engine.py: build
inverted indexes once, filter via set intersection (not a per-request scan
of all 393 records), score what's left, and hand groq_service/routes/
assessment.py real KB items that get engine-sourced fields overwritten onto
whatever the LLM returns — so the LLM can write coaching tips/summaries but
can never cause an invented exercise to reach a user.

MEDICAL SAFETY: condition detection is NOT reimplemented — resolve_conditions()
calls services/medical_conditions.detect_conditions() (the existing keyword
matcher) and maps its keys onto this KB's chronic_condition names. A handful
of conditions this KB covers that medical_conditions.py has no entry for at
all (neck pain, GERD, IBS, osteoporosis, ...) get a small keyword check of
their own, same pattern as food_engine.py's kidney/gluten/lactose additions.
"""

from __future__ import annotations

import json
import threading
from collections import defaultdict
from pathlib import Path
from typing import Any

from services import medical_conditions

_KB_PATH = Path(__file__).parent.parent / "workout" / "zitlas_kb_records.jsonl"


def _norm(s: str) -> str:
    return (s or "").strip().lower()


def _stable_tiebreak(eid: str, seed: str) -> str:
    """Deterministic (same input -> same output, unlike Python's salted
    hash()) but seed-dependent ordering key, so two different profiles that
    tie on score don't always fall back to the same alphabetical exercise id."""
    import hashlib
    return hashlib.md5(f"{eid}|{seed}".encode()).hexdigest()


# ══════════════════════════════════════════════════════════════════════════
# CONDITION / LIFESTYLE / RECOVERY NAME MAPPINGS
# ══════════════════════════════════════════════════════════════════════════

# medical_conditions.py CONDITION_RULES key -> this KB's chronic_condition name.
# Conditions with no fitness-safety entry here (knee_pain, underweight,
# depression, migraine as a *chronic* condition, fatty_liver, heart_disease)
# are intentionally absent — knee_pain maps via profile_disability instead
# (see _EXTRA_CONDITION_KEYWORDS), and the rest don't have a matching KB entry.
_CONDITION_KEY_TO_KB_NAME: dict[str, str] = {
    "asthma": "Asthma",
    "diabetes": "Type 2 Diabetes",
    "hypertension": "High Blood Pressure (Hypertension)",
    "hypothyroidism": "Hypothyroidism",
    "hyperthyroidism": "Hyperthyroidism",
    "pcos": "PCOS (Polycystic Ovary Syndrome)",
    "arthritis": "Arthritis",
    "back_pain": "Lower Back Pain (Non-Specific, Chronic)",
    "obesity": "Obesity",
    "anxiety": "Anxiety",
    "high_cholesterol": "High Cholesterol",
    "sleep_apnea": "Poor Sleep (Chronic Insomnia Pattern)",
}
# Covered by this KB but not by medical_conditions.py at all.
_EXTRA_CONDITION_KEYWORDS: dict[str, tuple[str, ...]] = {
    "Neck Pain (Chronic, Postural)": ("neck pain", "cervical", "stiff neck"),
    "Osteoporosis": ("osteoporosis", "bone density", "low bone mass"),
    "Acid Reflux (GERD)": ("acid reflux", "gerd", "heartburn"),
    "IBS (Irritable Bowel Syndrome)": ("ibs", "irritable bowel"),
    "Constipation": ("constipation",),
    "Sedentary Lifestyle": ("sedentary",),
    "Prediabetes": ("prediabetes", "pre-diabetes", "borderline sugar"),
    "Knee Pain / Limited Knee Mobility": ("knee pain", "knee injury", "bad knee", "knee mobility"),
    "Shoulder Pain / Limited Shoulder Mobility": ("shoulder pain", "shoulder injury", "frozen shoulder"),
}
# knee_pain/back_pain from medical_conditions.py map onto disability-style
# guidance too, for extra exercise-avoidance detail beyond the chronic_condition entry.
_EXTRA_CONDITION_ALIASES: dict[str, str] = {
    "knee_pain": "Knee Pain / Limited Knee Mobility",
}

# Acute "I'm sick today" detection — recovery_condition names in the KB.
_RECOVERY_CONDITION_KEYWORDS: dict[str, tuple[str, ...]] = {
    "Fever": ("fever", "high temperature"),
    "Common Cold": ("cold", "runny nose", "blocked nose", "congestion"),
    "Cough": ("cough",),
    "Throat Infection": ("throat infection", "sore throat", "tonsillitis"),
    "Typhoid Recovery": ("typhoid",),
    "Dengue Recovery": ("dengue",),
    "Food Poisoning Recovery": ("food poisoning", "stomach infection", "diarrhea", "diarrhoea", "vomiting"),
    "COVID-19 Recovery": ("covid", "coronavirus"),
    "Migraine": ("migraine",),
    "General Fatigue": ("fatigue", "exhausted", "burnt out", "burnout", "no energy",
                          "sick today", "feeling sick", "unwell", "not well", "injured", "injury"),
}

_DISABILITY_KEYWORDS: list[tuple[tuple[str, ...], str]] = [
    (("wheelchair",), "Wheelchair User Fitness"),
    (("lower-limb amputation", "lower limb amputation", "leg amputation"), "Lower-Limb Amputation Fitness"),
    (("upper-limb amputation", "upper limb amputation", "arm amputation"), "Upper-Limb Amputation Fitness"),
    (("knee mobility", "limited knee", "knee injury"), "Limited Knee Mobility Fitness"),
    (("shoulder mobility", "limited shoulder", "frozen shoulder"), "Limited Shoulder Mobility Fitness"),
    (("hearing impair", "deaf", "hard of hearing"), "Fitness for Hearing Impairment"),
    (("vision loss", "partial blind", "visually impaired", "low vision"), "Fitness for Partial Vision Loss"),
    (("cerebral palsy",), "Fitness for Mild Cerebral Palsy"),
]

_LIFESTYLE_KB_NAME: dict[str, str] = {
    "hostel": "Hostel Student Lifestyle",
    "college": "College Student Lifestyle",
    "student": "College Student Lifestyle",
    "working_professional": "Working Professional Lifestyle",
    "office": "Working Professional Lifestyle",
    "night_shift": "Night Shift Worker Lifestyle",
    "night shift": "Night Shift Worker Lifestyle",
    "traveller": "Traveller / Frequent Flyer Lifestyle",
    "traveler": "Traveller / Frequent Flyer Lifestyle",
    "travel": "Traveller / Frequent Flyer Lifestyle",
    "homemaker": "Homemaker Lifestyle",
    "home_maker": "Homemaker Lifestyle",
    "athlete": "Athlete Lifestyle",
    "busy_parent": "Busy Parent Lifestyle",
    "parent": "Busy Parent Lifestyle",
    "remote": "Remote Worker Lifestyle",
    "remote_worker": "Remote Worker Lifestyle",
}

# workout_preference (existing ZITLAS vocab: home/gym/walking/none/mixed,
# plus 'hostel' surfaced via living_situation) -> acceptable KB exercise tags.
_EQUIPMENT_TAGS_FROM_PREFERENCE: dict[str, set[str]] = {
    "home": {"home", "bodyweight", "no-equipment", "apartment-friendly", "resistance-band", "calisthenics"},
    "gym": {"gym", "machine", "dumbbell", "cable", "compound", "isolation", "barbell"},
    "walking": {"home", "bodyweight", "no-equipment", "cardio", "conditioning"},
    "none": {"bodyweight", "no-equipment", "calisthenics"},
    "mixed": {"home", "gym", "bodyweight", "dumbbell", "machine", "no-equipment"},
    "hostel": {"hostel", "bodyweight", "no-equipment", "travel", "apartment-friendly"},
}

_GOAL_TO_KB_GOALS: dict[str, list[str]] = {
    "weight_loss": ["Weight Loss", "Fat Loss", "General Fitness"],
    "muscle_gain": ["Muscle Gain", "Strength"],
    "general_fitness": ["General Fitness", "Flexibility", "Balance"],
    "transformation": ["Fat Loss", "Muscle Gain", "Strength"],
    "athletic_performance": ["Athletic", "Strength"],
}

# ══════════════════════════════════════════════════════════════════════════
# WEEKLY DAY-TYPE TEMPLATES — one per goal, mirroring the MANDATORY WEEKLY
# STRUCTURE each existing system prompt in routes/assessment.py already
# specifies (same day rhythm/frequency; exercises now come from the KB
# instead of the LLM inventing them).
# ══════════════════════════════════════════════════════════════════════════

_DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

# Each entry: (type, focus, categories, is_cardio, is_rest, is_active_recovery)
_WEEKLY_TEMPLATES: dict[str, list[dict[str, Any]]] = {
    "weight_loss": [
        {"type": "Workout", "focus": "Cardio + Lower Body Strength", "categories": ["Legs", "Glutes"], "cardio": True},
        {"type": "Cardio", "focus": "Cardio Focus", "categories": [], "cardio": True, "cardio_only": True},
        {"type": "Workout", "focus": "Upper Body + Core", "categories": ["Chest", "Back", "Shoulders", "Core"]},
        {"type": "Cardio", "focus": "Interval Cardio", "categories": [], "cardio": True, "cardio_only": True},
        {"type": "Workout", "focus": "Full Body Strength + Core", "categories": ["Full Body", "Core"]},
        {"type": "Cardio", "focus": "Longer Moderate Cardio", "categories": [], "cardio": True, "cardio_only": True},
        {"type": "Active Recovery", "focus": "Active Recovery", "categories": [], "active_recovery": True},
    ],
    "muscle_gain": [
        {"type": "Workout", "focus": "Push (Chest, Shoulders, Triceps)", "categories": ["Chest", "Shoulders", "Triceps"]},
        {"type": "Workout", "focus": "Pull (Back, Biceps)", "categories": ["Back", "Biceps", "Forearms"]},
        {"type": "Rest", "focus": "Full Rest", "categories": [], "rest": True},
        {"type": "Workout", "focus": "Legs (Quads, Glutes, Hamstrings, Calves)", "categories": ["Legs", "Glutes", "Hamstrings", "Calves"]},
        {"type": "Workout", "focus": "Full Body Hypertrophy + Core", "categories": ["Full Body", "Chest", "Back", "Core"]},
        {"type": "Active Recovery", "focus": "Active Recovery", "categories": [], "active_recovery": True},
        {"type": "Rest", "focus": "Full Rest", "categories": [], "rest": True},
    ],
    "general_fitness": [
        {"type": "Workout", "focus": "Functional Full Body Strength", "categories": ["Full Body"]},
        {"type": "Mobility", "focus": "Mobility & Flexibility", "categories": [], "mobility_day": True},
        {"type": "Workout", "focus": "Cardio + Light Strength", "categories": ["Core"], "cardio": True},
        {"type": "Workout", "focus": "Full Body + Core", "categories": ["Full Body", "Core"]},
        {"type": "Active Recovery", "focus": "Active Recovery", "categories": [], "active_recovery": True},
        {"type": "Workout", "focus": "Cardio + Functional Strength", "categories": ["Legs", "Glutes"], "cardio": True},
        {"type": "Rest", "focus": "Full Rest", "categories": [], "rest": True},
    ],
    "transformation": [
        {"type": "Resistance", "focus": "Upper Body + Core (Recomp)", "categories": ["Chest", "Back", "Shoulders", "Core"]},
        {"type": "Cardio", "focus": "LISS Cardio", "categories": [], "cardio": True, "cardio_only": True},
        {"type": "Resistance", "focus": "Lower Body + Core (Recomp)", "categories": ["Legs", "Glutes", "Core"]},
        {"type": "Cardio", "focus": "LISS Cardio", "categories": [], "cardio": True, "cardio_only": True},
        {"type": "Resistance", "focus": "Full Body + Core", "categories": ["Full Body", "Core"]},
        {"type": "Active Recovery", "focus": "Active Recovery", "categories": [], "active_recovery": True},
        {"type": "Rest", "focus": "Full Rest", "categories": [], "rest": True},
    ],
    "athletic_performance": [
        {"type": "Workout", "focus": "Power + Lower Body", "categories": ["Legs", "Glutes"]},
        {"type": "Cardio", "focus": "Conditioning / Sports Cardio", "categories": [], "cardio": True, "cardio_only": True},
        {"type": "Workout", "focus": "Upper Body Strength", "categories": ["Chest", "Back", "Shoulders"]},
        {"type": "Workout", "focus": "Core + Rotational Power", "categories": ["Core"]},
        {"type": "Workout", "focus": "Full Body Athletic", "categories": ["Full Body"]},
        {"type": "Active Recovery", "focus": "Active Recovery", "categories": [], "active_recovery": True},
        {"type": "Rest", "focus": "Full Rest", "categories": [], "rest": True},
    ],
}

_DIFFICULTY_BY_LEVEL: dict[str, list[str]] = {
    "beginner": ["Beginner"],
    "intermediate": ["Beginner", "Intermediate"],
    "advanced": ["Beginner", "Intermediate", "Advanced"],
}

# ── TIME BUDGET ─────────────────────────────────────────────────────────────
# The user's available_time is a HARD constraint: sections are allocated
# minutes FIRST, then exercises are retrieved to fill exactly the main-work
# remainder — never the other way around (the old code computed duration
# FROM the exercise count, which is how a 10-minute user got 40+ minute
# days). Tiers keyed by session length; a section allocated 0 minutes is
# simply not rendered that day.
#                      warmup mobility stretch breathe cooldown mind_reset
_TIME_TIERS: list[tuple[int, dict[str, int]]] = [
    (12, {"warmup": 1, "mobility": 1, "stretch": 1, "breathing": 1, "cooldown": 0, "mind_reset": 0}),
    (17, {"warmup": 2, "mobility": 1, "stretch": 2, "breathing": 1, "cooldown": 0, "mind_reset": 0}),
    (25, {"warmup": 3, "mobility": 2, "stretch": 2, "breathing": 1, "cooldown": 1, "mind_reset": 0}),
    (35, {"warmup": 4, "mobility": 2, "stretch": 3, "breathing": 2, "cooldown": 2, "mind_reset": 2}),
    (50, {"warmup": 5, "mobility": 3, "stretch": 4, "breathing": 2, "cooldown": 3, "mind_reset": 3}),
    (70, {"warmup": 6, "mobility": 4, "stretch": 5, "breathing": 3, "cooldown": 4, "mind_reset": 3}),
    (999, {"warmup": 8, "mobility": 5, "stretch": 6, "breathing": 4, "cooldown": 5, "mind_reset": 4}),
]
_MINUTES_PER_STRENGTH_EXERCISE = 4   # ~3 sets x (45s work + 45s rest)
_MINUTES_PER_CARDIO_BLOCK = 7        # cardio picks are longer continuous blocks


def allocate_time(total_min: int, high_stress: bool = False) -> dict[str, int]:
    """Split the user's total minutes across workout sections. Returns a
    dict with every section's minutes plus 'main' (the remainder for the
    actual workout). Sum of all values == total_min, always."""
    total_min = max(8, min(int(total_min or 30), 180))
    for cutoff, tier in _TIME_TIERS:
        if total_min <= cutoff:
            alloc = dict(tier)
            break
    if high_stress:
        # Spec: high stress always includes breathing + meditation — steal
        # the minutes from main work, never exceed the total.
        alloc["breathing"] = max(alloc["breathing"], 2)
        alloc["mind_reset"] = max(alloc["mind_reset"], 2)
    alloc["main"] = max(2, total_min - sum(alloc.values()))
    # If the stress top-up overflowed the total, trim overhead back down.
    overflow = sum(alloc.values()) - total_min
    if overflow > 0:
        for k in ("cooldown", "mobility", "stretch", "warmup"):
            take = min(overflow, alloc[k])
            alloc[k] -= take
            overflow -= take
            if overflow <= 0:
                break
    alloc["total"] = total_min
    return alloc

# avoid_ex fields in chronic_condition/recovery_condition/profile_disability/
# profile_senior records are mostly PROSE ("Heavy near-maximal lifting...",
# "High-impact plyometrics (box jumps, jump squats)..."), not exact exercise
# names — only profile_lifestyle's avoid_ex/recommended happen to use exact
# names. Exact-name matching alone would silently exclude nothing for most
# conditions, so every avoid_ex phrase is ALSO scanned for these risk
# keywords and matched against exercise tags/name/category/difficulty —
# same "derive intelligently from what's already tagged" approach as
# enrich_food_dataset.py's diseaseSuitable derivation.
_RISK_KEYWORD_RULES: list[tuple[tuple[str, ...], dict[str, Any]]] = [
    (("heavy near-maximal", "heavy loaded", "heavy spinal loading", "1-3 rep max", "maximal lifting"),
     {"tags": {"power"}, "difficulty": {"Advanced"}}),
    (("high-impact", "high impact", "plyometric", "box jump", "jump squat"),
     {"tags": {"plyometrics", "explosive"}}),
    (("breath-holding", "isometric holds at high effort", "maximal wall sit", "valsalva"),
     {"tags": {"isometric", "power"}}),
    (("sprint", "extended running", "running before"),
     {"name": ("sprint", "running")}),
    (("spinal flexion", "weighted sit-up", "loaded good morning", "flexion-rotation"),
     {"tags": {"rotational"}, "name": ("sit-up", "good morning")}),
    (("fall risk", "rapid, uncontrolled inversion", "balance preparation"),
     {"tags": {"plyometrics", "explosive"}}),
    (("shoulder pain", "shoulder impingement", "labral"),
     {"category": {"Shoulders"}}),
    (("affected knee", "knee range", "knee mobility"),
     {"category": {"Legs"}}),
    (("bouncing", "ballistic stretch"),
     {"tags": {"explosive"}}),
]


def _text_risk_exclusion_ids(engine: "WorkoutRecommendationEngine", phrases: list[str]) -> set[str]:
    combined = " | ".join(_norm(p) for p in phrases)
    exclude_tags: set[str] = set()
    exclude_names: tuple[str, ...] = ()
    exclude_categories: set[str] = set()
    exclude_difficulty: set[str] = set()
    for keywords, rule in _RISK_KEYWORD_RULES:
        if any(kw in combined for kw in keywords):
            exclude_tags |= rule.get("tags", set())
            exclude_names += rule.get("name", ())
            exclude_categories |= rule.get("category", set())
            exclude_difficulty |= rule.get("difficulty", set())

    ids: set[str] = set()
    for t in exclude_tags:
        ids |= engine._idx_tag.get(t, set())
    for c in exclude_categories:
        ids |= engine._idx_category.get(c, set())
    for d in exclude_difficulty:
        ids |= engine._idx_difficulty.get(d, set())
    if exclude_names:
        for e in engine.exercises:
            if any(n in _norm(e.get("name", "")) for n in exclude_names):
                ids.add(e["id"])
    return ids


class WorkoutRecommendationEngine:
    def __init__(self, path: Path = _KB_PATH):
        raw: list[dict] = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
        self.by_type: dict[str, list[dict]] = defaultdict(list)
        for r in raw:
            self.by_type[r.get("record_type", "unknown")].append(r)

        self.exercises: list[dict] = self.by_type["exercise"]
        self.by_id: dict[str, dict] = {e["id"]: e for e in self.exercises if e.get("id")}

        self._idx_category: dict[str, set[str]] = defaultdict(set)
        self._idx_goal: dict[str, set[str]] = defaultdict(set)
        self._idx_tag: dict[str, set[str]] = defaultdict(set)
        self._idx_difficulty: dict[str, set[str]] = defaultdict(set)
        self._name_to_id: dict[str, str] = {}

        for e in self.exercises:
            eid = e.get("id")
            if not eid:
                continue
            self._idx_category[e.get("category") or ""].add(eid)
            for g in e.get("goals", []) or []:
                self._idx_goal[g].add(eid)
            for t in e.get("tags", []) or []:
                self._idx_tag[t].add(eid)
            self._idx_difficulty[e.get("difficulty") or "Beginner"].add(eid)
            self._name_to_id[_norm(e.get("name", ""))] = eid

        # Gym-only exercises by EQUIPMENT STRING (#3). A few KB records are
        # tagged 'home' but their equipment field names a rack/machine
        # ("Barbell in a rack, Smith machine, or TRX") — contradictory data.
        # Trust the stricter signal: anything whose equipment string names
        # gym hardware is hard-excluded for non-gym users, even if tagged home.
        _GYM_KW = ("machine", "smith", "cable", "rack", "barbell", "ez bar",
                   "preacher", "ghd", "leg press", "pulldown", "treadmill",
                   "elliptical", "rower", "dip station")
        self._gym_only_ids: set[str] = {
            e["id"] for e in self.exercises
            if e.get("id") and any(kw in _norm(e.get("equipment") or "") for kw in _GYM_KW)
        }

        # Guidance records keyed by normalized name for fast lookup.
        self._chronic: dict[str, dict] = {_norm(r["name"]): r for r in self.by_type["chronic_condition"]}
        self._recovery: dict[str, dict] = {_norm(r["name"]): r for r in self.by_type["recovery_condition"]}
        self._lifestyle: dict[str, dict] = {_norm(r["name"]): r for r in self.by_type["profile_lifestyle"]}
        self._women: dict[str, dict] = {_norm(r["name"]): r for r in self.by_type["profile_women"]}
        self._disability: dict[str, dict] = {_norm(r["name"]): r for r in self.by_type["profile_disability"]}
        self._senior: dict[str, dict] = {_norm(r["name"]): r for r in self.by_type["profile_senior"]}
        self._kids: dict[str, dict] = {_norm(r["name"]): r for r in self.by_type["profile_kids"]}

        print(f"[WORKOUT ENGINE] Loaded {len(raw)} KB records "
              f"({len(self.exercises)} exercises, {len(self.by_type['warmup'])} warmups, "
              f"{len(self.by_type['mobility'])} mobility, {len(self.by_type['stretch'])} stretches, "
              f"{len(self.by_type['cooldown'])} cooldowns, {len(self.by_type['breathing'])} breathing, "
              f"{len(self.by_type['meditation'])} meditations, {len(self.by_type['yoga'])} yoga, "
              f"{len(self._chronic)} chronic conditions, {len(self._recovery)} recovery conditions)")

    # ── Condition / lifestyle resolution ────────────────────────────────

    @staticmethod
    def resolve_condition_names(medical_conditions_raw: str) -> list[str]:
        """Free-text medical condition -> this KB's chronic_condition names,
        via medical_conditions.detect_conditions() (no re-implementation)."""
        if not medical_conditions.has_medical_condition(medical_conditions_raw):
            return []
        matched = medical_conditions.detect_conditions(medical_conditions_raw)
        names = {_CONDITION_KEY_TO_KB_NAME[k] for k in matched if k in _CONDITION_KEY_TO_KB_NAME}
        for key, kb_name in _EXTRA_CONDITION_ALIASES.items():
            if key in matched:
                names.add(kb_name)
        norm = _norm(medical_conditions_raw)
        for name, keywords in _EXTRA_CONDITION_KEYWORDS.items():
            if any(kw in norm for kw in keywords):
                names.add(name)
        return sorted(names)

    @staticmethod
    def resolve_recovery_condition(free_text: str) -> str | None:
        """Detects an ACUTE 'I'm sick today' / 'injured' mention. Distinct
        from resolve_condition_names() (chronic) — this triggers a
        recovery-only plan for the whole week rather than just excluding
        some exercises."""
        norm = _norm(free_text)
        if not norm:
            return None
        for name, keywords in _RECOVERY_CONDITION_KEYWORDS.items():
            if any(kw in norm for kw in keywords):
                return name
        return None

    @staticmethod
    def resolve_lifestyle_name(living_situation: str, occupation: str = "") -> str | None:
        """Priority: hostel (a strong, distinct environmental constraint —
        no kitchen, shared space, mess timings — with its own KB entry) >
        specific occupation signal (athlete/working professional/homemaker/
        night shift/traveller/remote/parent) > generic student/college.
        Concatenating living_situation+occupation into one string and
        matching dict-iteration order was the previous bug: 'hostel' always
        won over 'athlete' regardless of occupation, AND checking occupation
        before living_situation unconditionally then lost the hostel-
        specific profile for any student who happens to live in a hostel —
        exactly the spec's first example scenario."""
        living_norm = _norm(living_situation)
        occ_norm = _norm(occupation)
        if "hostel" in living_norm or "hostel" in occ_norm:
            return _LIFESTYLE_KB_NAME["hostel"]
        for key in ("athlete", "working_professional", "night_shift", "night shift", "traveller",
                    "traveler", "travel", "homemaker", "home_maker", "busy_parent", "parent",
                    "remote_worker", "remote", "office"):
            if key in occ_norm:
                return _LIFESTYLE_KB_NAME[key]
        for key in ("college", "student"):
            if key in occ_norm or key in living_norm:
                return _LIFESTYLE_KB_NAME[key]
        return None

    def guidance_for(self, bucket: str, name: str) -> dict | None:
        table = getattr(self, "_" + bucket, None)
        return table.get(_norm(name)) if table else None

    def _unsafe_ids_for_condition(self, condition_name: str) -> set[str]:
        rec = self._chronic.get(_norm(condition_name)) or self._disability.get(_norm(condition_name)) \
            or self._senior.get(_norm(condition_name))
        if not rec:
            return set()
        avoid_phrases = rec.get("avoid_ex") or []
        unsafe: set[str] = set()
        for phrase in avoid_phrases:
            eid = self._name_to_id.get(_norm(phrase))
            if eid:
                unsafe.add(eid)
        # Prose-style phrases ("Heavy near-maximal lifting...") don't match
        # any single exercise name — resolve those via risk keywords instead.
        unsafe |= _text_risk_exclusion_ids(self, avoid_phrases)
        return unsafe

    def _preferred_ids_for_condition(self, condition_name: str) -> set[str]:
        rec = self._chronic.get(_norm(condition_name)) or self._disability.get(_norm(condition_name)) \
            or self._senior.get(_norm(condition_name)) or self._women.get(_norm(condition_name)) \
            or self._kids.get(_norm(condition_name))
        if not rec:
            return set()
        preferred: set[str] = set()
        for phrase in (rec.get("recommended") or []):
            eid = self._name_to_id.get(_norm(phrase))
            if eid:
                preferred.add(eid)
        return preferred

    @staticmethod
    def resolve_age_profile_name(age: int) -> str | None:
        if age >= 60:
            return "General Senior Fitness"
        if age <= 8:
            return "Kids Fitness: Ages 5-8"
        if age <= 12:
            return "Kids Fitness: Ages 9-12"
        if age <= 17:
            return "Kids Fitness: Ages 13-17"
        return None

    @staticmethod
    def resolve_disability_name(free_text: str) -> str | None:
        norm = _norm(free_text)
        if not norm:
            return None
        for keywords, name in _DISABILITY_KEYWORDS:
            if any(kw in norm for kw in keywords):
                return name
        return None

    @staticmethod
    def resolve_women_focus_name(gender: str, condition_names: list[str]) -> str | None:
        if _norm(gender) != "female":
            return None
        if any("pcos" in _norm(c) for c in condition_names):
            return "PCOS-Focused Fitness"
        return "General Women's Fitness"

    def _lifestyle_hint_ids(self, lifestyle_name: str | None) -> tuple[set[str], set[str]]:
        if not lifestyle_name:
            return set(), set()
        rec = self._lifestyle.get(_norm(lifestyle_name))
        if not rec:
            return set(), set()
        preferred = {self._name_to_id[_norm(n)] for n in (rec.get("recommended") or []) if _norm(n) in self._name_to_id}
        avoid_phrases = rec.get("avoid_ex") or []
        avoid = {self._name_to_id[_norm(n)] for n in avoid_phrases if _norm(n) in self._name_to_id}
        avoid |= _text_risk_exclusion_ids(self, avoid_phrases)
        return preferred, avoid

    # ── Filtering + scoring ──────────────────────────────────────────────

    def _candidate_ids(
        self,
        categories: list[str],
        kb_goals: list[str],
        equipment_tags: set[str],
        difficulty_levels: list[str],
        unsafe_ids: set[str],
        cardio_only: bool = False,
    ) -> set[str]:
        base = {e["id"] for e in self.exercises if e.get("id")}

        if categories:
            cat_ids: set[str] = set()
            for c in categories:
                cat_ids |= self._idx_category.get(c, set())
            base &= cat_ids
        elif cardio_only:
            cardio_ids = self._idx_tag.get("cardio", set()) | self._idx_tag.get("hiit", set()) | self._idx_tag.get("conditioning", set())
            base &= cardio_ids

        if kb_goals:
            goal_ids: set[str] = set()
            for g in kb_goals:
                goal_ids |= self._idx_goal.get(g, set())
            if base & goal_ids:
                base &= goal_ids

        if equipment_tags:
            # HARD constraint — a home/no-equipment user must never see a
            # bench press. Unconditional intersect; the relaxation ladder in
            # recommend_exercises() relaxes goal/difficulty/category instead,
            # and its last resort is the bodyweight pool, never "any equipment".
            equip_ids: set[str] = set()
            for t in equipment_tags:
                equip_ids |= self._idx_tag.get(t, set())
            base &= equip_ids
            if "gym" not in equipment_tags and "machine" not in equipment_tags:
                base -= self._gym_only_ids

        diff_ids: set[str] = set()
        for d in difficulty_levels:
            diff_ids |= self._idx_difficulty.get(d, set())
        if base & diff_ids:
            base &= diff_ids

        # Medical safety — never relaxed, subtract last.
        base -= unsafe_ids
        return base

    def _score(self, eid: str, preferred_ids: set[str], usage_count: int) -> float:
        pref = 1.0 if eid in preferred_ids else 0.55
        variety = max(0.0, 1.0 - usage_count * 0.4)
        return 0.7 * pref + 0.3 * variety

    def recommend_exercises(
        self,
        categories: list[str],
        kb_goals: list[str],
        equipment_tags: set[str],
        difficulty_levels: list[str],
        unsafe_ids: set[str],
        preferred_ids: set[str],
        usage_counts: dict[str, int],
        top_n: int = 4,
        cardio_only: bool = False,
        variety_seed: str = "",
    ) -> list[dict]:
        ids = self._candidate_ids(categories, kb_goals, equipment_tags, difficulty_levels, unsafe_ids, cardio_only)
        if not ids:
            # Relaxation ladder: goal → difficulty → category. Equipment and
            # medical safety are NEVER relaxed — a filter combination that
            # can't be satisfied within the user's equipment falls through to
            # the always-available bodyweight pool instead.
            ids = self._candidate_ids(categories, [], equipment_tags, difficulty_levels, unsafe_ids, cardio_only)
        if not ids:
            ids = self._candidate_ids(categories, [], equipment_tags, list(_DIFFICULTY_BY_LEVEL["advanced"]), unsafe_ids, cardio_only)
        if not ids and categories:
            ids = self._candidate_ids([], kb_goals, equipment_tags, list(_DIFFICULTY_BY_LEVEL["advanced"]), unsafe_ids, cardio_only)
        if not ids:
            # Bodyweight fallback — safe under every equipment preference.
            bodyweight = self._idx_tag.get("bodyweight", set()) | self._idx_tag.get("no-equipment", set())
            ids = bodyweight - unsafe_ids - self._gym_only_ids

        # Most candidates tie on _score() (few exercises are ever explicitly
        # "preferred" by name — most guidance is prose, not a list of exact
        # names). Without a profile-aware tiebreak, ties fall back to plain
        # alphabetical exercise id — every beginner/home/general-fitness
        # profile would then pick the exact same top-N regardless of medical
        # condition, age, or gender. Tiebreaking on a stable hash of
        # (id, variety_seed) instead means different profiles land on
        # different-but-reproducible selections among equally-safe options.
        scored = sorted(ids, key=lambda i: (-self._score(i, preferred_ids, usage_counts.get(i, 0)), _stable_tiebreak(i, variety_seed)))
        return [self.by_id[i] for i in scored[:top_n]]

    def _pick_one(self, record_type: str, difficulty_levels: list[str], usage_counts: dict[str, int], tag_hint: str | None = None) -> dict | None:
        pool = self.by_type.get(record_type, [])
        if not pool:
            return None
        candidates = [r for r in pool if (r.get("difficulty") or "Beginner") in difficulty_levels] or pool
        if tag_hint:
            tagged = [r for r in candidates if tag_hint in (r.get("tags") or [])]
            if tagged:
                candidates = tagged
        candidates = sorted(candidates, key=lambda r: usage_counts.get(r.get("id", r.get("name")), 0))
        pick = candidates[0]
        key = pick.get("id", pick.get("name"))
        usage_counts[key] = usage_counts.get(key, 0) + 1
        return pick

    # ── Public: full week builder ───────────────────────────────────────

    def build_week_plan(
        self,
        fitness_goal: str,
        difficulty_levels: list[str],
        equipment_tags: set[str],
        condition_names: list[str],
        lifestyle_name: str | None,
        high_stress: bool = False,
        exercises_per_workout: int | None = None,  # legacy override; None → derived from available_time
        available_time: int = 30,
        disliked_exercises: list[str] | None = None,
        equipment_label: str = "",
        level_label: str = "",
    ) -> dict[str, Any]:
        """Deterministic 7-day plan sourced entirely from the KB. Every
        exercise/warm-up/mobility/stretch/cooldown/breathing/meditation pick
        is a real KB record — see module docstring for the firewall this
        feeds into on the groq_service/routes/assessment.py side.

        available_time is a HARD budget: allocate_time() splits it across
        sections first, and the exercise count is whatever fits inside the
        main-work remainder — a 10-minute user gets a 10-minute day, always."""
        template = _WEEKLY_TEMPLATES.get(fitness_goal, _WEEKLY_TEMPLATES["general_fitness"])
        alloc = allocate_time(available_time, high_stress)

        unsafe_ids: set[str] = set()
        preferred_ids: set[str] = set()
        for name in condition_names:
            unsafe_ids |= self._unsafe_ids_for_condition(name)
            preferred_ids |= self._preferred_ids_for_condition(name)
        life_preferred, life_avoid = self._lifestyle_hint_ids(lifestyle_name)
        preferred_ids |= life_preferred
        unsafe_ids |= life_avoid

        # User preference memory (#13): exercises the athlete repeatedly
        # skips are excluded exactly like a medical exclusion — by name.
        for name in disliked_exercises or []:
            eid = self._name_to_id.get(_norm(name))
            if eid:
                unsafe_ids.add(eid)

        kb_goals = _GOAL_TO_KB_GOALS.get(fitness_goal, ["General Fitness"])
        usage_counts: dict[str, int] = defaultdict(int)
        section_usage: dict[str, int] = defaultdict(int)
        variety_seed = "|".join([fitness_goal, lifestyle_name or "", *sorted(condition_names), *sorted(equipment_tags)])

        # The "why this exercise" context — every constraint the pick already
        # satisfies, phrased once and reused (#10 Explanations).
        why_parts = [fitness_goal.replace("_", " ").title() + " goal",
                     f"{alloc['total']}-minute session"]
        if equipment_label:
            why_parts.append(equipment_label + " equipment")
        if level_label:
            why_parts.append(level_label.title() + " level")
        if condition_names:
            why_parts.append("safe for " + ", ".join(condition_names))
        why_context = ", ".join(why_parts)

        n_strength = exercises_per_workout or max(1, alloc["main"] // _MINUTES_PER_STRENGTH_EXERCISE)
        n_cardio = max(1, alloc["main"] // _MINUTES_PER_CARDIO_BLOCK)

        days = []
        for i, day_name in enumerate(_DAY_NAMES):
            slot = template[i % len(template)]

            if slot.get("rest"):
                days.append({
                    "day": day_name, "type": "Rest", "focus": "Full Rest", "duration_minutes": 0,
                    "exercises": [], "warmup": None, "mobility": None, "stretching": None,
                    "cooldown": None, "breathing": None, "mind_reset": None,
                    "daily_tip": "Rest is part of the programme, not a break from it — muscle repair and adaptation happen today.",
                })
                continue

            warmup = self._pick_one("warmup", difficulty_levels, section_usage) if alloc["warmup"] else None
            breathing = (self._pick_one("breathing", difficulty_levels, section_usage,
                                        tag_hint="stress-relief" if high_stress else None)
                         if alloc["breathing"] else None)
            meditation = self._pick_one("meditation", difficulty_levels, section_usage) if alloc["mind_reset"] else None
            cooldown = self._pick_one("cooldown", difficulty_levels, section_usage) if alloc["cooldown"] else None
            mobility = self._pick_one("mobility", difficulty_levels, section_usage) if alloc["mobility"] else None
            stretching = []
            if alloc["stretch"]:
                stretch1 = self._pick_one("stretch", difficulty_levels, section_usage)
                stretch2 = self._pick_one("stretch", difficulty_levels, section_usage) if (high_stress and alloc["stretch"] >= 3) else None
                stretching = [s for s in (stretch1, stretch2) if s]

            if slot.get("active_recovery"):
                days.append({
                    "day": day_name, "type": "Active Recovery", "focus": slot["focus"],
                    "duration_minutes": min(alloc["total"], 20),
                    "exercises": [],
                    "warmup": _kb_ref(warmup, alloc["warmup"]), "mobility": _kb_ref(mobility, alloc["mobility"]),
                    "stretching": [_kb_ref(s, alloc["stretch"]) for s in stretching],
                    "cooldown": _kb_ref(cooldown, alloc["cooldown"]),
                    "breathing": _kb_ref(breathing, alloc["breathing"]), "mind_reset": _kb_ref(meditation, alloc["mind_reset"]),
                    "daily_tip": "Easy movement today speeds recovery more than sitting completely still.",
                })
                continue

            is_cardio_day = slot.get("cardio_only", False)
            n_main = n_cardio if is_cardio_day else n_strength
            day_seed = f"{variety_seed}|{day_name}"
            main = self.recommend_exercises(
                categories=slot["categories"], kb_goals=kb_goals, equipment_tags=equipment_tags,
                difficulty_levels=difficulty_levels, unsafe_ids=unsafe_ids, preferred_ids=preferred_ids,
                usage_counts=usage_counts, top_n=n_main, cardio_only=is_cardio_day,
                variety_seed=day_seed,
            )
            for e in main:
                usage_counts[e["id"]] += 1

            # Accessory work only when the time budget actually has room for
            # it (2 extra exercises ≈ 8 minutes of main-block time).
            accessory = []
            if not is_cardio_day and len(main) >= 2 and alloc["main"] >= (n_strength + 2) * _MINUTES_PER_STRENGTH_EXERCISE - 2:
                accessory_categories = [c for c in ["Core", "Full Body"] if c not in slot["categories"]] or slot["categories"]
                accessory = self.recommend_exercises(
                    categories=accessory_categories, kb_goals=kb_goals, equipment_tags=equipment_tags,
                    difficulty_levels=difficulty_levels, unsafe_ids=unsafe_ids | {e["id"] for e in main},
                    preferred_ids=preferred_ids, usage_counts=usage_counts, top_n=2,
                    variety_seed=day_seed + "|accessory",
                )
                for e in accessory:
                    usage_counts[e["id"]] += 1

            per_ex_minutes = max(1, alloc["main"] // max(1, len(main) + len(accessory)))
            exercises = [_exercise_to_plan_item(e, is_accessory=False, time_minutes=per_ex_minutes, why_context=why_context) for e in main] + \
                        [_exercise_to_plan_item(e, is_accessory=True, time_minutes=per_ex_minutes, why_context=why_context) for e in accessory]

            days.append({
                "day": day_name, "type": slot["type"], "focus": slot["focus"],
                "duration_minutes": alloc["total"],
                "time_allocation": {k: v for k, v in alloc.items() if k != "total" and v},
                "exercises": exercises,
                "warmup": _kb_ref(warmup, alloc["warmup"]), "mobility": _kb_ref(mobility, alloc["mobility"]),
                "stretching": [_kb_ref(s, alloc["stretch"]) for s in stretching],
                "cooldown": _kb_ref(cooldown, alloc["cooldown"]),
                "breathing": _kb_ref(breathing, alloc["breathing"]), "mind_reset": _kb_ref(meditation, alloc["mind_reset"]),
                "daily_tip": None,
            })

        return {"days": days, "time_allocation": alloc, "why_context": why_context}

    def build_recovery_week(self, recovery_condition_name: str, high_stress: bool = False) -> dict[str, Any]:
        """'I'm sick today' / 'injured' override — recovery breathing +
        gentle stretch + light mobility only, explicitly no main/accessory
        strength work, for the whole week (spec: 'no heavy exercises')."""
        rec = self._recovery.get(_norm(recovery_condition_name)) or {}
        usage_counts: dict[str, int] = defaultdict(int)
        days = []
        for day_name in _DAY_NAMES:
            breathing = self._pick_one("breathing", ["Beginner"], usage_counts)
            meditation = self._pick_one("meditation", ["Beginner"], usage_counts)
            mobility = self._pick_one("mobility", ["Beginner"], usage_counts)
            stretch = self._pick_one("stretch", ["Beginner"], usage_counts)
            days.append({
                "day": day_name, "type": "Recovery", "focus": f"{recovery_condition_name} — Recovery Day",
                "duration_minutes": 15, "exercises": [],
                "warmup": None, "mobility": _kb_ref(mobility), "stretching": [_kb_ref(stretch)],
                "cooldown": None, "breathing": _kb_ref(breathing), "mind_reset": _kb_ref(meditation),
                "daily_tip": (rec.get("modification") or ["Rest and let your body recover — light movement only."])[0],
            })
        return {
            "days": days,
            "recovery_notice": rec.get("overview") or f"Recovery mode active for {recovery_condition_name}.",
            "red_flags": rec.get("red_flags") or [],
            "resume_guidance": rec.get("resume") or [],
        }


def _kb_ref(rec: dict | None, minutes: int = 0) -> dict | None:
    if not rec:
        return None
    return {
        "name": rec.get("name"),
        "steps": rec.get("steps") or [],
        "duration": (f"{minutes} min" if minutes else "") or rec.get("dose") or rec.get("duration") or rec.get("target") or "",
        "allocated_minutes": minutes or None,
        "breathing": rec.get("breathing"),
        "id": rec.get("id"),
    }


def _exercise_to_plan_item(e: dict, is_accessory: bool, time_minutes: int = 0, why_context: str = "") -> dict[str, Any]:
    why = f"Targets {e.get('primary', 'this muscle group')}"
    if why_context:
        why += f" — chosen to match your {why_context}."
    else:
        why += " — matched to your goal, equipment, and safety profile."
    return {
        "name": e["name"],
        "exercise_id": e["id"],
        "sets": e.get("sets") or "3",
        "reps_or_duration": e.get("reps") or "10-12 reps",
        "rest_seconds": _parse_rest_seconds(e.get("rest")),
        "time_minutes": time_minutes or None,
        "tip": (e.get("tips") or [""])[0] or "Focus on controlled form over speed.",
        "why_selected": why,
        "progression": e.get("progression") or "",
        "is_accessory": is_accessory,
        "category": e.get("category"),
    }


def _parse_rest_seconds(rest: str | None) -> int:
    if not rest:
        return 60
    import re
    nums = re.findall(r"\d+", rest)
    return int(nums[0]) if nums else 60


def difficulty_levels_for(fitness_level: str) -> list[str]:
    return _DIFFICULTY_BY_LEVEL.get(_norm(fitness_level), _DIFFICULTY_BY_LEVEL["intermediate"])


def equipment_tags_for(workout_preference: str, living_situation: str = "") -> set[str]:
    key = _norm(workout_preference)
    if "hostel" in _norm(living_situation):
        return _EQUIPMENT_TAGS_FROM_PREFERENCE["hostel"]
    return _EQUIPMENT_TAGS_FROM_PREFERENCE.get(key, _EQUIPMENT_TAGS_FROM_PREFERENCE["mixed"])


_GOAL_TOP_LEVEL_FIELDS: dict[str, str] = {
    # fitness_goal -> the extra top-level field name each existing system
    # prompt schema in routes/assessment.py already uses (kept so the
    # frontend/other readers see the exact same shape as before).
    "weight_loss": "weekly_calorie_burn_est",
    "general_fitness": "weekly_calorie_burn_est",
    "transformation": "weekly_calorie_burn_est",
    "athletic_performance": "weekly_calorie_burn_est",
    "muscle_gain": "weekly_training_volume_sets",
}


def format_week_for_output(week_plan: dict, fitness_goal: str, llm_parsed: dict | None) -> dict[str, Any]:
    """Hallucination firewall for workouts — same pattern as groq_service.
    _apply_engine_foods(): the LLM (if it ran) may supply plan_name/summary/
    daily_tip text, but every exercise/warmup/mobility/stretch/cooldown/
    breathing/mind_reset value is always the engine's, regardless of what
    the LLM returned. Reshapes into the EXACT existing per-goal schema
    (weekly_plan/day/type/focus/duration_minutes/exercises/daily_tip, plus
    that goal's own extra top-level field) so nothing downstream changes."""
    llm_parsed = llm_parsed or {}
    llm_days = llm_parsed.get("weekly_plan") if isinstance(llm_parsed.get("weekly_plan"), list) else []

    weekly_plan = []
    total_kcal = 0.0
    total_sets = 0
    for i, day in enumerate(week_plan["days"]):
        llm_day = llm_days[i] if i < len(llm_days) and isinstance(llm_days[i], dict) else {}
        day_kcal = 0.0
        for ex in day["exercises"]:
            src = get_engine().by_id.get(ex["exercise_id"])
            kcal_min = (src or {}).get("kcal_min") or 4.0
            day_kcal += kcal_min * (day["duration_minutes"] / max(1, len(day["exercises"]) or 1))
            try:
                total_sets += int(str(ex["sets"]).split("-")[0])
            except (ValueError, IndexError):
                pass
        total_kcal += day_kcal

        weekly_plan.append({
            "day": day["day"],
            "type": day["type"],
            "focus": day["focus"],
            "duration_minutes": day["duration_minutes"],
            "time_allocation": day.get("time_allocation"),
            "calories_burned_est": round(day_kcal) if day["exercises"] else 0,
            "exercises": day["exercises"],
            "warmup": day["warmup"],
            "mobility": day["mobility"],
            "stretching": day["stretching"],
            "cooldown": day["cooldown"],
            "breathing": day["breathing"],
            "mind_reset": day["mind_reset"],
            "daily_tip": (llm_day.get("daily_tip") or "").strip() or day.get("daily_tip") or
                         "Consistency beats intensity — showing up today is the win.",
        })

    result: dict[str, Any] = {
        "plan_name": (llm_parsed.get("plan_name") or "").strip() or f"7-Day {fitness_goal.replace('_', ' ').title()} Plan",
        "weekly_frequency": f"{sum(1 for d in weekly_plan if d['type'] not in ('Rest',))} days/week",
        "weekly_plan": weekly_plan,
        "summary": (llm_parsed.get("summary") or "").strip() or (
            "Every exercise below comes from the ZITLAS verified workout knowledge base, matched to "
            "your goal, equipment, experience level, and any medical conditions you've shared."
        ),
        # #10 Explanations — one concise, deterministic sentence stating the
        # constraints every pick in this plan already satisfies.
        "personalization_note": ("This plan matches your " + week_plan["why_context"] + ".")
                                 if week_plan.get("why_context") else None,
        # #7 Progressive overload — deterministic week-over-week guidance
        # (per-exercise `progression` from the KB gives the specific move).
        "progression_plan": {
            "week_2": "Add 1-2 reps to each strength exercise, or 2-3 minutes to cardio blocks.",
            "week_3": "Add one set to your two hardest exercises, or use each exercise's progression variation.",
            "week_4": "Swap 1-2 exercises for their harder progression (listed on each exercise), then deload lightly next week.",
        },
    }
    extra_field = _GOAL_TOP_LEVEL_FIELDS.get(fitness_goal, "weekly_calorie_burn_est")
    result[extra_field] = total_sets if extra_field == "weekly_training_volume_sets" else round(total_kcal)
    if fitness_goal in ("muscle_gain", "transformation"):
        result["training_split"] = (llm_parsed.get("training_split") or "").strip() or "Push / Pull / Legs + Core"
    if fitness_goal in ("weight_loss", "general_fitness"):
        result["fitness_level"] = llm_parsed.get("fitness_level") or "Intermediate"
    return result


def format_recovery_for_output(recovery_plan: dict, condition_name: str) -> dict[str, Any]:
    weekly_plan = [{
        "day": d["day"], "type": d["type"], "focus": d["focus"], "duration_minutes": d["duration_minutes"],
        "calories_burned_est": 0, "exercises": [],
        "warmup": d["warmup"], "mobility": d["mobility"], "stretching": d["stretching"],
        "cooldown": d["cooldown"], "breathing": d["breathing"], "mind_reset": d["mind_reset"],
        "daily_tip": d["daily_tip"],
    } for d in recovery_plan["days"]]
    return {
        "plan_name": f"{condition_name} — Recovery Week",
        "fitness_level": "Beginner",
        "weekly_frequency": "0 days/week (recovery mode)",
        "weekly_plan": weekly_plan,
        "weekly_calorie_burn_est": 0,
        "summary": recovery_plan["recovery_notice"],
        "recovery_mode": True,
        "red_flags": recovery_plan["red_flags"],
        "resume_guidance": recovery_plan["resume_guidance"],
    }


# ── Lazy singleton — loaded once, shared by every request ──────────────────
_engine: WorkoutRecommendationEngine | None = None
_engine_lock = threading.Lock()


def get_engine() -> WorkoutRecommendationEngine:
    global _engine
    if _engine is None:
        with _engine_lock:
            if _engine is None:
                _engine = WorkoutRecommendationEngine()
    return _engine
