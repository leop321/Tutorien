import 'package:flutter_test/flutter_test.dart';
import 'package:semester_planner/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SemesterApp());
    expect(find.text('Semesterplaner'), findsWidgets);
  });
}
