"""
Ad-hoc verification script for the workout knowledge-base integration —
NOT a pytest suite, just a direct runnable smoke test covering the 15+
assessment combinations the task asked to demonstrate. Run from backend/:
    python test_workout_engine.py
"""
from __future__ import annotations

from services import workout_engine as we
from services.assessment_service import AssessmentInput, run_assessment

ENGINE = we.get_engine()
ALL_REAL_IDS = set(ENGINE.by_id.keys())


def make_input(**overrides) -> AssessmentInput:
    defaults = dict(
        age=28, gender="male", height_cm=175, weight_kg=78, goal_weight_kg=70,
        activity_level="moderate", occupation="student", living_situation="hostel",
        diet_preference="mixed", workout_preference="home",
        sleep_hours=7, stress_level=5, available_time=30,
        budget="", medical_conditions="none", fitness_goal="weight_loss",
        health_goals=[], fitness_level="beginner",
    )
    defaults.update(overrides)
    return AssessmentInput(**defaults)


def build_plan(data: AssessmentInput):
    calc = run_assessment(data)["calculations"]
    if data.fitness_goal == "weight_loss":
        bmi_val = float(calc.get("bmi", 25.0))
        level = "beginner" if bmi_val > 30 else ("intermediate" if bmi_val > 25 else "advanced")
    else:
        level = data.fitness_level

    condition_names = we.WorkoutRecommendationEngine.resolve_condition_names(data.medical_conditions)
    age_p = we.WorkoutRecommendationEngine.resolve_age_profile_name(data.age)
    dis_p = we.WorkoutRecommendationEngine.resolve_disability_name(data.medical_conditions)
    women_p = we.WorkoutRecommendationEngine.resolve_women_focus_name(data.gender, condition_names)
    for extra in (age_p, dis_p, women_p):
        if extra:
            condition_names.append(extra)
    if data.age >= 60 or data.age <= 17:
        level = "beginner"

    recovery = we.WorkoutRecommendationEngine.resolve_recovery_condition(data.medical_conditions)
    lifestyle = we.WorkoutRecommendationEngine.resolve_lifestyle_name(data.living_situation, data.occupation)
    difficulty = we.difficulty_levels_for(level)
    equipment = we.equipment_tags_for(data.workout_preference, data.living_situation)
    high_stress = data.stress_level >= 8

    if recovery:
        rec_plan = ENGINE.build_recovery_week(recovery, high_stress=high_stress)
        return we.format_recovery_for_output(rec_plan, recovery), condition_names, lifestyle, recovery

    week = ENGINE.build_week_plan(
        fitness_goal=data.fitness_goal, difficulty_levels=difficulty, equipment_tags=equipment,
        condition_names=condition_names, lifestyle_name=lifestyle, high_stress=high_stress,
        exercises_per_workout=4,
    )
    return we.format_week_for_output(week, data.fitness_goal, None), condition_names, lifestyle, recovery


def collect_exercise_ids(plan: dict) -> set[str]:
    ids = set()
    for day in plan["weekly_plan"]:
        for ex in day["exercises"]:
            ids.add(ex["exercise_id"])
    return ids


COMBOS = [
    ("1. Hostel Student / Weight Loss", dict(occupation="student", living_situation="hostel", workout_preference="home", fitness_goal="weight_loss")),
    ("2. Working Professional / Muscle Gain / Gym", dict(occupation="working_professional", living_situation="home", workout_preference="gym", fitness_goal="muscle_gain")),
    ("3. General Fitness / Intermediate", dict(fitness_goal="general_fitness", fitness_level="intermediate")),
    ("4. Six Pack (Transformation) / Home", dict(fitness_goal="transformation", transformation_goal="six_pack", workout_preference="home")),
    ("5. Asthma / Weight Loss", dict(medical_conditions="I have asthma", fitness_goal="weight_loss")),
    ("6. PCOS / Female / General Fitness", dict(gender="female", medical_conditions="I have PCOS", fitness_goal="general_fitness")),
    ("7. High Stress (9/10) / Muscle Gain", dict(stress_level=9, fitness_goal="muscle_gain")),
    ("8. Diabetes / Weight Loss / Gym", dict(medical_conditions="type 2 diabetes", workout_preference="gym", fitness_goal="weight_loss")),
    ("9. Typhoid Recovery ('sick today')", dict(medical_conditions="recovering from typhoid, feeling weak")),
    ("10. Women / General Women's Fitness", dict(gender="female", fitness_goal="general_fitness")),
    ("11. Kids (age 14)", dict(age=14, fitness_goal="general_fitness", workout_preference="home")),
    ("12. Senior (age 68)", dict(age=68, living_situation="home", fitness_goal="general_fitness", workout_preference="home")),
    ("13. Wheelchair User (Disability)", dict(medical_conditions="wheelchair user", fitness_goal="general_fitness")),
    ("14. Hypertension / Traveller lifestyle", dict(medical_conditions="high blood pressure", occupation="traveller", living_situation="home")),
    ("15. Lower Back Pain / Homemaker / No equipment", dict(medical_conditions="chronic lower back pain", occupation="homemaker", workout_preference="none")),
    ("16. Arthritis + High Stress + Senior (compound)", dict(age=65, living_situation="home", medical_conditions="arthritis", stress_level=9, fitness_goal="general_fitness")),
    ("17. Athlete lifestyle / Muscle Gain / Gym", dict(occupation="athlete", living_situation="home", workout_preference="gym", fitness_goal="muscle_gain")),
]

print(f"Total real KB exercise IDs available: {len(ALL_REAL_IDS)}\n")

all_selected_names_by_combo = {}
violations = []

for label, overrides in COMBOS:
    data = make_input(**overrides)
    plan, condition_names, lifestyle, recovery = build_plan(data)

    ids = collect_exercise_ids(plan)
    hallucinated = ids - ALL_REAL_IDS
    if hallucinated:
        violations.append((label, "HALLUCINATED_ID", hallucinated))

    names = sorted({ENGINE.by_id[i]["name"] for i in ids}) if not recovery else ["(recovery mode — no exercises)"]
    all_selected_names_by_combo[label] = names

    print(f"{label}")
    print(f"   conditions={condition_names} lifestyle={lifestyle} recovery={recovery}")
    print(f"   plan_name: {plan['plan_name']}")
    print(f"   exercises used: {names[:8]}{'...' if len(names) > 8 else ''}")
    print(f"   zero hallucinated: {not hallucinated}")
    print()

# ── Cross-combo distinctness check (spec: "retrieves DIFFERENT exercises") ──
print("=" * 70)
unique_sets = {label: frozenset(names) for label, names in all_selected_names_by_combo.items()}
labels = list(unique_sets.keys())
identical_pairs = []
for i in range(len(labels)):
    for j in range(i + 1, len(labels)):
        if unique_sets[labels[i]] == unique_sets[labels[j]]:
            identical_pairs.append((labels[i], labels[j]))

print(f"Combinations tested: {len(COMBOS)}")
print(f"Identical exercise-set pairs (should be ~0): {len(identical_pairs)}")
for a, b in identical_pairs:
    print(f"   SAME: {a}  <->  {b}")

if violations:
    print("\nVIOLATIONS FOUND:")
    for v in violations:
        print("  ", v)
else:
    print("\nNO HALLUCINATED EXERCISE IDs ACROSS ANY COMBINATION")

print("\nDONE")
