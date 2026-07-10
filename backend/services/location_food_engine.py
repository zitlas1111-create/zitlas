"""
ZITLAS — Location-Aware Food Intelligence (backend/services/location_food_engine.py)

Adds a REGION dimension on top of the existing FoodRecommendationEngine
(services/food_engine.py). This module never loads a second food dataset
and never runs its own retrieval — it only maps a user's city/state to a
RegionProfile (dataset categories + real dish-name keywords already present
in food_dataset/zitlas_food_database_enriched.json) and hands that back as
a "boost" dict. The caller (groq_service._engine_query_context /
routes/assessment._generate_diet_plan) folds that boost into food_engine's
EXISTING preferredCategories / favorite_foods mechanisms — so location can
only ever re-rank or re-prioritize foods that were already going to pass
the medical/allergy/diet pipeline. It cannot bypass a hard filter and it
cannot introduce a food that isn't already in the dataset.

Coverage note: every keyword below was checked against the live dataset
before being added — a dish only appears here if a real dataset food name
contains it (e.g. "Poha", "Misal Pav", "Rajma Chawal"). Some named dishes
from the original regional spec (Tambda/Pandhra Rassa, Matki Usal, Saoji,
Tarri Poha, Muri, Luchi, Bamboo Shoot) have no match in the current 4500-
food dataset and are intentionally NOT included as keywords — inventing a
tag for a dish the engine can't actually retrieve would silently produce no
effect at best and a misleading explanation at worst. Regions without a
dedicated dataset category (Kerala/Tamil Nadu share the single "South
Indian Foods" category; West Bengal/Northeast have no dedicated category at
all) fall back to the closest general category plus whatever keyword
matches genuinely exist, rather than fabricating a category.

Fallback chain (STEP 12 of the spec): resolve_region() takes city AND state
AND falls back gracefully at every step — no match found simply returns
None, and every caller already treats a None boost as "behave exactly like
today" (no location signal at all). Nothing here can make food selection
fail; at worst it's a no-op.
"""

from __future__ import annotations


def _norm(s: str) -> str:
    return (s or "").strip().lower()


class RegionProfile:
    __slots__ = ("key", "label", "categories", "keywords")

    def __init__(self, key: str, label: str, categories: list[str], keywords: list[str]):
        self.key = key
        self.label = label
        self.categories = categories
        self.keywords = keywords


# ── Region definitions ──────────────────────────────────────────────────────
# categories: real food_dataset "category" values to add to preferredCategories.
# keywords:   real dataset food-name substrings to add to favorite_foods (the
#             existing scoring mechanism already boosts any food whose name
#             contains a favorite_foods entry — see food_engine._score()).
_REGIONS: dict[str, RegionProfile] = {
    "maharashtra_pune": RegionProfile(
        "maharashtra_pune", "Pune, Maharashtra",
        ["Maharashtrian Foods", "Street Foods"],
        ["poha", "misal pav", "vada pav", "sabudana khichdi", "bhakri", "solkadhi"],
    ),
    "maharashtra_kolhapur": RegionProfile(
        "maharashtra_kolhapur", "Kolhapur, Maharashtra",
        ["Maharashtrian Foods"],
        ["bhakri", "solkadhi", "poha", "misal pav"],
    ),
    "maharashtra_nagpur": RegionProfile(
        "maharashtra_nagpur", "Nagpur, Maharashtra",
        ["Maharashtrian Foods"],
        ["poha", "misal pav", "vada pav"],
    ),
    "maharashtra_general": RegionProfile(
        "maharashtra_general", "Maharashtra",
        ["Maharashtrian Foods", "Street Foods"],
        ["poha", "misal pav", "vada pav", "sabudana khichdi", "bhakri"],
    ),
    "delhi": RegionProfile(
        "delhi", "Delhi",
        ["North Indian Foods", "Punjabi Foods", "Street Foods"],
        ["rajma", "chole", "paratha"],
    ),
    "north_general": RegionProfile(
        "north_general", "North India",
        ["North Indian Foods", "Punjabi Foods"],
        ["rajma", "chole", "paratha"],
    ),
    "punjab": RegionProfile(
        "punjab", "Punjab",
        ["Punjabi Foods", "North Indian Foods"],
        ["lassi", "sarson ka saag", "makki", "paratha"],
    ),
    "south_general": RegionProfile(
        "south_general", "South India",
        ["South Indian Foods"],
        ["idli", "dosa", "sambar", "upma", "ragi"],
    ),
    "kerala": RegionProfile(
        "kerala", "Kerala",
        ["South Indian Foods"],
        ["appam", "puttu", "fish curry", "coconut water"],
    ),
    "tamil_nadu": RegionProfile(
        "tamil_nadu", "Tamil Nadu",
        ["South Indian Foods"],
        ["curd rice", "pongal", "lemon rice", "idli", "dosa"],
    ),
    "gujarat": RegionProfile(
        "gujarat", "Gujarat",
        ["Gujarati Foods"],
        ["thepla", "khakhra", "handvo"],
    ),
    "west_bengal": RegionProfile(
        "west_bengal", "West Bengal",
        ["Fish & Seafood"],
        ["fish curry"],
    ),
    "northeast": RegionProfile(
        "northeast", "North-East India",
        ["Fish & Seafood", "Vegetables"],
        ["fish curry"],
    ),
}

# Normalized city/district name -> region key. Extend this table as new
# cities come up — it's a pure lookup, nothing downstream needs to change.
_CITY_TO_REGION: dict[str, str] = {
    "pune": "maharashtra_pune",
    "pimpri": "maharashtra_pune", "pimpri-chinchwad": "maharashtra_pune",
    "kolhapur": "maharashtra_kolhapur",
    "nagpur": "maharashtra_nagpur",
    "mumbai": "maharashtra_general", "thane": "maharashtra_general",
    "nashik": "maharashtra_general", "aurangabad": "maharashtra_general",
    "solapur": "maharashtra_general",
    "delhi": "delhi", "new delhi": "delhi", "gurugram": "delhi", "gurgaon": "delhi", "noida": "delhi",
    "faridabad": "delhi", "ghaziabad": "delhi",
    "amritsar": "punjab", "ludhiana": "punjab", "jalandhar": "punjab",
    "patiala": "punjab", "chandigarh": "punjab", "mohali": "punjab",
    "lucknow": "north_general", "kanpur": "north_general", "agra": "north_general",
    "jaipur": "north_general", "bhopal": "north_general", "indore": "north_general",
    "chennai": "tamil_nadu", "coimbatore": "tamil_nadu", "madurai": "tamil_nadu",
    "trichy": "tamil_nadu", "tiruchirappalli": "tamil_nadu",
    "kochi": "kerala", "cochin": "kerala", "thiruvananthapuram": "kerala",
    "trivandrum": "kerala", "kozhikode": "kerala", "calicut": "kerala",
    "bengaluru": "south_general", "bangalore": "south_general",
    "hyderabad": "south_general", "secunderabad": "south_general",
    "visakhapatnam": "south_general", "vijayawada": "south_general",
    "ahmedabad": "gujarat", "surat": "gujarat", "vadodara": "gujarat",
    "rajkot": "gujarat", "gandhinagar": "gujarat",
    "kolkata": "west_bengal", "howrah": "west_bengal", "durgapur": "west_bengal",
    "guwahati": "northeast", "shillong": "northeast", "imphal": "northeast",
    "agartala": "northeast", "aizawl": "northeast", "itanagar": "northeast",
    "kohima": "northeast", "gangtok": "northeast",
}

# Normalized state name -> region key. Used when the city isn't in the table
# above but the state is known (a coarser but still useful signal).
_STATE_TO_REGION: dict[str, str] = {
    "maharashtra": "maharashtra_general",
    "delhi": "delhi", "nct of delhi": "delhi", "haryana": "delhi",
    "punjab": "punjab",
    "uttar pradesh": "north_general", "madhya pradesh": "north_general",
    "rajasthan": "north_general", "bihar": "north_general",
    "tamil nadu": "tamil_nadu", "puducherry": "tamil_nadu",
    "kerala": "kerala",
    "karnataka": "south_general", "telangana": "south_general", "andhra pradesh": "south_general",
    "gujarat": "gujarat",
    "west bengal": "west_bengal",
    "assam": "northeast", "meghalaya": "northeast", "manipur": "northeast",
    "tripura": "northeast", "mizoram": "northeast", "arunachal pradesh": "northeast",
    "nagaland": "northeast", "sikkim": "northeast",
}


def resolve_region(location: dict | None) -> RegionProfile | None:
    """city -> state -> None. `location` is whatever shape the frontend
    saved (city/district/state/country) — every key is optional."""
    if not location:
        return None
    city = _norm(location.get("city") or location.get("district") or "")
    if city:
        key = _CITY_TO_REGION.get(city)
        if key:
            return _REGIONS[key]
    state = _norm(location.get("state") or "")
    if state:
        key = _STATE_TO_REGION.get(state)
        if key:
            return _REGIONS[key]
    return None


# ── Healthy-local-alternative guidance (STEP 6) ─────────────────────────────
# Keyed by dish keyword, not by region — the same dish gets the same tip
# regardless of which region surfaced it. Applied as guidance TEXT (a coach
# tip / prompt instruction), never as a silent substitution — the spec asks
# to make regional foods healthier, not replace them with something else.
_HEALTHY_SWAP_TIPS: dict[str, str] = {
    "vada pav": "ask for it baked or with less oil, go light on the chutney, and pair it with buttermilk or curd.",
    "misal pav": "ask for less oil on top and extra usal/sprouts for protein and fibre.",
    "poha": "add a spoon of roasted peanuts or sprouts for extra protein.",
    "paratha": "go easy on the ghee/butter and pair it with curd instead of extra oil.",
    "chole": "pair it with roti instead of fried bhature, and keep the gravy light on oil.",
    "idli": "double up on the sambar and coconut chutney portion for more protein and fibre.",
    "dosa": "choose a plain or vegetable-stuffed dosa over the butter/ghee-roast version.",
    "lassi": "pick the less-sweet or low-fat version if it's available.",
}


def healthy_swap_tip(food_name: str) -> str | None:
    name_lc = _norm(food_name)
    for keyword, tip in _HEALTHY_SWAP_TIPS.items():
        if keyword in name_lc:
            return tip
    return None


def build_region_boost(location: dict | None) -> dict | None:
    """The one call the rest of the app needs. Returns None when there's no
    usable location signal (fallback chain ends here — callers already treat
    None as a no-op, i.e. today's unchanged behavior), or:

        {
          "region_label":        "Pune, Maharashtra",
          "preferred_categories": [...],   # -> merge into profile.preferredCategories
          "preferred_keywords":   [...],   # -> merge into favorite_foods
          "explanation":          "Because you're in Pune, ...",
        }
    """
    region = resolve_region(location)
    if region is None:
        return None
    return {
        "region_label": region.label,
        "preferred_categories": list(region.categories),
        "preferred_keywords": list(region.keywords),
        "explanation": (
            f"Because you're in {region.label}, these meals lean on foods that are "
            "easy to find nearby, culturally familiar, and fit your calorie target."
        ),
    }
