import 'dart:convert';

import 'package:fixloop_mobile/data/fake_fix_loop_api.dart';
import 'package:fixloop_mobile/main.dart';
import 'package:fixloop_mobile/preview/photo_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePhotoPicker implements PreviewPhotoPicker {
  FakePhotoPicker({this.tooLarge = false});
  final bool tooLarge;
  int calls = 0;

  @override
  Future<PreviewPhoto?> pickPhoto() async {
    calls++;
    if (tooLarge) throw const PhotoTooLargeException();
    return PreviewPhoto(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP43+DwHwAHAAK/K9fH4gAAAABJRU5ErkJggg==',
    ));
  }
}

Future<void> startApp(
  WidgetTester tester, {
  FakeFixLoopApi? api,
  PreviewPhotoPicker? picker,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FixLoopApp(
      api: api ?? FakeFixLoopApi(),
      photoPicker: picker ?? FakePhotoPicker(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> signInAs(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const ValueKey<String>('auth-email')), email);
  await tester.enterText(find.byKey(const ValueKey<String>('auth-password')), 'campus-lamp-2026');
  await tapVisible(tester, find.byKey(const ValueKey<String>('auth-submit')));
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> selectDropdown(WidgetTester tester, String keySubstring, String choiceText) async {
  final dropdown = find.byWidgetPredicate(
    (widget) => widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith(keySubstring),
  );
  await tapVisible(tester, dropdown);
  await tester.tap(find.text(choiceText).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('student sign-in, error feedback, notifications, and sign-out work', (tester) async {
    await startApp(tester);
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('auth-email')), 'student1@bmu.edu.in');
    await tester.enterText(find.byKey(const ValueKey<String>('auth-password')), 'wrong-password');
    await tapVisible(tester, find.byKey(const ValueKey<String>('auth-submit')));
    expect(find.text('Email or password is incorrect.'), findsOneWidget);

    await signInAs(tester, 'student1@bmu.edu.in');
    expect(find.text('My issues'), findsOneWidget);
    expect(find.text('Check it'), findsOneWidget);

    // Open Updates tab and mark notification read.
    await tapVisible(tester, find.text('Updates'));
    expect(find.text('1 unread update'), findsOneWidget);
    await tapVisible(tester, find.textContaining('FL-2026-000024'));
    expect(find.text('# FL-2026-000024'), findsOneWidget);

    await tapVisible(tester, find.byTooltip('Back'));
    await tapVisible(tester, find.text('Profile'));
    await tapVisible(tester, find.byKey(const ValueKey<String>('sign-out-button')));
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('student registration validates university email and signs in', (tester) async {
    await startApp(tester);
    await tapVisible(tester, find.text('Register'));
    await tester.enterText(find.byKey(const ValueKey<String>('auth-fullname')), 'New Student');
    await tester.enterText(find.byKey(const ValueKey<String>('auth-email')), 'newbie@gmail.com');
    await tester.enterText(find.byKey(const ValueKey<String>('auth-password')), 'campus-lamp-2026');
    await tapVisible(tester, find.byKey(const ValueKey<String>('auth-submit')));
    expect(find.textContaining('Only university email addresses'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('auth-email')), 'newbie@bmu.edu.in');
    await tapVisible(tester, find.byKey(const ValueKey<String>('auth-submit')));
    expect(find.text('My issues'), findsOneWidget);
  });

  testWidgets('4-step report flow enforces photo policy, dynamic locations, and submits real code', (tester) async {
    final picker = FakePhotoPicker();
    await startApp(tester, picker: picker);
    await signInAs(tester, 'student1@bmu.edu.in');

    await tapVisible(tester, find.byKey(const ValueKey<String>('start-report')));
    expect(find.text('What is wrong?'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('category-search')), 'plumb');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Plumbing & Water'));

    expect(find.text('Where is it?'), findsOneWidget);
    await selectDropdown(tester, 'loc-level-0', 'Boys Hostel T1');
    await selectDropdown(tester, 'loc-level-1', 'Floor 2');
    await selectDropdown(tester, 'loc-level-2', 'Room 204');
    await tapVisible(tester, find.text('Next'));

    expect(find.text('Tell us more'), findsOneWidget);
    expect(find.text('Photos (required · at least 1)'), findsOneWidget);

    final nextBtn = find.ancestor(of: find.text('Next'), matching: find.byType(FilledButton));
    await tester.enterText(find.byKey(const ValueKey<String>('issue-title')), 'Leaking tap in washroom');
    await tester.pumpAndSettle();
    // Photo is required for Plumbing, so Next remains disabled until a photo is added.
    expect(tester.widget<FilledButton>(nextBtn).onPressed, isNull);

    await tapVisible(tester, find.byKey(const ValueKey<String>('add-photo')));
    expect(picker.calls, 1);
    expect(tester.widget<FilledButton>(nextBtn).onPressed, isNotNull);

    await tapVisible(tester, find.text('Next'));
    expect(find.text('Check and send'), findsOneWidget);
    expect(find.text('Boys Hostel T1 · Floor 2 · Room 204'), findsOneWidget);

    await tapVisible(tester, find.byKey(const ValueKey<String>('submit-complaint')));
    expect(find.text('Report received'), findsOneWidget);
    expect(find.text('# FL-2026-000027'), findsOneWidget);

    await tapVisible(tester, find.text('Done'));
    expect(find.text('Leaking tap in washroom'), findsOneWidget);
  });

  testWidgets('student can verify or reopen resolved issue and missing attachment shows clean placeholder', (tester) async {
    final api = FakeFixLoopApi(missingAttachmentIds: <String>{'att-seeded-1'});
    await startApp(tester, api: api);
    await signInAs(tester, 'student1@bmu.edu.in');

    await tapVisible(tester, find.text('Check it'));
    expect(find.text('# FL-2026-000024'), findsOneWidget);
    expect(find.text('Sample photo unavailable on server'), findsOneWidget);

    // Reopen first (requires note).
    await tapVisible(tester, find.byKey(const ValueKey<String>('action-reopen')));
    await tester.enterText(find.byKey(const ValueKey<String>('dialog-note')), 'Drops intermittently again.');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Reopen issue'));
    expect(find.text('Assigned'), findsWidgets);
  });

  testWidgets('student can verify resolved issue to close the loop', (tester) async {
    await startApp(tester);
    await signInAs(tester, 'student1@bmu.edu.in');

    await tapVisible(tester, find.text('Check it'));
    await tapVisible(tester, find.byKey(const ValueKey<String>('action-verify')));
    expect(find.text('Loop closed.'), findsOneWidget);
    await tapVisible(tester, find.text('Done'));
    expect(find.text('My issues'), findsOneWidget);
  });

  testWidgets('staff queue claims, adds note, resolves, and views analytics', (tester) async {
    await startApp(tester);
    await signInAs(tester, 'tech.fac@bmu.edu.in');
    expect(find.text('Operations queue'), findsOneWidget);

    await tapVisible(tester, find.text('Department pool'));
    await tapVisible(tester, find.text('Streetlight flickering at Main Gate'));
    await tapVisible(tester, find.byKey(const ValueKey<String>('action-claim')));
    expect(find.text('In progress'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey<String>('add-note-input')), 'Replaced starter fuse.');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey<String>('add-note-submit')));
    expect(find.text('Replaced starter fuse.'), findsOneWidget);

    await tapVisible(tester, find.byKey(const ValueKey<String>('action-resolve')));
    await tester.enterText(find.byKey(const ValueKey<String>('resolve-note')), 'Fixture verified stable.');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Mark resolved').last);
    expect(find.text('Fixed, please check'), findsWidgets);

    await tapVisible(tester, find.byTooltip('Back'));
    await tapVisible(tester, find.byIcon(Icons.analytics_outlined));
    expect(find.text('Operations overview'), findsOneWidget);
    expect(find.text('Open by department'), findsOneWidget);
  });

  testWidgets('oversize photo upload shows friendly error', (tester) async {
    await startApp(tester, picker: FakePhotoPicker(tooLarge: true));
    await signInAs(tester, 'student1@bmu.edu.in');
    await tapVisible(tester, find.byKey(const ValueKey<String>('start-report')));
    await tapVisible(tester, find.text('Wi-Fi & Network'));
    await selectDropdown(tester, 'loc-level-0', 'Main Gate');
    await tapVisible(tester, find.text('Next'));
    await tapVisible(tester, find.byKey(const ValueKey<String>('add-photo')));
    expect(find.text('Choose a photo smaller than 5 MB.'), findsOneWidget);
  });

  testWidgets('supports dark mode and small 320px viewport with 1.5x text scale without overflow', (tester) async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      previousErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(FixLoopApp(api: FakeFixLoopApi(), photoPicker: FakePhotoPicker()));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Welcome back'))).brightness, Brightness.dark);

    await signInAs(tester, 'student1@bmu.edu.in');
    expect(find.text('My issues'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
