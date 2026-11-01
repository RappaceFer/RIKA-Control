import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rika_control/firenet_command.dart';
import 'package:rika_control/weekly_schedule.dart';
import 'package:rika_control/heating_history.dart';
import 'package:rika_control/history_page.dart';
import 'package:rika_control/planning_page.dart';
import 'firenet_command_test.dart' show fixture;

Map<String, dynamic> scheduledFixture() {
  final raw = fixture();
  final controls = raw['controls'] as Map;
  for (final day in weekCodes) {
    for (var n = 1; n <= 2; n++) { controls['heatingTime$day$n'] = '00000000'; }
  }
  controls['heatingTimesActiveForComfort'] = false;
  controls['setBackTemperature'] = '18';
  return raw;
}
void main() {
  test('native eight-digit slot round-trips minutes and disabled sentinel', () {
    final slot = HeatingSlot.decode('06150845')!;
    expect(slot.start, 375); expect(slot.end, 525);
    expect(slot.encode(), '06150845');
    expect(HeatingSlot.decode('00000000'), isNull);
    expect(HeatingSlot.decode('00000030')!.encode(), '00000030');
  });
  test('invalid format, hours, zero duration and overnight are refused', () {
    for (final value in ['23601200', '24002500', '12001200', '23000100', '1234567', 'abcd1234', 12345678]) {
      expect(() => HeatingSlot.decode(value), throwsFormatException);
    }
  });
  test('weekly payload writes 14 windows in one operation without turning on', () {
    final raw = scheduledFixture();
    final before = jsonEncode(raw);
    final week = WeeklySchedule.fromControls(objectMap(raw['controls']));
    week.enabled = true;
    week.slots[0][0] = const HeatingSlot(375, 525);
    week.copyDay(0, [1, 2, 3, 4]);
    final patch = week.patch();
    final prepared = FirenetCommand.prepare(StoveSnapshot(raw), patch);
    expect(prepared['operatingMode'], 2);
    expect(prepared['onOff'], false);
    expect(prepared['targetTemperature'], '22');
    expect(prepared['heatingTimeFri1'], '06150845');
    expect(prepared['frostProtectionActive'], true);
    expect(patch.containsKey('onOff'), false);
    expect(jsonEncode(raw), before);
  });
  test('reject partial scheduling instead of resetting unspecified days', () {
    expect(() => FirenetCommand.prepare(StoveSnapshot(scheduledFixture()), {'heatingTimeMon1': '06150845'}),
      throwsA(isA<FirenetException>()));
  });
  test('overlap, empty enabled week, and excessive setback are refused', () {
    final week = WeeklySchedule.fromControls(objectMap(scheduledFixture()['controls']));
    week.enabled = true;
    expect(week.validate, throwsFormatException);
    week.slots[0] = [const HeatingSlot(360, 600), const HeatingSlot(550, 800)];
    expect(week.validate, throwsFormatException);
    week.slots[0][1] = const HeatingSlot(600, 800);
    expect(week.patch, returnsNormally);
    week.setback = 29;
    expect(week.patch, throwsFormatException);
  });
  test('setback hotter than comfort is refused and saved profile is a deep copy', () {
    final raw = scheduledFixture();
    final week = WeeklySchedule.fromControls(objectMap(raw['controls']));
    final copy = week.copy();
    copy.slots[0][0] = const HeatingSlot(360, 480);
    expect(week.slots[0][0], isNull);
    copy.setback = 23;
    expect(() => FirenetCommand.prepare(StoveSnapshot(raw), copy.patch()), throwsA(isA<FirenetException>()));
  });
  test('all supported tenths are sent verbatim, never truncated to an integer', () {
    for (var n = 140; n <= 280; n++) {
      final patch = FirenetCommand.temperature(n / 10, comfort: true);
      expect(patch['targetTemperature'], (n / 10).toStringAsFixed(1));
    }
  });
  test('429 carries backoff and never automatically retries a POST', () async {
    var posts = 0;
    final client = FirenetClient((path, method, body) async {
      if (method == 'GET') { return ApiReply(200, jsonEncode(fixture())); }
      posts++; return const ApiReply(429, 'slow down', retryAfter: 120);
    }, '12345678');
    await expectLater(client.send({'onOff': true}), throwsA(isA<FirenetRateLimit>().having((e) => e.seconds, 'backoff', 120)));
    expect(posts, 1);
  });
  final t = DateTime.utc(2026, 11, 1, 8);
  HeatSample sample(int minutes, int state) => HeatSample(t.add(Duration(minutes: minutes)), 19, 22.2, 40, state);
  test('missing time is not extrapolated as heating or observation', () {
    final samples = [sample(0, 4), sample(1, 4), sample(60, 4), sample(61, 4)];
    final stats = summarizeHeat(samples, t, t.add(const Duration(hours: 2)));
    expect(stats.observedSeconds, 120); expect(stats.heatingSeconds, 120);
  });
  test('transitions do not become full heating periods; clip at range bounds', () {
    final samples = [sample(0, 1), sample(1, 4), sample(2, 4)];
    final stats = summarizeHeat(samples, t.add(const Duration(seconds: 90)), t.add(const Duration(minutes: 2)));
    expect(stats.observedSeconds, 30); expect(stats.heatingSeconds, 30);
  });
  test('offline/stale cloud samples are excluded', () {
    final raw = fixture(); raw['lastSeenMinutes'] = 1;
    expect(HeatSample.fromState(StoveSnapshot(raw)), isNull);
    raw['lastSeenMinutes'] = 0;
    final s = HeatSample.fromState(StoveSnapshot(raw))!;
    expect(HeatSample.fromJson(s.toJson()).target, 22);
  });
  testWidgets('history renders measured data without a WebView or overflow', (tester) async {
    final now = DateTime.now();
    final samples = [HeatSample(now.subtract(const Duration(minutes: 2)), 19, 22.2, 40, 4),
      HeatSample(now.subtract(const Duration(minutes: 1)), 19.1, 22.2, 40, 4)];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HistoryPage(samples: samples, storageInfo: 'Local'))));
    expect(find.text('Historique de chauffe'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('7 jours')); await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('opening weekly editor sends no commands', (tester) async {
    var sent = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlanningPage(
      state: StoveSnapshot(scheduledFixture()), busy: false, profiles: const {},
      onSaveProfiles: (_) async {}, onSend: (a, b, c) async { sent++; }))));
    expect(find.text('Planning de la semaine'), findsOneWidget);
    expect(sent, 0); expect(tester.takeException(), isNull);
  });
}
