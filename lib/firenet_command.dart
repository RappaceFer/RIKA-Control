import 'dart:convert';

/// Builds a full FIRENET controls payload from the latest confirmed snapshot.
/// This does not send network requests.
class FirenetCommand {
  static Map<String, dynamic> targetTemperature(
    Map<String, dynamic> controls,
    String requested,
  ) {
    final value = double.tryParse(requested);
    if (value == null || value < 14 || value > 28) {
      throw const FormatException('Consigne hors plage de test (14 à 28 °C)');
    }
    if (controls['revision'] == null) {
      throw const FormatException('Révision FIRENET manquante');
    }
    if (controls['operatingMode'] != 2) {
      throw const FormatException('Le mode Confort est requis');
    }
    final copy = Map<String, dynamic>.from(controls);
    copy['targetTemperature'] = requested;
    return copy;
  }

  static String jsonBody(Map<String, dynamic> payload) => jsonEncode(payload);
}
