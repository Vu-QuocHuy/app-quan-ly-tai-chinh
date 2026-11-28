import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../debts/data/debt_repository.dart';
import '../domain/chat_models.dart';
import '../domain/chat_routing_rules.dart';
import '../domain/local_debt_answer.dart';
import 'assistant_read_tools.dart';

/// H3: answers standard lookups on device with 0 LLM calls. Returns `null`
/// whenever the question is not a confident local match, the data cannot be
/// read in time, or the local assistant did not recognise the intent — the
/// caller then continues with the cloud path.
Future<({ChatReply reply, LocalChatIntent intent})?> tryAnswerLocally(
  WidgetRef ref,
  String question, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final intent = ChatRoutingRules.localIntent(question);
  if (intent == null) return null;
  try {
    final ChatReply reply;
    if (intent == LocalChatIntent.debt) {
      final debts = await ref
          .read(debtRepositoryProvider)
          .loadDebts()
          .timeout(timeout);
      reply = localDebtAnswer(question, debts);
    } else {
      reply = await ref
          .read(localChatAssistantProvider)
          .answer(question)
          .timeout(timeout);
    }
    // LocalChatAssistant's "did not understand" reply carries no data.
    if (reply.citations.isEmpty && reply.facts.isEmpty) return null;
    return (reply: reply, intent: intent);
  } on Object {
    return null;
  }
}

/// H4: reads FACTS for the tools guessed from [question] so they can be sent
/// with the first `chat` call. Returns `null` when no tool is guessed or any
/// read fails, so the caller keeps the original tool-calling flow.
Future<({List<ChatFact> facts, List<String> tools})?> prefetchChatFacts(
  WidgetRef ref,
  String question, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final calls = ChatRoutingRules.guessTools(question);
  if (calls.isEmpty) return null;
  try {
    final facts = <ChatFact>[];
    final seen = <String>{};
    for (final call in calls) {
      final extra = await readAssistantFacts(ref, call.name).timeout(timeout);
      final read =
          extra ??
          (await ref
                  .read(localChatAssistantProvider)
                  .executeTool(call)
                  .timeout(timeout))
              .facts;
      for (final fact in read) {
        if (seen.add(fact.key)) facts.add(fact);
      }
    }
    if (facts.isEmpty) return null;
    return (facts: facts, tools: [for (final call in calls) call.name]);
  } on Object {
    return null;
  }
}
