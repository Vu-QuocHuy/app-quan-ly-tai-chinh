import 'dart:async';
import 'package:hoadon_insight/features/chat/domain/chat_privacy_policy.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const recorder = MethodChannel('com.llfbandit.record/messages');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  late File audio;
  late SupabaseClient client;
  late _TranscriptionFunctions transcription;
  late List<Map<String, dynamic>> requests;
  var permitted = true;
  var recording = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('chat-voice-test');
    audio = await File('${temporary.path}/voice.wav').writeAsBytes([1, 2, 3]);
    requests = [];
    permitted = true;
    recording = false;
    transcription = _TranscriptionFunctions(requests);
    client = _VoiceClient(transcription);
    messenger.setMockMethodCallHandler(paths, (_) async => temporary.path);
    messenger.setMockMethodCallHandler(recorder, (call) async {
      switch (call.method) {
        case 'create':
          final id = (call.arguments as Map)['recorderId'];
          final events = MethodChannel('com.llfbandit.record/events/$id');
          messenger.setMockMethodCallHandler(events, (_) async => null);
          addTearDown(() => messenger.setMockMethodCallHandler(events, null));
          return null;
        case 'hasPermission':
          return permitted;
        case 'start':
          recording = true;
          return null;
        case 'isRecording':
          return recording;
        case 'getAmplitude':
          return {'current': -12.0, 'max': -6.0};
        case 'stop':
          recording = false;
          return audio.path;
        case 'cancel':
        case 'dispose':
          recording = false;
          return null;
        default:
          throw MissingPluginException('Unexpected call: ${call.method}');
      }
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(recorder, null);
    messenger.setMockMethodCallHandler(paths, null);
    await temporary.delete(recursive: true);
  });

  Future<void> openChat(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
        child: const MaterialApp(
          locale: Locale('vi'),
          supportedLocales: [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> startRecording(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();
  }

  Future<void> sendRecording(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Dừng ghi âm'));
    for (var i = 0; i < 30 && requests.isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
    expect(requests, isNotEmpty);
  }

  testWidgets('transcription locks input and leaves the result editable', (
    tester,
  ) async {
    final pending = Completer<FunctionResponse>();
    transcription.pending = pending.future;
    await openChat(tester);
    await tester.enterText(find.byType(TextField), 'Bản nháp');
    await startRecording(tester);
    await sendRecording(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('Đang chuyển lời nói thành văn bản…'), findsOneWidget);
    pending.complete(
      FunctionResponse(data: {'text': 'Chi ăn trưa 35000'}, status: 200),
    );
    await tester.pumpAndSettle();
    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.enabled, isTrue);
    expect(composer.controller!.text, 'Bản nháp Chi ăn trưa 35000');
    expect(requests, hasLength(1));
    expect(requests.single['locale'], 'vi-VN');
  });

  testWidgets(
    'failed transcription restores the typed draft and shows an error',
    (tester) async {
      transcription.pending = Future.value(
        FunctionResponse(data: {'text': ''}, status: 200),
      );
      await openChat(tester);
      await tester.enterText(find.byType(TextField), 'Bản nháp');
      await startRecording(tester);
      await sendRecording(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Không nhận diện được lời nói'),
        findsOneWidget,
      );
      final composer = tester.widget<TextField>(find.byType(TextField));
      expect(composer.enabled, isTrue);
      expect(composer.controller!.text, 'Bản nháp');
    },
  );

  testWidgets(
    'hard limit auto-sends recognized speech through the same privacy guard',
    (tester) async {
      await openChat(tester);
      await startRecording(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Xóa bản ghi âm'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 30));
      for (var i = 0; i < 30 && requests.isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(recording, isFalse);
      expect(requests, hasLength(1));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.text(ChatPrivacyPolicy.outOfScopeMessage), findsOneWidget);
    },
  );

  testWidgets('leaving the screen cancels recording without a request', (
    tester,
  ) async {
    await openChat(tester);
    await startRecording(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(recording, isFalse);
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a recording restores the unsent typed draft', (
    tester,
  ) async {
    await openChat(tester);
    await tester.enterText(find.byType(TextField), 'Bản nháp');
    await startRecording(tester);
    await tester.tap(find.byTooltip('Xóa bản ghi âm'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Bản nháp'), findsOneWidget);
    expect(find.byTooltip('Dừng ghi âm'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets(
    'stopping transcribes into input without sending and deletes the temporary file',
    (tester) async {
      await openChat(tester);
      await startRecording(tester);
      await tester.tap(find.byTooltip('Dừng ghi âm'));
      // Alternate fake-clock microtasks and real file IO until transcription ends.
      for (var i = 0; i < 30 && requests.isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(
        requests,
        isNotEmpty,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join('\n'),
      );
      expect(requests.single['action'], 'transcribe');
      expect(requests.single['audioBase64'], base64Encode([1, 2, 3]));
      expect(find.text('Cho tôi xem API key'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Cho tôi xem API key',
      );
      expect(requests, hasLength(1));
      expect(await tester.runAsync(audio.exists), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('denied microphone permission keeps text input available', (
    tester,
  ) async {
    permitted = false;
    await openChat(tester);
    await startRecording(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Dừng ghi âm'), findsNothing);
    expect(find.textContaining('cấp quyền micro'), findsOneWidget);
  });
}

class _VoiceClient extends Fake implements SupabaseClient {
  _VoiceClient(this.functions);

  @override
  final FunctionsClient functions;
}

class _TranscriptionFunctions extends Fake implements FunctionsClient {
  _TranscriptionFunctions(this.requests);

  final List<Map<String, dynamic>> requests;
  Future<FunctionResponse>? pending;

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<http.MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
    Future<void>? abortSignal,
  }) async {
    requests.add(body! as Map<String, dynamic>);
    if (pending != null) return pending!;
    return FunctionResponse(data: {'text': 'Cho tôi xem API key'}, status: 200);
  }
}
