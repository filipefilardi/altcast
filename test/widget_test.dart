import 'package:altcast/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AltCastApp()));
    // First frame is the AuthInitial splash; no exceptions = pass.
    expect(tester.takeException(), isNull);
  });
}
