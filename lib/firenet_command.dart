import 'dart:convert';

num? number(Object? value) => value is num ? value : num.tryParse('$value');
Map<String, dynamic> objectMap(Object? value) => value is Map
    ? Map<String, dynamic>.from(value) : <String, dynamic>{};

class FirenetException implements Exception {
  const FirenetException(this.message);
  final String message;
  @override
  String toString() => message;
}

class StoveSnapshot {
  StoveSnapshot(this.raw, {DateTime? received})
      : receivedAt = received ?? DateTime.now();
  final Map<String, dynamic> raw;
  final DateTime receivedAt;
  Map<String, dynamic> get controls => objectMap(raw['controls']);
  Map<String, dynamic> get sensors => objectMap(raw['sensors']);
  Map<String, dynamic> get features => objectMap(raw['stoveFeatures']);
  num? get revision => number(controls['revision']);
  num? get acknowledged => number(raw['lastConfirmedRevision']);
  num? get lastSeen => number(raw['lastSeenMinutes']);
  double? get target => number(controls['targetTemperature'])?.toDouble();
  double? get room {
    final value = number(sensors['inputRoomTemperature']);
    return value != null && value >= -40 && value <= 60
        ? value.toDouble() : null;
  }
  int? get mode => number(controls['operatingMode'])?.toInt();
  bool? get requestedOn => controls['onOff'] is bool ? controls['onOff'] as bool : null;
  String get modeName => switch (mode) {
    0 => 'Manuel', 1 => 'Automatique', 2 => 'Confort', _ => 'Inconnu',
  };
  String get physicalState {
    if (number(sensors['statusError']) != 0) { return 'État / alarme à vérifier'; }
    final state = number(sensors['statusMainState']);
    final sub = number(sensors['statusSubState']);
    if (state == 1) { return sub == 0 ? 'Éteint' : 'En attente'; }
    return switch (state) {
      2 => 'Allumage', 3 => 'Démarrage', 4 => 'En chauffe',
      5 => 'Nettoyage', 6 => 'Extinction en cours', _ => 'État $state / $sub',
    };
  }
}

/// A patch is a user-approved change, never a complete cached payload.
/// The full payload is rebuilt from a fresh status response just before POST.
class FirenetCommand {
  static Map<String, Object> temperature(double value, {required bool comfort}) {
    if (!value.isFinite || value < 14 || value > 28) {
      throw const FirenetException('Consigne autorisée : 14,0 à 28,0 °C.');
    }
    return <String, Object>{
      'targetTemperature': value.toStringAsFixed(1),
      if (comfort) 'operatingMode': 2,
    };
  }

  static bool equal(Object? a, Object? b) {
    if (a is bool || b is bool) { return a == b; }
    final x = number(a);
    final y = number(b);
    return x != null && y != null ? (x - y).abs() < 0.00001 : a == b;
  }

  static bool matches(StoveSnapshot state, Map<String, Object> patch) =>
      patch.entries.every((e) => equal(state.controls[e.key], e.value));

  static Map<String, dynamic> prepare(
    StoveSnapshot state, Map<String, Object> patch,
  ) {
    if (patch.isEmpty || state.revision == null || state.revision! <= 0) {
      throw const FirenetException('Contrôles ou révision FIRENET manquants.');
    }
    if (state.lastSeen == null || state.lastSeen! > 2 || state.lastSeen! < 0) {
      throw const FirenetException('Poêle hors ligne ou état trop ancien. Aucune commande envoyée.');
    }
    final stopOnly = patch.length == 1 && patch['onOff'] == false;
    if (!stopOnly) {
      if (number(state.sensors['statusError']) != 0 ||
          number(state.sensors['statusWarning']) != 0) {
        throw const FirenetException('Alarme, avertissement ou diagnostic inconnu : vérifier le poêle.');
      }
      if (state.acknowledged == null || state.acknowledged != state.revision) {
        throw const FirenetException('Une commande FIRENET est déjà en attente. Actualiser après sa confirmation.');
      }
    }
    final result = Map<String, dynamic>.from(state.controls);
    for (final entry in patch.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!result.containsKey(key)) {
        throw FirenetException('Fonction absente sur ce poêle : $key.');
      }
      if (key == 'onOff') {
        if (value is! bool) { throw const FirenetException('Marche/arrêt invalide.'); }
      } else if (key == 'operatingMode') {
        if (value is! int || ![0, 1, 2].contains(value)) {
          throw const FirenetException('Mode invalide.');
        }
      } else if (key == 'targetTemperature') {
        final n = number(value);
        if (n == null || !n.isFinite || n < 14 || n > 28) {
          throw const FirenetException('Consigne hors plage 14–28 °C.');
        }
        if (number(patch['operatingMode'] ?? result['operatingMode']) != 2) {
          throw const FirenetException('Sélectionner Confort pour utiliser une consigne.');
        }
        if (state.room == null) {
          throw const FirenetException('Température ambiante indisponible : vérifier la sonde.');
        }
      } else if (key == 'heatingPower') {
        if (value is! int || value < 30 || value > 100) {
          throw const FirenetException('Puissance autorisée : 30–100 %.');
        }
      } else if (key == 'convectionFan1Active' || key == 'convectionFan2Active') {
        final index = key == 'convectionFan1Active' ? 1 : 2;
        if (value is! bool || state.features['multiAir$index'] != true) {
          throw const FirenetException('Circuit MultiAir indisponible.');
        }
      } else {
        throw FirenetException('Modification interdite : $key.');
      }
      result[key] = value;
    }
    // Preserve revision, schedules, frost protection, unknown controls and types.
    // No sensor, combustion tuning or reset endpoint is writable here.
    return result;
  }
}

class ApiReply {
  const ApiReply(this.status, this.body);
  final int status;
  final String body;
}
typedef ApiRequest = Future<ApiReply> Function(
  String path, String method, Map<String, dynamic>? body,
);

enum Confirmation { waiting, stored, confirmed, different, unchanged }

class CommandReceipt {
  CommandReceipt({required this.patch, required this.before,
    required this.accepted, this.noChange = false}) : sentAt = DateTime.now();
  final Map<String, Object> patch;
  final StoveSnapshot before;
  final bool accepted;
  final bool noChange;
  final DateTime sentAt;

  Confirmation inspect(StoveSnapshot latest) {
    final same = FirenetCommand.matches(latest, patch);
    if (noChange && same && latest.acknowledged == latest.revision) {
      return Confirmation.unchanged;
    }
    final advanced = latest.revision != null && before.revision != null &&
        latest.revision! > before.revision!;
    final ack = advanced && latest.acknowledged != null &&
        latest.acknowledged! >= latest.revision!;
    if (ack) { return same ? Confirmation.confirmed : Confirmation.different; }
    if (advanced && same) { return Confirmation.stored; }
    return Confirmation.waiting;
  }
}

class FirenetClient {
  FirenetClient(this.request, this.stoveId) {
    if (!RegExp(r'^[0-9]+$').hasMatch(stoveId)) {
      throw const FirenetException('Identifiant du poêle invalide.');
    }
  }
  final ApiRequest request;
  final String stoveId;

  void _check(ApiReply reply) {
    if (reply.status == 401 || reply.status == 403 ||
        reply.body.trimLeft().startsWith('<')) {
      throw const FirenetException('Session expirée : ouvrir Compte FIRENET et se reconnecter.');
    }
    if (reply.status < 200 || reply.status >= 300) {
      throw FirenetException('FIRENET répond HTTP ${reply.status}. Pas de renvoi automatique.');
    }
  }

  Future<StoveSnapshot> read() async {
    final response = await request('/api/client/$stoveId/status?nocache=${DateTime.now().millisecondsSinceEpoch}', 'GET', null);
    _check(response);
    final dynamic decoded;
    try { decoded = jsonDecode(response.body); }
    catch (_) { throw const FirenetException('Réponse FIRENET non JSON. Reconnecter le compte.'); }
    if (decoded is! Map || decoded['controls'] is! Map || decoded['sensors'] is! Map ||
        decoded['stoveID']?.toString() != stoveId) {
      throw const FirenetException('État du poêle incomplet ou identifiant incohérent.');
    }
    return StoveSnapshot(Map<String, dynamic>.from(decoded));
  }

  Future<CommandReceipt> send(Map<String, Object> patch) async {
    final fresh = await read();
    final payload = FirenetCommand.prepare(fresh, patch);
    if (FirenetCommand.matches(fresh, patch) && fresh.acknowledged == fresh.revision) {
      return CommandReceipt(patch: Map.of(patch), before: fresh, accepted: true, noChange: true);
    }
    final response = await request('/api/client/$stoveId/controls', 'POST', payload);
    _check(response);
    final text = response.body.trim();
    var accepted = text.toUpperCase() == 'OK';
    if (!accepted && text.isNotEmpty) {
      try {
        final result = jsonDecode(text);
        if (result is Map && (result['error'] != null || result['success'] == false)) {
          throw const FirenetException('FIRENET a refusé la commande. Vérifier le poêle et actualiser.');
        }
        accepted = result == 'OK' || (result is Map &&
            (result['success'] == true || result['status'] == 'OK'));
      } on FormatException {
        throw const FirenetException('Réponse FIRENET inattendue. Envoi non confirmé ; actualiser avant un autre essai.');
      }
    }
    return CommandReceipt(patch: Map.of(patch), before: fresh, accepted: accepted);
  }
}
