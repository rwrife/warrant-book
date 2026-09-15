import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:warrant_book/features/reminders/local_notifications_platform.dart';

void main() {
  test('timezone refresh consults the device lookup every time', () async {
    tz_data.initializeTimeZones();
    var identifier = 'America/New_York';
    var lookups = 0;
    final platform = LocalNotificationsPlatform(null, () async {
      lookups++;
      return identifier;
    });

    await platform.refreshTimezone();
    expect(tz.local.name, 'America/New_York');

    identifier = 'Asia/Tokyo';
    await platform.refreshTimezone();
    expect(tz.local.name, 'Asia/Tokyo');
    expect(lookups, 2);
  });
}
