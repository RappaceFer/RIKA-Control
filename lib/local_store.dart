import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'heating_history.dart';

/// Private Android app storage; no account, cookie, password or raw JSON stored.
class LocalStore {
  LocalStore._(this.directory);
  final Directory directory;
  Future<void> _queue = Future.value();
  static Future<LocalStore> open(String stoveId) async {
    if (!RegExp(r'^\d+$').hasMatch(stoveId)) { throw const FormatException('Poêle invalide.'); }
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/stove_$stoveId');
    await dir.create(recursive: true);
    return LocalStore._(dir);
  }
  File get _history => File('${directory.path}/history.jsonl');
  Future<List<HeatSample>> loadHistory() async {
    if (!await _history.exists()) { return []; }
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 35));
    final samples = <HeatSample>[];
    for (final line in await _history.readAsLines()) {
      try {
        final s = HeatSample.fromJson(Map<String, dynamic>.from(jsonDecode(line) as Map));
        if (!s.time.isBefore(cutoff) && !s.time.isAfter(DateTime.now().toUtc())) { samples.add(s); }
      } on Object { /* One partial line must not hide the rest of the history. */ }
    }
    samples.sort((a, b) => a.time.compareTo(b.time));
    final kept = samples.length > 55000 ? samples.sublist(samples.length - 55000) : samples;
    final tmp = File('${_history.path}.tmp');
    await tmp.writeAsString(kept.map((s) => jsonEncode(s.toJson())).join('\n') + (kept.isEmpty ? '' : '\n'), flush: true);
    await tmp.rename(_history.path);
    return kept;
  }
  Future<void> append(HeatSample sample) {
    final op = _queue.then((_) => _history.writeAsString('${jsonEncode(sample.toJson())}\n', mode: FileMode.append, flush: true));
    _queue = op.then<void>((_) {}, onError: (Object _) {});
    return op.then<void>((_) {});
  }
  File get _profiles => File('${directory.path}/week-profiles.json');
  Future<Map<String, dynamic>> loadProfiles() async {
    if (!await _profiles.exists()) { return {}; }
    return Map<String, dynamic>.from(jsonDecode(await _profiles.readAsString()) as Map);
  }
  Future<void> saveProfiles(Map<String, dynamic> profiles) async {
    final tmp = File('${_profiles.path}.tmp');
    await tmp.writeAsString(jsonEncode(profiles), flush: true);
    await tmp.rename(_profiles.path);
  }
}
