import 'package:flutter/material.dart';
import 'firenet_command.dart';
import 'weekly_schedule.dart';

typedef SendControls = Future<void> Function(Map<String, Object>, String, String);
class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key, required this.state, required this.busy,
    required this.onSend, required this.profiles, required this.onSaveProfiles});
  final StoveSnapshot? state;
  final bool busy;
  final SendControls onSend;
  final Map<String, dynamic> profiles;
  final Future<void> Function(Map<String, dynamic>) onSaveProfiles;
  @override
  State<PlanningPage> createState() => _PlanningPageState();
}
class _PlanningPageState extends State<PlanningPage> {
  WeeklySchedule? _week;
  bool _dirty = false;
  String _message = '';
  @override
  void initState() { super.initState(); _read(); }
  @override
  void didUpdateWidget(covariant PlanningPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.state != widget.state) { _read(); }
  }
  void _read() {
    final state = widget.state;
    if (state == null) { return; }
    try {
      _week = WeeklySchedule.fromControls(state.controls);
      _dirty = false;
      _message = '';
    } catch (_) {
      _week = null;
      _message = 'Format de planning non reconnu. Aucune plage ne sera écrasée.';
    }
  }
  Future<void> _edit(int day, int slot) async {
    final original = _week!.slots[day][slot] ?? const HeatingSlot(360, 480);
    Future<TimeOfDay?> pick(int minutes, String title) => showTimePicker(
      context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: title, builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!));
    final start = await pick(original.start, '${weekLabels[day]} — début');
    if (start == null || !mounted) { return; }
    final end = await pick(original.end, '${weekLabels[day]} — fin');
    if (end == null || !mounted) { return; }
    final next = _week!.copy();
    next.slots[day][slot] = HeatingSlot(start.hour * 60 + start.minute, end.hour * 60 + end.minute);
    try {
      next.validate();
      setState(() { _week = next; _dirty = true; _message = 'Brouillon local : pas encore envoyé.'; });
    } catch (e) { setState(() { _message = e.toString(); }); }
  }
  Future<void> _saveProfile() async {
    var entered = '';
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Enregistrer cette semaine'),
      content: TextField(onChanged: (text) { entered = text; }, maxLength: 40,
        decoration: const InputDecoration(labelText: 'Nom : Habituel, Vacances…')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, entered.trim()), child: const Text('Enregistrer'))]));
    if (name == null || name.isEmpty || !mounted) { return; }
    try {
      final profiles = Map<String, dynamic>.from(widget.profiles);
      if (!profiles.containsKey(name) && profiles.length >= 20) {
        throw const FormatException('20 profils maximum. Réutiliser un nom existant.');
      }
      profiles[name] = _week!.toJson();
      await widget.onSaveProfiles(profiles);
      if (mounted) { setState(() { _message = 'Profil « $name » enregistré sur ce téléphone uniquement.'; }); }
    } catch (e) { if (mounted) { setState(() { _message = 'Enregistrement impossible : $e'; }); } }
  }
  Future<void> _publish() async {
    try {
      final patch = _week!.patch();
      final comfort = _week!.enabled;
      await widget.onSend(patch, 'Envoyer cette semaine au poêle ?',
        'Remplacer les 14 plages hebdomadaires par ce brouillon. '
        '${comfort ? 'Activer les horaires en mode Confort' : 'Désactiver les horaires du mode Confort'} ; '
        'température réduite ${_week!.setback} °C. '
        'La consigne Confort actuelle et marche/arrêt ne changent pas. '
        'Si le poêle est déjà en marche, son comportement peut changer immédiatement. '
        'Les horaires utilisent l’horloge du poêle : vérifier date, heure et changement saisonnier.');
    } catch (e) { if (mounted) { setState(() { _message = e.toString(); }); } }
  }
  @override
  Widget build(BuildContext context) {
    final week = _week;
    final disabled = widget.busy;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Planning de la semaine', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Lundi → dimanche, 2 plages par jour. Une semaine récurrente est enregistrée dans le poêle, pas exécutée par le téléphone.'),
      const SizedBox(height: 8),
      Text('Mode actuel : ${widget.state?.modeName ?? 'inconnu'} · Confort actuel : ${widget.state?.target ?? '—'} °C'),
      const Text('Dans les plages : consigne Confort globale. Hors plages : température réduite. '
        'Pas de température distincte par plage avec ce planning natif.', style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 12),
      if (_message.isNotEmpty) Text(_message, style: const TextStyle(color: Colors.orangeAccent)),
      if (week != null) ...[
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Utiliser les horaires en Confort'),
          subtitle: const Text('Brouillon : l’envoi nécessite une confirmation.'), value: week.enabled,
          onChanged: disabled ? null : (v) => setState(() { week.enabled = v; _dirty = true; })),
        Row(children: [const Expanded(child: Text('Température réduite')),
          IconButton(onPressed: disabled || week.setback <= 14 ? null : () => setState(() { week.setback--; _dirty = true; }), icon: const Icon(Icons.remove)),
          Text('${week.setback} °C'),
          IconButton(onPressed: disabled || week.setback >= 28 ? null : () => setState(() { week.setback++; _dirty = true; }), icon: const Icon(Icons.add))]),
        const Text('Réduction : pas de 1 °C dans cette version ; la consigne manuelle reste réglable à 0,1 °C.',
          style: TextStyle(fontSize: 11, color: Colors.white54)),
        for (var day = 0; day < 7; day++) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(weekLabels[day], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          for (var n = 0; n < 2; n++) Row(children: [
            Text('${n + 1}'), const SizedBox(width: 12),
            Expanded(child: OutlinedButton(onPressed: disabled ? null : () => _edit(day, n), child: Text(
              week.slots[day][n] == null ? 'Ajouter une plage' :
                '${HeatingSlot.clock(week.slots[day][n]!.start)} → ${HeatingSlot.clock(week.slots[day][n]!.end)}'))),
            IconButton(tooltip: 'Retirer la plage', onPressed: disabled || week.slots[day][n] == null ? null : () => setState(() {
              week.slots[day][n] = null; _dirty = true;
            }), icon: const Icon(Icons.close)),
          ]),
        ]))),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: disabled ? null : () => setState(() { week.copyDay(0, [1, 2, 3, 4]); _dirty = true; }), child: const Text('Lundi → lun–ven')),
          OutlinedButton(onPressed: disabled ? null : () => setState(() { week.copyDay(5, [6]); _dirty = true; }), child: const Text('Samedi → dimanche')),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: disabled ? null : _publish, icon: const Icon(Icons.send), label: const Text('Envoyer le planning au poêle')),
        OutlinedButton(onPressed: disabled ? null : () => setState(_read), child: const Text('Recharger le dernier état reçu (efface le brouillon)')),
        const Text('Enregistrer le planning ne met pas le poêle sur ON. '
          'Un démarrage programmé nécessite l’état de veille approprié. Consulter le retour de commande dans Chauffage.',
          style: TextStyle(fontSize: 12, color: Colors.white60)),
        const Divider(height: 32),
        const Text('Mes profils de semaine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
        const Text('Sauvegardés sur ce téléphone. Charger un profil ne l’envoie pas et ne programme pas de changement à une date future.',
          style: TextStyle(color: Colors.white60, fontSize: 12)),
        OutlinedButton.icon(onPressed: disabled ? null : _saveProfile, icon: const Icon(Icons.save_outlined), label: const Text('Enregistrer le brouillon comme profil')),
        for (final name in widget.profiles.keys) ListTile(title: Text(name), trailing: const Icon(Icons.file_open_outlined),
          onTap: disabled ? null : () {
            try { final loaded = WeeklySchedule.fromControls(objectMap(widget.profiles[name]));
              setState(() { _week = loaded; _dirty = true; _message = 'Profil « $name » chargé, non envoyé.'; });
            } catch (e) { setState(() { _message = 'Profil invalide : $e'; }); }
          }),
      ],
      const SizedBox(height: 24),
    ]);
  }
}
