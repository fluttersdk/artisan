import 'package:vm_service/vm_service.dart';

import 'tinker.dart';

/// Formats a VM Service evaluate result for REPL output.
///
/// Walks [casters] in insertion order (default: `Tinker.casters`); the
/// first non-null caster return wins. Falls through to [formatInstanceRef]
/// when every caster returns null.
String formatTinkerResult(
  Object? value, {
  List<TinkerCaster>? casters,
}) {
  final chain = casters ?? Tinker.casters;
  for (final caster in chain) {
    final formatted = caster(value);
    if (formatted != null) return formatted;
  }
  return formatInstanceRef(value);
}

/// Best-effort pretty-print for a raw VM Service evaluate result.
///
/// Unwraps [InstanceRef] into the value the user typed at the prompt
/// instead of dumping the raw VM internal shape:
/// - Primitive scalars carry their printed form on `valueAsString`. The
///   string is returned verbatim, with `"..."` quoting added when the
///   underlying kind is `String`.
/// - Non-primitive [InstanceRef]s render as `<ClassName#id>`.
/// - [ErrorRef] renders as `Error: <message>`.
/// - Plain Dart objects fall through to their `toString`.
String formatInstanceRef(Object? value) {
  if (value == null) return 'null';
  if (value is InstanceRef) {
    final printed = value.valueAsString;
    if (printed != null) {
      return value.kind == 'String' ? '"$printed"' : printed;
    }
    final className = value.classRef?.name ?? 'Instance';
    return '<$className#${value.id ?? '?'}>';
  }
  if (value is ErrorRef) return 'Error: ${value.message ?? value.id}';
  return value.toString();
}
