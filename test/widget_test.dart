import 'package:flutter_test/flutter_test.dart';
import 'package:photo_stamp/main.dart';

void main() {
  testWidgets('App loads with empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const PhotoStampApp());
    expect(find.text('저장된 스탬프가 없습니다'), findsOneWidget);
  });
}
