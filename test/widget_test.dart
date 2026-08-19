import 'package:flutter_test/flutter_test.dart';
import 'package:forestring_teacher_2/main.dart';

void main() {
  test('ForestringTeacher can be constructed', () {
    const app = ForestringTeacher();

    expect(
      app,
      isA<ForestringTeacher>(),
    );
  });
}
