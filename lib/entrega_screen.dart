import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'notifications_service.dart';

/// Tela de entrada de quem faz as entregas: só pedidos do tipo "entrega",
/// com o endereço (prédio/andar/sala) em destaque. Só pode marcar como
/// entregue quando o pedido já estiver "Pronto" — antes disso é só
/// acompanhamento (a cozinha ainda está preparando).
class EntregaScreen extends StatelessWidget {
  const EntregaScreen({super.key});

  Future<void> _sair(BuildContext context) async {
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
    if (confirmar == true) {
      await NotificationsService.instance.signOut();
      // authStateChanges em CaffetoApp cuida da navegação de volta ao login
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Entregas',
          style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF1A1A1A)),
            onPressed: () => _sair(context),
          ),
        ],
      ),
      // Requer índice composto em (tipoEntrega, status) — o Firebase mostra
      // um link pra criar automaticamente se faltar.
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('pedidos')
            .where('tipoEntrega', isEqualTo: 'entrega')
            .where('status', whereIn: ['Aguardando preparo', 'Em preparo', 'Pronto'])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Erro ao carregar pedidos.',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
              ),
            );
          }

          final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? []);
          docs.sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['criadoEm'] as Timestamp?;
            final bTs = (b.data() as Map<String, dynamic>)['criadoEm'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return aTs.compareTo(bTs);
          });

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delivery_dining_outlined, size: 72, color: Color(0xFFD9D9D9)),
                  SizedBox(height: 16),
                  Text(
                    'Nenhuma entrega no momento',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _EntregaCard(docId: doc.id, data: doc.data() as Map<String, dynamic>);
            },
          );
        },
      ),
    );
  }
}

class _EntregaCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _EntregaCard({required this.docId, required this.data});

  @override
  State<_EntregaCard> createState() => _EntregaCardState();
}

class _EntregaCardState extends State<_EntregaCard> {
  bool _updating = false;

  Color _statusColor(String status) {
    switch (status) {
      case 'Aguardando preparo':
        return const Color(0xFFFF9800);
      case 'Em preparo':
        return const Color(0xFF2196F3);
      case 'Pronto':
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF9C27B0);
    }
  }

  Future<void> _marcarEntregue() async {
    setState(() => _updating = true);
    try {
      await db.collection('pedidos').doc(widget.docId).update({
        'status': 'Entregue',
        'entregueEm': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao marcar como entregue.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.data['status'] as String? ?? '';
    final itens = (widget.data['itens'] as List<dynamic>?) ?? [];
    final total = (widget.data['total'] as num?)?.toDouble() ?? 0.0;
    final endereco = widget.data['enderecoEntrega'] as Map<String, dynamic>?;
    final shortId = widget.docId.substring(0, widget.docId.length.clamp(0, 6)).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: _statusColor(status), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Pedido #$shortId',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A1A1A))),
                const Spacer(),
                Text(status,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0E8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFFC8A96E), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          endereco != null
                              ? 'Prédio ${endereco['predio']} · ${endereco['andar']}º andar · ${endereco['sala']}'
                              : 'Endereço não informado',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...itens.map((item) {
                  final i = item as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${i['qty']}x ${i['nome']}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
                    ),
                  );
                }),
                const Divider(color: Color(0xFFEEEEEE), height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total pago', style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
                    Text(
                      'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFC8A96E)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_updating)
                  const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Color(0xFFC8A96E), strokeWidth: 2),
                    ),
                  )
                else if (status == 'Pronto')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _marcarEntregue,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Marcar como entregue'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9C27B0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F0E8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Ainda em preparo na cozinha',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9E9E9E)),
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
