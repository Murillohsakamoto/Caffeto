import 'package:flutter/material.dart';

class CartController extends ChangeNotifier {
  CartController._();
  static final CartController instance = CartController._();

  final List<Map<String, dynamic>> items = [];

  double get total => items.fold(
        0,
        (sum, item) => sum + (item['price'] as double) * (item['qty'] as int),
      );

  int get totalItems =>
      items.fold(0, (sum, item) => sum + (item['qty'] as int));

  void addItem(Map<String, dynamic> product) {
    final index = items.indexWhere((i) => i['name'] == product['name']);
    if (index >= 0) {
      items[index]['qty']++;
    } else {
      items.add({...product, 'qty': 1});
    }
    notifyListeners();
  }

  void increment(int index) {
    items[index]['qty']++;
    notifyListeners();
  }

  void decrement(int index) {
    if (items[index]['qty'] > 1) {
      items[index]['qty']--;
    } else {
      items.removeAt(index);
    }
    notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }

  /// Restaura o carrinho a partir dos itens gravados num pedido — usado
  /// quando um pagamento é recusado, pra não perder o que o cliente já
  /// tinha montado (o carrinho é esvaziado assim que o pedido é criado,
  /// antes de saber se o pagamento vai dar certo).
  void restaurarItens(List<dynamic> itensPedido) {
    items.clear();
    for (final item in itensPedido) {
      final i = item as Map<String, dynamic>;
      items.add({
        'name': i['nome'],
        'price': (i['preco'] as num).toDouble(),
        'qty': (i['qty'] as num).toInt(),
        'imageUrl': i['imageUrl'],
        if (i['itensCombo'] != null) 'itensCombo': i['itensCombo'],
      });
    }
    notifyListeners();
  }

  bool contains(String name) => items.any((i) => i['name'] == name);

  int qtyOf(String name) {
    final index = items.indexWhere((i) => i['name'] == name);
    return index >= 0 ? items[index]['qty'] as int : 0;
  }
}
