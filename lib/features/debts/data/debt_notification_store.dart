import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../notifications/data/budget_notification_service.dart';
import '../../auth/data/personal_profile_store.dart';
import '../domain/debt_notification.dart';
import 'debt_cookie_sync.dart';

class DebtNotificationStore {
  static const _storageKey = 'finmi.debt_notifications.v1';
  static const _phoneOwnerKey = 'finmi.phone_owner_map.v1';
  static const _registeredPhonesKey = 'finmi.registered_phones.v1';

  static const _seedPhones = {
    '0123456789',
    '0234567890',
    '0987654321',
    '0912345678',
  };

  static String _userPhoneKey(String? userId) => userId == null
      ? 'finmi.user_phone.guest.v1'
      : 'finmi.user_phone.$userId.v1';

  /// Lấy số điện thoại của người dùng hiện tại (từ cache local hoặc Supabase)
  static Future<String?> getCurrentUserPhone(
    dynamic ref, {
    String? userId,
    SupabaseClient? client,
  }) async {
    final effectiveClient = client ?? ref?.read(supabaseClientProvider);
    final user = effectiveClient?.auth.currentUser;
    final effectiveUserId = userId ?? user?.id;

    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _userPhoneKey(effectiveUserId);
    var localPhone = prefs.getString(scopedKey);
    if ((localPhone == null || localPhone.isEmpty) && effectiveUserId != null) {
      final legacyPhone = prefs.getString('finmi.user_phone.v1');
      if (legacyPhone != null && legacyPhone.isNotEmpty) {
        localPhone = legacyPhone;
        await prefs.setString(scopedKey, legacyPhone);
        await prefs.remove('finmi.user_phone.v1');
      }
    }
    if (localPhone != null && localPhone.trim().isNotEmpty) {
      final phone = localPhone.trim();
      _recordLocalPhoneOwnership(phone, effectiveUserId, prefs);
      return phone;
    }

    if (effectiveClient != null && user != null) {
      try {
        final row = await effectiveClient
            .from('profiles')
            .select('phone')
            .eq('user_id', user.id)
            .maybeSingle();
        final cloudPhone = row?['phone'] as String?;
        if (cloudPhone != null && cloudPhone.trim().isNotEmpty) {
          final phone = cloudPhone.trim();
          await prefs.setString(scopedKey, phone);
          _recordLocalPhoneOwnership(phone, effectiveUserId, prefs);
          return phone;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Cập nhật số điện thoại cá nhân của người dùng
  static Future<void> setCurrentUserPhone(
    String phone, {
    dynamic ref,
    SupabaseClient? client,
    String? userId,
    bool syncProfile = true,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '').trim();
    final effectiveClient = client ?? ref?.read(supabaseClientProvider);
    final user = effectiveClient?.auth.currentUser;
    final effectiveUserId = userId ?? user?.id;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userPhoneKey(effectiveUserId), cleanPhone);

    if (cleanPhone.isNotEmpty) {
      await _recordLocalPhoneOwnership(cleanPhone, effectiveUserId, prefs);
    }

    if (syncProfile &&
        effectiveClient != null &&
        user != null &&
        cleanPhone.isNotEmpty) {
      try {
        final store = PersonalProfileStore(effectiveClient);
        final profile = await store.load();
        await store.save(displayName: profile.displayName, phone: cleanPhone);
      } catch (_) {
        // Keep the local phone available offline; the profile stays unchanged
        // when its current name cannot be loaded or the server rejects a save.
      }
    }
  }

  /// Kiểm tra xem số điện thoại đã được dùng bởi tài khoản khác hay chưa
  static Future<bool> isPhoneTakenByAnotherUser(
    String phone, {
    dynamic ref,
    SupabaseClient? client,
    String? currentUserId,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleanPhone.isEmpty) return false;

    final SupabaseClient? effectiveClient =
        client ?? ref?.read(supabaseClientProvider);
    final effectiveUserId =
        currentUserId ?? effectiveClient?.auth.currentUser?.id;

    // 1. Kiểm tra qua RPC check_phone_available trên Supabase
    if (effectiveClient != null) {
      try {
        final isAvailable = await effectiveClient.rpc(
          'check_phone_available',
          params: {'p_phone': cleanPhone},
        );
        if (isAvailable is bool && !isAvailable) {
          return true;
        }
      } catch (_) {}
    }

    // 2. Kiểm tra qua local mapping phone -> owner userId
    final prefs = await SharedPreferences.getInstance();
    final rawMap = prefs.getString(_phoneOwnerKey);
    if (rawMap != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(rawMap) as Map);
        final ownerId = map[cleanPhone] as String?;
        if (ownerId != null &&
            effectiveUserId != null &&
            ownerId != effectiveUserId) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Kiểm tra xem số điện thoại đích có tồn tại người dùng trên hệ thống không
  static Future<bool> checkUserExistsByPhone(
    String phone,
    dynamic ref, {
    SupabaseClient? client,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleanPhone.isEmpty) return false;

    final SupabaseClient? effectiveClient =
        client ?? ref?.read(supabaseClientProvider);

    // 1. Kiểm tra qua RPC Supabase (SECURITY DEFINER, vượt qua RLS an toàn)
    if (effectiveClient != null) {
      try {
        final registered = await effectiveClient.rpc(
          'check_phone_registered',
          params: {'p_phone': cleanPhone},
        );
        if (registered is bool && registered) return true;
      } catch (_) {
        try {
          final row = await effectiveClient
              .from('profiles')
              .select('user_id')
              .eq('phone', cleanPhone)
              .maybeSingle();
          if (row != null) return true;
        } catch (_) {}
      }
    }

    // 2. Kiểm tra bản đồ local phone-owner map & danh sách số đã đăng ký
    final prefs = await SharedPreferences.getInstance();
    final rawMap = prefs.getString(_phoneOwnerKey);
    if (rawMap != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(rawMap) as Map);
        if (map.containsKey(cleanPhone)) return true;
      } catch (_) {}
    }

    final registeredPhones = prefs.getStringList(_registeredPhonesKey) ?? [];
    if (registeredPhones.contains(cleanPhone)) {
      return true;
    }

    // 3. Số điện thoại mẫu / seed
    if (_seedPhones.contains(cleanPhone)) {
      return true;
    }

    // 4. Kiểm tra với tài khoản hiện tại
    final currentPhone = await getCurrentUserPhone(
      ref,
      client: effectiveClient,
    );
    if (currentPhone != null && cleanPhone == currentPhone) {
      return true;
    }

    return false;
  }

  static Future<void> _recordLocalPhoneOwnership(
    String phone,
    String? userId,
    SharedPreferences prefs,
  ) async {
    try {
      final rawMap = prefs.getString(_phoneOwnerKey);
      final map = rawMap != null
          ? Map<String, dynamic>.from(jsonDecode(rawMap) as Map)
          : <String, dynamic>{};
      if (userId != null && userId.isNotEmpty) {
        map[phone] = userId;
        await prefs.setString(_phoneOwnerKey, jsonEncode(map));
      }

      final list = (prefs.getStringList(_registeredPhonesKey) ?? []).toSet();
      list.addAll(_seedPhones);
      list.add(phone);
      await prefs.setStringList(_registeredPhonesKey, list.toList());
    } catch (_) {}
  }

  /// Gửi thông báo trong app tới người dùng có SĐT đó. Trả về true nếu gửi thành công, false nếu không tìm thấy người dùng.
  static Future<bool> sendDebtNotification({
    required dynamic ref,
    required String targetPhone,
    required String senderName,
    String? senderPhone,
    String? debtId,
    required int amountMinor,
    String? notes,
    DateTime? dueDate,
  }) async {
    final cleanPhone = targetPhone.replaceAll(RegExp(r'\s+'), '').trim();
    final exists = await checkUserExistsByPhone(cleanPhone, ref);
    if (!exists) {
      // Đúng yêu cầu: Nếu không có thì thôi
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final list = raw != null ? (jsonDecode(raw) as List) : [];

    // Kiểm tra xem khoản nợ này đã được người nhận lưu trước đó chưa
    String? existingSavedDebtId;
    bool wasAlreadySaved = false;

    if (debtId != null) {
      for (final item in list) {
        if (item is Map &&
            item['debtId'] == debtId &&
            item['targetPhone'] == cleanPhone &&
            item['isSaved'] == true &&
            item['savedDebtId'] != null) {
          wasAlreadySaved = true;
          existingSavedDebtId = item['savedDebtId'] as String?;
          break;
        }
      }

      if (!wasAlreadySaved) {
        try {
          final cookieList = readSharedDebtNotificationsCookie();
          for (final item in cookieList) {
            if (item['debtId'] == debtId &&
                item['targetPhone'] == cleanPhone &&
                item['isSaved'] == true &&
                item['savedDebtId'] != null) {
              wasAlreadySaved = true;
              existingSavedDebtId = item['savedDebtId'] as String?;
              break;
            }
          }
        } catch (_) {}
      }
    }

    final notif = DebtInAppNotification(
      id: 'notif-${DateTime.now().millisecondsSinceEpoch}',
      targetPhone: cleanPhone,
      senderName: senderName,
      senderPhone: senderPhone,
      debtId: debtId,
      savedDebtId: wasAlreadySaved ? existingSavedDebtId : null,
      amountMinor: amountMinor,
      notes: notes,
      dueDate: dueDate,
      createdAt: DateTime.now(),
      isRead: false,
      isSaved: wasAlreadySaved,
    );

    // Xóa các bản ghi cũ của cùng debtId để không bị nhân bản
    if (debtId != null) {
      list.removeWhere((item) {
        if (item is Map) {
          final itemDebtId = item['debtId'] as String?;
          final itemTargetPhone = item['targetPhone'] as String?;
          return itemDebtId == debtId && itemTargetPhone == cleanPhone;
        }
        return false;
      });
    }

    final jsonItem = notif.toJson();
    list.add(jsonItem);
    await prefs.setString(_storageKey, jsonEncode(list));

    // Đồng bộ vào shared cookie để port 8080 và 8081 cùng nhận được ngay trên localhost
    try {
      final cookieList = readSharedDebtNotificationsCookie().toList();
      if (debtId != null) {
        cookieList.removeWhere(
          (e) => e['debtId'] == debtId && e['targetPhone'] == cleanPhone,
        );
      }
      cookieList.removeWhere((e) => e['id'] == notif.id);
      cookieList.add(jsonItem);
      writeSharedDebtNotificationsCookie(cookieList);
    } catch (_) {}

    // Kích hoạt thông báo hệ thống / đẩy kèm rung và hiển thị màn hình khóa
    try {
      final money = MoneyFormatter.format(amountMinor);
      final fromInfo =
          (senderPhone != null &&
              senderPhone.isNotEmpty &&
              senderName != senderPhone)
          ? '$senderName ($senderPhone)'
          : senderName;
      await BudgetNotificationService.instance.showDebtNotification(
        title: 'Thông báo nợ từ $fromInfo',
        body:
            'Khoản nợ: $money${notes != null && notes.isNotEmpty ? ' · $notes' : ''}',
        payload: '/invoices?tab=debts',
      );
    } catch (_) {}

    return true;
  }

  /// Lấy tất cả thông báo (từ cả local và shared cookie)
  static Future<List<DebtInAppNotification>> getAllNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final Map<String, DebtInAppNotification> mergedMap = {};

    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).map(
          (e) => DebtInAppNotification.fromJson(e as Map<String, dynamic>),
        );
        for (final item in list) {
          mergedMap[item.id] = item;
        }
      } catch (_) {}
    }

    try {
      final cookieItems = readSharedDebtNotificationsCookie();
      for (final rawItem in cookieItems) {
        final item = DebtInAppNotification.fromJson(rawItem);
        if (!mergedMap.containsKey(item.id)) {
          mergedMap[item.id] = item;
        } else {
          final existing = mergedMap[item.id]!;
          mergedMap[item.id] = existing.copyWith(
            isRead: item.isRead || existing.isRead,
            isSaved: item.isSaved || existing.isSaved,
            savedDebtId: item.savedDebtId ?? existing.savedDebtId,
          );
        }
      }
    } catch (_) {}

    final list = mergedMap.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Lấy thông báo gửi đi của một khoản nợ cụ thể
  static Future<DebtInAppNotification?> getNotificationForDebt(
    String debtId,
  ) async {
    final all = await getAllNotifications();
    final matching = all.where((n) => n.debtId == debtId).toList();
    if (matching.isEmpty) return null;
    final saved = matching.where((n) => n.isSaved).firstOrNull;
    if (saved != null) return saved;
    return matching.first;
  }

  /// Xác nhận và lưu thông báo nợ vào khoản nợ của người nhận
  static Future<void> confirmAndSaveNotification({
    required String notifId,
    required String savedDebtId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    List<DebtInAppNotification> currentList = [];
    if (raw != null) {
      try {
        currentList = (jsonDecode(raw) as List)
            .map(
              (e) => DebtInAppNotification.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      } catch (_) {}
    }

    final targetNotif = currentList.where((n) => n.id == notifId).firstOrNull;
    final targetDebtId = targetNotif?.debtId;

    final updated = currentList
        .map((n) {
          if (n.id == notifId ||
              (targetDebtId != null && n.debtId == targetDebtId)) {
            return n.copyWith(
              isSaved: true,
              savedDebtId: savedDebtId,
              isRead: true,
            );
          }
          return n;
        })
        .map((n) => n.toJson())
        .toList();
    await prefs.setString(_storageKey, jsonEncode(updated));

    // Cập nhật cookie chung để bên người gửi cũng thấy trạng thái đã lưu
    try {
      final cookieList = readSharedDebtNotificationsCookie().map((e) {
        if (e['id'] == notifId ||
            (targetDebtId != null && e['debtId'] == targetDebtId)) {
          e['isSaved'] = true;
          e['savedDebtId'] = savedDebtId;
          e['isRead'] = true;
        }
        return e;
      }).toList();
      writeSharedDebtNotificationsCookie(cookieList);
    } catch (_) {}
  }

  /// Lấy danh sách thông báo gửi đến số điện thoại (tổng hợp từ local và cookie đa cổng)
  static Future<List<DebtInAppNotification>> getNotificationsForPhone(
    String phone,
  ) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '').trim();
    final all = await getAllNotifications();
    final result = all.where((n) => n.targetPhone == cleanPhone).toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Đánh dấu đã đọc
  static Future<void> markAsRead(String notifId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    List<DebtInAppNotification> currentList = [];
    if (raw != null) {
      try {
        currentList = (jsonDecode(raw) as List)
            .map(
              (e) => DebtInAppNotification.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      } catch (_) {}
    }

    final updated = currentList
        .map((n) => n.id == notifId ? n.copyWith(isRead: true) : n)
        .map((n) => n.toJson())
        .toList();
    await prefs.setString(_storageKey, jsonEncode(updated));

    // Cập nhật cookie chung
    try {
      final cookieList = readSharedDebtNotificationsCookie().map((e) {
        if (e['id'] == notifId) {
          e['isRead'] = true;
        }
        return e;
      }).toList();
      writeSharedDebtNotificationsCookie(cookieList);
    } catch (_) {}
  }
}

final userPhoneProvider = FutureProvider.autoDispose<String?>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  return DebtNotificationStore.getCurrentUserPhone(ref, userId: user?.id);
});

final debtNotificationsProvider =
    FutureProvider.autoDispose<List<DebtInAppNotification>>((ref) async {
      final phone = await ref.watch(userPhoneProvider.future);
      if (phone == null || phone.isEmpty) return const [];

      // Tự động làm mới mỗi 3 giây để người nhận thấy thông báo từ máy người gửi ngay lập tức
      final timer = Timer(const Duration(seconds: 3), () {
        ref.invalidateSelf();
      });
      ref.onDispose(() => timer.cancel());

      return DebtNotificationStore.getNotificationsForPhone(phone);
    });

final sentDebtNotificationStatusProvider = FutureProvider.autoDispose
    .family<DebtInAppNotification?, String>((ref, debtId) async {
      final timer = Timer(const Duration(seconds: 3), () {
        ref.invalidateSelf();
      });
      ref.onDispose(() => timer.cancel());
      return DebtNotificationStore.getNotificationForDebt(debtId);
    });
