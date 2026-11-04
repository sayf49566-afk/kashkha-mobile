import 'dart:convert';
import 'package:http/http.dart' as http;

class SupabaseService {
  static const String defaultUrl = 'https://acagrmopsoodfwekmhok.supabase.co';
  static const String defaultKey = 'sb_publishable_MTMDUAQFuGHqQfUJqmSuHw_kBak9Axl';

  String supabaseUrl;
  String supabaseKey;

  SupabaseService({
    this.supabaseUrl = defaultUrl,
    this.supabaseKey = defaultKey,
  });

  Map<String, String> _headers({Map<String, String>? extra}) {
    final headers = <String, String>{
      'apikey': supabaseKey,
      'Content-Type': 'application/json',
    };
    if (supabaseKey.startsWith('eyJ')) {
      headers['Authorization'] = 'Bearer $supabaseKey';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  /// جلب جميع سجلات جدول معين من Supabase
  Future<List<Map<String, dynamic>>> fetchTable(String tableName) async {
    final uri = Uri.parse('$supabaseUrl/rest/v1/$tableName?select=id,data,updated_at');
    final response = await http.get(uri, headers: _headers());

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final List<dynamic> rows = jsonDecode(utf8.decode(response.bodyBytes));
      final List<Map<String, dynamic>> result = [];
      for (final row in rows) {
        if (row is Map && row['data'] is Map) {
          final mapData = Map<String, dynamic>.from(row['data'] as Map);
          mapData['id'] = (mapData['id'] ?? row['id']).toString();
          result.add(mapData);
        }
      }
      return result;
    } else {
      throw Exception('فشل جلب جدول $tableName (كود: ${response.statusCode})');
    }
  }

  /// جلب إعدادات المحل من جدول settings
  Future<Map<String, dynamic>> fetchSettings() async {
    final defaults = <String, dynamic>{
      'id': 'general',
      'shopName': '',
      'shopPhone': '',
      'shopAddress': '',
      'fabricPerThobe': 3.5,
      'taxRate': 0,
    };

    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/settings?id=eq.general&select=id,data');
      final response = await http.get(uri, headers: _headers());
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final List<dynamic> rows = jsonDecode(utf8.decode(response.bodyBytes));
        if (rows.isNotEmpty && rows.first['data'] is Map) {
          return {
            ...defaults,
            ...Map<String, dynamic>.from(rows.first['data'] as Map),
          };
        }
      }
    } catch (_) {}
    return defaults;
  }

  /// حفظ أو تحديث سجل في جدول معين (Upsert)
  Future<bool> upsertRecord(String tableName, Map<String, dynamic> recordData) async {
    final String id = recordData['id'].toString();
    final updatedData = Map<String, dynamic>.from(recordData);
    updatedData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final payload = [
      {
        'id': id,
        'data': updatedData,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }
    ];

    final uri = Uri.parse('$supabaseUrl/rest/v1/$tableName?on_conflict=id');
    final response = await http.post(
      uri,
      headers: _headers(extra: {
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      }),
      body: jsonEncode(payload),
    );

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  /// حذف سجل من جدول سحابي
  Future<bool> deleteRecord(String tableName, String recordId) async {
    final uri = Uri.parse(
      '$supabaseUrl/rest/v1/$tableName?id=eq.${Uri.encodeComponent(recordId)}',
    );
    final response = await http.delete(uri, headers: _headers());
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  /// تحديث حالة الطلب (جديد -> قيد التنفيذ -> جاهز للاستلام -> مكتمل)
  Future<bool> updateOrderStatus(Map<String, dynamic> order, String newStatus) async {
    final updated = Map<String, dynamic>.from(order);
    updated['status'] = newStatus;
    return upsertRecord('orders', updated);
  }

  /// تسديد مبلغ متبقي على طلب (كاش أو شبكة)
  Future<bool> payOrderRemaining({
    required Map<String, dynamic> order,
    required double amount,
    required String method, // 'cash' | 'network'
  }) async {
    final updated = Map<String, dynamic>.from(order);
    final double cash = _toDouble(updated['depositCash']);
    final double net = _toDouble(updated['depositNetwork']);
    final double oldDeposit = _toDouble(updated['deposit']);

    if (method == 'cash') {
      updated['depositCash'] = cash + amount;
    } else {
      updated['depositNetwork'] = net + amount;
    }
    updated['deposit'] = (cash + net > 0 ? cash + net : oldDeposit) + amount;

    final List<dynamic> history = updated['paymentHistory'] is List
        ? List<dynamic>.from(updated['paymentHistory'])
        : [];

    history.add({
      'amount': amount,
      'method': method,
      'date': DateTime.now().toIso8601String(),
      'type': 'سداد من تطبيق الجوال',
    });
    updated['paymentHistory'] = history;

    return upsertRecord('orders', updated);
  }

  /// إضافة مصروف جديد من الجوال
  Future<bool> addExpense({
    required String description,
    required String category,
    required double totalAmount,
    required double paidAmount,
  }) async {
    final String id = DateTime.now().millisecondsSinceEpoch.toString();
    final String nowIso = DateTime.now().toIso8601String();
    final double remaining = (totalAmount - paidAmount).clamp(0, double.infinity);

    final newExpense = <String, dynamic>{
      'id': id,
      'description': description,
      'category': category,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'remainingAmount': remaining,
      'date': nowIso,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'payments': paidAmount > 0
          ? [
              {
                'id': DateTime.now().millisecondsSinceEpoch,
                'amount': paidAmount,
                'date': nowIso,
                'note': paidAmount >= totalAmount ? 'سداد كامل (من الجوال)' : 'دفعة أولية (من الجوال)',
              }
            ]
          : [],
    };

    return upsertRecord('expenses', newExpense);
  }

  /// سداد دفعة لمصروف غير مكتمل
  Future<bool> payExpenseRemaining({
    required Map<String, dynamic> expense,
    required double amount,
    String note = 'دفعة سداد (من الجوال)',
  }) async {
    final updated = Map<String, dynamic>.from(expense);
    final double total = _toDouble(updated['totalAmount'] ?? updated['amount']);
    final double currentPaid = updated['paidAmount'] != null ? _toDouble(updated['paidAmount']) : total;
    final double newPaid = currentPaid + amount;
    final double newRem = (total - newPaid).clamp(0, double.infinity);

    updated['paidAmount'] = newPaid;
    updated['remainingAmount'] = newRem;

    final List<dynamic> payments = updated['payments'] is List
        ? List<dynamic>.from(updated['payments'])
        : [];
    payments.add({
      'id': DateTime.now().millisecondsSinceEpoch,
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
      'note': note,
    });
    updated['payments'] = payments;

    return upsertRecord('expenses', updated);
  }

  /// تزويد كمية صنف في المخزون
  Future<bool> restockInventoryItem(Map<String, dynamic> item, double additionalQty) async {
    final updated = Map<String, dynamic>.from(item);
    final double currentQty = _toDouble(updated['quantity']);
    updated['quantity'] = currentQty + additionalQty;
    return upsertRecord('inventory', updated);
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
}
