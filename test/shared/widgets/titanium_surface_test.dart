import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app/theme/app_theme.dart';
import 'package:gym_management_app/app/theme/design_tokens.dart';
import 'package:gym_management_app/shared/widgets/titanium_surface.dart';

void main() {
  double contrast(Color a, Color b) {
    final l1 = a.computeLuminance(), l2 = b.computeLuminance();
    return ((l1 > l2 ? l1 : l2) + .05) / ((l1 > l2 ? l2 : l1) + .05);
  }

  test(
    'Titanium readable foregrounds survive both ends of the illuminated canvas',
    () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final colors = theme.colorScheme;
        final surfaces = theme.extension<AppSurfaces>()!;
        for (final background in [
          surfaces.canvasStart,
          surfaces.canvasEnd,
          colors.surface,
        ]) {
          for (final foreground in [
            colors.onSurface,
            colors.onSurfaceVariant,
          ]) {
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
          }
        }
        expect(
          contrast(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(4.5),
        );
        // Frost may sit over the canvas or another content panel.
        for (final background in [surfaces.canvasEnd, colors.surface]) {
          final composed = Color.alphaBlend(surfaces.glass, background);
          expect(
            contrast(colors.onSurfaceVariant, composed),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'navigation glass is translucent and readable in ${theme.brightness}',
      (tester) async {
        final pixels = <Color>[];
        final surfaces = theme.extension<AppSurfaces>()!;
        for (final background in [
          Colors.black,
          Colors.white,
          surfaces.canvasEnd,
        ]) {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Center(
                child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: background,
                    child: TitaniumGlass(
                      opacity: AppGlass.navigation(theme.brightness),
                      blur: AppGlass.navigationBlur,
                      highlightOpacity: AppGlass.navigationHighlight,
                      child: const SizedBox.square(dimension: 80),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          pixels.add(
            (await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final offset = (40 * image.width + 40) * 4;
              final color = Color.fromARGB(
                bytes.getUint8(offset + 3),
                bytes.getUint8(offset),
                bytes.getUint8(offset + 1),
                bytes.getUint8(offset + 2),
              );
              image.dispose();
              return color;
            }))!,
          );
        }
        // Catch a second tint painted over the same glass, which makes it opaque.
        expect(
          (pixels[1].g - pixels[0].g) * 255,
          greaterThan(theme.brightness == Brightness.dark ? 80 : 40),
        );
        expect(
          contrast(theme.colorScheme.onSurfaceVariant, pixels[2]),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(theme.colorScheme.primary, pixels[2]),
          greaterThanOrEqualTo(4.5),
        );
      },
    );

    testWidgets(
      'financial glass stays readable over a dark modal scrim in ${theme.brightness}',
      (tester) async {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Material(
              color: Colors.black,
              child: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: const TitaniumGlass(
                    opacity: .96,
                    child: SizedBox.square(dimension: 80),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final pixel = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset = (40 * image.width + 40) * 4;
          final color = Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
          image.dispose();
          return color;
        });
        expect(
          contrast(theme.colorScheme.onSurfaceVariant, pixel!),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'entrance and press preserve action/focus with reduced motion $reduced',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: TitaniumCanvas(
                child: Scaffold(
                  body: Center(
                    child: TitaniumEntrance(
                      child: TitaniumGlass(
                        child: TitaniumPress(
                          child: TextButton(
                            onPressed: () => taps++,
                            child: const Text('Continue'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        if (reduced) {
          // Reduced motion must show the action immediately, without an entrance fade.
          expect(find.byType(Opacity), findsNothing);
        }
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(TextButton));
        final gesture = await tester.startGesture(rect.center);
        await tester.pump(const Duration(milliseconds: 150));
        final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
        expect(scale.scale, reduced ? 1 : .985);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(tester.getRect(find.byType(TextButton)), rect);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
