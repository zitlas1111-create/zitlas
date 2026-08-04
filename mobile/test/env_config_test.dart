import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/config/env.dart';

/// Regression guard for the physical-device outage where every FastAPI call
/// failed while Firebase kept working.
///
/// Root cause was `Env.apiBaseUrl` defaulting to `http://127.0.0.1:8000`.
/// On a real handset that address is the PHONE itself, not the developer's
/// machine, so `flutter build apk` produced a binary that could never reach
/// the backend — and because Firestore traffic goes to Google via the
/// Firebase SDK (not this base URL), login and all Firestore-backed screens
/// kept working, which disguised a connectivity fault as a data/parsing bug.
void main() {
  group('Env.apiBaseUrl', () {
    test('never defaults to a loopback/emulator-only host', () {
      // 10.0.2.2 is the Android *emulator* alias for the host machine and is
      // equally unreachable from a physical device.
      const unreachableFromDevice = ['127.0.0.1', 'localhost', '0.0.0.0', '10.0.2.2'];
      for (final host in unreachableFromDevice) {
        expect(
          Env.apiBaseUrl.contains(host),
          isFalse,
          reason: 'Env.apiBaseUrl ($host) is unreachable from a physical Android device. '
              'Point it at production, or pass a LAN IP via --dart-define=API_BASE_URL.',
        );
      }
    });

    test('is an absolute http(s) URL with no trailing slash', () {
      final uri = Uri.tryParse(Env.apiBaseUrl);
      expect(uri, isNotNull);
      expect(uri!.hasScheme, isTrue);
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
      // ApiClient joins as '$_baseUrl$path' where path starts with '/', so a
      // trailing slash here would produce a double slash.
      expect(Env.apiBaseUrl.endsWith('/'), isFalse);
    });

    test('composes the assessment endpoint into the same URL the website calls', () {
      // The website uses same-origin relative fetch('/api/assessment/generate-plan');
      // Flutter must resolve to that identical absolute path.
      final composed = Uri.parse('${Env.apiBaseUrl}/api/assessment/generate-plan');
      expect(composed.path, '/api/assessment/generate-plan');
    });
  });
}
