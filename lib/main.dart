import 'package:flutter/material.dart';

void main() => runApp(const RikaControlApp());

class RikaControlApp extends StatelessWidget {
  const RikaControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RIKA Control',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0C0E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF792B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const Dashboard(),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  double target = 20.1;
  String mode = 'Auto';

  void adjust(double change) {
    setState(() {
      target = ((target + change) * 10).round().clamp(50, 350) / 10;
    });
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF792B);
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.local_fire_department, color: orange),
          SizedBox(width: 8),
          Text('RIKA Control'),
        ]),
        backgroundColor: const Color(0xFF0B0C0E),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('DOMO MultiAir', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('MODE DÉMONSTRATION — aucune commande envoyée',
                style: TextStyle(color: orange, fontSize: 12)),
            const SizedBox(height: 28),
            Center(
              child: Container(
                width: 255,
                height: 255,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: orange, width: 9),
                  color: const Color(0xFF191A1D),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('TEMPÉRATURE CIBLE', style: TextStyle(color: Colors.white60)),
                    const SizedBox(height: 12),
                    Text('${target.toStringAsFixed(1)}°',
                        style: const TextStyle(fontSize: 58, fontWeight: FontWeight.bold)),
                    const Text('Consigne simulée', style: TextStyle(color: orange)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: () => adjust(-0.1),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 30),
                Text('${target.toStringAsFixed(1)} °C', style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 30),
                IconButton.filled(
                  onPressed: () => adjust(0.1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Card(
              color: const Color(0xFF1A1B1E),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mode de chauffage'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: ['Manuel', 'Auto', 'Confort'].map((value) {
                        return ChoiceChip(
                          label: Text(value),
                          selected: mode == value,
                          onSelected: (_) => setState(() => mode = value),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              color: Color(0xFF1A1B1E),
              child: ListTile(
                leading: Icon(Icons.wifi_off, color: orange),
                title: Text('FIRENET non connecté'),
                subtitle: Text('Lecture API et authentification à intégrer'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Le réglage à 0,1 °C est une simulation. La précision réelle acceptée par FIRENET reste à vérifier.',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
