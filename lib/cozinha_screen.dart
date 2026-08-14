import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

class CozinhaScreen extends StatelessWidget {
  const CozinhaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Cozinha',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('pedidos')
            .where('status', whereIn: ['Aguardando preparo', 'Em preparo'])
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

          final docs = List<QueryDocumentSnapshot>.from(
            snapshot.data?.docs ?? [],
          );

          docs.sort((a, b) {
            final aTs =
                (a.data() as Map<String, dynamic>)['criadoEm'] as Timestamp?;
            final bTs =
                (b.data() as Map<String, dynamic>)['criadoEm'] as Timestamp?;
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
                  Icon(
                    Icons.coffee_maker_outlined,
                    size: 72,
                    color: Color(0xFFD9D9D9),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum pedido no momento',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Os pedidos pagos aparecem aqui em tempo real',
                    style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildSummaryBar(docs),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _OrderCard(
                      docId: doc.id,
                      data: doc.data() as Map<String, dynamic>,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBar(List<QueryDocumentSnapshot> docs) {
    final aguardando = docs
        .where(
          (d) =>
              (d.data() as Map<String, dynamic>)['status'] ==
              'Aguardando preparo',
        )
        .length;
    final emPreparo = docs
        .where(
          (d) => (d.data() as Map<String, dynamic>)['status'] == 'Em preparo',
        )
        .length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _summaryChip('$aguardando aguardando', const Color(0xFFFF9800)),
          const SizedBox(width: 8),
          _summaryChip('$emPreparo em preparo', const Color(0xFF2196F3)),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _OrderCard({required this.docId, required this.data});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _updating = false;

  Color _statusColor(String status) {
    switch (status) {
      case 'Aguardando preparo':
        return const Color(0xFFFF9800);
      case 'Em preparo':
        return const Color(0xFF2196F3);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _updating = true);
    try {
      final update = <String, dynamic>{'status': newStatus};
      if (newStatus == 'Em preparo')
        update['iniciadoEm'] = FieldValue.serverTimestamp();
      else if (newStatus == 'Pronto')
        update['prontoEm'] = FieldValue.serverTimestamp();
      await db.collection('pedidos').doc(widget.docId).update(update);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao atualizar pedido.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
    final metodo = widget.data['metodoPagamento'] as String? ?? '';
    final shortId = widget.docId
        .substring(0, widget.docId.length.clamp(0, 6))
        .toUpperCase();
    final ts = widget.data['criadoEm'] as Timestamp?;
    final hora = ts != null
        ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pedido #$shortId',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const Spacer(),
                Text(
                  hora,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
                if (metodo.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      metodo,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(status),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...itens.map((item) {
                  final i = item as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5F0E8),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${i['qty']}x',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFC8A96E),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            i['nome'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(color: Color(0xFFEEEEEE), height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total pago',
                      style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                    ),
                    Text(
                      'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFC8A96E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildActionButton(status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String status) {
    if (_updating) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: Color(0xFFC8A96E),
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (status == 'Aguardando preparo') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _updateStatus('Em preparo'),
          icon: const Icon(Icons.coffee_maker_outlined, size: 18),
          label: const Text('Iniciar preparo'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }
    if (status == 'Em preparo') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _updateStatus('Pronto'),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Marcar como pronto'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
