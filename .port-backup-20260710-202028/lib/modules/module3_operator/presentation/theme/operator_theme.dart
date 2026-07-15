import 'package:flutter/material.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// Legacy operator design tokens, now forwarding to [CaptainTheme].
///
/// The operator app was merged into the driver ("Captain") shell — one phone
/// per vehicle, held by the driver — and the Captain look gained a persisted
/// light/dark toggle. Operator screens and widgets are still mounted inside
/// the Captain shell (trip cards, bin sheet, weighment entry, history), so
/// these tokens resolve against the live Captain palette and mode.
///
/// Like [CaptainTheme], every token is a getter: they can no longer be
/// captured inside `const` constructors. New code should import
/// [CaptainTheme] directly.
class OperatorTheme {
  OperatorTheme._();

  // Core palette — forwarded to CaptainTheme (mode-aware)
  static Color get primary => CaptainTheme.primary;
  static Color get primaryAccent => CaptainTheme.primaryAccent;
  static Color get primarySoft => CaptainTheme.primarySoft;

  static Color get accent => CaptainTheme.accent;
  static Color get accentDeep => CaptainTheme.accentDeep;
  static Color get accentSoft => CaptainTheme.accentSoft;

  static Color get background => CaptainTheme.background;
  static Color get surface => CaptainTheme.surface;
  static Color get surfaceMuted => CaptainTheme.surfaceMuted;

  static Color get strongText => CaptainTheme.strongText;
  static Color get mutedText => CaptainTheme.mutedText;
  static Color get hairline => CaptainTheme.hairline;

  static Color get success => CaptainTheme.success;
  static Color get warning => CaptainTheme.warning;
  static Color get danger => CaptainTheme.danger;
  static Color get info => CaptainTheme.info;

  static Color get attendanceAlert => danger;
  static Color get accentLight => accentSoft; // legacy alias
  static Color get cardBorder => hairline; // legacy alias

  // Gradients
  static LinearGradient get headerGradient => CaptainTheme.headerGradient;
  static LinearGradient get accentGradient => CaptainTheme.accentGradient;
  static LinearGradient get quickActionGradient => accentGradient;

  // Shadows
  static List<BoxShadow> get softShadow => CaptainTheme.softShadow;
  static List<BoxShadow> get elevatedShadow => CaptainTheme.elevatedShadow;

  // Radii
  static const BorderRadius cardRadius = CaptainTheme.cardRadius;
  static const BorderRadius chipRadius = CaptainTheme.chipRadius;

  static const EdgeInsets pagePadding = CaptainTheme.pagePadding;
}
