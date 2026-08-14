import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'cardapio_screen.dart';
import 'sacola_screen.dart';
import 'perfil_screen.dart';
import 'cart_controller.dart';
import 'cozinha_screen.dart';

late final FirebaseFirestore db;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'caffeto',
  );
  runApp(const CaffetoApp());
}

class CaffetoApp extends StatelessWidget {
  const CaffetoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caffeto',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC8A96E)),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
              ),
            );
          }
          if (snapshot.hasData) return const _AuthGate();
          return const LoginScreen();
        },
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FutureBuilder<DocumentSnapshot>(
      future: db.collection('usuarios').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
            ),
          );
        }
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final isAdmin = data?['admin'] == true;
        if (isAdmin) return const CozinhaScreen();
        return const HomeScreen();
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _navItems = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Início'),
    (
      icon: Icons.restaurant_menu_outlined,
      activeIcon: Icons.restaurant_menu,
      label: 'Cardápio',
    ),
    (
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag,
      label: 'Sacola',
    ),
    (icon: Icons.person_outline, activeIcon: Icons.person, label: 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _HomePage(),
          CardapioScreen(),
          SacolaScreen(),
          PerfilScreen(),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: CartController.instance,
        builder: (context, _) => _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    final cartCount = CartController.instance.totalItems;
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_navItems.length, (index) {
          final isActive = index == _selectedIndex;
          final isSacola = index == 2;
          final item = _navItems[index];
          return GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isActive ? item.activeIcon : item.icon,
                      color: isActive
                          ? const Color(0xFFC8A96E)
                          : const Color(0xFF9E9E9E),
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isActive
                            ? const Color(0xFFC8A96E)
                            : const Color(0xFF9E9E9E),
                      ),
                    ),
                  ],
                ),
                if (isSacola && cartCount > 0)
                  Positioned(
                    top: 4,
                    right: -8,
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: const BoxDecoration(
                        color: Color(0xFFC8A96E),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          cartCount > 99 ? '99+' : '$cartCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ────────────────────────────────────────────
//  HOME PAGE
// ────────────────────────────────────────────

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final _pageController = PageController(viewportFraction: 0.85);
  final _searchController = TextEditingController();
  Timer? _autoScrollTimer;

  int _currentPage = 0;
  String _searchQuery = '';

  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _featured = [];
  bool _partnersLoaded = false;
  bool _featuredLoaded = false;

  late final StreamSubscription<QuerySnapshot> _partnersSub;
  late final StreamSubscription<QuerySnapshot> _featuredSub;

  @override
  void initState() {
    super.initState();
    CartController.instance.addListener(_onCartChanged);
    _startAutoScroll();

    _partnersSub = db
        .collection('parceiros')
        .orderBy('ordem')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _partners = snap.docs.map((d) => d.data()).toList();
            _partnersLoaded = true;
          });
        });

    _featuredSub = db
        .collection('cardapio')
        .where('disponivel', isEqualTo: true)
        .where('destaque', isEqualTo: true)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _featured = snap.docs.map((d) => d.data()).toList();
            _featuredLoaded = true;
          });
        });
  }

  void _onCartChanged() => setState(() {});

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _partners.isEmpty) return;
      final next = (_currentPage + 1) % _partners.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _searchController.dispose();
    _partnersSub.cancel();
    _featuredSub.cancel();
    CartController.instance.removeListener(_onCartChanged);
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredFeatured {
    if (_searchQuery.isEmpty) return _featured;
    return _featured
        .where(
          (p) => (p['nome'] as String).toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();
  }

  void _addToCart(Map<String, dynamic> product) {
    CartController.instance.addItem({
      'name': product['nome'] as String,
      'price': (product['preco'] as num).toDouble(),
      'imageUrl': product['imagem_url'] as String?,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['nome']} adicionado à sacola!'),
        backgroundColor: const Color(0xFFC8A96E),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(user),
            _buildSearchBar(),
            _buildPartnersSection(),
            _buildFeaturedSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(User? user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset('assets/logo.png', height: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BEM-VINDO',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9E9E9E),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  user?.displayName?.split(' ').first ?? 'Cliente',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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
            hintText: 'O que deseja pedir?',
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

  Widget _buildPartnersSection() {
    if (!_partnersLoaded) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
        ),
      );
    }
    if (_partners.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 12, bottom: 12),
          child: Text(
            'NOSSOS PARCEIROS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _partners.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final partner = _partners[index];
              final colorHex = partner['cor'] as String? ?? 'C8A96E';
              final color = Color(int.parse('FF$colorHex', radix: 16));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.storefront,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              partner['nome'] as String? ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              partner['subtitulo'] as String? ?? '',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_partners.length, (index) {
            final isActive = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 16 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFC8A96E)
                    : const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildFeaturedSection() {
    final products = _filteredFeatured;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 20, bottom: 8),
          child: Row(
            children: [
              const Text(
                'EM DESTAQUE',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: Color(0xFFC8A96E),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!_featuredLoaded)
          const SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
            ),
          )
        else if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: Text(
                'Nenhum produto encontrado',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
              ),
            ),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                final nome = product['nome'] as String;
                final preco = (product['preco'] as num).toDouble();
                final imageUrl = product['imagem_url'] as String?;
                final qty = CartController.instance.qtyOf(nome);

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F0E8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) => const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFC8A96E),
                                      ),
                                    ),
                                    errorWidget: (_, _, _) => const Icon(
                                      Icons.coffee,
                                      color: Color(0xFFC8A96E),
                                      size: 40,
                                    ),
                                  )
                                : const Icon(
                                    Icons.coffee,
                                    color: Color(0xFFC8A96E),
                                    size: 40,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'R\$ ${preco.toStringAsFixed(2).replaceAll('.', ',')}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFC8A96E),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _addToCart(product),
                              child: Container(
                                width: 28,
                                height: 28,
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
                                            fontSize: 11,
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
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
