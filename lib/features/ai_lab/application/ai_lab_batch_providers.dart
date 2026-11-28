import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_lab_config.dart';
import 'ai_lab_chat_driver.dart';
import 'ai_lab_question.dart';

/// The driver the batch runner asks questions through (override in tests).
final aiLabChatDriverProvider = Provider<AiLabChatDriver>(
  ProviderChatDriver.new,
);

final aiLabQuestionsProvider = FutureProvider<List<AiLabQuestion>>(
  (ref) => loadAiLabQuestions(rootBundle),
);

final aiLabSeedExpectationsProvider = FutureProvider<Map<String, String>>(
  (ref) => loadSeedExpectations(rootBundle),
);

/// Pause between two questions.
final aiLabBatchPauseProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 400),
);

/// Value written to the CSV `flag_profile` column.
final aiLabFlagProfileProvider = Provider<String>(
  (ref) => AiLabConfig.flagProfile,
);
