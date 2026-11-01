import 'firenet_command.dart';

/// Minimal local observation, not an inferred cloud history.
class HeatSample {
  const HeatSample(this.time, this.room, this.target, this.power, this.state);
  final DateTime time;
  final double? room;
  final double? target;
  final double? power;
  final int state;
  static HeatSample? fromState(StoveSnapshot s) {
    final status = number(s.sensors['statusMainState']);
    if (s.lastSeen != 0 || status == null) { return null; }
    return HeatSample(s.receivedAt.toUtc(), s.room, s.target,
      number(s.controls['heatingPower'])?.toDouble(), status.toInt());
  }
  Map<String, dynamic> toJson() => {'t': time.toUtc().toIso8601String(),
    'r': room, 'c': target, 'p': power, 's': state};
  factory HeatSample.fromJson(Map<String, dynamic> j) => HeatSample(
    DateTime.parse(j['t'] as String).toUtc(), number(j['r'])?.toDouble(),
    number(j['c'])?.toDouble(), number(j['p'])?.toDouble(), (number(j['s']) ?? 0).toInt());
}

class HeatingSummary {
  const HeatingSummary(this.observedSeconds, this.heatingSeconds);
  final double observedSeconds;
  final double heatingSeconds;
}

/// Only adjacent observations <=150s apart count. Missing intervals stay unknown.
/// A state transition interval is not claimed as confirmed heating time.
HeatingSummary summarizeHeat(List<HeatSample> samples, DateTime start, DateTime end) {
  var observed = 0.0, heating = 0.0;
  for (var i = 1; i < samples.length; i++) {
    final a = samples[i - 1], b = samples[i];
    final gap = b.time.difference(a.time).inMilliseconds;
    if (gap <= 0 || gap > 150000) { continue; }
    final from = a.time.isBefore(start) ? start : a.time;
    final to = b.time.isAfter(end) ? end : b.time;
    if (!to.isAfter(from)) { continue; }
    final seconds = to.difference(from).inMilliseconds / 1000;
    observed += seconds;
    if (a.state == 4 && b.state == 4) { heating += seconds; }
  }
  return HeatingSummary(observed, heating);
}
