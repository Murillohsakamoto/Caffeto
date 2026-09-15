import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'cozinha_screen.dart';
import 'gerenciar_cardapio_screen.dart';
import 'horarios_retirada_screen.dart';
import 'parceiros_screen.dart';

const _statusPagos = ['Aguardando preparo', 'Em preparo', 'Pronto', 'Entregue'];

/// Tela de entrada do admin: resumo do dia (pedidos, faturamento, mais
/// vendidos) e atalhos de gestão (cardápio, horários, parceiros, cozinha).
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Future<void> _sair() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sair', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Tem certeza que deseja sair da conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar == true) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final inicioDeHoje = DateTime.now();
    final meiaNoite =
        DateTime(inicioDeHoje.year, inicioDeHoje.month, inicioDeHoje.day);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Painel',
          style: TextStyle(
              color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF9E9E9E)),
            onPressed: _sair,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFC8A96E),
        onRefresh: () async => setState(() {}),
        child: StreamBuilder<QuerySnapshot>(
          stream: db
              .collection('pedidos')
              .where('criadoEm', isGreaterThanOrEqualTo: Timestamp.fromDate(meiaNoite))
              .snapshots(),
          builder: (context, snapshot) {
            final pedidosPagosHoje = (snapshot.data?.docs ?? [])
                .where((d) =>
                    _statusPagos.contains((d.data() as Map)['status'] as String?))
                .toList();

            final faturamento = pedidosPagosHoje.fold<double>(
                0, (soma, d) => soma + ((d.data() as Map)['total'] as num? ?? 0));

            final contagemItens = <String, int>{};
            for (final d in pedidosPagosHoje) {
              final itens = (d.data() as Map)['itens'] as List<dynamic>? ?? [];
              for (final item in itens) {
                final nome = item['nome'] as String? ?? '?';
                final qty = (item['qty'] as num?)?.toInt() ?? 0;
                contagemItens[nome] = (contagemItens[nome] ?? 0) + qty;
              }
            }
            final maisVendidos = contagemItens.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        icon: Icons.receipt_long_outlined,
                        label: 'Pedidos hoje',
                        value: snapshot.connectionState == ConnectionState.waiting
                            ? '—'
                            : '${pedidosPagosHoje.length}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                        icon: Icons.payments_outlined,
                        label: 'Faturamento hoje',
                        value: snapshot.connectionState == ConnectionState.waiting
                            ? '—'
                            : 'R\$ ${faturamento.toStringAsFixed(2).replaceAll('.', ',')}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mais vendidos hoje',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFC8A96E), strokeWidth: 2),
                          ),
                        )
                      else if (maisVendidos.isEmpty)
                        const Text('Nenhum pedido pago ainda hoje.',
                            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13))
                      else
                        ...maisVendidos.take(5).map(
                              (e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(e.key,
                                          style: const TextStyle(fontSize: 13)),
                                    ),
                                    Text('${e.value}x',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFC8A96E))),
                                  ],
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'GESTÃO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF9E9E9E),
                      letterSpacing: 1,
                    ),
                  ),
                ),
                _menuTile(
                  icon: Icons.soup_kitchen_outlined,
                  title: 'Fila da cozinha',
                  subtitle: 'Acompanhar pedidos em preparo',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const CozinhaScreen())),
                ),
                _menuTile(
                  icon: Icons.restaurant_menu_outlined,
                  title: 'Cardápio',
                  subtitle: 'Cadastrar, editar e excluir produtos',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GerenciarCardapioScreen())),
                ),
                _menuTile(
                  icon: Icons.schedule_outlined,
                  title: 'Horários de retirada',
                  subtitle: 'Grade de horários disponíveis',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const HorariosRetiradaScreen())),
                ),
                _menuTile(
                  icon: Icons.handshake_outlined,
                  title: 'Parceiros',
                  subtitle: 'Carrossel da tela inicial',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ParceirosScreen())),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFC8A96E), size: 22),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
        ],
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFFF5F0E8),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFFC8A96E), size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFFBBBBBB)),
      ),
    );
  }
}
