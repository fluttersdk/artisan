import 'dart:io';

/// Xcode project (`project.pbxproj`) build-setting writer for the installer.
///
/// A `.pbxproj` is an OpenStep plist, not XML, so none of the XML-backed
/// helpers can touch it. This editor exists for exactly one job: pointing the
/// application target at an entitlements file. Writing `Runner.entitlements`
/// to disk is not enough on its own, because Xcode only reads that file when
/// the target's `CODE_SIGN_ENTITLEMENTS` build setting names it.
///
/// Three invariants make it safe to run against a real project:
///
/// 1. **Round-trip proof before any write.** The file is parsed into a
///    trivia-preserving tree and re-emitted; unless the re-emission matches
///    the original byte for byte, the editor throws and writes nothing. A
///    project it cannot reproduce exactly is a project it must not edit,
///    because a corrupt `.pbxproj` makes the project unopenable and the
///    installer does not roll helper-backed writes back.
/// 2. **Application-target scoping.** A stock Flutter project holds nine
///    `XCBuildConfiguration` blocks: three for the app, three for the test
///    bundle and three project-level defaults. Only the three reachable from
///    the `PBXNativeTarget` whose `productType` is
///    `com.apple.product-type.application` are touched. Signing entitlements
///    on a test bundle is a build failure, not a harmless extra.
/// 3. **No repointing.** A project already signing with a different
///    entitlements file keeps it, and the paths that blocked the write come
///    back to the caller. Overwriting would unsign whatever that file grants,
///    which the macOS Flutter template relies on.
///
/// The operation is idempotent: a second call with the same path leaves the
/// file byte-identical and performs no write at all.
///
/// ## Usage
///
/// ```dart
/// XcodeProjectEditor.setEntitlementsPath(
///   'ios/Runner.xcodeproj/project.pbxproj',
///   'Runner/Runner.entitlements',
/// );
/// ```
final class XcodeProjectEditor {
  XcodeProjectEditor._();

  /// Build setting naming the entitlements file that signs the product.
  static const String _entitlementsSetting = 'CODE_SIGN_ENTITLEMENTS';

  /// `isa` value of a buildable native target.
  static const String _nativeTargetIsa = 'PBXNativeTarget';

  /// `productType` identifying the application target among the native ones.
  static const String _applicationProductType =
      'com.apple.product-type.application';

  /// Target name the Flutter templates give the application target; used only
  /// to disambiguate a project that declares more than one application.
  static const String _flutterTargetName = 'Runner';

  /// Placeholder reported when a configuration holds a non-string value under
  /// the setting; it still blocks the write.
  static const String _nonStringValue = '<non-string value>';

  /// Point every build configuration of the application target in
  /// [pbxprojPath] at [entitlementsPath].
  ///
  /// [entitlementsPath] is written verbatim as the build-setting value, so it
  /// must be expressed the way Xcode resolves it: relative to the directory
  /// holding the `.xcodeproj`, e.g. `Runner/Runner.entitlements`.
  ///
  /// A project that already signs with a DIFFERENT entitlements file is left
  /// alone and reported back instead: repointing it would silently drop
  /// whatever that file grants, and the macOS Flutter template ships exactly
  /// that case (`Runner/DebugProfile.entitlements` plus
  /// `Runner/Release.entitlements`). The caller decides how loudly to say so.
  ///
  /// @param pbxprojPath       Path to `<platform>/Runner.xcodeproj/project.pbxproj`.
  /// @param entitlementsPath  Project-relative path to the entitlements file.
  /// @return The distinct entitlements paths already configured that blocked
  ///         the write, or an empty set when every configuration of the
  ///         application target now names [entitlementsPath].
  ///
  /// @throws [FileSystemException]  if the project file does not exist.
  /// @throws [FormatException]      if the project file cannot be parsed.
  /// @throws [StateError]           if the parsed project does not re-emit
  ///                                byte for byte, or if no single application
  ///                                target and its configurations can be
  ///                                resolved. Nothing is written in either
  ///                                case.
  static Set<String> setEntitlementsPath(
    String pbxprojPath,
    String entitlementsPath,
  ) {
    final file = File(pbxprojPath);
    if (!file.existsSync()) {
      throw FileSystemException('Xcode project file not found', pbxprojPath);
    }

    // 1. Parse the OpenStep plist, keeping every byte of whitespace and
    //    comment trivia so the document can be re-emitted unchanged.
    final original = file.readAsStringSync();
    final document = _PbxParser(original, pbxprojPath).parseDocument();

    // 2. Safety gate: prove the parse understood the whole file before
    //    trusting it to write one back.
    if (document.emit() != original) {
      throw StateError(
        'Refusing to edit $pbxprojPath: the parsed project does not re-emit '
        'byte for byte, so an edit could corrupt it. Set '
        '$_entitlementsSetting by hand in Xcode instead.',
      );
    }

    // 3. Resolve the application target's own build configurations, never
    //    the test bundle's and never the project-level defaults.
    final objects = _objectsOf(document, pbxprojPath);
    final target = _applicationTarget(objects, pbxprojPath);
    final settings = _buildSettingsOf(objects, target, pbxprojPath);

    // 4. All-or-nothing: one configuration pointing somewhere else blocks the
    //    whole write, because signing the same product against two different
    //    entitlements files depending on the configuration is worse than not
    //    writing at all.
    final conflicting = <String>{};
    for (final dict in settings) {
      final current = dict.valueFor(_entitlementsSetting);
      if (current == null) continue;
      if (current is _PbxString && current.value == entitlementsPath) continue;
      conflicting.add(
        current is _PbxString ? current.value : _nonStringValue,
      );
    }
    if (conflicting.isNotEmpty) return conflicting;

    // 5. Insert where missing, and skip the write entirely when nothing
    //    changed so a re-install leaves the file (and its hash) alone.
    var changed = false;
    for (final dict in settings) {
      if (_insertString(dict, _entitlementsSetting, entitlementsPath)) {
        changed = true;
      }
    }
    if (changed) {
      // The installer does not roll helper-backed writes back and a truncated
      // .pbxproj cannot be opened, so land the new content through a sibling
      // temp file and one rename rather than in place.
      final staged = File('$pbxprojPath.tmp')
        ..writeAsStringSync(document.emit());
      staged.renameSync(pbxprojPath);
    }
    return const <String>{};
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Resolve the root `objects` dictionary, which maps every object ID in the
  /// project to its definition.
  static _PbxDict _objectsOf(_PbxDocument document, String path) {
    final root = document.root;
    if (root is! _PbxDict) {
      throw StateError('Root of $path is not a dictionary.');
    }
    final objects = root.dictFor('objects');
    if (objects == null) {
      throw StateError('No "objects" dictionary in $path.');
    }
    return objects;
  }

  /// Locate the single application target among the project's native targets.
  ///
  /// A stock Flutter project has exactly one. When a project declares several
  /// (an app plus an extension, say) the one named `Runner` wins; anything
  /// more ambiguous throws rather than guessing which product to sign.
  static _PbxDict _applicationTarget(_PbxDict objects, String path) {
    final applications = <_PbxDict>[];
    for (final entry in objects.entries) {
      final object = entry.value;
      if (object is! _PbxDict) continue;
      if (object.stringFor('isa') != _nativeTargetIsa) continue;
      if (object.stringFor('productType') != _applicationProductType) continue;
      applications.add(object);
    }

    if (applications.isEmpty) {
      throw StateError(
        'No $_nativeTargetIsa with productType $_applicationProductType in '
        '$path; there is no application target to sign.',
      );
    }
    if (applications.length == 1) {
      return applications.single;
    }

    final named = applications
        .where((target) => target.stringFor('name') == _flutterTargetName)
        .toList();
    if (named.length == 1) {
      return named.single;
    }
    throw StateError(
      '$path declares ${applications.length} application targets and none is '
      'uniquely named "$_flutterTargetName"; refusing to guess which one to '
      'sign.',
    );
  }

  /// Collect the `buildSettings` dictionary of every build configuration
  /// listed by [target]'s own `XCConfigurationList`.
  static List<_PbxDict> _buildSettingsOf(
    _PbxDict objects,
    _PbxDict target,
    String path,
  ) {
    final listId = target.stringFor('buildConfigurationList');
    if (listId == null) {
      throw StateError('Application target in $path has no '
          'buildConfigurationList.');
    }
    final list = objects.valueFor(listId);
    if (list is! _PbxDict) {
      throw StateError('buildConfigurationList $listId is missing from the '
          'objects of $path.');
    }
    final configurations = list.arrayFor('buildConfigurations');
    if (configurations == null || configurations.items.isEmpty) {
      throw StateError('Configuration list $listId in $path holds no build '
          'configurations.');
    }

    final settings = <_PbxDict>[];
    for (final item in configurations.items) {
      final reference = item.value;
      if (reference is! _PbxString) {
        throw StateError('Configuration list $listId in $path holds a '
            'non-identifier entry.');
      }
      final configuration = objects.valueFor(reference.value);
      if (configuration is! _PbxDict) {
        throw StateError('Build configuration ${reference.value} is missing '
            'from the objects of $path.');
      }
      final buildSettings = configuration.dictFor('buildSettings');
      if (buildSettings == null) {
        throw StateError('Build configuration ${reference.value} in $path has '
            'no buildSettings dictionary.');
      }
      settings.add(buildSettings);
    }
    return settings;
  }

  /// Insert `key = value;` into [settings] when the key is absent.
  ///
  /// The new key lands in alphabetical position, matching how Xcode itself
  /// orders build settings, and copies its neighbour's indentation so the
  /// emitted line is indistinguishable from a hand-written one.
  ///
  /// @return `true` when the dictionary changed, `false` when [key] is already
  ///         present. The caller has already proved a present key carries
  ///         [value], so this is the idempotent case.
  static bool _insertString(_PbxDict settings, String key, String value) {
    for (final entry in settings.entries) {
      if (entry.key == key) return false;
    }

    final index =
        settings.entries.indexWhere((entry) => entry.key.compareTo(key) > 0);
    final anchor = index >= 0
        ? settings.entries[index]
        : (settings.entries.isEmpty ? null : settings.entries.last);
    final entry = _PbxEntry(
      leadingTrivia: anchor?.leadingTrivia ?? '${settings.trailingTrivia}\t',
      key: key,
      keyWasQuoted: false,
      beforeEquals: ' ',
      afterEquals: ' ',
      value: _PbxString(value),
      beforeSemicolon: '',
    );

    if (index >= 0) {
      settings.entries.insert(index, entry);
    } else {
      settings.entries.add(entry);
    }
    return true;
  }
}

/// A parsed OpenStep plist document: the root value plus the trivia framing
/// it (the `// !$*UTF8*$!` header line and the trailing newline).
final class _PbxDocument {
  _PbxDocument({
    required this.leadingTrivia,
    required this.root,
    required this.trailingTrivia,
  });

  final String leadingTrivia;
  final _PbxValue root;
  final String trailingTrivia;

  /// Serialise the document back to text.
  String emit() {
    final out = StringBuffer()..write(leadingTrivia);
    root.emit(out);
    out.write(trailingTrivia);
    return out.toString();
  }
}

/// A value in an OpenStep plist: a string, a dictionary or an array.
sealed class _PbxValue {
  /// Append this value's text form to [out].
  void emit(StringBuffer out);
}

/// A string value, held unescaped and unquoted.
///
/// [wasQuoted] records how the source spelled it. Xcode quotes more than its
/// own character rules require (a real project holds `path = "Runner.app";`
/// beside `path = Runner.app;`), so re-deriving quotation from the content
/// alone would flag nine of the projects in this workspace as unreproducible
/// and refuse to edit them. Keeping the original decision leaves the
/// round-trip guard measuring what it is for: that every byte was tokenised
/// and every escape understood.
final class _PbxString extends _PbxValue {
  _PbxString(this.value, {this.wasQuoted = false});

  final String value;
  final bool wasQuoted;

  /// Whether [unit] may appear in an unquoted token.
  ///
  /// This predicate is shared by both halves of the round trip: the parser
  /// scans an unquoted token with it and [quote] refuses to emit a bare token
  /// without it.
  static bool isBareUnit(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || // A-Z
      (unit >= 0x61 && unit <= 0x7A) || // a-z
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      unit == 0x5F || // _
      unit == 0x2E || // .
      unit == 0x2F; //  /

  /// Render [raw] as a token: bare when every character allows it and
  /// [quoted] is false, quoted and escaped otherwise.
  static String quote(String raw, {bool quoted = false}) {
    if (!quoted && raw.isNotEmpty && raw.codeUnits.every(isBareUnit)) {
      return raw;
    }
    final escaped = raw
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }

  @override
  void emit(StringBuffer out) => out.write(quote(value, quoted: wasQuoted));
}

/// A dictionary value. [entries] keeps document order; [trailingTrivia] is
/// whatever sits between the last entry and the closing brace.
final class _PbxDict extends _PbxValue {
  final List<_PbxEntry> entries = <_PbxEntry>[];
  String trailingTrivia = '';

  /// Value stored under [key], or `null` when the key is absent.
  _PbxValue? valueFor(String key) {
    for (final entry in entries) {
      if (entry.key == key) return entry.value;
    }
    return null;
  }

  /// [key]'s value when it is a string, `null` otherwise.
  String? stringFor(String key) {
    final value = valueFor(key);
    return value is _PbxString ? value.value : null;
  }

  /// [key]'s value when it is a dictionary, `null` otherwise.
  _PbxDict? dictFor(String key) {
    final value = valueFor(key);
    return value is _PbxDict ? value : null;
  }

  /// [key]'s value when it is an array, `null` otherwise.
  _PbxArray? arrayFor(String key) {
    final value = valueFor(key);
    return value is _PbxArray ? value : null;
  }

  @override
  void emit(StringBuffer out) {
    out.write('{');
    for (final entry in entries) {
      entry.emit(out);
    }
    out
      ..write(trailingTrivia)
      ..write('}');
  }
}

/// An array value. [trailingTrivia] is whatever sits between the last comma
/// (or the opening paren, for an empty array) and the closing paren.
final class _PbxArray extends _PbxValue {
  final List<_PbxItem> items = <_PbxItem>[];
  String trailingTrivia = '';

  @override
  void emit(StringBuffer out) {
    out.write('(');
    for (final item in items) {
      item.emit(out);
    }
    out
      ..write(trailingTrivia)
      ..write(')');
  }
}

/// One `key = value;` pair, carrying every byte of trivia around its tokens
/// so the dictionary re-emits unchanged.
final class _PbxEntry {
  _PbxEntry({
    required this.leadingTrivia,
    required this.key,
    required this.keyWasQuoted,
    required this.beforeEquals,
    required this.afterEquals,
    required this.value,
    required this.beforeSemicolon,
  });

  final String leadingTrivia;
  final String key;
  final bool keyWasQuoted;
  final String beforeEquals;
  final String afterEquals;
  final String beforeSemicolon;
  final _PbxValue value;

  /// Append this entry's text form to [out].
  void emit(StringBuffer out) {
    out
      ..write(leadingTrivia)
      ..write(_PbxString.quote(key, quoted: keyWasQuoted))
      ..write(beforeEquals)
      ..write('=')
      ..write(afterEquals);
    value.emit(out);
    out
      ..write(beforeSemicolon)
      ..write(';');
  }
}

/// One array element, with the trivia around it and whether it was followed
/// by a comma (Xcode writes one after every element, including the last).
final class _PbxItem {
  _PbxItem({
    required this.leadingTrivia,
    required this.value,
    required this.beforeComma,
    required this.hasComma,
  });

  final String leadingTrivia;
  final _PbxValue value;
  final String beforeComma;
  final bool hasComma;

  /// Append this element's text form to [out].
  void emit(StringBuffer out) {
    out.write(leadingTrivia);
    value.emit(out);
    out.write(beforeComma);
    if (hasComma) out.write(',');
  }
}

/// Recursive-descent parser for the OpenStep plist subset Xcode writes:
/// dictionaries, arrays, bare and quoted strings, `//` and block comments.
///
/// It is deliberately strict. Anything it does not recognise raises a
/// [FormatException] rather than being skipped, and anything it recognises
/// but cannot reproduce is caught by the caller's round-trip comparison.
final class _PbxParser {
  _PbxParser(this._source, this._path);

  final String _source;
  final String _path;
  int _offset = 0;

  /// Parse the whole document, rejecting trailing content.
  _PbxDocument parseDocument() {
    final leadingTrivia = _readTrivia();
    final root = _parseValue();
    final trailingTrivia = _readTrivia();
    if (_offset != _source.length) {
      _fail('Unexpected content after the root object');
    }
    return _PbxDocument(
      leadingTrivia: leadingTrivia,
      root: root,
      trailingTrivia: trailingTrivia,
    );
  }

  /// Consume whitespace, `//` line comments and `/* */` block comments.
  String _readTrivia() {
    final start = _offset;
    while (_offset < _source.length) {
      final unit = _source.codeUnitAt(_offset);
      if (unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D) {
        _offset++;
        continue;
      }
      if (unit != 0x2F || _offset + 1 >= _source.length) break;
      final next = _source.codeUnitAt(_offset + 1);
      if (next == 0x2F) {
        final lineEnd = _source.indexOf('\n', _offset);
        _offset = lineEnd == -1 ? _source.length : lineEnd;
        continue;
      }
      if (next == 0x2A) {
        final close = _source.indexOf('*/', _offset + 2);
        if (close == -1) _fail('Unterminated block comment');
        _offset = close + 2;
        continue;
      }
      break;
    }
    return _source.substring(start, _offset);
  }

  /// Parse a dictionary, an array or a string, whichever comes next.
  _PbxValue _parseValue() {
    if (_offset >= _source.length) _fail('Expected a value');
    final unit = _source.codeUnitAt(_offset);
    if (unit == 0x7B) return _parseDict();
    if (unit == 0x28) return _parseArray();
    return _parseString();
  }

  /// Parse `{ key = value; ... }`.
  _PbxDict _parseDict() {
    _expect(0x7B, '{');
    final dict = _PbxDict();
    while (true) {
      final leadingTrivia = _readTrivia();
      if (_peekIs(0x7D)) {
        dict.trailingTrivia = leadingTrivia;
        _offset++;
        return dict;
      }
      final key = _parseString();
      final beforeEquals = _readTrivia();
      _expect(0x3D, '=');
      final afterEquals = _readTrivia();
      final value = _parseValue();
      final beforeSemicolon = _readTrivia();
      _expect(0x3B, ';');
      dict.entries.add(
        _PbxEntry(
          leadingTrivia: leadingTrivia,
          key: key.value,
          keyWasQuoted: key.wasQuoted,
          beforeEquals: beforeEquals,
          afterEquals: afterEquals,
          value: value,
          beforeSemicolon: beforeSemicolon,
        ),
      );
    }
  }

  /// Parse `( value, value, )`.
  _PbxArray _parseArray() {
    _expect(0x28, '(');
    final array = _PbxArray();
    while (true) {
      final leadingTrivia = _readTrivia();
      if (_peekIs(0x29)) {
        array.trailingTrivia = leadingTrivia;
        _offset++;
        return array;
      }
      final value = _parseValue();
      final beforeComma = _readTrivia();
      final hasComma = _peekIs(0x2C);
      if (hasComma) _offset++;
      array.items.add(
        _PbxItem(
          leadingTrivia: leadingTrivia,
          value: value,
          beforeComma: beforeComma,
          hasComma: hasComma,
        ),
      );
      if (!hasComma) {
        // A last element without a trailing comma: the paren must follow, and
        // the whitespace before it already rode along on the element.
        if (!_peekIs(0x29)) _fail('Expected "," or ")" in array');
        _offset++;
        return array;
      }
    }
  }

  /// Parse a bare or quoted string token, remembering which form it took.
  _PbxString _parseString() {
    if (_offset >= _source.length) _fail('Expected a string');
    if (_source.codeUnitAt(_offset) == 0x22) {
      return _PbxString(_parseQuotedString(), wasQuoted: true);
    }

    final start = _offset;
    while (_offset < _source.length) {
      final unit = _source.codeUnitAt(_offset);
      if (!_PbxString.isBareUnit(unit)) break;
      // A bare token may hold "/" (paths do), but never the "//" or "/*"
      // that open a comment.
      if (unit == 0x2F && _offset + 1 < _source.length) {
        final next = _source.codeUnitAt(_offset + 1);
        if (next == 0x2F || next == 0x2A) break;
      }
      _offset++;
    }
    if (_offset == start) _fail('Expected a string');
    return _PbxString(_source.substring(start, _offset));
  }

  /// Parse a `"..."` token, resolving escape sequences.
  String _parseQuotedString() {
    _offset++;
    final buffer = StringBuffer();
    while (true) {
      if (_offset >= _source.length) _fail('Unterminated quoted string');
      final unit = _source.codeUnitAt(_offset);
      if (unit == 0x22) {
        _offset++;
        return buffer.toString();
      }
      if (unit == 0x5C) {
        if (_offset + 1 >= _source.length) _fail('Unterminated escape');
        final escaped = _source[_offset + 1];
        // An escape this parser does not model resolves to the bare
        // character, which re-emits differently and so trips the caller's
        // round-trip guard instead of corrupting the file.
        buffer.write(switch (escaped) {
          'n' => '\n',
          't' => '\t',
          _ => escaped,
        });
        _offset += 2;
        continue;
      }
      buffer.write(_source[_offset]);
      _offset++;
    }
  }

  /// Whether the next character is [unit].
  bool _peekIs(int unit) =>
      _offset < _source.length && _source.codeUnitAt(_offset) == unit;

  /// Consume [unit] or fail, naming [display] in the message.
  void _expect(int unit, String display) {
    if (!_peekIs(unit)) _fail('Expected "$display"');
    _offset++;
  }

  /// Abort the parse, pointing at the current offset.
  Never _fail(String message) {
    throw FormatException('$message in $_path', _source, _offset);
  }
}
