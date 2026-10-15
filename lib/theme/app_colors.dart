import 'package:flutter/material.dart';

/// The official 4-color palette for Probashi Guard.
/// The application is strictly restricted to these four colors.
abstract final class AppColors {
  /// Soft, high-legibility foundation for backgrounds and cards (#F5F2EB).
  static const Color cloudDancer = Color(0xFFF5F2EB);

  /// Primary brand anchor across navigation and headers (#1A4B9C).
  static const Color royalBlue = Color(0xFF1A4B9C);

  /// Positive outcomes, momentum, send actions, and success confirmations (#1E824C).
  static const Color emeraldGreen = Color(0xFF1E824C);

  /// Critical friction, warnings, insufficient balance, failures, destructive actions (#D32F2F).
  static const Color crimsonRed = Color(0xFFD32F2F);
}
