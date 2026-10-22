import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/app_providers.dart';
import '../domain/debt_models.dart';

class DebtRepository {
  const DebtRepository({this.userId});

  final String? userId;

  String get _storageKey =>
      userId == null ? 'finmi.debts.guest.v1' : 'finmi.debts.$userId.v1';

  Future<List<DebtRecord>> loadDebts() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_storageKey);
    if ((raw == null || raw.isEmpty) && userId != null) {
      final legacyRaw = prefs.getString('finmi.debts.v1');
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        raw = legacyRaw;
        await prefs.setString(_storageKey, legacyRaw);
        await prefs.remove('finmi.debts.v1');
      }
    }
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .map(DebtRecord.fromJson)
          .toList();
      // Sort: active debts first (closest due date first), then settled ones
      list.sort((a, b) {
        if (a.isSettled != b.isSettled) {
          return a.isSettled ? 1 : -1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
      return list;
    } on Object {
      return const [];
    }
  }

  Future<void> saveDebts(List<DebtRecord> debts) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(debts.map((d) => d.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
  }

  Future<void> upsertDebt(DebtRecord record) async {
    final current = await loadDebts();
    final index = current.indexWhere((d) => d.id == record.id);
    final updated = List<DebtRecord>.from(current);
    if (index >= 0) {
      updated[index] = record;
    } else {
      updated.insert(0, record);
    }
    await saveDebts(updated);
  }

  Future<void> deleteDebt(String id) async {
    final current = await loadDebts();
    final updated = current.where((d) => d.id != id).toList();
    await saveDebts(updated);
  }

  Future<void> settleDebt(String id) async {
    final current = await loadDebts();
    final index = current.indexWhere((d) => d.id == id);
    if (index < 0) return;
    final target = current[index];
    final updatedRecord = target.copyWith(
      paidAmountMinor: target.amountMinor,
      status: DebtStatus.settled,
      settledAt: DateTime.now(),
    );
    final updated = List<DebtRecord>.from(current);
    updated[index] = updatedRecord;
    await saveDebts(updated);
  }

  Future<void> recordPartialPayment(String id, int paymentAmountMinor) async {
    final current = await loadDebts();
    final index = current.indexWhere((d) => d.id == id);
    if (index < 0) return;
    final target = current[index];
    final newPaid = (target.paidAmountMinor + paymentAmountMinor).clamp(
      0,
      target.amountMinor,
    );
    final isDone = newPaid >= target.amountMinor;
    final updatedRecord = target.copyWith(
      paidAmountMinor: newPaid,
      status: isDone ? DebtStatus.settled : target.status,
      settledAt: isDone ? DateTime.now() : target.settledAt,
    );
    final updated = List<DebtRecord>.from(current);
    updated[index] = updatedRecord;
    await saveDebts(updated);
  }
}

final debtRepositoryProvider = Provider<DebtRepository>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  return DebtRepository(userId: user?.id);
});

class DebtNotifier extends AsyncNotifier<List<DebtRecord>> {
  @override
  Future<List<DebtRecord>> build() async {
    final repo = ref.watch(debtRepositoryProvider);
    return repo.loadDebts();
  }

  Future<void> addOrUpdate(DebtRecord record) async {
    state = const AsyncLoading();
    final repo = ref.read(debtRepositoryProvider);
    await repo.upsertDebt(record);
    state = AsyncData(await repo.loadDebts());
  }

  Future<void> upsert(DebtRecord record) => addOrUpdate(record);

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    final repo = ref.read(debtRepositoryProvider);
    await repo.deleteDebt(id);
    state = AsyncData(await repo.loadDebts());
  }

  Future<void> settle(String id) async {
    state = const AsyncLoading();
    final repo = ref.read(debtRepositoryProvider);
    await repo.settleDebt(id);
    state = AsyncData(await repo.loadDebts());
  }

  Future<void> recordPayment(String id, int paymentAmountMinor) async {
    state = const AsyncLoading();
    final repo = ref.read(debtRepositoryProvider);
    await repo.recordPartialPayment(id, paymentAmountMinor);
    state = AsyncData(await repo.loadDebts());
  }
}

final debtsListProvider = AsyncNotifierProvider<DebtNotifier, List<DebtRecord>>(
  () {
    return DebtNotifier();
  },
);

final debtSummaryProvider = Provider<DebtSummary>((ref) {
  final debts = ref.watch(debtsListProvider).valueOrNull ?? const [];
  int receivable = 0;
  int payable = 0;
  int activeReceivable = 0;
  int activePayable = 0;

  for (final d in debts) {
    if (d.isSettled) continue;
    if (d.type == DebtType.theyOwe) {
      receivable += d.remainingMinor;
      activeReceivable++;
    } else {
      payable += d.remainingMinor;
      activePayable++;
    }
  }

  return DebtSummary(
    totalReceivableMinor: receivable,
    totalPayableMinor: payable,
    activeReceivableCount: activeReceivable,
    activePayableCount: activePayable,
  );
});
