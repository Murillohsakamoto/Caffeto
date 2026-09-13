import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

/// Tela de admin: tempo estimado de preparo por categoria (padrão) e,
/// opcionalmente, por prato específico (sobrescreve o da categoria).
/// Usado na sacola pra filtrar horários de retirada inalcançáveis.
class GerenciarCardapioScreen extends StatefulWidget {
  const GerenciarCardapioScreen({super.key});

  @override
  State<GerenciarCardapioScreen> createState() =>
      _GerenciarCardapioScreenState();
}

class _GerenciarCardapioScreenState extends State<GerenciarCardapioScreen> {
  bool _loading = true;
  String? _error;

  // categoria -> [itens]
  final Map<String, List<QueryDocumentSnapshot>> _porCategoria = {};
  final Map<String, num> _tempoPorCategoria = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cardapioSnap = await db.collection('cardapio').get();
      _porCategoria.clear();
      for (final doc in cardapioSnap.docs) {
        final categoria = (doc.data())['categoria'] as String? ?? 'Outros';
        _porCategoria.putIfAbsent(categoria, () => []).add(doc);
      }

      final categoriasSnap = await db.collection('categorias').get();
      _tempoPorCategoria.clear();
      for (final doc in categoriasSnap.docs) {
        final tempo = doc.data()['tempoEstimadoMin'] as num?;
        if (tempo != null) _tempoPorCategoria[doc.id] = tempo;
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar o cardápio.';
        });
      }
    }
  }

  Future<void> _editarTempoCategoria(String categoria) async {
    final atual = _tempoPorCategoria[categoria];
    final novo = await _mostrarDialogoTempo(
      titulo: 'Tempo estimado — $categoria',
      valorAtual: atual,
      permitirPadrao: false,
    );
    if (novo == null) return;

    await db.collection('categorias').doc(categoria).set({
      'nome': categoria,
      'tempoEstimadoMin': novo,
    });

    if (mounted) {
      setState(() => _tempoPorCategoria[categoria] = novo);
    }
  }

  Future<void> _editarTempoItem(QueryDocumentSnapshot item) async {
    final data = item.data() as Map<String, dynamic>;
    final atual = data['tempoEstimadoMin'] as num?;

    final novo = await _mostrarDialogoTempo(
      titulo: 'Tempo estimado — ${data['nome']}',
      valorAtual: atual,
      permitirPadrao: true,
    );
    if (novo == null) return;

    if (novo < 0) {
      // sentinela: "usar padrão da categoria" -> remove o override
      await db
          .collection('cardapio')
          .doc(item.id)
          .update({'tempoEstimadoMin': FieldValue.delete()});
    } else {
      await db
          .collection('cardapio')
          .doc(item.id)
          .update({'tempoEstimadoMin': novo});
    }
    _carregar();
  }

  Future<num?> _mostrarDialogoTempo({
    required String titulo,
    required num? valorAtual,
    required bool permitirPadrao,
  }) async {
    final controller =
        TextEditingController(text: valorAtual?.toInt().toString() ?? '');

    return showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Minutos',
            suffixText: 'min',
          ),
        ),
        actions: [
          if (permitirPadrao)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text(
                'Usar padrão da categoria',
                style: TextStyle(color: Color(0xFF9E9E9E)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = int.tryParse(controller.text);
              if (valor == null || valor <= 0) return;
              Navigator.pop(ctx, valor);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8A96E),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Salvar',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: Color(0xFF1A1A1A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Tempo estimado de preparo',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
            )
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFF9E9E9E))),
                )
              : RefreshIndicator(
                  color: const Color(0xFFC8A96E),
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _porCategoria.entries.map((entry) {
                      final categoria = entry.key;
                      final itens = entry.value;
                      final tempoCategoria = _tempoPorCategoria[categoria];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: const Color(0xFFF5F0E8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: ExpansionTile(
                          shape: const RoundedRectangleBorder(
                              side: BorderSide.none),
                          title: Text(categoria,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          subtitle: Text(
                            tempoCategoria != null
                                ? 'Padrão: ${tempoCategoria.toInt()}min'
                                : 'Padrão: não definido (15min)',
                            style:
                                const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                color: Color(0xFFC8A96E)),
                            onPressed: () => _editarTempoCategoria(categoria),
                          ),
                          children: itens.map((item) {
                            final data = item.data() as Map<String, dynamic>;
                            final nome = data['nome'] as String? ?? '';
                            final override =
                                data['tempoEstimadoMin'] as num?;
                            return ListTile(
                              title: Text(nome,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                override != null
                                    ? '${override.toInt()}min (próprio)'
                                    : 'Usa o padrão da categoria',
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF9E9E9E)),
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  color: Color(0xFFBBBBBB)),
                              onTap: () => _editarTempoItem(item),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}
