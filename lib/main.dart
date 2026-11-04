import 'package:flutter/material.dart';
import 'services/supabase_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KashkhaTailorMobileApp());
}

class KashkhaTailorMobileApp extends StatelessWidget {
  const KashkhaTailorMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'كشخة للخياطة - تطبيق المتابعة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A2E4D),
          primary: const Color(0xFF0A2E4D),
          secondary: const Color(0xFFD97706),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A2E4D),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MainHomeShell(),
    );
  }
}

class MainHomeShell extends StatefulWidget {
  const MainHomeShell({super.key});

  @override
  State<MainHomeShell> createState() => _MainHomeShellState();
}

class _MainHomeShellState extends State<MainHomeShell> {
  final SupabaseService _api = SupabaseService();

  int _currentIndex = 0;
  bool _isLoading = true;
  String? _errorMsg;
  DateTime? _lastSyncTime;

  Map<String, dynamic> _settings = {
    'shopName': 'كشخة للخياطة الرجالية',
    'shopPhone': '0548962387',
    'fabricPerThobe': 3.5,
  };
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _inventory = [];

  // فلاتر صفحة الطلبات
  String _orderSearch = '';
  String _orderStatusFilter = 'الكل';

  // فلاتر صفحة المصروفات
  String _expenseCategoryFilter = 'all';

  // فلتر فترة التقارير
  String _reportPeriod = 'month'; // 'today' | 'week' | 'month' | 'all'

  static const List<Map<String, String>> expenseCategories = [
    {'id': 'general', 'label': 'عام', 'icon': '📝'},
    {'id': 'returns', 'label': 'مرتجع مبيعات', 'icon': '↩️'},
    {'id': 'salaries', 'label': 'رواتب', 'icon': '👷‍♂️'},
    {'id': 'rent', 'label': 'إيجار', 'icon': '🏠'},
    {'id': 'materials', 'label': 'مواد خام', 'icon': '🧵'},
    {'id': 'bills', 'label': 'فواتير (كهرباء/نت)', 'icon': '💡'},
    {'id': 'maintenance', 'label': 'صيانة', 'icon': '🔧'},
    {'id': 'transport', 'label': 'نقل وتوصيل', 'icon': '🚚'},
    {'id': 'marketing', 'label': 'تسويق', 'icon': '📣'},
  ];

  @override
  void initState() {
    super.initState();
    _loadAllCloudData();
  }

  Future<void> _loadAllCloudData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }

    try {
      final results = await Future.wait([
        _api.fetchSettings(),
        _api.fetchTable('orders'),
        _api.fetchTable('expenses'),
        _api.fetchTable('inventory'),
      ]);

      final settingsData = results[0] as Map<String, dynamic>;
      final ordersList = List<Map<String, dynamic>>.from(results[1] as List);
      final expensesList = List<Map<String, dynamic>>.from(results[2] as List);
      final inventoryList = List<Map<String, dynamic>>.from(results[3] as List);

      // ترتيب الطلبات من الأحدث للأقدم
      ordersList.sort((a, b) {
        final tA = _toInt(a['createdAt']);
        final tB = _toInt(b['createdAt']);
        return tB.compareTo(tA);
      });

      // ترتيب المصروفات من الأحدث للأقدم
      expensesList.sort((a, b) {
        final dA = DateTime.tryParse(a['date']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
        final dB = DateTime.tryParse(b['date']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
        return dB.compareTo(dA);
      });

      if (!mounted) return;
      setState(() {
        _settings = settingsData;
        _orders = ordersList;
        _expenses = expensesList;
        _inventory = inventoryList;
        _lastSyncTime = DateTime.now();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'تعذر الاتصال بالسحابة: $e';
        _isLoading = false;
      });
    }
  }

  // ==========================================
  // دوال الحسابات المساعدة (مطابقة لنظام سطح المكتب)
  // ==========================================
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  static DateTime? _parseAnyDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    final asInt = int.tryParse(raw.toString());
    if (asInt != null && asInt > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(asInt);
    }
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  static double _calcOrderPaid(Map<String, dynamic> order) {
    if (order['status'] == 'ملغي') return 0.0;
    final total = _toDouble(order['totalPrice']);
    if (order['isInstallments'] == true) {
      final inst = _toDouble(order['depositInstallment']);
      return inst > 0 ? inst : total;
    }
    final cash = _toDouble(order['depositCash']);
    final net = _toDouble(order['depositNetwork']);
    if ((cash + net) > 0) return cash + net;
    return _toDouble(order['deposit']);
  }

  static double _calcOrderRemaining(Map<String, dynamic> order) {
    if (order['status'] == 'ملغي' || order['isInstallments'] == true) return 0.0;
    final total = _toDouble(order['totalPrice']);
    final paid = _calcOrderPaid(order);
    return (total - paid).clamp(0.0, double.infinity);
  }

  static int _calcOrderThobes(Map<String, dynamic> order) {
    final items = order['items'];
    if (items is List && items.isNotEmpty) {
      int sum = 0;
      for (final item in items) {
        if (item is Map) {
          sum += _toInt(item['quantity'] ?? 1);
        }
      }
      return sum > 0 ? sum : 1;
    }
    final q = _toInt(order['quantity']);
    return q > 0 ? q : 1;
  }

  // ==========================================
  // الواجهة الرئيسية (Scaffold + BottomNav)
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final shopName = (_settings['shopName']?.toString().trim().isNotEmpty ?? false)
        ? _settings['shopName'].toString()
        : 'كشخة للخياطة الرجالية';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shopName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Text(
              _lastSyncTime != null
                  ? '☁️ متصل بالسحابة • آخر تحديث ${_lastSyncTime!.hour.toString().padLeft(2, '0')}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}'
                  : '☁️ جاري المزامنة مع السحابة...',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA7F3D0)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات الآن',
            onPressed: () => _loadAllCloudData(),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: _errorMsg != null
          ? _buildErrorState()
          : _isLoading && _orders.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : IndexedStack(
                  index: _currentIndex,
                  children: [
                    _buildDashboardTab(),
                    _buildOrdersTab(),
                    _buildExpensesTab(),
                    _buildInventoryTab(),
                    _buildReportsTab(),
                  ],
                ),
      floatingActionButton: _currentIndex == 2
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              onPressed: _showAddExpenseSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('مصروف جديد', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDBEAFE),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded, color: Color(0xFF0A2E4D)),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.content_cut_outlined),
            selectedIcon: Icon(Icons.content_cut_rounded, color: Color(0xFF0A2E4D)),
            label: 'الطلبات',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0A2E4D)),
            label: 'المصروفات',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded, color: Color(0xFF0A2E4D)),
            label: 'المخزون',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded, color: Color(0xFF0A2E4D)),
            label: 'التقارير',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              _errorMsg ?? 'حدث خطأ',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAllCloudData,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 1. تبويب الرئيسية (Dashboard)
  // ==========================================
  Widget _buildDashboardTab() {
    final now = DateTime.now();

    // حساب مقبوضات اليوم
    double todayCash = 0;
    double todayNet = 0;
    double todayInst = 0;
    int todayThobes = 0;

    // حساب الإجماليات العامة
    double totalCollectedIncome = 0;
    double totalRemainingWithCustomers = 0;
    int activeOrdersCount = 0;

    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final List<Map<String, dynamic>> urgentOrders = [];

    for (final order in _orders) {
      final status = order['status']?.toString() ?? 'جديد';
      if (status == 'ملغي') continue;

      if (status != 'مكتمل') {
        activeOrdersCount++;
      }

      totalCollectedIncome += _calcOrderPaid(order);
      totalRemainingWithCustomers += _calcOrderRemaining(order);

      final createdDate = _parseAnyDate(order['createdAt']);
      if (createdDate != null && _isSameDay(createdDate, now)) {
        todayThobes += _calcOrderThobes(order);
      }

      // فحص سجل الدفعات لليوم
      final history = order['paymentHistory'];
      if (history is List && history.isNotEmpty) {
        for (final p in history) {
          if (p is Map) {
            final pDate = _parseAnyDate(p['date']);
            if (pDate != null && _isSameDay(pDate, now)) {
              final amt = _toDouble(p['amount']);
              final method = p['method']?.toString() ?? 'cash';
              if (method == 'cash') {
                todayCash += amt;
              } else if (method == 'network') {
                todayNet += amt;
              } else {
                todayInst += amt;
              }
            }
          }
        }
      } else if (createdDate != null && _isSameDay(createdDate, now)) {
        if (order['isInstallments'] == true) {
          final v = _toDouble(order['depositInstallment']);
          todayInst += v > 0 ? v : _toDouble(order['totalPrice']);
        } else {
          todayCash += _toDouble(order['depositCash']);
          todayNet += _toDouble(order['depositNetwork']);
        }
      }

      // فحص تنبيهات التسليم العاجلة
      final deliv = order['deliveryDate']?.toString() ?? '';
      if (deliv.isNotEmpty &&
          status != 'مكتمل' &&
          status != 'جاهز للاستلام' &&
          deliv.compareTo(todayStr) <= 0) {
        urgentOrders.add(order);
      }
    }

    final todayTotal = todayCash + todayNet + todayInst;

    double totalExpensesPaid = 0;
    for (final exp in _expenses) {
      final t = _toDouble(exp['totalAmount'] ?? exp['amount']);
      final p = exp['paidAmount'] != null ? _toDouble(exp['paidAmount']) : t;
      totalExpensesPaid += p;
    }

    final netActualProfit = totalCollectedIncome - totalExpensesPaid;

    return RefreshIndicator(
      onRefresh: () => _loadAllCloudData(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة مقبوضات اليوم الذهبية
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A2E4D), Color(0xFF16436D)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0A2E4D).withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '💰 إجمالي مقبوضات اليوم',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '👔 $todayThobes ثوب اليوم',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${todayTotal.toStringAsFixed(0)} ريال',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildMiniTodayPill('💵 كاش', '${todayCash.toStringAsFixed(0)} ر.س'),
                    const SizedBox(width: 8),
                    _buildMiniTodayPill('💳 شبكة', '${todayNet.toStringAsFixed(0)} ر.س'),
                    const SizedBox(width: 8),
                    _buildMiniTodayPill('🛍️ أقساط', '${todayInst.toStringAsFixed(0)} ر.س'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // شبكة الملخص المالي الفعلي (4 مربعات)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _buildMetricCard(
                title: 'الدخل الفعلي المقبوض',
                value: '${totalCollectedIncome.toStringAsFixed(0)} ريال',
                subtitle: 'بدون المتبقي عند العملاء',
                color: const Color(0xFF10B981),
                icon: Icons.trending_up_rounded,
              ),
              _buildMetricCard(
                title: 'المصروفات المسددة',
                value: '${totalExpensesPaid.toStringAsFixed(0)} ريال',
                subtitle: '${_expenses.length} عملية مسجلة',
                color: const Color(0xFFEF4444),
                icon: Icons.trending_down_rounded,
              ),
              _buildMetricCard(
                title: 'صافي الربح الفعلي',
                value: '${netActualProfit.toStringAsFixed(0)} ريال',
                subtitle: 'الدخل الفعلي - المصروفات',
                color: const Color(0xFF2563EB),
                icon: Icons.account_balance_rounded,
              ),
              _buildMetricCard(
                title: 'المتبقي عند العملاء',
                value: '${totalRemainingWithCustomers.toStringAsFixed(0)} ريال',
                subtitle: '$activeOrdersCount طلب نشط حالياً',
                color: const Color(0xFFD97706),
                icon: Icons.pending_actions_rounded,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // تنبيهات التسليم العاجلة
          if (urgentOrders.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔥 تنبيهات تسليم عاجلة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${urgentOrders.length} طلب',
                    style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...urgentOrders.take(4).map((o) => _buildOrderCard(o)),
            const SizedBox(height: 16),
          ],

          // أحدث الطلبات
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '📋 أحدث طلبات التفصيل',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0A2E4D)),
              ),
              TextButton(
                onPressed: () => setState(() => _currentIndex = 1),
                child: const Text('عرض الكل ⬅'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_orders.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('لا توجد طلبات مسجلة حالياً')),
              ),
            )
          else
            ..._orders.take(6).map((o) => _buildOrderCard(o)),
        ],
      ),
    );
  }

  Widget _buildMiniTodayPill(String label, String val) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              val,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(right: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. تبويب الطلبات والتفصيل (Orders)
  // ==========================================
  Widget _buildOrdersTab() {
    const statuses = ['الكل', 'جديد', 'قيد التنفيذ', 'جاهز للاستلام', 'مكتمل', 'ملغي'];

    final filtered = _orders.where((o) {
      final status = o['status']?.toString() ?? 'جديد';
      if (_orderStatusFilter != 'الكل' && status != _orderStatusFilter) {
        return false;
      }
      if (_orderSearch.trim().isNotEmpty) {
        final q = _orderSearch.trim().toLowerCase();
        final numStr = (o['orderNumber']?.toString() ?? '').toLowerCase();
        final nameStr = (o['name']?.toString() ?? '').toLowerCase();
        final phoneStr = (o['phone']?.toString() ?? '').toLowerCase();
        return numStr.contains(q) || nameStr.contains(q) || phoneStr.contains(q);
      }
      return true;
    }).toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setState(() => _orderSearch = v),
                decoration: InputDecoration(
                  hintText: 'ابحث برقم الطلب، اسم العميل، أو الجوال...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: statuses.map((st) {
                    final isSelected = _orderStatusFilter == st;
                    final count = st == 'الكل'
                        ? _orders.length
                        : _orders.where((o) => (o['status']?.toString() ?? 'جديد') == st).length;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text('$st ($count)'),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _orderStatusFilter = st),
                        selectedColor: const Color(0xFF0A2E4D),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadAllCloudData(silent: true),
            child: filtered.isEmpty
                ? const Center(child: Text('لا توجد طلبات مطابقة للبحث'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) => _buildOrderCard(filtered[idx]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'جديد';
    final total = _toDouble(order['totalPrice']);
    final remaining = _calcOrderRemaining(order);
    final thobes = _calcOrderThobes(order);
    final orderNum = order['orderNumber']?.toString() ?? '-';
    final name = order['name']?.toString() ?? 'عميل';
    final phone = order['phone']?.toString() ?? '';
    final deliveryDate = order['deliveryDate']?.toString() ?? '';

    Color statusColor = const Color(0xFF2563EB);
    Color statusBg = const Color(0xFFEFF6FF);
    if (status == 'قيد التنفيذ') {
      statusColor = const Color(0xFFD97706);
      statusBg = const Color(0xFFFFFBEB);
    } else if (status == 'جاهز للاستلام') {
      statusColor = const Color(0xFF7C3AED);
      statusBg = const Color(0xFFF5F3FF);
    } else if (status == 'مكتمل') {
      statusColor = const Color(0xFF059669);
      statusBg = const Color(0xFFECFDF5);
    } else if (status == 'ملغي') {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEF2F2);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showOrderDetailsModal(order),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '#$orderNum',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0A2E4D),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFF1F5F9)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('👔 $thobes ثوب', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      if (deliveryDate.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Text('📅 تسليم: $deliveryDate', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '${total.toStringAsFixed(0)} ريال',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0A2E4D), fontSize: 15),
                      ),
                      const SizedBox(width: 8),
                      if (status != 'ملغي')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: remaining > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            remaining > 0 ? 'متبقي: ${remaining.toStringAsFixed(0)}' : 'مدفوع ✅',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: remaining > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // نافذة تفاصيل الطلب والتحكم السريع (تغيير الحالة + سداد المتبقي + عرض المقاسات)
  void _showOrderDetailsModal(Map<String, dynamic> order) {
    final total = _toDouble(order['totalPrice']);
    final paid = _calcOrderPaid(order);
    final remaining = _calcOrderRemaining(order);
    final measurements = order['measurements'] is Map
        ? Map<String, dynamic>.from(order['measurements'] as Map)
        : <String, dynamic>{};
    final items = order['items'] is List ? List<dynamic>.from(order['items'] as List) : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'تفاصيل الطلب #${order['orderNumber']}',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF0A2E4D)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '👤 العميل: ${order['name'] ?? ''}  •  📱 ${order['phone'] ?? ''}',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                ),
                if (order['notebookNumber'] != null || order['pageNumber'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '📔 دفتر: ${order['notebookNumber'] ?? '-'}  /  صفحة: ${order['pageNumber'] ?? '-'}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFFD97706), fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(height: 16),

                // الملخص المالي للطلب
                Row(
                  children: [
                    Expanded(
                      child: _buildOrderFinanceBox('الإجمالي', '${total.toStringAsFixed(0)} ر.س', const Color(0xFF0A2E4D)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildOrderFinanceBox('المدفوع', '${paid.toStringAsFixed(0)} ر.س', const Color(0xFF059669)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildOrderFinanceBox('المتبقي', '${remaining.toStringAsFixed(0)} ر.س', const Color(0xFFDC2626)),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // تحكم سريع بحالة الطلب
                const Text(
                  '⚡ تحديث حالة الطلب في السحابة:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['جديد', 'قيد التنفيذ', 'جاهز للاستلام', 'مكتمل'].map((st) {
                    final isCurrent = (order['status'] ?? 'جديد') == st;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrent ? const Color(0xFF0A2E4D) : const Color(0xFFF1F5F9),
                        foregroundColor: isCurrent ? Colors.white : const Color(0xFF334155),
                        elevation: 0,
                      ),
                      onPressed: isCurrent
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              final ok = await _api.updateOrderStatus(order, st);
                              if (ok) {
                                await _loadAllCloudData(silent: true);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('تم تحديث حالة الطلب إلى "$st" ✅')),
                                  );
                                }
                              }
                            },
                      child: Text(st),
                    );
                  }).toList(),
                ),

                // زر تحصيل المبلغ المتبقي إن وجد
                if (remaining > 0 && order['status'] != 'ملغي') ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '💵 تحصيل المبلغ المتبقي (${remaining.toStringAsFixed(0)} ريال):',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  final ok = await _api.payOrderRemaining(
                                    order: order,
                                    amount: remaining,
                                    method: 'cash',
                                  );
                                  if (ok) {
                                    await _loadAllCloudData(silent: true);
                                  }
                                },
                                icon: const Icon(Icons.payments_outlined, size: 18),
                                label: const Text('سداد كامل كاش'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  final ok = await _api.payOrderRemaining(
                                    order: order,
                                    amount: remaining,
                                    method: 'network',
                                  );
                                  if (ok) {
                                    await _loadAllCloudData(silent: true);
                                  }
                                },
                                icon: const Icon(Icons.credit_card_rounded, size: 18),
                                label: const Text('سداد كامل شبكة'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // الأقمشة والأصناف
                if (items.isNotEmpty) ...[
                  const Text(
                    '🧵 الأقمشة والأصناف:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ...items.map((it) {
                    if (it is! Map) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${it['fabricName'] ?? 'ثوب'} (العدد: ${it['quantity'] ?? 1})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('${it['unitPrice'] ?? 0} ريال / للثوب'),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                ],

                // جدول المقاسات
                if (measurements.isNotEmpty) ...[
                  const Text(
                    '📏 مقاسات التفصيل:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildMeasureChip('الطول', measurements['length']),
                      _buildMeasureChip('الكتف', measurements['shoulder']),
                      _buildMeasureChip('طول الكم', measurements['sleeveLength']),
                      _buildMeasureChip('وسع الصدر', measurements['chestWidth']),
                      _buildMeasureChip('وسع البطن', measurements['stomachWidth']),
                      _buildMeasureChip('الرقبة', measurements['neck']),
                      _buildMeasureChip('اليد', measurements['hand']),
                      _buildMeasureChip('الكبك', measurements['cuff']),
                      _buildMeasureChip('القلاب', measurements['collarType']),
                      _buildMeasureChip('الجبزور', measurements['jabzoor']),
                    ].whereType<Widget>().toList(),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOrderFinanceBox(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget? _buildMeasureChip(String label, dynamic val) {
    if (val == null || val.toString().trim().isEmpty) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          Text(
            val.toString(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0A2E4D)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 3. تبويب المصروفات والالتزامات (Expenses)
  // ==========================================
  Widget _buildExpensesTab() {
    final filtered = _expenses.where((e) {
      if (_expenseCategoryFilter == 'all') return true;
      return (e['category']?.toString() ?? 'general') == _expenseCategoryFilter;
    }).toList();

    double totalAll = 0;
    double paidAll = 0;
    for (final e in filtered) {
      final t = _toDouble(e['totalAmount'] ?? e['amount']);
      final p = e['paidAmount'] != null ? _toDouble(e['paidAmount']) : t;
      totalAll += t;
      paidAll += p;
    }
    final remAll = (totalAll - paidAll).clamp(0.0, double.infinity);

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildOrderFinanceBox('الإجمالي', '${totalAll.toStringAsFixed(0)} ر.س', const Color(0xFF0A2E4D)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildOrderFinanceBox('المدفوع', '${paidAll.toStringAsFixed(0)} ر.س', const Color(0xFF059669)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildOrderFinanceBox('المتبقي', '${remAll.toStringAsFixed(0)} ر.س', const Color(0xFFDC2626)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text('📂 الكل (${_expenses.length})'),
                        selected: _expenseCategoryFilter == 'all',
                        onSelected: (_) => setState(() => _expenseCategoryFilter = 'all'),
                      ),
                    ),
                    ...expenseCategories.map((cat) {
                      final id = cat['id']!;
                      final isSelected = _expenseCategoryFilter == id;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text('${cat['icon']} ${cat['label']}'),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _expenseCategoryFilter = id),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadAllCloudData(silent: true),
            child: filtered.isEmpty
                ? const Center(child: Text('لا توجد مصروفات مسجلة في هذا التصنيف'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final exp = filtered[idx];
                      final total = _toDouble(exp['totalAmount'] ?? exp['amount']);
                      final paid = exp['paidAmount'] != null ? _toDouble(exp['paidAmount']) : total;
                      final rem = (total - paid).clamp(0.0, double.infinity);
                      final catId = exp['category']?.toString() ?? 'general';
                      final catObj = expenseCategories.firstWhere(
                        (c) => c['id'] == catId,
                        orElse: () => expenseCategories.first,
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFFFBEB),
                            child: Text(catObj['icon'] ?? '📝', style: const TextStyle(fontSize: 20)),
                          ),
                          title: Text(
                            exp['description']?.toString() ?? catObj['label']!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            rem > 0
                                ? 'المدفوع: ${paid.toStringAsFixed(0)} • المتبقي: ${rem.toStringAsFixed(0)} ريال'
                                : 'مسدد بالكامل ✅',
                            style: TextStyle(
                              color: rem > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${total.toStringAsFixed(0)} ر.س',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0A2E4D)),
                              ),
                              if (rem > 0)
                                GestureDetector(
                                  onTap: () async {
                                    final ok = await _api.payExpenseRemaining(expense: exp, amount: rem);
                                    if (ok) {
                                      await _loadAllCloudData(silent: true);
                                    }
                                  },
                                  child: const Text(
                                    'سداد المتبقي 💵',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _showAddExpenseSheet() {
    String selectedCat = 'general';
    final descCtrl = TextEditingController();
    final totalCtrl = TextEditingController();
    final paidCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                right: 20,
                left: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '➕ تسجيل مصروف جديد في السحابة',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0A2E4D)),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: expenseCategories.map((cat) {
                        final isSel = selectedCat == cat['id'];
                        return ChoiceChip(
                          label: Text('${cat['icon']} ${cat['label']}'),
                          selected: isSel,
                          onSelected: (_) => setModalState(() => selectedCat = cat['id']!),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'وصف أو ملاحظة المصروف',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: totalCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (v) => paidCtrl.text = v,
                            decoration: const InputDecoration(
                              labelText: 'المبلغ الكلي (ريال)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: paidCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'المدفوع الآن (ريال)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final total = double.tryParse(totalCtrl.text.trim()) ?? 0;
                          if (total <= 0) return;
                          final paid = double.tryParse(paidCtrl.text.trim()) ?? total;
                          final catLabel = expenseCategories.firstWhere((c) => c['id'] == selectedCat)['label']!;
                          final customDesc = descCtrl.text.trim();
                          final finalDesc = customDesc.isNotEmpty
                              ? (selectedCat == 'general' ? customDesc : '$catLabel - $customDesc')
                              : catLabel;

                          Navigator.pop(ctx);
                          final ok = await _api.addExpense(
                            description: finalDesc,
                            category: selectedCat,
                            totalAmount: total,
                            paidAmount: paid,
                          );
                          if (ok) {
                            await _loadAllCloudData(silent: true);
                          }
                        },
                        child: const Text('حفظ المصروف في السحابة ☁️', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // 4. تبويب المخزون والأقمشة (Inventory)
  // ==========================================
  Widget _buildInventoryTab() {
    final rate = _toDouble(_settings['fabricPerThobe']) > 0 ? _toDouble(_settings['fabricPerThobe']) : 3.5;

    double totalMeters = 0;
    int lowStockCount = 0;
    for (final item in _inventory) {
      final q = _toDouble(item['quantity']);
      final unit = item['unit']?.toString() ?? 'متر';
      if (unit != 'حبة') totalMeters += q;
      if (q < 20) lowStockCount++;
    }
    final estThobes = (totalMeters / rate).floor();

    return RefreshIndicator(
      onRefresh: () => _loadAllCloudData(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _buildOrderFinanceBox('إجمالي الأمتار', '${totalMeters.toStringAsFixed(1)} م', const Color(0xFF2563EB)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOrderFinanceBox('تكفي لتفصيل', '~$estThobes ثوب', const Color(0xFF059669)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOrderFinanceBox('قارب على النفاد', '$lowStockCount صنف', const Color(0xFFD97706)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._inventory.map((item) {
            final qty = _toDouble(item['quantity']);
            final unit = item['unit']?.toString() ?? 'متر';
            final price = _toDouble(item['price']);
            final isLow = qty < 20;
            final thobes = unit != 'حبة' ? (qty / rate).floor() : null;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isLow ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['type']?.toString() ?? 'قماش',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0A2E4D)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'السعر: ${price.toStringAsFixed(0)} ريال  •  المتبقي: ${qty.toStringAsFixed(1)} $unit',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                        ),
                        if (thobes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '👔 يكفي لتفصيل ~$thobes ثوب',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isLow ? const Color(0xFFB45309) : const Color(0xFF059669),
                              ),
                            ),
                          ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1D4ED8),
                        elevation: 0,
                      ),
                      onPressed: () => _showRestockDialog(item),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('تزويد'),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showRestockDialog(Map<String, dynamic> item) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تزويد مخزون: ${item['type']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'الكمية المضافة (${item['unit'] ?? 'متر'})',
            hintText: 'مثال: 25',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final add = double.tryParse(ctrl.text.trim()) ?? 0;
              if (add <= 0) return;
              Navigator.pop(ctx);
              final ok = await _api.restockInventoryItem(item, add);
              if (ok) {
                await _loadAllCloudData(silent: true);
              }
            },
            child: const Text('تأكيد التزويد'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 5. تبويب التقارير المالية الشاملة (Reports)
  // ==========================================
  Widget _buildReportsTab() {
    final now = DateTime.now();

    bool matchesPeriod(DateTime? d) {
      if (d == null) return false;
      if (_reportPeriod == 'today') return _isSameDay(d, now);
      if (_reportPeriod == 'week') return now.difference(d).inDays <= 7;
      if (_reportPeriod == 'month') return d.year == now.year && d.month == now.month;
      return true; // 'all'
    }

    double cashIn = 0;
    double netIn = 0;
    double instIn = 0;
    int periodOrdersCount = 0;
    int periodThobesCount = 0;

    for (final o in _orders) {
      if (o['status'] == 'ملغي') continue;
      final cDate = _parseAnyDate(o['createdAt']);
      if (matchesPeriod(cDate)) {
        periodOrdersCount++;
        periodThobesCount += _calcOrderThobes(o);
      }

      final history = o['paymentHistory'];
      if (history is List && history.isNotEmpty) {
        for (final p in history) {
          if (p is Map) {
            final pDate = _parseAnyDate(p['date']);
            if (matchesPeriod(pDate)) {
              final amt = _toDouble(p['amount']);
              final m = p['method']?.toString() ?? 'cash';
              if (m == 'cash') {
                cashIn += amt;
              } else if (m == 'network') {
                netIn += amt;
              } else {
                instIn += amt;
              }
            }
          }
        }
      } else if (matchesPeriod(cDate)) {
        if (o['isInstallments'] == true) {
          final v = _toDouble(o['depositInstallment']);
          instIn += v > 0 ? v : _toDouble(o['totalPrice']);
        } else {
          cashIn += _toDouble(o['depositCash']);
          netIn += _toDouble(o['depositNetwork']);
        }
      }
    }

    double expensesOut = 0;
    for (final exp in _expenses) {
      final eDate = _parseAnyDate(exp['date']);
      if (matchesPeriod(eDate)) {
        final t = _toDouble(exp['totalAmount'] ?? exp['amount']);
        final p = exp['paidAmount'] != null ? _toDouble(exp['paidAmount']) : t;
        expensesOut += p;
      }
    }

    final totalRevenue = cashIn + netIn + instIn;
    final netProfit = totalRevenue - expensesOut;
    final netCashInDrawer = cashIn - expensesOut;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // أزرار اختيار الفترة
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'today', label: Text('اليوم')),
            ButtonSegment(value: 'week', label: Text('7 أيام')),
            ButtonSegment(value: 'month', label: Text('هذا الشهر')),
            ButtonSegment(value: 'all', label: Text('الكل')),
          ],
          selected: {_reportPeriod},
          onSelectionChanged: (s) => setState(() => _reportPeriod = s.first),
        ),
        const SizedBox(height: 16),

        _buildReportRowCard('💰 إجمالي المقبوضات الفعلية', '${totalRevenue.toStringAsFixed(0)} ريال', const Color(0xFF059669)),
        _buildReportRowCard('💵 مقبوضات الكاش', '${cashIn.toStringAsFixed(0)} ريال', const Color(0xFF10B981)),
        _buildReportRowCard('💳 مقبوضات الشبكة', '${netIn.toStringAsFixed(0)} ريال', const Color(0xFF0284C7)),
        _buildReportRowCard('🛍️ مقبوضات الأقساط (تابي/تمارا)', '${instIn.toStringAsFixed(0)} ريال', const Color(0xFFD97706)),
        _buildReportRowCard('💸 إجمالي المصروفات المسددة', '${expensesOut.toStringAsFixed(0)} ريال', const Color(0xFFDC2626)),
        const Divider(height: 24),
        _buildReportRowCard('📈 صافي الربح الفعلي للفترة', '${netProfit.toStringAsFixed(0)} ريال', const Color(0xFF0A2E4D)),
        _buildReportRowCard('🗄️ الصافي النقدي في الدرج (الكاش - المصروفات)', '${netCashInDrawer.toStringAsFixed(0)} ريال', const Color(0xFF7C3AED)),
        _buildReportRowCard('✂️ عدد الطلبات والثياب المفصلة', '$periodOrdersCount طلب  •  $periodThobesCount ثوب', const Color(0xFF334155)),
      ],
    );
  }

  Widget _buildReportRowCard(String title, String val, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF334155)),
              ),
            ),
            Text(
              val,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
