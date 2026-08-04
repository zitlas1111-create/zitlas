import 'package:flutter/widgets.dart';

/// Which main screen a tour stop belongs to. The tour drives the bottom-nav
/// branch, the same way the website's tour navigated between pages.
enum ZinoTourScreen { dashboard, diet, training, experts, profile }

/// A registry of the real widgets a tour stop can spotlight.
///
/// Keys are attached to the ACTUAL widgets (the goal card, the swap button,
/// …) rather than to a duplicated mock, so the spotlight always frames what
/// the athlete will really tap. A key that never gets attached simply
/// resolves to null and its stop is skipped — mirroring the website, where
/// `document.querySelector` returning nothing skips the stop rather than
/// stalling the tour.
class ZinoTourKeys {
  ZinoTourKeys._();

  static final goalCard = GlobalKey(debugLabel: 'zinoTour.goalCard');
  static final goalActionButton = GlobalKey(debugLabel: 'zinoTour.goalActionBtn');
  static final healthStatus = GlobalKey(debugLabel: 'zinoTour.healthStatus');
  static final activityCard = GlobalKey(debugLabel: 'zinoTour.activityCard');
  static final dietFocusCard = GlobalKey(debugLabel: 'zinoTour.dietFocusCard');
  static final dietSwapButton = GlobalKey(debugLabel: 'zinoTour.dietSwapBtn');
  static final trainingContent = GlobalKey(debugLabel: 'zinoTour.trainingContent');
  static final expertsList = GlobalKey(debugLabel: 'zinoTour.expertsList');
  static final profileHeader = GlobalKey(debugLabel: 'zinoTour.profileHeader');

  /// The Zino launcher itself — spotlighted so the athlete learns WHERE Zino
  /// lives, which is the whole point of the top-right placement.
  static final zinoFab = GlobalKey(debugLabel: 'zinoTour.zinoFab');

  /// Clears any stale attachment state between tests.
  @visibleForTesting
  static List<GlobalKey> get all => [
        goalCard,
        goalActionButton,
        healthStatus,
        activityCard,
        dietFocusCard,
        dietSwapButton,
        trainingContent,
        expertsList,
        profileHeader,
        zinoFab,
      ];
}

/// One stop in the walkthrough.
@immutable
class ZinoTourStop {
  const ZinoTourStop({
    required this.id,
    required this.screen,
    required this.title,
    required this.body,
    this.target,
    this.hero,
    this.optional = false,
    this.coachExtra,
  });

  final String id;
  final ZinoTourScreen screen;
  final String title;
  final String body;

  /// The widget to spotlight. Null means a full-screen "slide" stop
  /// (intro/finish), which is how the website distinguishes them via `hero`.
  final GlobalKey? target;

  /// Hero image asset for a full-slide stop.
  final String? hero;

  /// The website skips these silently when the element isn't present
  /// (`stop.optional`) — used for features that only exist for some athletes.
  final bool optional;

  /// Appended only when the athlete actually has an active Personal Coach —
  /// `zino.js` does exactly this for the Swap Meal stop.
  final String? coachExtra;

  bool get isSlide => hero != null;
}

/// The walkthrough, ported from `TutorialEngine.STOPS` (`zino.js:278-329`).
///
/// Titles and body copy are **verbatim** from the website — this is an
/// existing, deliberate onboarding script, not something to rewrite. Two
/// adaptations were necessary and are marked below:
///
///  * Stops that lived on the website's Expert Profile page
///    (`request-review`, `hire-coach`, `chat`) are folded into the Experts
///    stop: reaching an expert's profile requires picking a specific expert
///    first, and auto-navigating into one athlete's profile mid-tour would be
///    both arbitrary and impossible on a fresh account with no experts loaded.
///    Their content is preserved as part of the Experts stop's copy.
///  * A `zino-here` stop is ADDED to introduce Zino's own top-right location.
///    The website never needed it — its FAB is visible on every page from the
///    first second — but on mobile the athlete should be shown explicitly
///    where their companion lives.
const kZinoTourStops = <ZinoTourStop>[
  ZinoTourStop(
    id: 'intro',
    screen: ZinoTourScreen.dashboard,
    hero: 'assets/images/zino_intro.png',
    title: '👋 Hey! Welcome to ZITLAS.',
    body: "I'm Zino, your personal AI fitness companion.\n\n"
        "I'll quickly show you how everything works. It'll only take a minute.",
  ),
  ZinoTourStop(
    id: 'goal',
    screen: ZinoTourScreen.dashboard,
    target: null, // resolved at runtime — see ZinoTourController._targetFor
    title: 'Your Fitness Journey',
    body: 'This is your fitness journey. You can set your goal, track progress, '
        'and monitor everything from here.',
  ),
  ZinoTourStop(
    id: 'reset-goal',
    screen: ZinoTourScreen.dashboard,
    optional: true,
    title: 'Changed your mind?',
    body: "If your goal changes, you can reset everything here. I'll generate a "
        'completely new roadmap.',
  ),
  ZinoTourStop(
    id: 'health-status',
    screen: ZinoTourScreen.dashboard,
    title: 'How Are You Feeling?',
    body: "Every day you can tell me how you're feeling. I'll automatically "
        "adjust today's diet and workout.\n\n"
        "If you have a Personal Coach, they'll be notified too.",
  ),
  ZinoTourStop(
    id: 'activity',
    screen: ZinoTourScreen.dashboard,
    optional: true,
    title: 'Your Daily Steps',
    body: 'Your steps are tracked automatically — even when ZITLAS is closed. '
        "I'll nudge you when you're close to your daily goal 👟",
  ),
  ZinoTourStop(
    id: 'diet-today',
    screen: ZinoTourScreen.diet,
    title: "Today's Diet",
    body: "This is your today's AI generated diet 🍽️",
  ),
  ZinoTourStop(
    id: 'diet-swap',
    screen: ZinoTourScreen.diet,
    optional: true,
    title: 'Swap Meal',
    body: "If you don't like a meal, you can swap it.",
    coachExtra: 'When your Personal Coach creates a plan, Swap Meal uses ONLY '
        'the three alternatives your coach provided.',
  ),
  ZinoTourStop(
    id: 'training',
    screen: ZinoTourScreen.training,
    title: 'Your Training Plan',
    body: 'This is your daily workout. You can see your entire weekly plan '
        'here.\n\nIf your Personal Coach updates your training, it instantly '
        'appears here — no refresh needed.',
  ),
  ZinoTourStop(
    id: 'ask-expert',
    screen: ZinoTourScreen.experts,
    title: 'Connect With Experts',
    body: 'You can connect with verified experts here.\n\n'
        '"Ask Expert" is for one-time reviews — the expert checks your plan and '
        'suggests improvements, then the relationship ends.',
  ),
  ZinoTourStop(
    id: 'personal-coach-diff',
    screen: ZinoTourScreen.experts,
    optional: true,
    title: 'Personal Coaching',
    body: 'Personal Coaching is different — a dedicated coach who gives you '
        'unlimited chat, manages your diet AND training, reviews your meals '
        'daily, and guides your full transformation.\n\n'
        'Open any expert to request a plan review, hire them, or chat.',
  ),
  ZinoTourStop(
    id: 'profile',
    screen: ZinoTourScreen.profile,
    title: 'Your Profile',
    body: 'This is where all your personal information lives — goals, '
        'assessment, health details, medical conditions, and progress.',
  ),
  ZinoTourStop(
    id: 'zino-here',
    screen: ZinoTourScreen.profile,
    title: "And I'll always be right here 👋",
    body: 'Tap me any time — top-right, on every screen — and I\'ll help with '
        'your diet, training, steps, or anything else on your mind.',
  ),
  ZinoTourStop(
    id: 'finish',
    screen: ZinoTourScreen.profile,
    hero: 'assets/images/zino_done.png',
    title: "Awesome! You're all set.",
    body: "Remember, I'm always here if you need help.\n\n"
        "Let's build the healthiest version of you. 🚀",
  ),
];

/// Stop id -> the key it spotlights.
///
/// Kept out of the const stop list because `GlobalKey`s aren't const —
/// `kZinoTourStops` stays a pure, testable description of the script.
GlobalKey? zinoTourTargetFor(String stopId) => switch (stopId) {
      'goal' => ZinoTourKeys.goalCard,
      'reset-goal' => ZinoTourKeys.goalActionButton,
      'health-status' => ZinoTourKeys.healthStatus,
      'activity' => ZinoTourKeys.activityCard,
      'diet-today' => ZinoTourKeys.dietFocusCard,
      'diet-swap' => ZinoTourKeys.dietSwapButton,
      'training' => ZinoTourKeys.trainingContent,
      'ask-expert' || 'personal-coach-diff' => ZinoTourKeys.expertsList,
      'profile' => ZinoTourKeys.profileHeader,
      'zino-here' => ZinoTourKeys.zinoFab,
      _ => null,
    };
