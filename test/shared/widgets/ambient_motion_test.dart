import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/shared/widgets/ambient_motion.dart';

void main() {
  testWidgets('backgrounding freezes the loop and resuming continues it', (
    tester,
  ) async {
    late Animation<double> phase;
    await tester.pumpWidget(
      MaterialApp(
        home: AmbientMotion(
          duration: const Duration(seconds: 10),
          builder: (context, animation) {
            phase = animation;
            return const SizedBox.square(dimension: 100);
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final before = phase.value;
    expect(before, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(phase.value, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(phase.value, isNot(before));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
