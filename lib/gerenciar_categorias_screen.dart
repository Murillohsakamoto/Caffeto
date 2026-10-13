import 'package:flutter/material.dart';
import 'main.dart';

/// Tela de admin: criar, renomear e excluir categorias do cardápio.
/// Categoria também pode "existir" implicitamente só por estar escrita no
/// campo `categoria` de algum produto — essa tela junta as duas fontes
/// (coleção `categorias` + valores usados em `cardapio`) pra mostrar a
/// lista completa.
class GerenciarCategoriasScreen extends StatefulWidget {
  const GerenciarCategoriasScreen({super.key});

  @override
  State<GerenciarCategoriasScreen> createState() =>
      _GerenciarCategoriasScreenState();
}

class _GerenciarCategoriasScreenState
    extends State<GerenciarCategoriasScreen> {
  bool _loading = true;
  String? _error;

  // nome -> quantidade de produtos
  final Map<String, int> _qtdProdutosPorCategoria = {};
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
      final resultados = await Future.wait([
        db.collection('cardapio').get(),
        db.collection('categorias').get(),
      ]);
      final cardapioSnap = resultados[0];
      final categoriasSnap = resultados[1];

      _qtdProdutosPorCategoria.clear();
      _tempoPorCategoria.clear();

      for (final doc in categoriasSnap.docs) {
        _qtdProdutosPorCategoria.putIfAbsent(doc.id, () => 0);
        final tempo = doc.data()['tempoEstimadoMin'] as num?;
        if (tempo != null) _tempoPorCategoria[doc.id] = tempo;
      }
      for (final doc in cardapioSnap.docs) {
        final categoria = doc.data()['categoria'] as String?;
        if (categoria == null || categoria.isEmpty) continue;
        _qtdProdutosPorCategoria[categoria] =
            (_qtdProdutosPorCategoria[categoria] ?? 0) + 1;
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar as categorias.';
        });
      }
    }
  }

  Future<String?> _pedirNome({String titulo = 'Nova categoria', String inicial = ''}) {
    final controller = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome da categoria'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            onPressed: () {
              final nome = controller.text.trim();
              if (nome.isEmpty) return;
              Navigator.pop(ctx, nome);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8A96E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _adicionarCategoria() async {
    final nome = await _pedirNome();
    if (nome == null) return;
    if (_qtdProdutosPorCategoria.containsKey(nome)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A categoria "$nome" já existe.')),
        );
      }
      return;
    }
    try {
      await db.collection('categorias').doc(nome).set({'nome': nome});
      _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar categoria: $e')),
        );
      }
    }
  }

  Future<void> _renomearCategoria(String nomeAtual) async {
    final novoNome = await _pedirNome(titulo: 'Renomear categoria', inicial: nomeAtual);
    if (novoNome == null || novoNome == nomeAtual) return;
    if (_qtdProdutosPorCategoria.containsKey(novoNome)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Já existe uma categoria "$novoNome".')),
        );
      }
      return;
    }

    try {
      final produtosDaCategoria = await db
          .collection('cardapio')
          .where('categoria', isEqualTo: nomeAtual)
          .get();

      final batch = db.batch();
      for (final doc in produtosDaCategoria.docs) {
        batch.update(doc.reference, {'categoria': novoNome});
      }

      final categoriaAntigaRef = db.collection('categorias').doc(nomeAtual);
      final categoriaAntigaSnap = await categoriaAntigaRef.get();
      final tempoAtual = categoriaAntigaSnap.data()?['tempoEstimadoMin'] as num?;
      final novaCategoriaData = <String, dynamic>{'nome': novoNome};
      if (tempoAtual != null) novaCategoriaData['tempoEstimadoMin'] = tempoAtual;
      batch.set(db.collection('categorias').doc(novoNome), novaCategoriaData);
      if (categoriaAntigaSnap.exists) batch.delete(categoriaAntigaRef);

      await batch.commit();
      _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao renomear: $e')),
        );
      }
    }
  }

  Future<void> _excluirCategoria(String nome) async {
    final qtd = _qtdProdutosPorCategoria[nome] ?? 0;
    if (qtd > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Essa categoria tem $qtd produto(s). Mova ou exclua eles antes de remover a categoria.',
          ),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir categoria', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Remover a categoria "$nome"?'),
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
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await db.collection('categorias').doc(nome).delete();
      _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categorias = _qtdProdutosPorCategoria.keys.toList()..sort();

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
          'Categorias',
          style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800, fontSize: 20),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _adicionarCategoria,
        backgroundColor: const Color(0xFFC8A96E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFC8A96E)))
          : _error != null
              ? Center(
                  child: Text(_error!, style: const TextStyle(color: Color(0xFF9E9E9E))))
              : categorias.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nenhuma categoria ainda.\nToque no + para adicionar a primeira.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFFC8A96E),
                      onRefresh: _carregar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: categorias.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final nome = categorias[index];
                          final qtd = _qtdProdutosPorCategoria[nome] ?? 0;
                          final tempo = _tempoPorCategoria[nome];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F0E8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(nome,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              subtitle: Text(
                                '$qtd produto(s)${tempo != null ? ' · padrão ${tempo.toInt()}min' : ''}',
                                style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Color(0xFFC8A96E)),
                                    onPressed: () => _renomearCategoria(nome),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Color(0xFFE53935)),
                                    onPressed: () => _excluirCategoria(nome),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
