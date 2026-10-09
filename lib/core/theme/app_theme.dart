import 'package:flutter/material.dart';

/// Colors, fonts and radii shared by the whole app.
/// Lime is reserved for the primary action, selection, focus and active states.
abstract final class AppTheme {
  static const lime = Color(0xFFCCFF00);
  static const ink = Color(0xFF0A100E); // app chrome, logo background
  static const cream = Color(0xFFFBFFE9); // primary text
  static const canvas = Color(0xFF070A09); // editor canvas behind the device
  static const surface = Color(0xFF101614); // panels
  static const surfaceHigh = Color(0xFF161E1B); // inputs, raised controls
  static const hover = Color(0xFF1C2622);
  static const line = Color(0xFF232D29); // hairlines
  static const lineStrong = Color(0xFF2F3B36);
  static const muted = Color(0xFF8B958F); // secondary text
  static const faint = Color(0xFF5F6964); // tertiary text, disabled
  static const danger = Color(0xFFF2554A);
  static const warning = Color(0xFFFFB020); // hints the user should not miss

  static const displayFont = 'Unbounded';

  // radii
  static const rControl = 6.0;
  static const rPanel = 8.0;
}

String bodyFontFor(Locale l) => l.languageCode == 'ar' ? 'Alexandria' : 'Lexend';

ThemeData buildTheme(Locale locale) {
  final body = bodyFontFor(locale);
  const scheme = ColorScheme.dark(
    primary: AppTheme.lime,
    onPrimary: AppTheme.ink,
    secondary: AppTheme.lime,
    onSecondary: AppTheme.ink,
    surface: AppTheme.surface,
    onSurface: AppTheme.cream,
    onSurfaceVariant: AppTheme.muted,
    surfaceContainerHighest: AppTheme.surfaceHigh,
    surfaceContainerHigh: AppTheme.surfaceHigh,
    surfaceContainer: AppTheme.surface,
    outline: AppTheme.lineStrong,
    outlineVariant: AppTheme.line,
    error: AppTheme.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTheme.ink,
    fontFamily: body,
    fontFamilyFallback: const ['Alexandria', 'Lexend'],
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    hoverColor: AppTheme.hover,
    highlightColor: Colors.transparent,
  );
  final rc = BorderRadius.circular(AppTheme.rControl);
  OutlineInputBorder border(Color c) => OutlineInputBorder(borderRadius: rc, borderSide: BorderSide(color: c));
  final text = base.textTheme
      .copyWith(
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
        titleMedium: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
        titleSmall: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 13, height: 1.4),
        bodyMedium: const TextStyle(fontSize: 13, height: 1.4),
        bodySmall: const TextStyle(fontSize: 12, height: 1.4),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      )
      .apply(bodyColor: AppTheme.cream, displayColor: AppTheme.cream, fontFamily: body);
  final buttonText = TextStyle(fontFamily: body, fontSize: 13, fontWeight: FontWeight.w500);
  const buttonPad = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
  final buttonShape = RoundedRectangleBorder(borderRadius: rc);

  return base.copyWith(
    textTheme: text,
    iconTheme: const IconThemeData(color: AppTheme.muted, size: 18),
    dividerTheme: const DividerThemeData(color: AppTheme.line, space: 1, thickness: 1),
    cardTheme: CardThemeData(
      color: AppTheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rPanel), side: const BorderSide(color: AppTheme.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTheme.surfaceHigh,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: border(AppTheme.line),
      enabledBorder: border(AppTheme.line),
      focusedBorder: border(AppTheme.lime),
      labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
      hintStyle: const TextStyle(color: AppTheme.faint, fontSize: 13),
      suffixIconColor: AppTheme.muted,
      prefixIconColor: AppTheme.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.lime,
        foregroundColor: AppTheme.ink,
        disabledBackgroundColor: AppTheme.surfaceHigh,
        disabledForegroundColor: AppTheme.faint,
        textStyle: buttonText.copyWith(fontWeight: FontWeight.w600),
        shape: buttonShape,
        padding: buttonPad,
        minimumSize: const Size(0, 34),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.cream,
        backgroundColor: AppTheme.surfaceHigh,
        side: const BorderSide(color: AppTheme.line),
        textStyle: buttonText,
        shape: buttonShape,
        padding: buttonPad,
        minimumSize: const Size(0, 34),
        iconColor: AppTheme.muted,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.cream,
        textStyle: buttonText,
        shape: buttonShape,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 32),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppTheme.muted,
        hoverColor: AppTheme.hover,
        shape: buttonShape,
        minimumSize: const Size(32, 32),
        padding: const EdgeInsets.all(6),
        iconSize: 18,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppTheme.ink : AppTheme.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppTheme.lime : AppTheme.surfaceHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppTheme.lime : AppTheme.lineStrong),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppTheme.lime,
      thumbColor: AppTheme.cream,
      inactiveTrackColor: AppTheme.lineStrong,
      overlayColor: Color(0x14CCFF00),
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0, pressedElevation: 0),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      showValueIndicator: ShowValueIndicator.never,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppTheme.surfaceHigh,
        selectedBackgroundColor: AppTheme.hover,
        selectedForegroundColor: AppTheme.cream,
        foregroundColor: AppTheme.muted,
        side: const BorderSide(color: AppTheme.line),
        shape: buttonShape,
        textStyle: buttonText.copyWith(fontSize: 12),
        visualDensity: VisualDensity.compact,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppTheme.cream,
      unselectedLabelColor: AppTheme.muted,
      labelStyle: TextStyle(fontFamily: body, fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontFamily: body, fontSize: 13, fontWeight: FontWeight.w500),
      indicatorColor: AppTheme.lime,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppTheme.line,
      dividerHeight: 1,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppTheme.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppTheme.line)),
      titleTextStyle: TextStyle(fontFamily: body, fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.cream),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppTheme.surfaceHigh,
      contentTextStyle: TextStyle(fontFamily: body, color: AppTheme.cream, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      width: 420,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rPanel), side: const BorderSide(color: AppTheme.line)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.line)),
      textStyle: TextStyle(fontFamily: body, color: AppTheme.cream, fontSize: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppTheme.surfaceHigh,
      elevation: 6,
      textStyle: TextStyle(fontFamily: body, fontSize: 13, color: AppTheme.cream),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rPanel), side: const BorderSide(color: AppTheme.line)),
    ),
    menuTheme: const MenuThemeData(style: MenuStyle(backgroundColor: WidgetStatePropertyAll(AppTheme.surfaceHigh))),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(AppTheme.surfaceHigh)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppTheme.lime, linearTrackColor: AppTheme.lineStrong),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AppTheme.lineStrong.withValues(alpha: 0.9)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
  );
}
