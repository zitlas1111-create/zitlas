import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/widgets/zitlas_loading_ring.dart';

/// Pins the three promises this widget makes: it uses the shipped asset, the
/// asset never rotates (only the ring does), and its ticker is released when
/// the loading cover is removed.
void main() {
  Widget host({double size = 168}) => MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: ZitlasLoadingRing(size: size)),
        ),
      );

  testWidgets('renders lodo.png from the declared asset path', (tester) async {
    await tester.pumpWidget(host());
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as AssetImage;
    expect(provider.assetName, 'assets/images/lodo.png');
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('the image is NOT rotated — only the ring animates', (tester) async {
    await tester.pumpWidget(host());
    // Scoped to this widget's OWN subtree: MaterialApp wraps the whole page in
    // a RotationTransition for its route animation, so an unscoped finder would
    // report a false positive that has nothing to do with the logo.
    final subtree = find.byType(ZitlasLoadingRing);
    expect(
      find.descendant(of: subtree, matching: find.byType(RotationTransition)),
      findsNothing,
      reason: 'lodo.png must remain stationary and unrotated',
    );
    expect(
      find.descendant(of: subtree, matching: find.byType(Transform)),
      findsNothing,
      reason: 'no transform may be applied to the logo',
    );
  });

  testWidgets('the image is clipped to a circle so the landscape streaks crop away',
      (tester) async {
    await tester.pumpWidget(host());
    expect(
      find.ancestor(of: find.byType(Image), matching: find.byType(ClipOval)),
      findsOneWidget,
    );
  });

  testWidgets('paints inside a RepaintBoundary so the ring repaints alone',
      (tester) async {
    await tester.pumpWidget(host());
    // Again scoped to this widget's subtree — the framework creates its own
    // CustomPaints/RepaintBoundaries elsewhere in a MaterialApp.
    final subtree = find.byType(ZitlasLoadingRing);
    expect(
      find.descendant(of: subtree, matching: find.byType(RepaintBoundary)),
      findsWidgets,
      reason: 'the animated arc must be isolated from the surrounding tree',
    );
    expect(
      find.descendant(of: subtree, matching: find.byType(CustomPaint)),
      findsWidgets,
    );
  });

  testWidgets('animates continuously without throwing', (tester) async {
    await tester.pumpWidget(host());
    // Several frames across more than one full revolution (1500ms cycle).
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 220));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes its AnimationController when removed (no ticker leak)',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));
    // Replacing the tree unmounts the ring. flutter_test fails a test that
    // leaves a Ticker running, so reaching the end of this test IS the
    // assertion that dispose() stopped it.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ZitlasLoadingRing), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scales responsively — the footprint follows the given size',
      (tester) async {
    await tester.pumpWidget(host(size: 100));
    final small = tester.getSize(find.byType(ZitlasLoadingRing));
    await tester.pumpWidget(host(size: 240));
    final large = tester.getSize(find.byType(ZitlasLoadingRing));
    expect(large.width, greaterThan(small.width));
    // Square, and larger than the badge because the arc orbits outside it.
    expect(small.width, small.height);
    expect(small.width, greaterThan(100));
  });
}
