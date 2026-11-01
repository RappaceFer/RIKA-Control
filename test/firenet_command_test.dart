import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rika_control/firenet_command.dart';
import 'package:rika_control/firenet_bridge.dart';

Map<String, dynamic> fixture() => {
  'stoveID': '12345678', 'name': 'Test', 'lastSeenMinutes': 0,
  'lastConfirmedRevision': 100,
  'controls': {'revision': 100, 'onOff': false, 'operatingMode': 1,
    'targetTemperature': '22', 'heatingPower': 40, 'bakeTemperature': '340',
    'heatingTimeMon1': '06150830', 'frostProtectionActive': true,
    'frostProtectionTemperature': '4', 'ecoMode': false, 'debug0': 0,
    'futureUnknownControl': 'keep-me', 'convectionFan1Active': false,
    'convectionFan2Active': false},
  'sensors': {'inputRoomTemperature': '19', 'inputBakeTemperature': '1024',
    'statusError': 0, 'statusWarning': 0, 'statusMainState': 1, 'statusSubState': 0},
  'stoveFeatures': {'multiAir1': true, 'multiAir2': true},
};

void main() {
  test('22.2 is a decimal string, comfort is explicit, onOff is unchanged', () {
    final raw = fixture();
    final source = jsonEncode(raw);
    final patch = FirenetCommand.temperature(22.2, comfort: true);
    final result = FirenetCommand.prepare(StoveSnapshot(raw), patch);
    expect(result['targetTemperature'], '22.2');
    expect(result['operatingMode'], 2);
    expect(result['onOff'], false);
    expect(jsonEncode(raw), source);
  });
  test('preserves schedules, frost, revision, unknown and debug fields', () {
    final raw = fixture();
    final result = FirenetCommand.prepare(StoveSnapshot(raw), {'onOff': true});
    for (final e in objectMap(raw['controls']).entries) {
      expect(result[e.key], e.key == 'onOff' ? true : e.value);
    }
    expect(result.containsKey('sensors'), false);
  });
  test('parse temperatures as strings or numbers; no bake /10 guess', () {
    final state = StoveSnapshot(fixture());
    expect(state.target, 22); expect(state.room, 19);
    final raw = fixture(); raw['sensors']['inputRoomTemperature'] = '1024';
    expect(StoveSnapshot(raw).room, isNull);
  });
  test('mode 0/1/2 labels', () {
    for (var i = 0; i < 3; i++) {
      final raw = fixture(); raw['controls']['operatingMode'] = i;
      expect(StoveSnapshot(raw).modeName, ['Manuel', 'Automatique', 'Confort'][i]);
    }
  });
  test('onOff false is not proof of physically extinguished stove', () {
    final raw = fixture(); raw['sensors']['statusMainState'] = 6;
    expect(StoveSnapshot(raw).requestedOn, false);
    expect(StoveSnapshot(raw).physicalState, 'Extinction en cours');
  });
  test('temperature alone in Auto is refused, not silently ignored', () {
    expect(() => FirenetCommand.prepare(StoveSnapshot(fixture()),
      {'targetTemperature': '22.2'}), throwsA(isA<FirenetException>()));
  });
  test('rejects invalid temperatures including NaN', () {
    for (final n in [13.9, 28.1, double.nan, double.infinity]) {
      expect(() => FirenetCommand.temperature(n, comfort: true), throwsA(isA<FirenetException>()));
    }
  });
  test('sensor missing blocks comfort temperature', () {
    final raw = fixture(); raw['sensors']['inputRoomTemperature'] = '1024';
    expect(() => FirenetCommand.prepare(StoveSnapshot(raw),
      FirenetCommand.temperature(22.2, comfort: true)), throwsA(isA<FirenetException>()));
  });
  test('offline, missing revision and pending cloud revision are refused', () {
    for (final field in ['offline', 'revision', 'pending']) {
      final raw = fixture();
      if (field == 'offline') { raw['lastSeenMinutes'] = 3; }
      if (field == 'revision') { raw['controls'].remove('revision'); }
      if (field == 'pending') { raw['lastConfirmedRevision'] = 99; }
      expect(() => FirenetCommand.prepare(StoveSnapshot(raw), {'onOff': true}),
        throwsA(isA<FirenetException>()));
    }
  });
  test('alarms block start but do not suppress a normal stop request', () {
    final raw = fixture(); raw['sensors']['statusError'] = 8;
    expect(() => FirenetCommand.prepare(StoveSnapshot(raw), {'onOff': true}),
      throwsA(isA<FirenetException>()));
    expect(FirenetCommand.prepare(StoveSnapshot(raw), {'onOff': false})['onOff'], false);
  });
  test('warning blocks other control changes', () {
    final raw = fixture(); raw['sensors']['statusWarning'] = 2;
    expect(() => FirenetCommand.prepare(StoveSnapshot(raw), {'operatingMode': 2}),
      throwsA(isA<FirenetException>()));
  });
  test('cannot write sensors, safety parameters or revision', () {
    for (final key in ['revision', 'debug0', 'frostProtectionActive', 'statusError']) {
      expect(() => FirenetCommand.prepare(StoveSnapshot(fixture()), {key: 0}),
        throwsA(isA<FirenetException>()));
    }
  });
  test('power and mode limits are enforced', () {
    for (final patch in [{'operatingMode': 3}, {'heatingPower': 29}, {'heatingPower': 101}]) {
      expect(() => FirenetCommand.prepare(StoveSnapshot(fixture()), patch),
        throwsA(isA<FirenetException>()));
    }
  });
  test('fan activation requires advertised capability', () {
    final raw = fixture(); raw['stoveFeatures']['multiAir2'] = false;
    expect(() => FirenetCommand.prepare(StoveSnapshot(raw), {'convectionFan2Active': true}),
      throwsA(isA<FirenetException>()));
    expect(FirenetCommand.prepare(StoveSnapshot(raw), {'convectionFan1Active': true})['convectionFan1Active'], true);
  });
  test('no confirmation from HTTP OK alone or old revision', () {
    final state = StoveSnapshot(fixture());
    final receipt = CommandReceipt(patch: {'targetTemperature': '22.2'}, before: state, accepted: true);
    final raw = fixture(); raw['controls']['targetTemperature'] = '22.2';
    expect(receipt.inspect(StoveSnapshot(raw)), Confirmation.waiting);
  });
  test('cloud-stored without stove ack remains pending', () {
    final receipt = CommandReceipt(patch: {'targetTemperature': '22.2'},
      before: StoveSnapshot(fixture()), accepted: true);
    final raw = fixture(); raw['controls']['targetTemperature'] = '22.2'; raw['controls']['revision'] = 101;
    expect(receipt.inspect(StoveSnapshot(raw)), Confirmation.stored);
  });
  test('new revision plus ack and equal value is confirmed', () {
    final receipt = CommandReceipt(patch: {'targetTemperature': '22.2'},
      before: StoveSnapshot(fixture()), accepted: true);
    final raw = fixture(); raw['controls']['targetTemperature'] = '22.2';
    raw['controls']['revision'] = 101; raw['lastConfirmedRevision'] = 101;
    expect(receipt.inspect(StoveSnapshot(raw)), Confirmation.confirmed);
  });
  test('22.2 requested but 22 returned is reported as different', () {
    final receipt = CommandReceipt(patch: {'targetTemperature': '22.2'},
      before: StoveSnapshot(fixture()), accepted: true);
    final raw = fixture(); raw['controls']['revision'] = 101; raw['lastConfirmedRevision'] = 101;
    expect(receipt.inspect(StoveSnapshot(raw)), Confirmation.different);
  });
  test('fresh GET precedes POST; exact decimal and all fields survive', () async {
    final calls = <String>[];
    Map<String, dynamic>? sent;
    final fresh = fixture(); fresh['controls']['revision'] = 200; fresh['lastConfirmedRevision'] = 200;
    final client = FirenetClient((path, method, body) async {
      calls.add(method);
      if (method == 'GET') { return ApiReply(200, jsonEncode(fresh)); }
      sent = body; return const ApiReply(200, 'OK');
    }, '12345678');
    final result = await client.send(FirenetCommand.temperature(22.2, comfort: true));
    expect(calls, ['GET', 'POST']); expect(sent!['revision'], 200);
    expect(sent!['targetTemperature'], '22.2'); expect(sent!['onOff'], false);
    expect(sent!['futureUnknownControl'], 'keep-me'); expect(result.accepted, true);
  });
  test('already confirmed value produces no POST', () async {
    var posts = 0;
    final client = FirenetClient((path, method, body) async {
      if (method == 'POST') { posts++; }
      return ApiReply(200, jsonEncode(fixture()));
    }, '12345678');
    final result = await client.send({'onOff': false});
    expect(posts, 0); expect(result.noChange, true);
  });
  test('server error or unknown reply is never retried automatically', () async {
    for (final reply in [const ApiReply(500, 'error'), const ApiReply(200, 'NOT OK'),
      const ApiReply(200, '{"error":"bad request"}')]) {
      var posts = 0;
      final client = FirenetClient((path, method, body) async {
        if (method == 'GET') { return ApiReply(200, jsonEncode(fixture())); }
        posts++; return reply;
      }, '12345678');
      await expectLater(client.send({'onOff': true}), throwsA(isA<FirenetException>()));
      expect(posts, 1);
    }
  });
  test('login HTML is not a successful API response', () async {
    final client = FirenetClient((path, method, body) async => const ApiReply(200, '<html>login</html>'), '12345678');
    await expectLater(client.read(), throwsA(isA<FirenetException>()));
  });
  test('wrong stove identity is rejected before POST', () async {
    var posts = 0;
    final raw = fixture(); raw['stoveID'] = '99999';
    final client = FirenetClient((path, method, body) async {
      if (method == 'POST') { posts++; }
      return ApiReply(200, jsonEncode(raw));
    }, '12345678');
    await expectLater(client.send({'onOff': true}), throwsA(isA<FirenetException>()));
    expect(posts, 0);
  });
  test('origin allowlist rejects HTTP and lookalike domains', () {
    expect(FirenetBridge.trusted('https://www.rika-firenet.com/web/login'), true);
    expect(FirenetBridge.trusted('https://rika-firenet.com/web/summary'), true);
    for (final url in ['http://www.rika-firenet.com', 'https://rika-firenet.com.evil.test',
      'javascript:alert(1)', 'file:///tmp/test', 'https://example.org']) {
      expect(FirenetBridge.trusted(url), false);
    }
  });
}
