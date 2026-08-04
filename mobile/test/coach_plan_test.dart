import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/coaching/data/coaching_plan_repository.dart';
import 'package:zitlas_mobile/features/coaching/models/coach_diet_plan.dart';
import 'package:zitlas_mobile/features/coaching/models/protein_variety.dart';

/// Coach-authored plans.
///
/// The properties that matter are the ones that keep a coach's work safe: the
/// AI plan and the coach plan are different documents so neither can overwrite
/// the other, every publish leaves a restorable snapshot, and a plan authored
/// against an abandoned goal retires itself instead of quietly prescribing.
void main() {
  const athlete = 'athlete_1';
  const coach = 'coach_1';

  CoachDietPlan planWith(Map<String, List<String>> dayToFoods) {
    return CoachDietPlan(
      days: [
        for (final entry in dayToFoods.entries)
          CoachDietDay(
            day: entry.key,
            meals: [
              for (var i = 0; i < entry.value.length; i++)
                CoachMeal(
                  id: 'meal_$i',
                  name: kCoachDefaultMeals[i % kCoachDefaultMeals.length],
                  options: [CoachMealOption(name: entry.value[i], calories: 400, protein: 25)],
                ),
            ],
          ),
      ],
    );
  }

  Future<void> save(
    CoachingPlanRepository repo,
    CoachDietPlan plan, {
    String? planId,
  }) {
    return repo.saveDiet(
      athleteId: athlete,
      athleteName: 'Rohit',
      coachId: coach,
      coachName: 'Coach Rahul',
      planType: 'complete',
      diet: plan,
      athletePlanId: planId,
    );
  }

  group('publishing a coach diet', () {
    test('writes coaching_plans, NOT the athlete\'s AI plan', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(athlete).set({
        'dietPlan': {'originalDietPlan': {'days': ['ai-generated']}},
      });

      await save(CoachingPlanRepository(firestore: db), planWith({'Monday': ['Paneer Bhurji']}));

      final coachDoc = await db.collection('coaching_plans').doc(athlete).get();
      expect(coachDoc.exists, isTrue);
      expect(coachDoc.data()!['diet'], isNotNull);

      // The AI plan is untouched — this is the whole of "AI never overwrites
      // coach modifications", and its converse.
      final user = await db.collection('users').doc(athlete).get();
      expect(user.data()!['dietPlan']['originalDietPlan']['days'], ['ai-generated']);
    });

    test('carries the coach identity the athlete will see', () async {
      final db = FakeFirebaseFirestore();
      await save(CoachingPlanRepository(firestore: db), planWith({'Monday': ['Dal']}));

      final data = (await db.collection('coaching_plans').doc(athlete).get()).data()!;
      expect(data['coachId'], coach);
      expect(data['coachName'], 'Coach Rahul');
      expect(data['athleteId'], athlete);
      expect(data['planType'], 'complete');
      expect(data['dietUpdatedAt'], isNotNull);
    });

    test('the version number increments on every publish', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);

      await save(repo, planWith({'Monday': ['Dal']}));
      expect((await repo.fetch(athlete)).dietVersion, 1);

      await save(repo, planWith({'Monday': ['Rajma']}));
      expect((await repo.fetch(athlete)).dietVersion, 2);

      await save(repo, planWith({'Monday': ['Chole']}));
      expect((await repo.fetch(athlete)).dietVersion, 3);
    });

    test('the athlete is notified, in the shape the website writes', () async {
      final db = FakeFirebaseFirestore();
      await save(CoachingPlanRepository(firestore: db), planWith({'Monday': ['Dal']}));

      final notes = await db.collection('notifications').get();
      expect(notes.docs.length, 1);
      final n = notes.docs.first.data();
      expect(n['userId'], athlete);
      expect(n['title'], contains('Coach Rahul'));
      expect(n['title'], contains('diet'));
      expect(n['type'], 'diet_update');
      expect(n['action'], 'diet', reason: 'tapping it must open the diet screen');
      expect(n['isRead'], isFalse);
    });

    test('training publishes notify separately and version separately', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);

      await save(repo, planWith({'Monday': ['Dal']}));
      await repo.saveTraining(
        athleteId: athlete,
        athleteName: 'Rohit',
        coachId: coach,
        coachName: 'Coach Rahul',
        planType: 'complete',
        training: {
          'days': [
            {'day': 'Monday', 'focus': 'Push', 'exercises': []},
          ],
        },
      );

      final doc = await repo.fetch(athlete);
      expect(doc.dietVersion, 1);
      expect(doc.trainingVersion, 1, reason: 'the two plans version independently');
      expect(doc.hasTraining, isTrue);

      final types = (await db.collection('notifications').get())
          .docs
          .map((d) => d.data()['type'])
          .toList();
      expect(types, containsAll(['diet_update', 'training_update']));
    });
  });

  group('version history — nothing is ever overwritten', () {
    test('every publish leaves a restorable snapshot', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);

      await save(repo, planWith({'Monday': ['Original AI-based']}));
      await save(repo, planWith({'Monday': ['Coach revision 1']}));
      await save(repo, planWith({'Monday': ['Coach revision 2']}));

      final versions = await repo.watchVersions(athlete, type: 'diet').first;
      expect(versions.length, 3);
      expect(versions.first.version, 3, reason: 'newest first');
      expect(versions.last.version, 1);
      expect(versions.every((v) => v.isDiet), isTrue);
      expect(versions.first.savedBy, 'Coach Rahul');
    });

    test('a restore is saved FORWARD, keeping the replaced revision visible',
        () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);

      await save(repo, planWith({'Monday': ['Paneer Bhurji']}));
      await save(repo, planWith({'Monday': ['Chicken Curry']}));

      final versions = await repo.watchVersions(athlete, type: 'diet').first;
      final first = versions.firstWhere((v) => v.version == 1);

      await repo.restoreVersion(
        athleteId: athlete,
        athleteName: 'Rohit',
        coachId: coach,
        coachName: 'Coach Rahul',
        planType: 'complete',
        version: first,
      );

      final doc = await repo.fetch(athlete);
      expect(doc.diet.days.first.meals.first.options.first.name, 'Paneer Bhurji');
      expect(doc.dietVersion, 3, reason: 'a rollback is itself an edit');

      // The revision that was rolled back is still in the history.
      final after = await repo.watchVersions(athlete, type: 'diet').first;
      expect(after.length, 3);
      expect(after.any((v) => v.version == 2), isTrue);
    });

    test('diet and training histories can be read separately', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);
      await save(repo, planWith({'Monday': ['Dal']}));
      await repo.saveTraining(
        athleteId: athlete,
        athleteName: 'Rohit',
        coachId: coach,
        coachName: 'Coach Rahul',
        planType: 'complete',
        training: {'days': []},
      );

      expect((await repo.watchVersions(athlete, type: 'diet').first).length, 1);
      expect((await repo.watchVersions(athlete, type: 'training').first).length, 1);
      expect((await repo.watchVersions(athlete).first).length, 2);
    });
  });

  group('goal-reset protection (fail closed)', () {
    test('a plan authored against the current generation is live', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);
      await save(repo, planWith({'Monday': ['Dal']}), planId: 'plan_v1');

      expect((await repo.fetch(athlete)).isStaleFor('plan_v1'), isFalse);
    });

    test('a plan authored against an abandoned goal is stale', () async {
      // The athlete reset their goal, so users/{uid}.planId moved on. The
      // coach plan must retire rather than keep prescribing for a goal that
      // no longer exists.
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);
      await save(repo, planWith({'Monday': ['Dal']}), planId: 'plan_v1');

      expect((await repo.fetch(athlete)).isStaleFor('plan_v2'), isTrue);
    });

    test('an unstamped plan is not treated as stale', () async {
      // Plans written before the stamp existed must keep working.
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);
      await save(repo, planWith({'Monday': ['Dal']}));

      expect((await repo.fetch(athlete)).isStaleFor('plan_v2'), isFalse);
    });
  });

  group('what the coach is allowed to edit', () {
    test('a diet-only engagement cannot rewrite training', () {
      const doc = CoachingPlanDoc(planType: 'diet');
      expect(doc.canEditDiet, isTrue);
      expect(doc.canEditTraining, isFalse);
    });

    test('a training-only engagement cannot rewrite food', () {
      const doc = CoachingPlanDoc(planType: 'training');
      expect(doc.canEditDiet, isFalse);
      expect(doc.canEditTraining, isTrue);
    });

    test('a complete engagement covers both', () {
      const doc = CoachingPlanDoc(planType: 'complete');
      expect(doc.canEditDiet, isTrue);
      expect(doc.canEditTraining, isTrue);
    });
  });

  group('the athlete sees changes without refreshing', () {
    test('a publish arrives on the live listener', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);
      final seen = <CoachingPlanDoc>[];
      final sub = repo.watch(athlete).listen(seen.add);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen.last.exists, isFalse);

      await save(repo, planWith({'Monday': ['Paneer Bhurji']}));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(seen.last.exists, isTrue);
      expect(seen.last.diet.days.first.meals.first.options.first.name, 'Paneer Bhurji');
      await sub.cancel();
    });
  });

  group('the plan round-trips through the website\'s shape', () {
    test('a full week survives save and reload unchanged', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoachingPlanRepository(firestore: db);
      final original = CoachDietPlan(days: [
        CoachDietDay(day: 'Monday', meals: [
          const CoachMeal(id: 'meal_0', name: 'Breakfast', time: '08:00', options: [
            CoachMealOption(name: 'Paneer Bhurji', calories: 320, protein: 22, notes: 'Low oil'),
            CoachMealOption(name: 'Moong Dal Chilla', calories: 280, protein: 18),
          ]),
        ]),
      ]);

      await save(repo, original);
      final reloaded = (await repo.fetch(athlete)).diet;

      final meal = reloaded.days.first.meals.first;
      expect(meal.id, 'meal_0');
      expect(meal.time, '08:00');
      expect(meal.options.length, 2);
      expect(meal.options.first.name, 'Paneer Bhurji');
      expect(meal.options.first.calories, 320);
      expect(meal.options.first.notes, 'Low oil');
    });

    test('a blank calorie stays blank rather than becoming zero', () {
      final parsed = CoachDietPlan.fromMap({
        'days': [
          {
            'day': 'Monday',
            'meals': [
              {'id': 'm0', 'name': 'Breakfast', 'options': [{'name': 'Poha'}]},
            ],
          },
        ],
      });
      expect(parsed.days.first.meals.first.options.first.calories, isNull);
    });

    test('malformed entries are skipped, not fatal', () {
      final parsed = CoachDietPlan.fromMap({
        'days': [
          {
            'day': 'Monday',
            'meals': [
              {'id': 'm0', 'name': 'Breakfast', 'options': [
                {'name': 'Poha'},
                {'calories': 100},
                'not a map',
              ]},
              'not a meal',
            ],
          },
        ],
      });
      expect(parsed.days.first.meals.length, 1);
      expect(parsed.days.first.meals.first.options.length, 1);
    });
  });

  _athleteView();
  _websiteTypeTolerance();

  group('protein variety', () {
    test('a genuinely varied week raises nothing', () {
      final plan = planWith({
        'Monday': ['Egg Bhurji', 'Rajma Chawal', 'Roasted Chana', 'Paneer Tikka'],
        'Tuesday': ['Moong Dal Chilla', 'Chicken Curry', 'Almonds', 'Fish Curry'],
      });
      final report = analyseProteinVariety(plan);

      expect(report.isLowVariety, isFalse);
      expect(report.warning, isNull);
      expect(report.distinctSources, greaterThanOrEqualTo(3));
    });

    test('chicken every day is flagged with real counts', () {
      final plan = planWith({
        'Monday': ['Chicken Curry', 'Chicken Salad'],
        'Tuesday': ['Grilled Chicken', 'Chicken Soup'],
        'Wednesday': ['Chicken Biryani', 'Chicken Roll'],
      });
      final report = analyseProteinVariety(plan);

      expect(report.isLowVariety, isTrue);
      expect(report.dominant!.source, ProteinSource.chicken);
      expect(report.dominant!.mealCount, 6);
      expect(report.warning, contains('Chicken'));
      expect(report.warning, contains('100%'));
    });

    test('the report names concrete alternatives from the recognised sources', () {
      final plan = planWith({
        'Monday': ['Chicken Curry', 'Chicken Salad'],
        'Tuesday': ['Grilled Chicken', 'Chicken Soup'],
      });
      final unused = analyseProteinVariety(plan).unusedSources;

      expect(unused, contains(ProteinSource.paneer));
      expect(unused, contains(ProteinSource.legume));
      expect(unused, isNot(contains(ProteinSource.chicken)));
    });

    test('several options of the SAME source count as one meal', () {
      // The athlete eats one option, not all three.
      final plan = CoachDietPlan(days: [
        CoachDietDay(day: 'Monday', meals: [
          const CoachMeal(id: 'm0', name: 'Lunch', options: [
            CoachMealOption(name: 'Chicken Curry'),
            CoachMealOption(name: 'Chicken Tikka'),
            CoachMealOption(name: 'Grilled Chicken'),
          ]),
        ]),
      ]);
      final report = analyseProteinVariety(plan);
      expect(report.usage.single.mealCount, 1);
      expect(report.mealsWithProtein, 1);
    });

    test('a meal offering different sources counts towards each', () {
      final plan = CoachDietPlan(days: [
        CoachDietDay(day: 'Monday', meals: [
          const CoachMeal(id: 'm0', name: 'Lunch', options: [
            CoachMealOption(name: 'Paneer Tikka'),
            CoachMealOption(name: 'Rajma'),
          ]),
        ]),
      ]);
      final report = analyseProteinVariety(plan);
      expect(report.usage.map((u) => u.source),
          containsAll([ProteinSource.paneer, ProteinSource.legume]));
    });

    test('a half-built week is not nagged about', () {
      final plan = planWith({'Monday': ['Chicken Curry', 'Chicken Salad']});
      expect(analyseProteinVariety(plan).isLowVariety, isFalse,
          reason: 'warning a coach mid-build is noise');
    });

    test('meals with no recognisable protein are reported separately', () {
      final plan = planWith({
        'Monday': ['Fruit Salad', 'Green Tea', 'Steamed Vegetables', 'Tomato Soup'],
      });
      final report = analyseProteinVariety(plan);
      expect(report.mealsWithProtein, 0);
      expect(report.mealsWithoutProtein, 4);
      expect(report.isLowVariety, isFalse, reason: 'nothing to be repetitive about yet');
    });

    group('classification', () {
      test('recognises common Indian protein dishes', () {
        expect(ProteinSource.classify('Paneer Bhurji'), ProteinSource.paneer);
        expect(ProteinSource.classify('Moong Dal Chilla'), ProteinSource.legume);
        expect(ProteinSource.classify('Anda Curry'), ProteinSource.egg);
        expect(ProteinSource.classify('Murgh Tikka'), ProteinSource.chicken);
        expect(ProteinSource.classify('Machli Fry'), ProteinSource.fish);
        expect(ProteinSource.classify('Soya Chunk Curry'), ProteinSource.soy);
        expect(ProteinSource.classify('Masala Chaas'), ProteinSource.dairy);
        expect(ProteinSource.classify('Rajma Chawal'), ProteinSource.legume);
      });

      test('egg is matched before chicken so it is not miscounted', () {
        expect(ProteinSource.classify('Egg Bhurji'), ProteinSource.egg);
      });

      test('paneer is not swallowed by dairy', () {
        expect(ProteinSource.classify('Paneer Tikka'), ProteinSource.paneer);
      });

      test('an unrecognised dish returns null rather than a guess', () {
        expect(ProteinSource.classify('Steamed Broccoli'), isNull);
      });
    });
  });
}

/// The athlete's view of a coach plan — the read half of the loop.
///
/// These are in this file rather than the diet suite because what they pin is
/// the coach-plan contract: when a coach's prescription is shown, and the two
/// independent conditions under which it must NOT be.
void _athleteView() {
  group('when the athlete is shown the coach plan', () {
    CoachingPlanDoc docWith({
      String? planId,
      bool withMeals = true,
      bool exists = true,
    }) {
      return CoachingPlanDoc(
        exists: exists,
        coachName: 'Coach Rahul',
        planType: 'complete',
        diet: CoachDietPlan(
          planId: planId,
          days: [
            CoachDietDay(
              day: 'Monday',
              meals: [
                CoachMeal(
                  id: 'meal_0',
                  name: 'Breakfast',
                  options: withMeals
                      ? const [CoachMealOption(name: 'Paneer Bhurji', calories: 320)]
                      : const [],
                ),
              ],
            ),
          ],
        ),
      );
    }

    test('a published plan for the current goal is live', () {
      expect(docWith(planId: 'plan_v1').isStaleFor('plan_v1'), isFalse);
      expect(docWith(planId: 'plan_v1').diet.hasDays, isTrue);
    });

    test('an empty plan is not shown — it must not blank the AI plan', () {
      // A coach who opened the editor but published nothing.
      expect(docWith(withMeals: false).diet.hasDays, isFalse);
    });

    test('a plan for an abandoned goal retires itself', () {
      expect(docWith(planId: 'plan_v1').isStaleFor('plan_v2'), isTrue);
    });

    test('no coach document at all means no card', () {
      expect(docWith(exists: false).exists, isFalse);
    });

    test('selections are keyed day:mealId, matching the website', () {
      const doc = CoachingPlanDoc(selections: {'Monday:meal_0': 1});
      expect(doc.selections['Monday:meal_0'], 1);
    });
  });
}

/// The website writes these documents too, and JS is not fussy about types.
/// A hard cast here threw on the real production document and took the whole
/// coach plan down with it — caught on device, not in the unit tests.
void _websiteTypeTolerance() {
  group('tolerates the types the website actually stores', () {
    test('a version stored as a string still parses', () {
      final doc = CoachingPlanDoc.fromMap({
        'dietVersion': '3',
        'trainingVersion': '1',
        'diet': {'days': []},
      });
      expect(doc.dietVersion, 3);
      expect(doc.trainingVersion, 1);
    });

    test('a selection index stored as a string still parses', () {
      final doc = CoachingPlanDoc.fromMap({
        'dietSelections': {'Monday:meal_0': '2'},
      });
      expect(doc.selections['Monday:meal_0'], 2);
    });

    test('string calories and protein still parse', () {
      final plan = CoachDietPlan.fromMap({
        'days': [
          {
            'day': 'Monday',
            'meals': [
              {'id': 'm0', 'name': 'Breakfast', 'options': [
                {'name': 'Poha', 'calories': '250', 'protein': '8'},
              ]},
            ],
          },
        ],
      });
      final option = plan.days.first.meals.first.options.first;
      expect(option.calories, 250);
      expect(option.protein, 8);
    });

    test('genuinely unusable values become null, not zero', () {
      final plan = CoachDietPlan.fromMap({
        'days': [
          {'day': 'Monday', 'meals': [
            {'id': 'm0', 'name': 'Breakfast', 'options': [
              {'name': 'Poha', 'calories': 'unknown'},
            ]},
          ]},
        ],
      });
      expect(plan.days.first.meals.first.options.first.calories, isNull);
    });

    test('a garbage document does not throw', () {
      expect(() => CoachingPlanDoc.fromMap({'dietVersion': {}, 'diet': 'nope'}), returnsNormally);
    });
  });
}
