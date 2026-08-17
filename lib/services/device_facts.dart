import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The three facts every problem report carries, so nobody has to be asked for
/// them: which phone, which operating system, which build of the app.
///
/// Read at the moment a report is sent and nowhere else — this is not a
/// telemetry hook. Nothing here identifies a person or a device: the model name
/// is the same string for every unit of that phone, and there is no serial,
/// advertising id or install id anywhere in it.
class DeviceFacts {
  const DeviceFacts({
    required this.device,
    required this.os,
    required this.appVersion,
  });

  /// What the phone is — "Samsung SM-G991B", "iPhone15,2". Falls back to the
  /// platform name when the plugin cannot answer.
  final String device;

  /// The operating system and its version — "Android 14", "iOS 17.4".
  final String os;

  /// The app's own version and build number, with a debug marker so a report
  /// from a development build is never mistaken for one from the store.
  final String appVersion;

  static const DeviceFacts unknown = DeviceFacts(
    device: 'לא ידוע',
    os: 'לא ידוע',
    appVersion: 'לא ידועה',
  );

  /// Collects all three. Never throws: a report that reaches the developer
  /// without the model is worth far more than one that failed to send because
  /// a plugin channel was unavailable.
  static Future<DeviceFacts> read() async {
    return DeviceFacts(
      device: await _device(),
      os: await _os(),
      appVersion: await _appVersion(),
    );
  }

  static Future<String> _device() async {
    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo android = await info.androidInfo;
        final String maker = android.manufacturer.trim();
        final String model = android.model.trim();
        return <String>[
          if (maker.isNotEmpty) maker,
          if (model.isNotEmpty) model,
        ].join(' ').trim();
      }
      if (Platform.isIOS) {
        final IosDeviceInfo ios = await info.iosInfo;
        final String machine = ios.utsname.machine.trim();
        return machine.isEmpty ? ios.model : machine;
      }
      return Platform.operatingSystem;
    } on Object {
      return unknown.device;
    }
  }

  static Future<String> _os() async {
    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo android = await info.androidInfo;
        return 'Android ${android.version.release} '
            '(API ${android.version.sdkInt})';
      }
      if (Platform.isIOS) {
        final IosDeviceInfo ios = await info.iosInfo;
        return '${ios.systemName} ${ios.systemVersion}';
      }
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } on Object {
      return unknown.os;
    }
  }

  static Future<String> _appVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String debug = kDebugMode ? ' (debug)' : '';
      return '${info.version}+${info.buildNumber}$debug';
    } on Object {
      return unknown.appVersion;
    }
  }
}
