/// Native FIRENET weekly windows: HHmmHHmm, two windows per day.
/// This codec contains no timers and never turns the stove on by itself.
const weekCodes = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekLabels = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

class HeatingSlot {
  const HeatingSlot(this.start, this.end);
  final int start;
  final int end;
  static HeatingSlot? decode(Object? value) {
    if (value == '00000000') { return null; }
    if (value is! String || !RegExp(r'^\d{8}$').hasMatch(value)) {
      throw const FormatException('Plage horaire FIRENET invalide.');
    }
    int parse(String text) {
      final h = int.parse(text.substring(0, 2));
      final m = int.parse(text.substring(2));
      if (h > 23 || m > 59) { throw const FormatException('Heure invalide.'); }
      return h * 60 + m;
    }
    final slot = HeatingSlot(parse(value.substring(0, 4)), parse(value.substring(4)));
    slot.validate();
    return slot;
  }
  void validate() {
    if (start < 0 || end > 1439 || start >= end) {
      throw const FormatException('Le début doit précéder la fin, dans la même journée.');
    }
  }
  static String clock(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  String encode() {
    validate();
    return '${clock(start)}${clock(end)}'.replaceAll(':', '');
  }
}

class WeeklySchedule {
  WeeklySchedule(this.slots, {required this.enabled, required this.setback});
  final List<List<HeatingSlot?>> slots;
  bool enabled;
  int setback;
  factory WeeklySchedule.fromControls(Map<String, dynamic> controls) => WeeklySchedule(
    [for (final day in weekCodes) [for (var n = 1; n <= 2; n++)
      HeatingSlot.decode(controls['heatingTime$day$n'])]],
    enabled: controls['heatingTimesActiveForComfort'] == true,
    setback: _readSetback(controls['setBackTemperature']),
  );
  static int _readSetback(Object? value) {
    final n = num.tryParse('$value');
    if (n == null || !n.isFinite || n % 1 != 0) {
      throw const FormatException('Température réduite reçue non prise en charge.');
    }
    return n.toInt();
  }
  WeeklySchedule copy() => WeeklySchedule([for (final day in slots) List.of(day)], enabled: enabled, setback: setback);
  void validate() {
    if (slots.length != 7 || slots.any((day) => day.length != 2)) {
      throw const FormatException('Le planning doit contenir 7 jours et 2 plages par jour.');
    }
    if (setback < 14 || setback > 28) { throw const FormatException('Température réduite : 14 à 28 °C.'); }
    for (final day in slots) {
      for (final slot in day) { slot?.validate(); }
      final a = day[0], b = day[1];
      if (a != null && b != null && a.start < b.end && b.start < a.end) {
        throw const FormatException('Deux plages du même jour ne doivent pas se chevaucher.');
      }
    }
    if (enabled && slots.every((day) => day.every((slot) => slot == null))) {
      throw const FormatException('Ajouter au moins une plage avant activation.');
    }
  }
  Map<String, Object> patch({bool activateComfort = true}) {
    validate();
    return {
      for (var d = 0; d < 7; d++) for (var n = 0; n < 2; n++)
        'heatingTime${weekCodes[d]}${n + 1}': slots[d][n]?.encode() ?? '00000000',
      'heatingTimesActiveForComfort': enabled,
      'setBackTemperature': setback.toString(),
      if (enabled && activateComfort) 'operatingMode': 2,
    };
  }
  Map<String, dynamic> toJson() => patch(activateComfort: false);
  void copyDay(int source, Iterable<int> destinations) {
    for (final day in destinations) { slots[day] = List.of(slots[source]); }
  }
}
