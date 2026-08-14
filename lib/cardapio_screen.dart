import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'cart_controller.dart';
import 'main.dart';

class CardapioScreen extends StatefulWidget {
  const CardapioScreen({super.key});

  @override
  State<CardapioScreen> createState() => _CardapioScreenState();
}

class _CardapioScreenState extends State<CardapioScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;

  List<Map<String, dynamic>> _allItems = [];
  List<String> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    CartController.instance.addListener(_onCartChanged);
    _carregarCardapio();
  }

  void _onCartChanged() => setState(() {});

  @override
  void dispose() {
    _searchController.dispose();
    CartController.instance.removeListener(_onCartChanged);
    super.dispose();
  }

  Future<void> _carregarCardapio() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await db
          .collection('cardapio')
          .where('disponivel', isEqualTo: true)
          .get();

      final items = snap.docs.map((doc) => doc.data()).toList();

      // DEBUG — remover após confirmar imagens
      for (final item in items.take(3)) {
        debugPrint('DEBUG imagem_url [${item['nome']}]: ${item['imagem_url']}');
      }

      final cats = <String>[];
      for (final item in items) {
        final cat = item['categoria'] as String? ?? '';
        if (cat.isNotEmpty && !cats.contains(cat)) cats.add(cat);
      }

      if (mounted) {
        setState(() {
          _allItems = items;
          _categories = cats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar o cardápio.';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _allItems.where((item) {
      final matchSearch =
          _searchQuery.isEmpty ||
          (item['nome'] as String).toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );
      final matchCategory =
          _selectedCategory == null || item['categoria'] == _selectedCategory;
      return matchSearch && matchCategory;
    }).toList();
  }

  void _addToCart(Map<String, dynamic> item) {
    CartController.instance.addItem({
      'name': item['nome'] as String,
      'price': (item['preco'] as num).toDouble(),
      'imageUrl': item['imagem_url'] as String?,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item['nome']} adicionado à sacola!'),
        backgroundColor: const Color(0xFFC8A96E),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Cardápio',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
            )
          : _error != null
          ? _buildError()
          : RefreshIndicator(
              color: const Color(0xFFC8A96E),
              onRefresh: _carregarCardapio,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCategories(),
                  _buildSearchBar(),
                  Expanded(child: _buildItemList()),
                ],
              ),
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.wifi_off_outlined,
            size: 48,
            color: Color(0xFF9E9E9E),
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _carregarCardapio,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8A96E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Tentar novamente',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () =>
                setState(() => _selectedCategory = isSelected ? null : cat),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFC8A96E)
                          : const Color(0xFFF5F0E8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _iconParaCategoria(cat),
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFFC8A96E),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 70,
                    child: Text(
                      cat,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFFC8A96E)
                            : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F0E8),
          borderRadius: BorderRadius.circular(30),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val),
          decoration: InputDecoration(
            hintText: 'Buscar no cardápio...',
            hintStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
                  )
                : const Icon(Icons.search, color: Color(0xFF9E9E9E)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemList() {
    final items = _filteredItems;
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum produto encontrado',
          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final nome = item['nome'] as String;
        final preco = (item['preco'] as num).toDouble();
        final categoria = item['categoria'] as String? ?? '';
        final imagemUrl = item['imagem_url'] as String?;
        final qty = CartController.instance.qtyOf(nome);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0E8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: imagemUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imagemUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFC8A96E),
                          ),
                        ),
                        errorWidget: (_, _, _) => Icon(
                          _iconParaCategoria(categoria),
                          color: const Color(0xFFC8A96E),
                          size: 32,
                        ),
                      )
                    : Icon(
                        _iconParaCategoria(categoria),
                        color: const Color(0xFFC8A96E),
                        size: 32,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      categoria,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'R\$ ${preco.toStringAsFixed(2).replaceAll('.', ',')}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFC8A96E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _addToCart(item),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFC8A96E),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: qty > 0
                            ? Text(
                                '$qty',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconParaCategoria(String categoria) {
    final c = categoria.toLowerCase();
    if (c.contains('cafe') ||
        c.contains('café') ||
        c.contains('cappuc') ||
        c.contains('espresso') ||
        c.contains('latte')) {
      return Icons.coffee;
    } else if (c.contains('gelad') ||
        c.contains('frio') ||
        c.contains('cold') ||
        c.contains('frapp')) {
      return Icons.local_drink;
    } else if (c.contains('suco') ||
        c.contains('bebida') ||
        c.contains('vitamina')) {
      return Icons.emoji_food_beverage;
    } else if (c.contains('sobremesa') ||
        c.contains('bolo') ||
        c.contains('doce') ||
        c.contains('bombon')) {
      return Icons.cake;
    } else if (c.contains('sanduiche') ||
        c.contains('sanduíche') ||
        c.contains('wrap')) {
      return Icons.lunch_dining;
    } else if (c.contains('salgado') || c.contains('padaria')) {
      return Icons.bakery_dining;
    } else if (c.contains('refeic') || c.contains('refeição')) {
      return Icons.restaurant;
    }
    return Icons.fastfood;
  }
}
