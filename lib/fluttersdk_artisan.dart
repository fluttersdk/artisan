/// fluttersdk_artisan: canonical package-name barrel.
///
/// Re-exports the artisan public API from [package:fluttersdk_artisan/artisan.dart].
/// pub.dev convention prefers `lib/<package_name>.dart` as the primary
/// import target so users do not have to discover the alternative barrel
/// name. Both imports are equivalent:
///
/// ```dart
/// import 'package:fluttersdk_artisan/fluttersdk_artisan.dart';
/// import 'package:fluttersdk_artisan/artisan.dart';
/// ```
library;

export 'artisan.dart';
