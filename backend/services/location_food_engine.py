"""
ZITLAS — Location-Aware Food Intelligence (backend/services/location_food_engine.py)

Adds a REGION dimension on top of the existing FoodRecommendationEngine
(services/food_engine.py). This module never loads a second food dataset
and never runs its own retrieval — it only maps a user's city/state to a
canonical state name and asks food_engine (via foods_by_state /
regional_categories_for_state, which read the state_of_origin/region fields
enrich_food_dataset_v2.py added to every food) which real dataset foods and
categories are associated with that state. The caller (groq_service._engine_
query_context / routes/assessment._generate_diet_plan) folds the result into
food_engine's EXISTING preferredCategories / favorite_foods mechanisms — so
location can only ever re-rank or re-prioritize foods that were already going
to pass the medical/allergy/diet pipeline. It cannot bypass a hard filter and
it cannot introduce a food that isn't already in the dataset.

DATA-DRIVEN, not hand-typed (STEP 5/11 of the enrichment spec): the previous
version of this module carried a small hand-picked dictionary of ~13 regions
with manually chosen dish keywords. That dictionary could only ever cover the
regions someone remembered to add. This version instead queries the dataset
itself, so coverage is exactly as wide as enrich_food_dataset_v2.py's verified
regional-dish tagging and grows automatically as that tagging grows — no code
change needed here to pick up a newly-tagged state.

Honest fallback: a handful of states/UTs have no verified regional-dish match
in the current 4500-food dataset (see enrich_food_dataset_v2.py's own coverage
notes — e.g. Uttarakhand, Chhattisgarh, Odisha, Assam, Meghalaya, Nagaland,
Manipur, Tripura, Mizoram). For those, foods_by_state() legitimately returns
an empty list, and build_region_boost() returns None rather than fabricating
a boost — every caller already treats None as "behave exactly like today"
(Pan-India staples continue to dominate, which is the correct default).
"""

from __future__ import annotations

from services import food_engine


def _norm(s: str) -> str:
    return (s or "").strip().lower()


# ── Geography lookup tables (pure geography — kept as hand-typed data since
# city/district -> state is not something the food dataset encodes at all).
# Values are canonical state names EXACTLY as they appear in the dataset's
# state_of_origin field (see enrich_food_dataset_v2.py's REGIONAL_DISHES /
# CATEGORY_REGION tables) — that string is the key food_engine indexes on.

_CITY_TO_STATE: dict[str, str] = {
    "pune": "Maharashtra", "pimpri": "Maharashtra", "pimpri-chinchwad": "Maharashtra",
    "kolhapur": "Maharashtra", "nagpur": "Maharashtra", "mumbai": "Maharashtra",
    "thane": "Maharashtra", "nashik": "Maharashtra", "aurangabad": "Maharashtra",
    "solapur": "Maharashtra",
    "delhi": "Delhi", "new delhi": "Delhi",
    "gurugram": "Haryana", "gurgaon": "Haryana", "faridabad": "Haryana",
    "noida": "Uttar Pradesh", "ghaziabad": "Uttar Pradesh",
    "amritsar": "Punjab", "ludhiana": "Punjab", "jalandhar": "Punjab",
    "patiala": "Punjab", "chandigarh": "Punjab", "mohali": "Punjab",
    "lucknow": "Uttar Pradesh", "kanpur": "Uttar Pradesh", "agra": "Uttar Pradesh",
    "varanasi": "Uttar Pradesh",
    "jaipur": "Rajasthan", "jodhpur": "Rajasthan", "udaipur": "Rajasthan",
    "bhopal": "Madhya Pradesh", "indore": "Madhya Pradesh", "jabalpur": "Madhya Pradesh",
    "chennai": "Tamil Nadu", "coimbatore": "Tamil Nadu", "madurai": "Tamil Nadu",
    "trichy": "Tamil Nadu", "tiruchirappalli": "Tamil Nadu",
    "kochi": "Kerala", "cochin": "Kerala", "thiruvananthapuram": "Kerala",
    "trivandrum": "Kerala", "kozhikode": "Kerala", "calicut": "Kerala",
    "bengaluru": "Karnataka", "bangalore": "Karnataka", "mysuru": "Karnataka", "mysore": "Karnataka",
    "hyderabad": "Telangana", "secunderabad": "Telangana", "warangal": "Telangana",
    "visakhapatnam": "Andhra Pradesh", "vijayawada": "Andhra Pradesh", "vizag": "Andhra Pradesh",
    "ahmedabad": "Gujarat", "surat": "Gujarat", "vadodara": "Gujarat",
    "rajkot": "Gujarat", "gandhinagar": "Gujarat",
    "kolkata": "West Bengal", "howrah": "West Bengal", "durgapur": "West Bengal",
    "patna": "Bihar", "gaya": "Bihar",
    "ranchi": "Jharkhand", "jamshedpur": "Jharkhand",
    "panaji": "Goa", "margao": "Goa",
    "srinagar": "Jammu & Kashmir", "jammu": "Jammu & Kashmir",
    "leh": "Ladakh",
    "shimla": "Himachal Pradesh", "manali": "Himachal Pradesh",
    "gangtok": "Sikkim",
    "itanagar": "Arunachal Pradesh",
    "guwahati": "Assam", "dispur": "Assam",
    "shillong": "Meghalaya",
    "imphal": "Manipur",
    "agartala": "Tripura",
    "aizawl": "Mizoram",
    "kohima": "Nagaland",
    "dehradun": "Uttarakhand", "haridwar": "Uttarakhand",
    "raipur": "Chhattisgarh",
    "bhubaneswar": "Odisha", "cuttack": "Odisha",
}

# Normalized state-name variants -> canonical dataset spelling. Anything not
# listed here is assumed to already match the canonical spelling once
# normalized (most assessment `state` values will).
_STATE_ALIASES: dict[str, str] = {
    "jammu and kashmir": "Jammu & Kashmir", "jammu & kashmir": "Jammu & Kashmir",
    "j&k": "Jammu & Kashmir", "jk": "Jammu & Kashmir",
    "nct of delhi": "Delhi", "delhi ncr": "Delhi", "ncr": "Delhi",
    "orissa": "Odisha",
    "pondicherry": "Puducherry",
    "uttaranchal": "Uttarakhand",
}

# Canonical -> normalized, for matching a canonical-cased alias value back.
_CANONICAL_NORM_TO_NAME: dict[str, str] = {}
for _v in set(_CITY_TO_STATE.values()) | set(_STATE_ALIASES.values()):
    _CANONICAL_NORM_TO_NAME[_norm(_v)] = _v


# ── State -> dataset zone (STEP: availability GATING, not just boost) ──────
# The dataset's own `region` field (enrich_food_dataset_v2.py) uses exactly
# these 6 zone labels (verified against the live dataset: West/Pan-India/
# South/North/East/Northeast/Central all appear). This table is pure
# geography (India's standard zonal classification) — it does not invent
# any food metadata, it only tells us which of the dataset's OWN region
# labels count as "this user's zone" so `compatible_regions()` below can
# build the eligibility set food_engine filters candidates against.
_STATE_TO_ZONE: dict[str, str] = {
    "Maharashtra": "West", "Gujarat": "West", "Goa": "West", "Rajasthan": "West",
    "Punjab": "North", "Haryana": "North", "Delhi": "North", "Uttar Pradesh": "North",
    "Uttarakhand": "North", "Himachal Pradesh": "North", "Jammu & Kashmir": "North",
    "Ladakh": "North", "Chandigarh": "North", "Madhya Pradesh": "North",
    "Tamil Nadu": "South", "Karnataka": "South", "Kerala": "South",
    "Andhra Pradesh": "South", "Telangana": "South", "Puducherry": "South",
    "West Bengal": "East", "Odisha": "East", "Bihar": "East", "Jharkhand": "East",
    "Chhattisgarh": "Central",
    "Assam": "Northeast", "Sikkim": "Northeast", "Arunachal Pradesh": "Northeast",
    "Meghalaya": "Northeast", "Manipur": "Northeast", "Mizoram": "Northeast",
    "Nagaland": "Northeast", "Tripura": "Northeast",
}


def compatible_regions(location: dict | None) -> set[str] | None:
    """The set of dataset `region` values that count as a default-eligible
    match for this location — always the user's own zone plus `"Pan-India"`.
    Returns `None` (meaning: no restriction, fail-open) when the state can't
    be resolved or isn't in the zone table, so an unmapped/unknown location
    can never accidentally exclude everything.

    This is deliberately independent of `build_region_boost()` — a state
    with zero *verified regional dishes* in the dataset (so `build_region_boost`
    itself returns `None`) can still have a perfectly good zone mapping here;
    exclusion only needs geography, not per-state dish coverage.
    """
    state = resolve_state(location)
    if not state:
        return None
    zone = _STATE_TO_ZONE.get(state)
    if not zone:
        return None
    return {zone, "Pan-India"}


def resolve_state(location: dict | None) -> str | None:
    """city/district -> state -> None. `location` is whatever shape the
    frontend saved (city/district/state/country) — every key is optional.
    Returns the canonical dataset spelling of the state, or None if nothing
    in `location` maps to a known Indian state."""
    if not location:
        return None
    city = _norm(location.get("city") or location.get("district") or "")
    if city and city in _CITY_TO_STATE:
        return _CITY_TO_STATE[city]
    state_raw = _norm(location.get("state") or "")
    if not state_raw:
        return None
    if state_raw in _STATE_ALIASES:
        return _STATE_ALIASES[state_raw]
    if state_raw in _CANONICAL_NORM_TO_NAME:
        return _CANONICAL_NORM_TO_NAME[state_raw]
    # Not a city/state we recognize at all — return the raw value titlecased
    # as a best-effort canonical guess; foods_by_state() simply returns []
    # for an unknown key, which build_region_boost() already treats as a
    # clean no-op, so a wrong guess here can never break anything downstream.
    return location.get("state").strip().title() if location.get("state") else None


# ── Healthy-local-alternative guidance (STEP 6) ─────────────────────────────
# Keyed by dish keyword, not by region — the same dish gets the same tip
# regardless of which region surfaced it. Applied as guidance TEXT (a coach
# tip / prompt instruction), never as a silent substitution — the spec asks
# to make regional foods healthier, not replace them with something else.
_HEALTHY_SWAP_TIPS: dict[str, str] = {
    "vada pav": "ask for it baked or with less oil, go light on the chutney, and pair it with buttermilk or curd.",
    "misal": "ask for less oil on top and extra usal/sprouts for protein and fibre.",
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
    usable location signal, or when the resolved state has no verified
    regional-dish data in the dataset yet (fallback chain ends here — callers
    already treat None as a no-op, i.e. today's unchanged, Pan-India-led
    behavior), or:

        {
          "region_label":        "Maharashtra",
          "preferred_categories": [...],   # -> merge into profile.preferredCategories
          "preferred_keywords":   [...],   # -> merge into favorite_foods
          "explanation":          "Because you're in Maharashtra, ...",
        }
    """
    state = resolve_state(location)
    if not state:
        return None
    engine = food_engine.get_engine()
    top_foods = engine.foods_by_state(state, limit=8)
    if not top_foods:
        return None
    categories = engine.regional_categories_for_state(state, limit=4)
    keywords = [f["name"] for f in top_foods]
    return {
        "region_label": state,
        "preferred_categories": categories,
        "preferred_keywords": keywords,
        "explanation": (
            f"Because you're in {state}, these meals lean on foods that are "
            "easy to find nearby, culturally familiar, and fit your calorie target."
        ),
    }
