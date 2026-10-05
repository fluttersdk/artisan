import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../installer/android_intent_filter.dart';

/// XML and Plist file manipulation helper for CLI commands.
///
/// Provides string/regex-based utilities for reading and modifying XML files
/// (Android manifests, iOS plist files). Package `xml` is used only where a
/// decision needs the structure (is this activity already declared, and with
/// which filters); every write is a string splice so the rest of the file keeps
/// its bytes. All mutation methods are idempotent unless the task spec states
/// otherwise.
///
/// ## Usage
///
/// ```dart
/// // Read raw XML content
/// final content = XmlEditor.read('/path/to/AndroidManifest.xml');
///
/// // Add an Android permission (idempotent)
/// XmlEditor.addAndroidPermission(
///   '/path/to/AndroidManifest.xml',
///   'android.permission.POST_NOTIFICATIONS',
/// );
///
/// // Read Info.plist key-value pairs
/// final info = XmlEditor.readPlist('/path/to/Info.plist');
/// print(info['CFBundleName']); // MyApp
/// ```
class XmlEditor {
  XmlEditor._();

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Read the raw XML content from [path].
  ///
  /// @param path  Absolute or relative path to the XML file.
  /// @return The file content as a [String].
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('XML file not found', path);
    }
    return file.readAsStringSync();
  }

  // -------------------------------------------------------------------------
  // Inspection
  // -------------------------------------------------------------------------

  /// Check whether [pattern] is present anywhere inside the XML file.
  ///
  /// This is a simple [String.contains] search — not a structural query.
  ///
  /// @param path     Path to the XML file.
  /// @param pattern  Literal string to search for.
  /// @return `true` if the pattern was found, `false` otherwise.
  static bool hasElement(String path, String pattern) {
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    return file.readAsStringSync().contains(pattern);
  }

  // -------------------------------------------------------------------------
  // Generic insertion
  // -------------------------------------------------------------------------

  /// Insert [element] directly before [parentXpath] in the XML file.
  ///
  /// [parentXpath] is treated as a literal closing tag string, e.g.
  /// `</manifest>`. The method is idempotent: if [element] already appears
  /// in the file it will not be inserted again.
  ///
  /// @param path         Path to the XML file.
  /// @param parentXpath  Literal closing tag string used as the anchor.
  /// @param element      XML element string to insert.
  ///
  /// @throws [StateError] if [parentXpath] is not found in the file.
  static void addElement(String path, String parentXpath, String element) {
    var content = read(path);

    // 1. Idempotency check — skip when element is already present.
    if (content.contains(element)) {
      return;
    }

    // 2. Locate the anchor closing tag.
    if (!content.contains(parentXpath)) {
      throw StateError('Cannot find anchor "$parentXpath" in XML file: $path');
    }

    // 3. Insert element immediately before the anchor.
    content = content.replaceFirst(parentXpath, '$element\n$parentXpath');

    File(path).writeAsStringSync(content);
  }

  // -------------------------------------------------------------------------
  // Android manifest helpers
  // -------------------------------------------------------------------------

  /// Add a `<uses-permission>` element to an Android manifest.
  ///
  /// The tag is inserted immediately before `</manifest>`. The operation is
  /// idempotent — if [permission] is already referenced anywhere in the file
  /// the method returns without making changes.
  ///
  /// @param manifestPath  Path to `AndroidManifest.xml`.
  /// @param permission    The full Android permission string, e.g.
  ///                      `android.permission.POST_NOTIFICATIONS`.
  ///
  /// @throws [FileSystemException] if the manifest file is not found.
  /// @throws [StateError]          if `</manifest>` is not present in the file.
  static void addAndroidPermission(String manifestPath, String permission) {
    var content = read(manifestPath);

    // 1. Idempotency — skip when the permission is already declared.
    if (content.contains(permission)) {
      return;
    }

    // 2. Validate the manifest structure before mutating.
    if (!content.contains('</manifest>')) {
      throw StateError('Cannot find </manifest> closing tag in: $manifestPath');
    }

    // 3. Build and insert the permission element.
    final tag = '  <uses-permission android:name="$permission"/>';
    content = content.replaceFirst('</manifest>', '$tag\n</manifest>');

    File(manifestPath).writeAsStringSync(content);
  }

  /// Add a `<meta-data>` element inside the `<application>` block of an
  /// Android manifest.
  ///
  /// The element is inserted at the start of the `<application>` content
  /// (right after the opening `<application...>` tag). The operation is
  /// idempotent — if [name] already appears in the file the method returns
  /// without making changes.
  ///
  /// @param manifestPath  Path to `AndroidManifest.xml`.
  /// @param name          Value for `android:name` attribute.
  /// @param value         Value for `android:value` attribute.
  ///
  /// @throws [FileSystemException] if the manifest file is not found.
  /// @throws [StateError]          if no `<application` opening tag is found.
  static void addAndroidMetaData(
    String manifestPath, {
    required String name,
    required String value,
  }) {
    var content = read(manifestPath);

    // 1. Idempotency — skip when meta-data with this name is already present.
    if (content.contains('android:name="$name"')) {
      return;
    }

    // 2. Find the <application ...> opening tag (may span multiple attributes).
    final appTagMatch = RegExp(
      r'<application[^>]*>',
      dotAll: true,
    ).firstMatch(content);
    if (appTagMatch == null) {
      throw StateError(
        'Cannot find <application> opening tag in: $manifestPath',
      );
    }

    // 3. Build the meta-data element and insert after the opening tag.
    final tag = '    <meta-data android:name="$name" android:value="$value"/>';
    final applicationTag = appTagMatch.group(0)!;
    content = content.replaceFirst(applicationTag, '$applicationTag\n$tag');

    File(manifestPath).writeAsStringSync(content);
  }

  /// Add an `<activity>` element to the `<application>` block of an Android
  /// manifest.
  ///
  /// The manifest is parsed with package `xml` to decide, and the element is
  /// then spliced in as text immediately before `</application>`, so every
  /// other byte of the file stays as it was. Idempotency compares content, not
  /// only the name:
  ///
  /// - No `<activity>` with this `android:name` under `<application>` (a name
  ///   inside an XML comment does not count): the element is inserted.
  /// - One exists with an equal set of `<intent-filter>` elements (same
  ///   `autoVerify`, actions, categories and `<data>` attributes, in any order):
  ///   no-op.
  /// - One exists with a different set: the file is left alone and
  ///   [AndroidActivityOutcome.conflict] is returned. The activity may be
  ///   hand-edited, so it is never rewritten; the caller reports it.
  ///
  /// `android:exported` and `android:taskAffinity` are not part of the
  /// comparison.
  ///
  /// @param manifestPath    Path to `AndroidManifest.xml`.
  /// @param name            Value for `android:name`.
  /// @param exported        Value for `android:exported`.
  /// @param taskAffinity    Value for `android:taskAffinity`; `''` renders an
  ///                        empty affinity, `null` omits the attribute.
  /// @param intentFilters   The filters the activity must declare.
  /// @return What was done; see [AndroidActivityOutcome].
  ///
  /// @throws [FileSystemException] if the manifest file is not found.
  /// @throws [XmlException]        if the manifest is not well-formed XML.
  /// @throws [StateError]          if the manifest has no `<application>`
  ///                               element with a closing tag.
  static AndroidActivityOutcome addAndroidActivity(
    String manifestPath, {
    required String name,
    required bool exported,
    String? taskAffinity,
    List<AndroidIntentFilter> intentFilters = const <AndroidIntentFilter>[],
  }) {
    final content = read(manifestPath);

    // 1. Parse for detection only; the parsed tree is never written back.
    final application = XmlDocument.parse(content)
        .rootElement
        .findElements('application')
        .firstOrNull;
    if (application == null) {
      throw StateError('Cannot find <application> element in: $manifestPath');
    }

    // 2. Compare content, not only the name, so a hand-edited activity is
    //    reported instead of being skipped silently or rewritten.
    final existing = application
        .findElements('activity')
        .where((e) => e.getAttribute('name', namespace: _androidNs) == name)
        .firstOrNull;
    if (existing != null) {
      return _sameFilters(existing, intentFilters)
          ? AndroidActivityOutcome.unchanged
          : AndroidActivityOutcome.conflict;
    }

    // 3. Anchor on the real closing tag; one inside a comment is not it.
    final anchor = _maskComments(content).lastIndexOf('</application>');
    if (anchor == -1) {
      throw StateError(
        'Cannot find </application> closing tag in: $manifestPath',
      );
    }

    // 4. Splice the block in one indent level deeper than the closing tag.
    final eol = content.contains('\r\n') ? '\r\n' : '\n';
    final lineStart = content.lastIndexOf('\n', anchor - 1) + 1;
    final leading = content.substring(lineStart, anchor);
    final onOwnLine = leading.trim().isEmpty;
    final childIndent = '${onOwnLine ? leading : ''}    ';
    final block = renderAndroidActivity(
      name: name,
      exported: exported,
      taskAffinity: taskAffinity,
      intentFilters: intentFilters,
    ).split('\n').map((line) => '$childIndent$line').join(eol);

    File(manifestPath).writeAsStringSync(
      onOwnLine
          ? content.replaceRange(lineStart, lineStart, '$block$eol')
          : content.replaceRange(anchor, anchor, '$eol$block$eol'),
    );
    return AndroidActivityOutcome.added;
  }

  /// The `<activity>` element [addAndroidActivity] would insert, indented from
  /// column zero with four spaces per level and `\n` line breaks.
  ///
  /// Also what a caller shows an operator when a hand-edited activity of the
  /// same name blocked the write. Attribute values are escaped.
  ///
  /// @param name           Value for `android:name`.
  /// @param exported       Value for `android:exported`.
  /// @param taskAffinity   Value for `android:taskAffinity`, or `null` to omit.
  /// @param intentFilters  The filters the activity declares.
  static String renderAndroidActivity({
    required String name,
    required bool exported,
    String? taskAffinity,
    List<AndroidIntentFilter> intentFilters = const <AndroidIntentFilter>[],
  }) {
    final attributes = <String>[
      _attribute('name', name),
      _attribute('exported', '$exported'),
      if (taskAffinity != null) _attribute('taskAffinity', taskAffinity),
    ];
    final open = '<activity\n${attributes.map((a) => '    $a').join('\n')}';
    if (intentFilters.isEmpty) return '$open/>';

    return <String>[
      '$open>',
      for (final filter in intentFilters) ..._renderIntentFilter(filter),
      '</activity>',
    ].join('\n');
  }

  // -------------------------------------------------------------------------
  // Plist
  // -------------------------------------------------------------------------

  /// Parse basic string key-value pairs from an Apple Plist XML file.
  ///
  /// Only top-level `<key>` → `<string>` pairs inside the root `<dict>` are
  /// extracted. Nested structures, arrays, booleans, and integers are ignored.
  ///
  /// @param plistPath  Path to the `.plist` file.
  /// @return A [Map<String, dynamic>] of the extracted string values.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static Map<String, dynamic> readPlist(String plistPath) {
    final content = read(plistPath);
    final result = <String, dynamic>{};

    // Match consecutive <key>…</key> <string>…</string> pairs.
    final keyPattern = RegExp(r'<key>([^<]+)</key>\s*<string>([^<]*)</string>');

    for (final match in keyPattern.allMatches(content)) {
      final key = match.group(1)!.trim();
      final val = match.group(2)!;
      result[key] = val;
    }

    return result;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Namespace the Android manifest binds its `android:` attributes to.
  static const String _androidNs = 'http://schemas.android.com/apk/res/android';

  /// Renders `android:[local]="[value]"` with the value escaped for a
  /// double-quoted attribute.
  static String _attribute(String local, String value) {
    final escaped = const XmlDefaultEntityMapping.xml()
        .encodeAttributeValue(value, XmlAttributeType.DOUBLE_QUOTE);
    return 'android:$local="$escaped"';
  }

  /// Renders one `<intent-filter>` indented one level, as lines.
  static List<String> _renderIntentFilter(AndroidIntentFilter filter) {
    return <String>[
      filter.autoVerify
          ? '    <intent-filter android:autoVerify="true">'
          : '    <intent-filter>',
      for (final action in filter.actions)
        '        <action ${_attribute('name', action)}/>',
      for (final category in filter.categories)
        '        <category ${_attribute('name', category)}/>',
      for (final data in filter.data)
        '        <data ${data.attributes.entries.map((e) => _attribute(e.key, e.value)).join(' ')}/>',
      '    </intent-filter>',
    ];
  }

  /// Copy of [content] with every comment blanked to spaces of the same
  /// length, so an offset found in it is valid in [content] and a tag spelled
  /// inside a comment cannot be found.
  static String _maskComments(String content) {
    return content.replaceAllMapped(
      RegExp(r'<!--.*?-->', dotAll: true),
      (match) => ' ' * match.group(0)!.length,
    );
  }

  /// Whether the `<intent-filter>` children of [activity] are exactly
  /// [expected], ignoring order within and between filters.
  static bool _sameFilters(
    XmlElement activity,
    List<AndroidIntentFilter> expected,
  ) {
    final declared = <String>{
      for (final filter in activity.findElements('intent-filter'))
        _signature(
          autoVerify:
              filter.getAttribute('autoVerify', namespace: _androidNs) ==
                  'true',
          actions: _names(filter, 'action'),
          categories: _names(filter, 'category'),
          data: [
            for (final data in filter.findElements('data'))
              {
                for (final attribute in data.attributes)
                  if (attribute.namespaceUri == _androidNs)
                    attribute.name.local: attribute.value,
              },
          ],
        ),
    };
    final wanted = <String>{
      for (final filter in expected)
        _signature(
          autoVerify: filter.autoVerify,
          actions: filter.actions,
          categories: filter.categories,
          data: [for (final data in filter.data) data.attributes],
        ),
    };
    return declared.length == wanted.length && declared.containsAll(wanted);
  }

  /// The `android:name` of every [tag] child of [filter].
  static List<String> _names(XmlElement filter, String tag) {
    return <String>[
      for (final element in filter.findElements(tag))
        if (element.getAttribute('name', namespace: _androidNs)
            case final name?)
          name,
    ];
  }

  /// Order-independent canonical form of one intent filter, so two filters
  /// compare equal exactly when a device would treat them alike.
  static String _signature({
    required bool autoVerify,
    required Iterable<String> actions,
    required Iterable<String> categories,
    required Iterable<Map<String, String>> data,
  }) {
    List<String> sorted(Iterable<String> values) => values.toList()..sort();

    String canonical(Map<String, String> attributes) {
      final keys = attributes.keys.toList()..sort();
      return jsonEncode(<List<String>>[
        for (final key in keys) <String>[key, attributes[key]!],
      ]);
    }

    return jsonEncode(<Object>[
      autoVerify,
      sorted(actions),
      sorted(categories),
      sorted(data.map(canonical)),
    ]);
  }
}
