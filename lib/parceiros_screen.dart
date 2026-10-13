import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

/// Tela de admin: parceiros exibidos no carrossel da tela inicial.
class ParceirosScreen extends StatefulWidget {
  const ParceirosScreen({super.key});

  @override
  State<ParceirosScreen> createState() => _ParceirosScreenState();
}

class _ParceirosScreenState extends State<ParceirosScreen> {
  Future<void> _abrirFormulario({QueryDocumentSnapshot? doc}) async {
    final data = doc?.data() as Map<String, dynamic>?;
    final nomeController = TextEditingController(text: data?['nome'] as String? ?? '');
    final subtituloController =
        TextEditingController(text: data?['subtitulo'] as String? ?? '');
    final corController =
        TextEditingController(text: data?['cor'] as String? ?? 'C8A96E');
    final ordemController =
        TextEditingController(text: (data?['ordem'] as num?)?.toInt().toString() ?? '0');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doc == null ? 'Novo parceiro' : 'Editar parceiro',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subtituloController,
              decoration: const InputDecoration(labelText: 'Subtítulo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: corController,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Cor (hex, sem #)',
                hintText: 'C8A96E',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ordemController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ordem de exibição'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final nome = nomeController.text.trim();
                  if (nome.isEmpty) return;
                  final novoData = {
                    'nome': nome,
                    'subtitulo': subtituloController.text.trim(),
                    'cor': corController.text.trim().isEmpty
                        ? 'C8A96E'
                        : corController.text.trim(),
                    'ordem': int.tryParse(ordemController.text) ?? 0,
                  };
                  if (doc == null) {
                    await db.collection('parceiros').add(novoData);
                  } else {
                    await doc.reference.update(novoData);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8A96E),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('Salvar',
                    style:
                        TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remover(QueryDocumentSnapshot doc) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remover parceiro',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Remover', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar == true) await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A1A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Parceiros',
          style: TextStyle(
              color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800, fontSize: 20),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(),
        backgroundColor: const Color(0xFFC8A96E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('parceiros').orderBy('ordem').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFFC8A96E)));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nenhum parceiro cadastrado ainda.\nToque no + para adicionar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final corHex = data['cor'] as String? ?? 'C8A96E';
              Color cor;
              try {
                cor = Color(int.parse('FF$corHex', radix: 16));
              } catch (_) {
                cor = const Color(0xFFC8A96E);
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['nome'] as String? ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          Text(data['subtitulo'] as String? ?? '',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF9E9E9E))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Color(0xFFC8A96E)),
                      onPressed: () => _abrirFormulario(doc: doc),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFE53935)),
                      onPressed: () => _remover(doc),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
