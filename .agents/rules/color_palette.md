# Strict Color Palette Rule

The application design is strictly restricted to ONLY the following 4 colors. No other colors may be introduced unless explicitly overridden by the user.

| Color Name | Hex Code | Purpose & Role |
| :--- | :--- | :--- |
| **Cloud Dancer** | `#F5F2EB` | Soft, high-legibility foundation for backgrounds, surfaces, and cards without harsh glare under bright sunlight. |
| **Royal Blue** | `#1A4B9C` | Primary brand anchor, establishing structural authority, institutional trust, and stability across navigation and headers. |
| **Emerald Green** | `#1E824C` | Applied situationally for positive outcomes, financial momentum, primary "Send" actions, and successful transfer confirmations. |
| **Crimson Red** | `#D32F2F` | Applied situationally for critical friction, warning banners, insufficient balance alerts, transaction failures, and destructive actions. |

### Implementation Constraints:
- Use `AppColors` constants defined in `lib/theme/app_colors.dart` everywhere.
- Never use random colors, default Flutter greens, purples, or unapproved shades.
