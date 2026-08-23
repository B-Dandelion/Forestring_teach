import 'dart:io';

void main() {
  final projectFile = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!projectFile.existsSync()) {
    stderr.writeln('iOS project file not found. Run this from the project root.');
    exitCode = 1;
    return;
  }

  var project = projectFile.readAsStringSync();

  project = project
      .replaceAll(
        'com.example.forestringTeacher2.RunnerTests',
        'forestring.teacher.app.RunnerTests',
      )
      .replaceAll(
        'com.example.forestringTeacher2',
        'forestring.teacher.app',
      );

  final cleanedLines = project
      .split('\n')
      .where(
        (line) =>
            !line.contains('GoogleService-Info.plist') &&
            !line.contains('FLUTTER_BUILD_NAME =') &&
            !line.contains('FLUTTER_BUILD_NUMBER ='),
      )
      .toList();
  projectFile.writeAsStringSync('${cleanedLines.join('\n').trimRight()}\n');

  final firebasePlist = File('ios/Runner/GoogleService-Info.plist');
  if (firebasePlist.existsSync()) {
    firebasePlist.deleteSync();
  }

  final firebaseJson = File('firebase.json');
  if (firebaseJson.existsSync()) {
    firebaseJson.deleteSync();
  }

  final result = projectFile.readAsStringSync();
  final errors = <String>[];

  if (!result.contains('PRODUCT_BUNDLE_IDENTIFIER = forestring.teacher.app;')) {
    errors.add('Production iOS bundle identifier was not found.');
  }
  if (result.contains('com.example.forestringTeacher2')) {
    errors.add('Example iOS bundle identifier remains.');
  }
  if (result.contains('GoogleService-Info.plist')) {
    errors.add('Firebase plist reference remains in the Xcode project.');
  }
  if (result.contains('FLUTTER_BUILD_NAME =') ||
      result.contains('FLUTTER_BUILD_NUMBER =')) {
    errors.add('Hardcoded Flutter iOS version override remains.');
  }
  if (firebasePlist.existsSync()) {
    errors.add('Firebase plist file still exists.');
  }

  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('ERROR: $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Teacher release cleanup complete.');
  stdout.writeln('iOS bundle id: forestring.teacher.app');
  stdout.writeln('Legacy Firebase iOS references: removed');
  stdout.writeln('Hardcoded Flutter iOS version overrides: removed');
}
