import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'cart_controller.dart';
import 'payment_screen.dart';
import 'main.dart';

class SacolaScreen extends StatefulWidget {
  const SacolaScreen({super.key});

  @override
  State<SacolaScreen> createState() => _SacolaScreenState();
}

class _SacolaScreenState extends State<SacolaScreen> {
  bool _finalizando = false;

  bool _carregandoHorarios = true;
  List<String> _horariosDisponiveis = [];
  String? _horarioEscolhido;
  int _tempoEstimadoMin = 15;

  @override
  void initState() {
    super.initState();
    CartController.instance.addListener(_onCartChanged);
    _carregarHorarios();
  }

  void _onCartChanged() {
    setState(() {});
    _recalcularHorariosDisponiveis();
  }

  @override
  void dispose() {
    CartController.instance.removeListener(_onCartChanged);
    super.dispose();
  }

  final Map<String, num> _tempoPorNome = {};
  final Map<String, String> _categoriaPorNome = {};
  final Map<String, num> _tempoPorCategoria = {};
  List<String> _todosHorarios = [];

  /// Busca o cardápio (pra saber o tempo estimado de cada prato/categoria)
  /// e a grade de horários ativa cadastrada pelo admin.
  Future<void> _carregarHorarios() async {
    setState(() => _carregandoHorarios = true);
    try {
      final cardapioSnap = await db.collection('cardapio').get();
      for (final doc in cardapioSnap.docs) {
        final data = doc.data();
        final nome = data['nome'] as String?;
        if (nome == null) continue;
        _categoriaPorNome[nome] = data['categoria'] as String? ?? '';
        final tempo = data['tempoEstimadoMin'] as num?;
        if (tempo != null) _tempoPorNome[nome] = tempo;
      }

      final categoriasSnap = await db.collection('categorias').get();
      for (final doc in categoriasSnap.docs) {
        final tempo = doc.data()['tempoEstimadoMin'] as num?;
        if (tempo != null) _tempoPorCategoria[doc.id] = tempo;
      }

      final horariosSnap = await db
          .collection('horarios_retirada')
          .where('ativo', isEqualTo: true)
          .orderBy('hora')
          .get();
      _todosHorarios =
          horariosSnap.docs.map((d) => d.data()['hora'] as String).toList();

      _recalcularHorariosDisponiveis();
    } catch (_) {
      if (mounted) {
        setState(() {
          _todosHorarios = [];
          _horariosDisponiveis = [];
        });
      }
    } finally {
      if (mounted) setState(() => _carregandoHorarios = false);
    }
  }

  /// Tempo estimado do pedido = o maior tempo estimado entre os itens da
  /// sacola (prato tem prioridade; senão usa o padrão da categoria; senão
  /// 15min). Usado só pra filtrar horários que a cozinha não alcançaria.
  int _calcularTempoEstimadoPedido() {
    var maior = 15;
    for (final item in CartController.instance.items) {
      final nome = item['name'] as String;
      final categoria = _categoriaPorNome[nome];
      final tempo = _tempoPorNome[nome] ??
          (categoria != null ? _tempoPorCategoria[categoria] : null) ??
          15;
      if (tempo > maior) maior = tempo.toInt();
    }
    return maior;
  }

  void _recalcularHorariosDisponiveis() {
    _tempoEstimadoMin = _calcularTempoEstimadoPedido();
    final limite = DateTime.now().add(Duration(minutes: _tempoEstimadoMin));

    final disponiveis = _todosHorarios.where((hora) {
      final partes = hora.split(':');
      if (partes.length != 2) return false;
      final horaSlot = DateTime(
        limite.year,
        limite.month,
        limite.day,
        int.parse(partes[0]),
        int.parse(partes[1]),
      );
      return !horaSlot.isBefore(limite);
    }).toList();

    setState(() {
      _horariosDisponiveis = disponiveis;
      if (_horarioEscolhido != null &&
          !_horariosDisponiveis.contains(_horarioEscolhido)) {
        _horarioEscolhido = null;
      }
    });
  }

  Future<void> _criarPedidoEPagar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final horario = _horarioEscolhido;
    if (horario == null) return;

    final cart = CartController.instance;
    final total = cart.total;

    setState(() => _finalizando = true);
    try {
      final docRef = await db.collection('pedidos').add({
        'userId': user.uid,
        'itens': cart.items
            .map(
              (i) => {
                'nome': i['name'],
                'preco': i['price'],
                'qty': i['qty'],
                'imageUrl': i['imageUrl'],
              },
            )
            .toList(),
        'total': total,
        'status': 'Aguardando pagamento',
        'horarioRetirada': horario,
        'criadoEm': FieldValue.serverTimestamp(),
      });

      cart.clear();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(orderId: docRef.id, total: total),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao criar pedido. Tente novamente.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _finalizando = false);
    }
  }

  void _confirmarFinalizacao() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirmar pedido',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Total: R\$ ${CartController.instance.total.toStringAsFixed(2).replaceAll('.', ',')}\n'
          'Retirada às $_horarioEscolhido\n\n'
          'Continuar para o pagamento?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF9E9E9E)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _criarPedidoEPagar();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8A96E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Ir para pagamento',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorarioRetirada() {
    if (_carregandoHorarios) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFFC8A96E)),
          ),
        ),
      );
    }

    if (_todosHorarios.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Nenhum horário de retirada cadastrado no momento.',
          style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Retirar às (tempo estimado de preparo: ${_tempoEstimadoMin}min)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          if (_horariosDisponiveis.isEmpty)
            const Text(
              'Nenhum horário disponível hoje. Tente novamente amanhã.',
              style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
            )
          else
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _horariosDisponiveis.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final hora = _horariosDisponiveis[index];
                  final isSelected = _horarioEscolhido == hora;
                  return GestureDetector(
                    onTap: () => setState(() => _horarioEscolhido = hora),
                    child: Container(
                      alignment: Alignment.center,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFC8A96E)
                            : const Color(0xFFF5F0E8),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        hora,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = CartController.instance.items;
    final total = CartController.instance.total;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Sacola',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => CartController.instance.clear(),
              child: const Text(
                'Limpar',
                style: TextStyle(
                  color: Color(0xFFC8A96E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 80,
                    color: Color(0xFFC8A96E),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Sua sacola está vazia',
                    style: TextStyle(fontSize: 16, color: Color(0xFF9E9E9E)),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Adicione produtos para começar',
                    style: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final imageUrl = item['imageUrl'] as String?;
                      final price = (item['price'] as double)
                          .toStringAsFixed(2)
                          .replaceAll('.', ',');

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
                                        size: 32,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.coffee,
                                      color: Color(0xFFC8A96E),
                                      size: 32,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'R\$ $price',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFC8A96E),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      CartController.instance.decrement(index),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFFC8A96E),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.remove,
                                      size: 16,
                                      color: Color(0xFFC8A96E),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Text(
                                    '${item['qty']}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      CartController.instance.increment(index),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFC8A96E),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
                  ),
                  child: Column(
                    children: [
                      _buildHorarioRetirada(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFC8A96E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_finalizando || _horarioEscolhido == null)
                              ? null
                              : _confirmarFinalizacao,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC8A96E),
                            disabledBackgroundColor: const Color(0xFFE0C99A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: _finalizando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Finalizar Pedido',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
