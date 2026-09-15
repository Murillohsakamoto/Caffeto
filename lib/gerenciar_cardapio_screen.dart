import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

/// Tela de admin: cadastro de produtos (criar/editar/excluir) e tempo
/// estimado de preparo por categoria (padrão) e por prato (sobrescreve o
/// da categoria). O tempo estimado é usado na sacola pra filtrar horários
/// de retirada inalcançáveis.
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
    final controller =
        TextEditingController(text: atual?.toInt().toString() ?? '');

    final novo = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Tempo estimado — $categoria',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Minutos', suffixText: 'min'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = int.tryParse(controller.text);
              if (valor == null || valor <= 0) return;
              Navigator.pop(ctx, valor);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8A96E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Salvar',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (novo == null) return;

    await db.collection('categorias').doc(categoria).set({
      'nome': categoria,
      'tempoEstimadoMin': novo,
    });

    if (mounted) setState(() => _tempoPorCategoria[categoria] = novo);
  }

  Future<void> _abrirFormularioItem({
    QueryDocumentSnapshot? item,
    String? categoriaPadrao,
  }) async {
    final data = item?.data() as Map<String, dynamic>?;
    final nomeController = TextEditingController(text: data?['nome'] as String? ?? '');
    final precoController = TextEditingController(
        text: (data?['preco'] as num?)?.toString() ?? '');
    final categoriaController =
        TextEditingController(text: data?['categoria'] as String? ?? categoriaPadrao ?? '');
    final tempoController = TextEditingController(
        text: (data?['tempoEstimadoMin'] as num?)?.toInt().toString() ?? '');
    var disponivel = data?['disponivel'] as bool? ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item == null ? 'Novo produto' : 'Editar produto',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nomeController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: precoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preço', prefixText: 'R\$ '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoriaController,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tempo estimado (opcional)',
                    suffixText: 'min',
                    helperText: 'Vazio = usa o padrão da categoria',
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Disponível no cardápio'),
                  value: disponivel,
                  activeThumbColor: const Color(0xFFC8A96E),
                  onChanged: (v) => setSheetState(() => disponivel = v),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final nome = nomeController.text.trim();
                      final preco = double.tryParse(
                          precoController.text.trim().replaceAll(',', '.'));
                      final categoria = categoriaController.text.trim();
                      if (nome.isEmpty || preco == null || categoria.isEmpty) return;

                      final tempo = int.tryParse(tempoController.text.trim());

                      final novoData = <String, dynamic>{
                        'nome': nome,
                        'preco': preco,
                        'categoria': categoria,
                        'disponivel': disponivel,
                      };
                      if (tempo != null) {
                        novoData['tempoEstimadoMin'] = tempo;
                      }

                      if (item == null) {
                        await db.collection('cardapio').add(novoData);
                      } else {
                        if (tempo == null) {
                          novoData['tempoEstimadoMin'] = FieldValue.delete();
                        }
                        await item.reference.update(novoData);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _carregar();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC8A96E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
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
        ),
      ),
    );
  }

  Future<void> _excluirItem(QueryDocumentSnapshot item) async {
    final nome = (item.data() as Map<String, dynamic>)['nome'] as String? ?? '';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir produto',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Remover "$nome" do cardápio? Essa ação não pode ser desfeita.'),
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
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await item.reference.delete();
      _carregar();
    }
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
          'Cardápio',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormularioItem(),
        backgroundColor: const Color(0xFFC8A96E),
        child: const Icon(Icons.add, color: Colors.white),
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
              : _porCategoria.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nenhum produto cadastrado ainda.\nToque no + para adicionar o primeiro.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFFC8A96E),
                      onRefresh: _carregar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
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
                                style: const TextStyle(
                                    color: Color(0xFF9E9E9E), fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.schedule,
                                    color: Color(0xFFC8A96E)),
                                onPressed: () => _editarTempoCategoria(categoria),
                              ),
                              children: [
                                ...itens.map((item) {
                                  final data = item.data() as Map<String, dynamic>;
                                  final nome = data['nome'] as String? ?? '';
                                  final preco = (data['preco'] as num?)?.toDouble() ?? 0;
                                  final disponivel = data['disponivel'] as bool? ?? true;
                                  final override = data['tempoEstimadoMin'] as num?;
                                  return ListTile(
                                    title: Text(nome,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: disponivel
                                              ? const Color(0xFF1A1A1A)
                                              : const Color(0xFFBBBBBB),
                                          decoration: disponivel
                                              ? null
                                              : TextDecoration.lineThrough,
                                        )),
                                    subtitle: Text(
                                      'R\$ ${preco.toStringAsFixed(2).replaceAll('.', ',')} · ${override != null ? '${override.toInt()}min próprio' : 'tempo padrão'}${disponivel ? '' : ' · indisponível'}',
                                      style: const TextStyle(
                                          fontSize: 11, color: Color(0xFF9E9E9E)),
                                    ),
                                    onTap: () => _abrirFormularioItem(item: item),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Color(0xFFE53935)),
                                      onPressed: () => _excluirItem(item),
                                    ),
                                  );
                                }),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 16, right: 16, bottom: 12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => _abrirFormularioItem(
                                          categoriaPadrao: categoria),
                                      icon: const Icon(Icons.add,
                                          size: 18, color: Color(0xFFC8A96E)),
                                      label: Text(
                                        'Adicionar em "$categoria"',
                                        style: const TextStyle(
                                            color: Color(0xFFC8A96E),
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
    );
  }
}
