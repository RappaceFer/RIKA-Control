import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'heating_history.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.samples, required this.storageInfo});
  final List<HeatSample> samples;
  final String storageInfo;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}
class _HistoryPageState extends State<HistoryPage> {
  int _days = 1;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: _days));
    final samples = widget.samples.where((s) => !s.time.isBefore(start) && !s.time.isAfter(now)).toList();
    final summary = summarizeHeat(widget.samples, start, now);
    String duration(double seconds) => '${seconds ~/ 3600} h ${(seconds ~/ 60) % 60} min';
    final coverage = summary.observedSeconds / now.difference(start).inSeconds * 100;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Historique de chauffe', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      SegmentedButton<int>(segments: const [ButtonSegment(value: 1, label: Text('24 h')),
        ButtonSegment(value: 7, label: Text('7 jours')), ButtonSegment(value: 30, label: Text('30 jours'))],
        selected: {_days}, onSelectionChanged: (v) => setState(() { _days = v.first; })),
      const SizedBox(height: 12),
      Text(widget.storageInfo, style: const TextStyle(fontSize: 12, color: Colors.white60)),
      const Text('Collecte uniquement quand l’application est ouverte au premier plan. '
        'Aucun historique antérieur n’est téléchargé. Les trous restent inconnus.',
        style: TextStyle(fontSize: 12, color: Colors.white60)),
      const SizedBox(height: 16),
      _metric('Chauffe observée (estimation)', duration(summary.heatingSeconds)),
      _metric('Période couverte par des observations', '${duration(summary.observedSeconds)} · ${coverage.toStringAsFixed(1)} %'),
      const Text('Calcul entre observations distantes de 150 s maximum, état « En chauffe » aux deux extrémités. '
        'Ce n’est pas le total réel si le téléphone était fermé.', style: TextStyle(fontSize: 11, color: Colors.white54)),
      const SizedBox(height: 20),
      const Text('Températures · °C', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
      const Text('Orange : ambiance mesurée · blanc : consigne relue FIRENET', style: TextStyle(fontSize: 11, color: Colors.white60)),
      _chart(samples, start, now, false),
      const SizedBox(height: 20),
      const Text('Puissance demandée · %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
      _chart(samples, start, now, true),
      const SizedBox(height: 20),
      const Text('Chauffe observée par jour', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
      for (var i = math.min(_days, 7) - 1; i >= 0; i--) _daily(now, i),
      const SizedBox(height: 16),
      const Text('Les horaires des graphiques suivent le fuseau du téléphone. '
        'Aucune consommation en kWh ni masse de granulés n’est déduite de la puissance demandée.',
        style: TextStyle(fontSize: 12, color: Colors.white60)),
    ]);
  }
  Widget _metric(String title, String value) => Card(child: ListTile(title: Text(title), subtitle: Text(value, style: const TextStyle(fontSize: 20))));
  Widget _daily(DateTime now, int ago) {
    final start = DateTime(now.year, now.month, now.day - ago);
    final tomorrow = DateTime(start.year, start.month, start.day + 1);
    final end = tomorrow.isAfter(now) ? now : tomorrow;
    final summary = summarizeHeat(widget.samples, start, end);
    final seconds = end.difference(start).inSeconds;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')} : '
        '${summary.heatingSeconds ~/ 60} min de chauffe observée · ${summary.observedSeconds ~/ 60} min suivies'),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: seconds <= 0 ? 0 : (summary.heatingSeconds / seconds).clamp(0, 1).toDouble()),
    ]));
  }
  Widget _chart(List<HeatSample> samples, DateTime start, DateTime end, bool power) {
    if (samples.isEmpty) { return const SizedBox(height: 150, child: Center(child: Text('Pas encore de mesures sur cette période.'))); }
    return Semantics(label: power ? 'Courbe de puissance demandée' : 'Courbes de température ambiante et consigne',
      child: SizedBox(height: 220, child: CustomPaint(painter: HeatChart(samples, start, end, power))));
  }
}

class HeatChart extends CustomPainter {
  HeatChart(this.samples, this.start, this.end, this.power);
  final List<HeatSample> samples;
  final DateTime start, end;
  final bool power;
  void _text(Canvas c, String s, Offset p) {
    final text = TextPainter(text: TextSpan(text: s, style: const TextStyle(color: Colors.white60, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
    text.paint(c, p);
  }
  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(38, 14, math.max(1, size.width - 48), size.height - 46);
    final values = <double>[for (final s in samples) ...(power ? [if (s.power != null) s.power!] : [if (s.room != null) s.room!, if (s.target != null) s.target!])];
    final low = power ? 0.0 : (values.isEmpty ? 10.0 : values.reduce(math.min).floorToDouble() - 1);
    final high = power ? 100.0 : (values.isEmpty ? 30.0 : values.reduce(math.max).ceilToDouble() + 1);
    final grid = Paint()..color = Colors.white12..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, (low + (high - low) * i / 4).toStringAsFixed(0), Offset(0, y - 5));
    }
    Offset point(HeatSample s, double v) => Offset(
      plot.left + plot.width * s.time.difference(start).inMilliseconds / math.max(1, end.difference(start).inMilliseconds),
      plot.bottom - plot.height * (v - low) / math.max(1.0, high - low));
    void line(double? Function(HeatSample) select, Color color) {
      final paint = Paint()..color = color..strokeWidth = 2;
      HeatSample? previous;
      double? lastValue;
      for (final sample in samples) {
        final v = select(sample);
        if (v == null) { previous = null; lastValue = null; continue; }
        final p = point(sample, v);
        if (previous != null && lastValue != null && sample.time.difference(previous.time).inSeconds <= 150) {
          canvas.drawLine(point(previous, lastValue), p, paint);
        } else { canvas.drawCircle(p, 2, paint); }
        previous = sample; lastValue = v;
      }
    }
    canvas.save(); canvas.clipRect(plot);
    if (power) { line((s) => s.power, const Color(0xFFFF792B)); }
    else { line((s) => s.target, Colors.white70); line((s) => s.room, const Color(0xFFFF792B)); }
    canvas.restore();
    String stamp(DateTime t) { final d = t.toLocal(); return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'; }
    _text(canvas, stamp(start), Offset(plot.left, plot.bottom + 10));
    _text(canvas, stamp(end), Offset(math.max(plot.left, plot.right - 90), plot.bottom + 10));
  }
  @override
  bool shouldRepaint(covariant HeatChart old) => true;
}
