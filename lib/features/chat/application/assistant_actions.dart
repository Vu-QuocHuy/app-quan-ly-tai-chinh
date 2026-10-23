import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../debts/data/debt_repository.dart';
import '../../debts/domain/debt_models.dart';
import '../../groups/domain/group_models.dart';
import '../../income/data/income_repository.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../planning/domain/plan_models.dart';
import '../domain/assistant_command.dart';

class AssistantActionResult {
  const AssistantActionResult(
    this.text, {
    this.route,
    this.confirmDuplicate = false,
    this.needsInput = false,
  });
  final String text;
  final String? route;
  final bool confirmDuplicate;
  final bool needsInput;
}

/// Session-owned executor. The model never chooses database IDs or account IDs.
/// All writes go through the same repositories/RPCs as the regular forms.
class AssistantActions {
  AssistantActions(this.ref);
  final Ref ref;
  AssistantCommand? last;
  String? _lastId;
  Object? _lastSnapshot;
  String? _lastFingerprint;
  String? _account;
  bool _busy = false;

  void reset() {
    last = null;
    _lastId = null;
    _lastSnapshot = null;
    _lastFingerprint = null;
  }

  Future<AssistantActionResult> execute(
    AssistantCommand command, {
    required bool english,
    bool allowDuplicate = false,
  }) async {
    command = AssistantCommand.fromJson(
      Map<String, dynamic>.from(command.toJson()),
    );
    String say(String vi, String en) => english ? en : vi;
    if (_busy) throw StateError('An action is already running');
    final account = ref.read(authUserProvider).valueOrNull?.id;
    void checkAccount() {
      if (ref.read(authUserProvider).valueOrNull?.id != account) {
        throw StateError('Account changed');
      }
    }

    if (_account != account) {
      reset();
      _account = account;
    }
    final missing = command.clarification(english);
    if (missing != null) return AssistantActionResult(missing);
    final editing = command.operation == 'update_last';
    if (editing &&
        (last == null || last!.kind != command.kind || _lastId == null)) {
      return AssistantActionResult(
        say(
          'Chỉ sửa được khoản vừa ghi trong phiên chat này. Bạn muốn ghi khoản mới nào?',
          'I can only edit the last entry saved in this chat. What would you like to record?',
        ),
      );
    }
    if (editing && command.kind == 'group') {
      return AssistantActionResult(
        say(
          'Hãy sửa giao dịch quỹ hoặc tên nhóm trong màn hình nhóm để tránh ghi trùng.',
          'Please edit fund entries or the group name on the group screen to avoid duplicates.',
        ),
      );
    }
    final fingerprint = command.toJson().toString();
    if (!editing && !allowDuplicate && fingerprint == _lastFingerprint) {
      return AssistantActionResult(
        say(
          'Khoản này vừa được ghi. Bạn có chắc muốn ghi thêm một khoản giống vậy?',
          'This entry was just saved. Do you want to record another identical entry?',
        ),
        confirmDuplicate: true,
      );
    }
    _busy = true;
    try {
      final now = DateTime.now();
      final date = command.date ?? DateTime(now.year, now.month, now.day);
      var id = editing ? _lastId! : const Uuid().v4();
      final amount = command.amountMinor ?? 0;
      final money = MoneyFormatter.format(amount);
      final categoryKind = {'income', 'recurring_income'}.contains(command.kind)
          ? CategoryKind.income
          : CategoryKind.expense;
      String? categoryId = command.categoryId;
      if ({
        'income',
        'expense',
        'recurring_income',
        'recurring_expense',
      }.contains(command.kind)) {
        final categories = await ref.read(
          categoryKind == CategoryKind.income
              ? incomeCategoriesProvider.future
              : categoriesProvider.future,
        );
        if (categoryId != null &&
            !categories.any(
              (c) => c.id == categoryId && c.kind == categoryKind,
            )) {
          throw const FormatException('Invalid category');
        }
      }
      Object? saved;
      switch (command.kind) {
        case 'income':
          final repo = ref.read(incomeRepositoryProvider);
          final existing = editing
              ? (await repo.getAll()).where((item) => item.id == id).firstOrNull
              : null;
          if (editing &&
              (existing == null ||
                  existing.toPayload().toString() != _lastSnapshot)) {
            return _conflict(english);
          }
          if (!editing &&
              !allowDuplicate &&
              await repo.hasPotentialDuplicate(amount, date)) {
            return AssistantActionResult(
              say(
                'Có khoản thu cùng ngày và số tiền. Bạn có muốn ghi thêm?',
                'An income entry has the same date and amount. Record another?',
              ),
              confirmDuplicate: true,
            );
          }
          // save accepts an existing identity; use a fixed identity even for creates.
          final entry =
              existing ??
              IncomeEntry(
                id: id,
                amountMinor: amount,
                source: IncomeSource.manual,
                receivedAt: date,
                updatedAt: now,
              );
          checkAccount();
          await repo.save(
            amount,
            source: entry.source,
            categoryId: categoryId,
            note: command.description,
            receivedAt: date,
            existing: entry,
          );
          saved = (await repo.getAll())
              .firstWhere((item) => item.id == id)
              .toPayload()
              .toString();
        case 'expense':
          final repo = ref.read(invoiceRepositoryProvider);
          final existing = editing ? await repo.findById(id) : null;
          if (editing &&
              (existing == null || _invoiceState(existing) != _lastSnapshot)) {
            return _conflict(english);
          }
          final entry =
              (existing ??
                      InvoiceEntity(
                        id: id,
                        sellerName: command.description,
                        currencyCode: 'VND',
                        subtotalMinor: amount,
                        taxMinor: 0,
                        totalMinor: amount,
                        sourceType: InvoiceSourceType.manual,
                        status: InvoiceStatus.confirmed,
                        createdAt: now,
                        updatedAt: now,
                      ))
                  .copyWith(
                    sellerName: command.description,
                    notes: command.description,
                    subtotalMinor: amount,
                    totalMinor: amount,
                    categoryId: categoryId,
                    issuedAt: date,
                    updatedAt: now,
                    confirmedAt: now,
                    revision: existing == null ? 1 : existing.revision + 1,
                  );
          if (!editing &&
              !allowDuplicate &&
              (await repo.findDuplicateCandidates(entry)).any(
                (item) =>
                    item.totalMinor == amount &&
                    AssistantCommand.dateKey(item.issuedAt ?? item.createdAt) ==
                        AssistantCommand.dateKey(date),
              )) {
            return AssistantActionResult(
              say(
                'Có khoản chi cùng ngày và số tiền. Bạn có muốn ghi thêm?',
                'An expense has the same date and amount. Record another?',
              ),
              confirmDuplicate: true,
            );
          }
          checkAccount();
          await repo.saveInvoice(entry);
          saved = _invoiceState((await repo.findById(id))!);
        case 'debt':
          final repo = ref.read(debtRepositoryProvider);
          final debts = await repo.loadDebts();
          final existing = debts.where((d) => d.id == id).firstOrNull;
          if (editing &&
              (existing == null ||
                  existing.toJson().toString() != _lastSnapshot)) {
            return _conflict(english);
          }
          final type = command.debtDirection == 'i_owe'
              ? DebtType.iOwe
              : DebtType.theyOwe;
          if (existing != null &&
              (existing.paidAmountMinor > 0 || existing.isSettled)) {
            return _conflict(english);
          }
          if (!editing &&
              !allowDuplicate &&
              debts.any(
                (d) =>
                    !d.isSettled &&
                    d.type == type &&
                    d.amountMinor == amount &&
                    d.personName.toLowerCase() ==
                        command.personName!.toLowerCase(),
              )) {
            return AssistantActionResult(
              say(
                'Đã có khoản nợ tương tự với người này. Bạn có muốn ghi thêm?',
                'A similar debt already exists with this person. Record another?',
              ),
              confirmDuplicate: true,
            );
          }
          final entry = DebtRecord(
            id: id,
            personName: command.personName!,
            type: type,
            amountMinor: amount,
            createdAt: existing?.createdAt ?? now,
            dueDate: command.date,
            notes: command.description,
          );
          checkAccount();
          await repo.upsertDebt(entry);
          ref.invalidate(debtsListProvider);
          saved = entry.toJson().toString();
        case 'recurring_income':
        case 'recurring_expense':
          final repo = ref.read(planRepositoryProvider);
          final existing = editing ? await repo.findById(id) : null;
          if (editing &&
              (existing == null ||
                  existing.toPayload().toString() != _lastSnapshot)) {
            return _conflict(english);
          }
          final PlanItem item = command.kind == 'recurring_income'
              ? RecurringIncome(
                  id: id,
                  updatedAt: now,
                  title: command.description,
                  amountMinor: amount,
                  categoryId: categoryId ?? IncomeEntry.unclassifiedCategoryId,
                  anchorDate: date,
                  nextDueDate: date,
                )
              : RecurringBill(
                  id: id,
                  updatedAt: now,
                  title: command.description,
                  amountMinor: amount,
                  categoryId: categoryId,
                  frequency: BillFrequency.values.byName(command.frequency!),
                  anchorDate: date,
                  nextDueDate: date,
                );
          if (!editing &&
              !allowDuplicate &&
              (await repo.getAll()).any(
                (p) =>
                    p is RecurringBill &&
                        item is RecurringBill &&
                        p.title == item.title &&
                        p.amountMinor == amount ||
                    p is RecurringIncome &&
                        item is RecurringIncome &&
                        p.title == item.title &&
                        p.amountMinor == amount,
              )) {
            return AssistantActionResult(
              say(
                'Đã có lịch tương tự. Bạn có muốn tạo thêm?',
                'A similar schedule exists. Create another?',
              ),
              confirmDuplicate: true,
            );
          }
          checkAccount();
          await repo.save(item);
          saved = item.toPayload().toString();
        case 'group':
        case 'fund_deposit':
        case 'fund_expense':
        case 'open_split':
          final service = ref.read(expenseGroupServiceProvider);
          if (service == null) throw StateError('Group service unavailable');
          final groups = await service.listGroups();
          final matches = matchingGroups(groups, command.groupName!);
          if (command.kind == 'group') {
            if (matches.isNotEmpty) {
              return AssistantActionResult(
                say(
                  'Đã có nhóm tên này. Hãy chọn tên khác hoặc mở nhóm hiện có.',
                  'A group with this name already exists. Choose another name or open the existing group.',
                ),
                needsInput: true,
              );
            }
            checkAccount();
            id = (await service.createGroup(command.groupName!)).id;
          } else {
            if (matches.length != 1) {
              return AssistantActionResult(
                say(
                  matches.isEmpty
                      ? 'Không tìm thấy nhóm. Bạn hãy nói lại đúng tên nhóm.'
                      : 'Có nhiều nhóm trùng tên. Hãy mở nhóm cần dùng và đổi tên để phân biệt.',
                  matches.isEmpty
                      ? 'Group not found. Please give its exact name.'
                      : 'Several groups have that name. Please rename them on the group screen to distinguish them.',
                ),
                needsInput: true,
              );
            }
            final group = matches.single;
            if (command.kind == 'open_split') {
              return AssistantActionResult(
                say(
                  'Mở chia tiền nhóm ${group.name}.',
                  'Opening split expenses for ${group.name}.',
                ),
                route: '/groups/${group.id}?split=1',
              );
            }
            checkAccount();
            if (editing) {
              if (last!.groupName != command.groupName) {
                return _conflict(english);
              }
              await service.updateOwnFundEntry(
                id: id,
                amountMinor: amount,
                note: command.description,
                expectedAmountMinor: last!.amountMinor!,
                expectedNote: last!.description.trim(),
              );
            } else {
              id = await service.addFundEntryWithId(
                groupId: group.id,
                kind: command.kind == 'fund_deposit' ? 'deposit' : 'expense',
                amountMinor: amount,
                note: command.description,
              );
            }
          }
          ref.invalidate(expenseGroupsProvider);
          ref.read(sharedGroupRefreshSignalProvider.notifier).state++;
        default:
          throw const FormatException('Unsupported action');
      }
      last = command;
      _lastId = id;
      _lastSnapshot = saved;
      _lastFingerprint = fingerprint;
      final labels = {
        'income': say('khoản thu', 'income'),
        'expense': say('khoản chi', 'expense'),
        'debt': command.debtDirection == 'i_owe'
            ? say(
                'bạn nợ ${command.personName}',
                'you owe ${command.personName}',
              )
            : say(
                '${command.personName} nợ bạn',
                '${command.personName} owes you',
              ),
        'recurring_income': say(
          'lịch thu định kỳ',
          'recurring income schedule',
        ),
        'recurring_expense': say(
          'lịch nhắc chi định kỳ',
          'recurring bill reminder',
        ),
        'group': say('nhóm ${command.groupName}', 'group ${command.groupName}'),
        'fund_deposit': say(
          'thu quỹ ${command.groupName}',
          'deposit to ${command.groupName}',
        ),
        'fund_expense': say(
          'chi quỹ ${command.groupName}',
          'expense from ${command.groupName}',
        ),
      };
      return AssistantActionResult(
        say(
          'Đã ${editing ? 'sửa' : 'ghi'} ${labels[command.kind]}${command.kind == 'group' ? '' : ' · $money'}.',
          '${editing ? 'Updated' : 'Saved'} ${labels[command.kind]}${command.kind == 'group' ? '' : ' · $money'}.',
        ),
      );
    } finally {
      _busy = false;
    }
  }

  static List<ExpenseGroup> matchingGroups(
    List<ExpenseGroup> groups,
    String name,
  ) {
    // Case/whitespace insensitive, but never fuzzy-select a different group.
    String normalize(String text) =>
        text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return groups.where((g) => normalize(g.name) == normalize(name)).toList();
  }

  static String _invoiceState(InvoiceEntity item) => [
    item.id,
    item.revision,
    item.updatedAt,
    item.totalMinor,
    item.categoryId,
    item.sellerName,
    item.notes,
    item.issuedAt,
    item.status,
  ].join('|');

  AssistantActionResult _conflict(bool en) => AssistantActionResult(
    en
        ? 'This entry changed outside this chat or has payments. Please edit it on its own screen.'
        : 'Khoản này đã thay đổi ngoài cuộc chat hoặc đã có thanh toán. Hãy sửa trong màn hình của khoản đó.',
  );
}

final assistantActionsProvider = Provider.autoDispose
    .family<AssistantActions, String>((ref, sessionId) {
      return AssistantActions(ref);
    });
