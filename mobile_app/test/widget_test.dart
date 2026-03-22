import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typing_assistant/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TypingAssistantApp());

    // Verify that the app title is displayed
    expect(find.text('跨设备打字助手'), findsOneWidget);
  });
}
