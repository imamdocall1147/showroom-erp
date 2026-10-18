import 'package:flutter/material.dart';

/// রিপোর্টে যেসব ফিল্টার থাকতে পারে
enum RFilter {
  dateRange,
  customer,
  supplier,
  product,
  warehouse, // শোরুম/গোডাউন
  brand,
  category,
  paymentMode,
  area,
  account,
  search, // চেসিস/ইঞ্জিন নম্বর
  days,
}

/// তারিখের ডিফল্ট রেঞ্জ
enum RRange { none, today, thisMonth, thisYear }

class ReportDef {
  /// ব্যাকএন্ডে এন্ডপয়েন্ট হবে: GET /report-data/<key>
  final String key;
  final String title;
  final Set<RFilter> filters;

  /// এই ফিল্টারগুলো না দিলে রিপোর্ট চালানো যাবে না
  final Set<RFilter> mustHave;
  final RRange range;
  final int? days;

  const ReportDef(
    this.key,
    this.title, {
    this.filters = const {},
    this.mustHave = const {},
    this.range = RRange.none,
    this.days,
  });
}

class ReportGroup {
  final String title;
  final IconData icon;
  final List<ReportDef> reports;

  const ReportGroup(this.title, this.icon, this.reports);
}

const Set<RFilter> _salesF = {
  RFilter.dateRange,
  RFilter.warehouse,
  RFilter.customer,
  RFilter.product,
  RFilter.brand,
  RFilter.category,
  RFilter.paymentMode,
};

const Set<RFilter> _purchaseF = {
  RFilter.dateRange,
  RFilter.warehouse,
  RFilter.supplier,
  RFilter.product,
  RFilter.brand,
  RFilter.category,
};

const Set<RFilter> _stockF = {
  RFilter.warehouse,
  RFilter.brand,
  RFilter.product,
  RFilter.category,
};

const List<ReportGroup> reportGroups = [
  ReportGroup('Dashboard ও ম্যানেজমেন্ট', Icons.dashboard, [
    ReportDef('daily_business_summary', 'Daily Business Summary',
        filters: {RFilter.dateRange}, range: RRange.today),
    ReportDef('monthly_business_summary', 'Monthly Business Summary',
        filters: {RFilter.dateRange}, range: RRange.thisMonth),
    ReportDef('yearly_business_summary', 'Yearly Business Summary',
        filters: {RFilter.dateRange}, range: RRange.thisYear),
    ReportDef('showroom_performance', 'Showroom-wise Performance Report',
        filters: {RFilter.dateRange, RFilter.warehouse}, range: RRange.thisMonth),
    ReportDef('profit_loss', 'Profit & Loss Report',
        filters: {RFilter.dateRange}, range: RRange.thisMonth),
    ReportDef('cash_bank_position', 'Cash & Bank Position Report'),
    ReportDef('business_growth', 'Business Growth Report',
        filters: {RFilter.dateRange}, range: RRange.thisYear),
  ]),
  ReportGroup('Sales (বিক্রয়)', Icons.point_of_sale, [
    ReportDef('daily_sales', 'Daily Sales Report',
        filters: _salesF, range: RRange.today),
    ReportDef('monthly_sales', 'Monthly Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('showroom_sales', 'Showroom-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('product_sales', 'Product-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('category_sales', 'Category-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('brand_sales', 'Brand-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('salesperson_sales', 'Salesperson-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('customer_sales', 'Customer-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('invoice_sales', 'Invoice-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('sales_return', 'Sales Return Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('discount_report', 'Discount Report',
        filters: _salesF, range: RRange.thisMonth),
    ReportDef('payment_method_sales', 'Payment Method-wise Sales Report',
        filters: _salesF, range: RRange.thisMonth),
  ]),
  ReportGroup('Purchase (ক্রয়)', Icons.shopping_cart, [
    ReportDef('daily_purchase', 'Daily Purchase Report',
        filters: _purchaseF, range: RRange.today),
    ReportDef('monthly_purchase', 'Monthly Purchase Report',
        filters: _purchaseF, range: RRange.thisMonth),
    ReportDef('supplier_purchase', 'Supplier-wise Purchase Report',
        filters: _purchaseF, range: RRange.thisMonth),
    ReportDef('product_purchase', 'Product-wise Purchase Report',
        filters: _purchaseF, range: RRange.thisMonth),
    ReportDef('purchase_return', 'Purchase Return Report',
        filters: _purchaseF, range: RRange.thisMonth),
    ReportDef('purchase_due', 'Purchase Due Report',
        filters: {RFilter.supplier}),
  ]),
  ReportGroup('Stock / Inventory', Icons.inventory_2, [
    ReportDef('current_stock', 'Current Stock Report', filters: _stockF),
    ReportDef('low_stock', 'Low Stock Alert Report', filters: _stockF),
    ReportDef('out_of_stock', 'Out of Stock Report', filters: _stockF),
    ReportDef('stock_valuation', 'Stock Valuation Report', filters: _stockF),
    ReportDef('showroom_stock', 'Showroom-wise Stock Report', filters: _stockF),
    ReportDef('warehouse_stock', 'Warehouse-wise Stock Report', filters: _stockF),
    ReportDef('product_movement', 'Product Movement Report',
        filters: {RFilter.dateRange, RFilter.warehouse, RFilter.product},
        range: RRange.thisMonth),
    ReportDef('stock_in_out', 'Stock In/Out Report',
        filters: {
          RFilter.dateRange,
          RFilter.warehouse,
          RFilter.product,
          RFilter.brand
        },
        range: RRange.thisMonth),
    ReportDef('stock_adjustment', 'Stock Adjustment Report',
        filters: {RFilter.dateRange, RFilter.warehouse},
        range: RRange.thisMonth),
    ReportDef('fast_moving', 'Fast-moving Products Report',
        filters: {RFilter.warehouse, RFilter.brand, RFilter.days}, days: 30),
    ReportDef('slow_moving', 'Slow-moving Products Report',
        filters: {RFilter.warehouse, RFilter.brand, RFilter.days}, days: 60),
    ReportDef('dead_stock', 'Dead Stock Report',
        filters: {RFilter.warehouse, RFilter.brand, RFilter.days}, days: 90),
    ReportDef('serial_stock', 'Serial/Engine/Chassis-wise Stock Report',
        filters: {RFilter.search, RFilter.warehouse, RFilter.brand}),
  ]),
  ReportGroup('Customer ও বাকি', Icons.people, [
    ReportDef('customer_due', 'Customer Due Report',
        filters: {RFilter.customer, RFilter.area}),
    ReportDef('customer_ledger', 'Customer Ledger',
        filters: {RFilter.customer, RFilter.dateRange},
        mustHave: {RFilter.customer},
        range: RRange.thisYear),
    ReportDef('area_due', 'Area-wise Customer Due Report',
        filters: {RFilter.area}),
    ReportDef('customer_payment_history', 'Customer Payment History',
        filters: {RFilter.customer, RFilter.dateRange},
        range: RRange.thisMonth),
    ReportDef('overdue_customers', 'Overdue Customer Report',
        filters: {RFilter.customer, RFilter.days}, days: 30),
    ReportDef('customer_sales_due_summary', 'Customer-wise Sales & Due Summary',
        filters: {RFilter.customer, RFilter.dateRange},
        range: RRange.thisYear),
    ReportDef('advance_orders', 'Advance Order Report',
        filters: {RFilter.customer, RFilter.product, RFilter.dateRange},
        range: RRange.thisYear),
  ]),
  ReportGroup('Accounts ও Finance', Icons.account_balance, [
    ReportDef('daily_cash_book', 'Daily Cash Book',
        filters: {RFilter.dateRange}, range: RRange.today),
    ReportDef('bank_transactions', 'Bank Transaction Report',
        filters: {RFilter.dateRange, RFilter.account},
        range: RRange.thisMonth),
    ReportDef('income_report', 'Income Report',
        filters: {RFilter.dateRange}, range: RRange.thisMonth),
    ReportDef('expense_report', 'Expense Report',
        filters: {RFilter.dateRange, RFilter.category},
        range: RRange.thisMonth),
    ReportDef('expense_by_category', 'Expense Category-wise Report',
        filters: {RFilter.dateRange}, range: RRange.thisMonth),
    ReportDef('receivable', 'Receivable Report',
        filters: {RFilter.customer}),
    ReportDef('payable', 'Payable Report', filters: {RFilter.supplier}),
    ReportDef('cash_flow', 'Cash Flow Report',
        filters: {RFilter.dateRange}, range: RRange.thisMonth),
    ReportDef('bank_balance', 'Bank-wise Balance Report'),
  ]),
];