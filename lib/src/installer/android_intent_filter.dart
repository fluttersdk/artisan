/// What [XmlEditor.addAndroidActivity] did to the manifest.
enum AndroidActivityOutcome {
  /// The activity was spliced into `<application>`.
  added,

  /// An activity with this name and an equal intent-filter set is already
  /// declared; the file is untouched.
  unchanged,

  /// An activity with this name is declared with different intent filters. It
  /// may be hand-edited, so the file is untouched and the caller reports it.
  conflict,
}

/// One `<data>` element of an `<intent-filter>`.
///
/// Only the attributes a social-login callback needs are modelled. A `<data>`
/// that carries any other attribute in a manifest compares as different.
final class AndroidIntentData {
  /// `android:scheme`.
  final String? scheme;

  /// `android:host`.
  final String? host;

  /// `android:path`.
  final String? path;

  /// `android:pathPrefix`.
  final String? pathPrefix;

  /// Creates an [AndroidIntentData].
  const AndroidIntentData({this.scheme, this.host, this.path, this.pathPrefix});

  /// Rebuilds an entry from [toJson] output, as read back from an install
  /// record.
  factory AndroidIntentData.fromJson(Map<dynamic, dynamic> json) {
    return AndroidIntentData(
      scheme: json['scheme'] as String?,
      host: json['host'] as String?,
      path: json['path'] as String?,
      pathPrefix: json['pathPrefix'] as String?,
    );
  }

  /// The attributes that are set, keyed by their local `android:` name, in the
  /// order a rendered `<data>` lists them.
  Map<String, String> get attributes => <String, String>{
        if (scheme case final value?) 'scheme': value,
        if (host case final value?) 'host': value,
        if (path case final value?) 'path': value,
        if (pathPrefix case final value?) 'pathPrefix': value,
      };

  /// The install-record payload; unset attributes are left out.
  Map<String, dynamic> toJson() => <String, dynamic>{...attributes};
}

/// One `<intent-filter>` of an activity.
final class AndroidIntentFilter {
  /// Whether the filter carries `android:autoVerify="true"`.
  final bool autoVerify;

  /// `<action android:name>` values.
  final List<String> actions;

  /// `<category android:name>` values.
  final List<String> categories;

  /// `<data>` elements, one rendered element per entry.
  final List<AndroidIntentData> data;

  /// Creates an [AndroidIntentFilter].
  const AndroidIntentFilter({
    this.autoVerify = false,
    this.actions = const <String>[],
    this.categories = const <String>[],
    this.data = const <AndroidIntentData>[],
  });

  /// Rebuilds a filter from [toJson] output, as read back from an install
  /// record.
  factory AndroidIntentFilter.fromJson(Map<dynamic, dynamic> json) {
    List<String> strings(Object? raw) => raw is List
        ? raw.map((entry) => entry.toString()).toList(growable: false)
        : const <String>[];

    final rawData = json['data'];
    return AndroidIntentFilter(
      autoVerify: json['autoVerify'] == true,
      actions: strings(json['actions']),
      categories: strings(json['categories']),
      data: rawData is List
          ? <AndroidIntentData>[
              for (final entry in rawData.whereType<Map<dynamic, dynamic>>())
                AndroidIntentData.fromJson(entry),
            ]
          : const <AndroidIntentData>[],
    );
  }

  /// The install-record payload.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'autoVerify': autoVerify,
        'actions': actions,
        'categories': categories,
        'data': <Map<String, dynamic>>[for (final d in data) d.toJson()],
      };
}
