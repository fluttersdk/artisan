import 'dart:io';

import 'package:xml/xml.dart';

/// Apple XML plist (v1.0) DOM writer for CLI plugin installers.
///
/// All mutations target the top-level `<dict>` element inside
/// `<plist version="1.0">`. Keys are identified by their `<key>` element;
/// the value is always the element that immediately follows the `<key>` in
/// document order among the dict's element children.
///
/// Every method is idempotent: calling it twice with the same arguments
/// produces the same file state as calling it once.
///
/// The file is written back via [XmlDocument.toXmlString] with
/// `pretty: true, indent: '\t'` (Apple plist convention uses hard tabs).
/// The XML declaration and DOCTYPE are preserved because the parser retains
/// them as [XmlProcessingInstruction] and [XmlDoctype] nodes.
///
/// ## Usage
///
/// ```dart
/// PlistWriter.setStringKey(
///   'ios/Runner/Info.plist',
///   'NSCameraUsageDescription',
///   'Required for QR scanning',
/// );
///
/// PlistWriter.appendToArrayKey(
///   'ios/Runner/Runner.entitlements',
///   'com.apple.developer.associated-domains',
///   'applinks:example.com',
/// );
/// ```
class PlistWriter {
  PlistWriter._();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Insert or update a `<key>K</key><string>V</string>` pair in the
  /// top-level `<dict>` of [plistPath].
  ///
  /// If [key] already exists with [value], the file is left unchanged.
  /// If [key] exists with a different value, the sibling value element is
  /// replaced in place.
  ///
  /// @param plistPath  Absolute or relative path to the `.plist` file.
  /// @param key        The plist key string.
  /// @param value      The string value to write.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if the file does not contain a root `<dict>`.
  static void setStringKey(String plistPath, String key, String value) {
    final doc = _parse(plistPath);
    final dict = _rootDict(plistPath, doc);

    final existing = _findValueElement(dict, key);
    if (existing != null) {
      // 1. Same value: idempotent no-op.
      if (existing.name.local == 'string' && existing.innerText == value) {
        return;
      }
      // 2. Different value: replace the sibling in place.
      final replacement = XmlElement(XmlName.parts('string'))
        ..children.add(XmlText(value));
      existing.replace(replacement);
    } else {
      // 3. Key is absent: append the pair.
      _appendPair(dict, key,
          XmlElement(XmlName.parts('string'))..children.add(XmlText(value)));
    }

    _write(plistPath, doc);
  }

  /// Insert or update a `<key>K</key><true/>` / `<key>K</key><false/>` pair
  /// in the top-level `<dict>` of [plistPath].
  ///
  /// If [key] already exists with the same boolean, the file is left unchanged.
  ///
  /// @param plistPath  Absolute or relative path to the `.plist` file.
  /// @param key        The plist key string.
  /// @param value      The boolean value to write.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if the file does not contain a root `<dict>`.
  static void setBoolKey(String plistPath, String key, bool value) {
    final tagName = value ? 'true' : 'false';
    final doc = _parse(plistPath);
    final dict = _rootDict(plistPath, doc);

    final existing = _findValueElement(dict, key);
    if (existing != null) {
      // 1. Same value: idempotent no-op.
      if (existing.name.local == tagName) {
        return;
      }
      // 2. Different value: replace in place.
      existing.replace(XmlElement(XmlName.parts(tagName)));
    } else {
      // 3. Key is absent: append the pair.
      _appendPair(dict, key, XmlElement(XmlName.parts(tagName)));
    }

    _write(plistPath, doc);
  }

  /// Insert or replace an `<array>` value for [key] in the top-level `<dict>`
  /// of [plistPath].
  ///
  /// Each item in [values] becomes a `<string>` child of the `<array>`.
  /// If [key] already exists its value element is replaced entirely regardless
  /// of previous contents.
  ///
  /// @param plistPath  Absolute or relative path to the `.plist` file.
  /// @param key        The plist key string.
  /// @param values     Ordered list of string values.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if the file does not contain a root `<dict>`.
  static void setArrayKey(String plistPath, String key, List<String> values) {
    final doc = _parse(plistPath);
    final dict = _rootDict(plistPath, doc);
    final arrayEl = _buildArray(values);

    final existing = _findValueElement(dict, key);
    if (existing != null) {
      // Replace the existing value element with the new array.
      existing.replace(arrayEl);
    } else {
      _appendPair(dict, key, arrayEl);
    }

    _write(plistPath, doc);
  }

  /// Append [value] as a `<string>` entry to the existing `<array>` for [key]
  /// in the top-level `<dict>` of [plistPath].
  ///
  /// Behavior:
  /// - If the array does not exist, a new `<array>` containing [value] is
  ///   created (equivalent to `setArrayKey(path, key, [value])`).
  /// - If [value] is already present in the array, the call is a no-op
  ///   (idempotent on duplicates).
  ///
  /// @param plistPath  Absolute or relative path to the `.plist` file.
  /// @param key        The plist key string.
  /// @param value      The string value to append.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if the file does not contain a root `<dict>`.
  static void appendToArrayKey(String plistPath, String key, String value) {
    final doc = _parse(plistPath);
    final dict = _rootDict(plistPath, doc);

    final existing = _findValueElement(dict, key);
    if (existing == null) {
      // 1. Key is absent: create a fresh single-element array.
      _appendPair(dict, key, _buildArray([value]));
      _write(plistPath, doc);
      return;
    }

    if (existing.name.local != 'array') {
      throw StateError(
        'Expected an <array> value for key "$key" in $plistPath, '
        'found <${existing.name.local}>.',
      );
    }

    // 2. Idempotency: skip if value already present.
    final currentStrings =
        existing.findElements('string').map((e) => e.innerText).toList();
    if (currentStrings.contains(value)) {
      return;
    }

    // 3. Append the new <string> child.
    existing.children
        .add(XmlElement(XmlName.parts('string'))..children.add(XmlText(value)));
    _write(plistPath, doc);
  }

  /// Remove the `<key>K</key>` element and its immediately following sibling
  /// value element from the top-level `<dict>` of [plistPath].
  ///
  /// If [key] is not present the call is a no-op (idempotent).
  ///
  /// @param plistPath  Absolute or relative path to the `.plist` file.
  /// @param key        The plist key string to remove.
  ///
  /// @throws [FileSystemException] if the file does not exist.
  /// @throws [StateError]          if the file does not contain a root `<dict>`.
  static void removeKey(String plistPath, String key) {
    final doc = _parse(plistPath);
    final dict = _rootDict(plistPath, doc);

    final keyEl = _findKeyElement(dict, key);
    if (keyEl == null) {
      return; // Idempotent no-op.
    }

    final valueEl = _findValueElement(dict, key);
    valueEl?.remove();
    keyEl.remove();

    _write(plistPath, doc);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Parse [plistPath] into an [XmlDocument].
  ///
  /// @throws [FileSystemException] if the file does not exist.
  static XmlDocument _parse(String plistPath) {
    final file = File(plistPath);
    if (!file.existsSync()) {
      throw FileSystemException('Plist file not found', plistPath);
    }
    return XmlDocument.parse(file.readAsStringSync());
  }

  /// Locate the root `<dict>` element inside the `<plist>` element.
  ///
  /// @throws [StateError] if no `<dict>` is found.
  static XmlElement _rootDict(String plistPath, XmlDocument doc) {
    final plistEl = doc.findElements('plist').firstOrNull;
    final dictEl = plistEl?.findElements('dict').firstOrNull;
    if (dictEl == null) {
      throw StateError('No root <dict> found in plist: $plistPath');
    }
    return dictEl;
  }

  /// Find the `<key>` element whose text content equals [key] among the
  /// direct element children of [dict].
  ///
  /// Returns `null` when [key] is not present.
  static XmlElement? _findKeyElement(XmlElement dict, String key) {
    for (final child in dict.childElements) {
      if (child.name.local == 'key' && child.innerText == key) {
        return child;
      }
    }
    return null;
  }

  /// Find the value element that immediately follows the `<key>` element
  /// matching [key] in [dict]'s element children.
  ///
  /// Returns `null` when [key] is not present.
  static XmlElement? _findValueElement(XmlElement dict, String key) {
    final elements = dict.childElements.toList();
    for (var i = 0; i < elements.length - 1; i++) {
      if (elements[i].name.local == 'key' && elements[i].innerText == key) {
        return elements[i + 1];
      }
    }
    return null;
  }

  /// Build an `<array>` element whose children are `<string>` elements, one
  /// per entry in [values].
  static XmlElement _buildArray(List<String> values) {
    final array = XmlElement(XmlName.parts('array'));
    for (final v in values) {
      array.children
          .add(XmlElement(XmlName.parts('string'))..children.add(XmlText(v)));
    }
    return array;
  }

  /// Append a `<key>` + [valueEl] pair to [dict].
  static void _appendPair(XmlElement dict, String key, XmlElement valueEl) {
    dict.children
        .add(XmlElement(XmlName.parts('key'))..children.add(XmlText(key)));
    dict.children.add(valueEl);
  }

  /// Serialise [doc] back to [plistPath] using Apple plist tab indentation.
  static void _write(String plistPath, XmlDocument doc) {
    File(plistPath).writeAsStringSync(
      doc.toXmlString(pretty: true, indent: '\t'),
    );
  }
}
