/// Build-time environment configuration.
abstract final class Env {
  /// FastAPI backend base URL.
  ///
  /// Defaults to **production**, which is the same origin the website itself
  /// talks to: the website calls `fetch('/api/...')` with relative URLs
  /// because FastAPI serves `frontend/` as static files from that same host
  /// (see `render.yaml` — `rootDir: backend`, frontend mounted last).
  ///
  /// This MUST NOT default to `localhost`/`127.0.0.1`: on a physical Android
  /// device those resolve to the phone itself, not the developer's PC, so
  /// every backend call fails with a connection error while Firebase (which
  /// goes to Google's servers via the SDK) keeps working — making it look
  /// like a data/parsing bug rather than a connectivity one.
  ///
  /// To point at a local dev server, pass an address reachable *from the
  /// device* — your PC's LAN IP, not localhost:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
  /// Note that a plain-HTTP target is blocked by Android's default
  /// cleartext policy and would additionally need a `networkSecurityConfig`
  /// exemption scoped to that specific host. None is shipped here on
  /// purpose — production is HTTPS, and a blanket `usesCleartextTraffic`
  /// would weaken the release build for a dev-only convenience.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://zitlas.com',
  );

  /// Shared Firebase project — see docs/MIGRATION_INVENTORY.md §4.
  static const firebaseProjectId = 'zitlas-b8677';

  /// Default per-request budget. `/api/assessment/generate-plan` overrides
  /// this with a much longer one (2 RAG retrievals + 2 LLM generations
  /// server-side) — see `AssessmentRepository.generatePlan`.
  static const apiTimeout = Duration(seconds: 30);
}
