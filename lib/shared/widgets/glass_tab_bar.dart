import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/design_tokens.dart';

class GlassTab {
  const GlassTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon, selectedIcon;
}

/// The floating tab bar as clear glass: no tint and no blur, just a bright
/// rim and a faint sheen. The screen sinks into the dark just before it
/// reaches the bar, so nothing runs behind the icons and labels. The current
/// tab sits under a glass lens that glides to it and magnifies its icon.
///
/// Use as a Scaffold's `bottomNavigationBar` with `extendBody: true`, and
/// pad the body's bottom by [GlassTabBar.space].
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<GlassTab> tabs;

  /// -1 when no tab is current; the lens then hides.
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const height = 68.0;
  static const gap = 22.0;
  static const side = 14.0;
  static const lensInset = 6.0;

  /// How far above the bar the screen starts sinking into the dark.
  static const fadeAbove = 44.0;

  static double bottomOf(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom > gap
      ? MediaQuery.paddingOf(context).bottom
      : gap;

  /// Space a screen must leave at its bottom so content clears the bar.
  static double space(BuildContext context) => bottomOf(context) + height + 16;

  @override
  Widget build(BuildContext context) {
    final bottom = bottomOf(context);
    final reduced = AppMotion.reduced(context);
    return SizedBox(
      height: fadeAbove + height + bottom,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0),
                      AppColors.background.withValues(alpha: .95),
                      AppColors.background,
                    ],
                    stops: const [0, fadeAbove / (fadeAbove + height), 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: side,
            right: side,
            bottom: bottom,
            height: height,
            child: _Bar(
              tabs: tabs,
              selectedIndex: selectedIndex,
              onSelected: onSelected,
              reduced: reduced,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.reduced,
  });
  final List<GlassTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(GlassTabBar.height / 2));
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .38)),
          // Sheen: a little light across the top, nothing at the bottom.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(255, 255, 255, .16),
              Color.fromRGBO(255, 255, 255, .04),
              Color.fromRGBO(255, 255, 255, .02),
            ],
            stops: [0, .5, 1],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / tabs.length;
            final at = selectedIndex;
            return Stack(
              children: [
                const Positioned(
                  top: 0,
                  left: 18,
                  right: 18,
                  height: 1,
                  child: ColoredBox(color: Color.fromRGBO(255, 255, 255, .7)),
                ),
                if (at >= 0 && at < tabs.length)
                  AnimatedPositioned(
                    duration: reduced ? Duration.zero : AppMotion.lens,
                    curve: AppMotion.easeOut,
                    left: at * slot + GlassTabBar.lensInset,
                    top: GlassTabBar.lensInset,
                    bottom: GlassTabBar.lensInset,
                    width: slot - GlassTabBar.lensInset * 2,
                    child: const IgnorePointer(child: _Lens()),
                  ),
                Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: _Tab(
                          tab: tabs[i],
                          selected: i == at,
                          reduced: reduced,
                          onTap: () {
                            if (i == at) return;
                            HapticFeedback.selectionClick();
                            onSelected(i);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Lens extends StatelessWidget {
  const _Lens();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadii.xxl),
      border: Border.all(color: const Color.fromRGBO(255, 255, 255, .55)),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.fromRGBO(255, 255, 255, .28),
          Color.fromRGBO(255, 255, 255, .06),
          Color.fromRGBO(255, 255, 255, .14),
        ],
        stops: [0, .55, 1],
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.reduced,
    required this.onTap,
  });
  final GlassTab tab;
  final bool selected, reduced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = selected ? AppColors.text : AppColors.tabInactive;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected && !reduced ? 1.18 : 1,
              duration: reduced ? Duration.zero : AppMotion.medium,
              curve: AppMotion.pop,
              child: Icon(
                selected ? tab.selectedIcon : tab.icon,
                size: 22,
                color: tint,
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tab.label,
                  maxLines: 1,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                  style: AppType.tab.copyWith(
                    color: tint,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    shadows: const [
                      Shadow(
                        color: Color.fromRGBO(0, 0, 0, .6),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
