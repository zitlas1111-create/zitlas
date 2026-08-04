/// A navigation shortcut Zino can offer alongside its reply.
///
/// SECURITY MODEL — this is the whole point of the file:
///
///  * Actions are a **fixed, typed allowlist** ([ZinoAction.values]). There is
///    no string-to-route evaluation and no dynamic dispatch, so no reachable
///    code path can navigate anywhere that isn't enumerated here.
///  * Actions are derived from the **athlete's own message**, never from the
///    model's reply. The LLM cannot emit an action, so a prompt-injected or
///    hallucinated response cannot cause one. (The backend persona is
///    explicitly a chat companion that never claims to act — see
///    `ZINO_COMPANION_SYSTEM` — and this design keeps that true rather than
///    quietly contradicting it.)
///  * Every action is **navigation only** — it opens a screen the athlete
///    could already reach from the nav bar. Nothing here writes data, spends
///    money, or changes a plan.
///  * Actions are **suggestions, not automation**. They render as a chip the
///    athlete taps; nothing navigates on its own. That tap IS the
///    confirmation step, which is why no separate dialog is needed for these
///    read-only destinations.
///
/// Anything genuinely destructive or costly (swapping a meal, hiring a coach,
/// spending from the wallet) is deliberately NOT here: those keep their own
/// existing screens and confirmation flows, and Zino's role is to point at
/// them — exactly what [swapMeal] does by opening the Diet screen where the
/// real Swap Meal sheet lives.
/// Every route here is verified against `app/router.dart` — an action can
/// only ever point at a screen that actually exists.
enum ZinoAction {
  openDiet('/diet', '🍽', "Today's Diet"),
  openTraining('/training', '🏋', 'My Workout'),
  openProgress('/activity', '📊', 'My Activity'),
  openExperts('/experts', '👨‍⚕️', 'Browse Experts'),
  openDashboard('/dashboard', '🏠', 'Dashboard'),
  openProfile('/profile', '👤', 'My Profile'),

  /// Opens the Diet screen, where each meal card's own Swap Meal sheet
  /// (reason → alternatives → confirm) handles the actual change. Zino never
  /// performs the swap itself.
  swapMeal('/diet', '🔄', 'Swap a Meal');

  const ZinoAction(this.route, this.icon, this.label);

  final String route;
  final String icon;
  final String label;
}

/// Deterministic intent detection over the athlete's message.
///
/// Pure and keyword-based on purpose: an LLM round-trip to decide "did they
/// ask to open the diet page" would be slower, non-deterministic, and would
/// reintroduce exactly the model-controls-navigation risk the typed allowlist
/// exists to prevent.
///
/// Returns at most ONE action — offering a row of competing chips for a
/// single sentence reads as clutter, not help.
ZinoAction? detectZinoAction(String message) {
  final m = message.toLowerCase();

  // Requires an explicit navigational or "show me" framing. Merely mentioning
  // a topic ("is my diet high in protein?") is a question to answer, not a
  // request to leave the conversation — offering a chip there would be noise.
  final wantsToGo = _anyOf(m, const [
    'open', 'show', 'take me', 'go to', 'navigate', 'view', 'see my', 'see today',
    'where is', 'where can i',
  ]);

  // Checked before the navigation gate: "I can't eat this" is a request for
  // help, phrased without any "show me".
  if (_anyOf(m, const ['swap', 'replace this meal', 'replace my meal', 'change this meal']) ||
      _anyOf(m, const ["can't eat", 'cannot eat', "don't like this meal", 'dont like this meal'])) {
    return ZinoAction.swapMeal;
  }

  if (!wantsToGo) return null;

  if (_anyOf(m, const ['diet', 'meal', 'food', 'eat', 'nutrition'])) return ZinoAction.openDiet;
  if (_anyOf(m, const ['workout', 'training', 'exercise', 'gym'])) return ZinoAction.openTraining;
  if (_anyOf(m, const ['progress', 'weight', 'history', 'trend'])) return ZinoAction.openProgress;
  if (_anyOf(m, const ['expert', 'coach', 'nutritionist', 'trainer'])) return ZinoAction.openExperts;
  if (_anyOf(m, const ['profile', 'account', 'settings'])) return ZinoAction.openProfile;
  if (_anyOf(m, const ['dashboard', 'home', 'steps', 'activity'])) return ZinoAction.openDashboard;
  return null;
}

bool _anyOf(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(n)) return true;
  }
  return false;
}

/// Debug-only description, used in logs to show which action was offered.
String describeAction(ZinoAction? a) => a == null ? '(none)' : '${a.name} -> ${a.route}';
