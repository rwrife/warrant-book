import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/features/reminders/local_notifications_platform.dart';

void main() {
  test('configured Android notification icon is a monochrome drawable', () {
    final icon = File(
      'android/app/src/main/res/drawable/'
      '$notificationIconResourceName.xml',
    );

    expect(icon.existsSync(), isTrue);
    final xml = icon.readAsStringSync();
    expect(xml, contains('<vector'));
    expect(xml, contains('android:fillColor="#FFFFFFFF"'));
    expect(xml, isNot(contains('mipmap')));

    final keepFile = File('android/app/src/main/res/raw/keep.xml');
    expect(keepFile.existsSync(), isTrue);
    final keepXml = keepFile.readAsStringSync();
    expect(
      keepXml,
      contains('tools:keep="@drawable/$notificationIconResourceName"'),
    );
  });
}
