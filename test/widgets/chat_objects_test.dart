import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/services/chat_service.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/utils/app_theme.dart';
import 'package:shadchan/widgets/chat_objects.dart';

/// Cards and ideas drawn inside the chat as things to act on, and the quiet
/// system lines — so nobody leaves the conversation to answer an idea.
void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('chat_objects_');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDownAll(() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // A temp dir.
    }
  });

  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );

  IdeaProposal proposal(String status) => IdeaProposal.fromMap('p1', {
    'fromUid': 'b',
    'toUid': 'me',
    'fromName': 'שרה לוי',
    'toName': 'יונתן',
    'status': status,
    'target': {'personId': 't1', 'firstName': 'נועה'},
    'candidate': {'personId': 'c1', 'firstName': 'דוד'},
    'sides': <String, Object?>{},
  })!;

  testWidgets('an idea waiting for me is answered inside the chat', (
    WidgetTester tester,
  ) async {
    MatchmakerNetwork.debugSet(
      uid: 'me',
      proposals: <IdeaProposal>[proposal('pending')],
    );
    await tester.pumpWidget(
      wrap(
        const ChatObject(
          chatRef: ChatRef(kind: 'proposal', id: 'p1', label: 'דוד ונועה'),
          me: 'me',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('רעיון: דוד ונועה'), findsOneWidget);
    expect(find.text('ממתין לתשובה שלך'), findsOneWidget);
    // "אשר | דחה" — approving opens the idea at once.
    expect(find.text('אשר'), findsOneWidget);
    expect(find.text('דחה'), findsOneWidget);
  });

  testWidgets('the state follows the idea; no buttons once it is answered', (
    WidgetTester tester,
  ) async {
    MatchmakerNetwork.debugSet(
      uid: 'me',
      proposals: <IdeaProposal>[proposal('declined')],
    );
    await tester.pumpWidget(
      wrap(
        const ChatObject(
          chatRef: ChatRef(kind: 'proposal', id: 'p1', label: 'דוד ונועה'),
          me: 'me',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('הרעיון לא אושר'), findsOneWidget);
    expect(find.text('אישור'), findsNothing);
  });

  testWidgets('a card no longer shared says so instead of opening', (
    WidgetTester tester,
  ) async {
    MatchmakerNetwork.debugSet(uid: 'me');
    await tester.pumpWidget(
      wrap(
        const Column(
          children: <Widget>[
            ChatObject(
              chatRef: ChatRef(
                kind: 'card',
                id: 'x',
                ownerUid: 'b',
                label: 'נועה כהן',
              ),
              me: 'me',
            ),
            ChatSystemLine(text: 'דוד ונועה: עבר להמתנה (אצל שרה)'),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('הכרטיס כבר לא זמין לך'), findsOneWidget);
    expect(find.text('דוד ונועה: עבר להמתנה (אצל שרה)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
