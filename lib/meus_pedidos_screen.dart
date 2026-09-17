import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'payment_screen.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'Entregue':
      return const Color(0xFF4CAF50);
    case 'Pagamento recusado':
      return const Color(0xFFE53935);
    case 'Pronto':
      return const Color(0xFF2196F3);
    default:
      return const Color(0xFFF59300);
  }
}

const _statusRetomaveis = ['Aguardando pagamento', 'Pagamento recusado'];

/// Aba do cliente: histórico e acompanhamento em tempo real dos próprios
/// pedidos. Pedidos ainda não pagos (ou recusados) podem ser retomados
/// tocando no card, o que reabre a tela de pagamento pro mesmo pedido.
class MeusPedidosScreen extends StatelessWidget {
  const MeusPedidosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Meus Pedidos',
          style: TextStyle(
              color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800, fontSize: 22),
        ),
      ),
      body: uid == null
          ? const SizedBox.shrink()
          : StreamBuilder<QuerySnapshot>(
              // Requer índice composto em (userId, criadoEm desc) — o
              // Firebase mostra um link pra criar automaticamente se faltar.
              stream: FirebaseFirestore.instance
                  .collection('pedidos')
                  .where('userId', isEqualTo: uid)
                  .orderBy('criadoEm', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
                  );
                }
                final pedidos = snapshot.data?.docs ?? [];
                if (pedidos.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Você ainda não fez nenhum pedido.',
                        style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pedidos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = pedidos[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final itens = (data['itens'] as List<dynamic>? ?? [])
                        .map((i) => '${i['nome']} x${i['qty']}')
                        .join(', ');
                    final total = (data['total'] as num? ?? 0).toDouble();
                    final status = data['status'] as String? ?? 'Aguardando pagamento';
                    final horarioRetirada = data['horarioRetirada'] as String?;
                    final ts = data['criadoEm'] as Timestamp?;
                    final date = ts != null
                        ? '${ts.toDate().day.toString().padLeft(2, '0')}/${ts.toDate().month.toString().padLeft(2, '0')}/${ts.toDate().year}'
                        : '--';
                    final retomavel = _statusRetomaveis.contains(status);

                    return GestureDetector(
                      onTap: !retomavel
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PaymentScreen(orderId: doc.id, total: total),
                                ),
                              ),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F0E8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '#${doc.id.substring(0, 6).toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _statusColor(status),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(itens,
                                style:
                                    const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
                            const SizedBox(height: 4),
                            Text(
                              horarioRetirada != null
                                  ? 'Retirada às $horarioRetirada'
                                  : 'Retirada imediata',
                              style:
                                  const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                            ),
                            if (retomavel) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'Toque para retomar o pagamento',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFC8A96E)),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(date,
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(0xFF9E9E9E))),
                                Text(
                                  'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFC8A96E),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
