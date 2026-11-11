import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';
import 'ordem_cardapio.dart';

/// Tela de admin: cadastro de produtos (criar/editar/excluir) e tempo
/// estimado de preparo por categoria (padrão) e por prato (sobrescreve o
/// da categoria). O tempo estimado é usado na sacola pra filtrar horários
/// de retirada inalcançáveis.
///
/// Dentro de cada categoria os produtos podem ser reordenados segurando e
/// arrastando (alça ≡). A ordem fica no campo `ordem` de cada produto e é a
/// mesma que o cliente vê no cardápio. A ordem das categorias é definida na
/// tela Categorias.
class GerenciarCardapioScreen extends StatefulWidget {
  const GerenciarCardapioScreen({super.key});

  @override
  State<GerenciarCardapioScreen> createState() =>
      _GerenciarCardapioScreenState();
}

class _GerenciarCardapioScreenState extends State<GerenciarCardapioScreen> {
  bool _loading = true;
  String? _error;

  // categoria -> [itens], já na ordem de exibição
  final Map<String, List<QueryDocumentSnapshot>> _porCategoria = {};
  List<String> _ordemCategorias = [];
  bool _salvandoOrdem = false;
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
      for (final lista in _porCategoria.values) {
        lista.sort((a, b) => compararProdutos(
            a.data() as Map<String, dynamic>, b.data() as Map<String, dynamic>));
      }

      final categoriasSnap = await db.collection('categorias').get();
      _tempoPorCategoria.clear();
      final ordemSalva = <String, num>{};
      for (final doc in categoriasSnap.docs) {
        final tempo = doc.data()['tempoEstimadoMin'] as num?;
        if (tempo != null) _tempoPorCategoria[doc.id] = tempo;
        final ordem = doc.data()['ordem'] as num?;
        if (ordem != null) ordemSalva[doc.id] = ordem;
      }
      _ordemCategorias = ordenarCategorias(_porCategoria.keys, ordemSalva);

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

    try {
      await db.collection('categorias').doc(categoria).set({
        'nome': categoria,
        'tempoEstimadoMin': novo,
      }, SetOptions(merge: true)); // merge: não apaga a `ordem` da categoria
      if (mounted) setState(() => _tempoPorCategoria[categoria] = novo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    }
  }

  Future<void> _reordenarProdutos(String categoria, int de, int para) async {
    if (para > de) para -= 1; // convenção do ReorderableListView
    if (de == para) return;
    final itens = _porCategoria[categoria]!;
    final anterior = List<QueryDocumentSnapshot>.from(itens);
    setState(() {
      final item = itens.removeAt(de);
      itens.insert(para, item);
      _salvandoOrdem = true;
    });
    try {
      final batch = db.batch();
      for (var i = 0; i < itens.length; i++) {
        batch.update(itens[i].reference, {'ordem': i});
      }
      await batch.commit();
    } catch (e) {
      if (mounted) {
        setState(() => _porCategoria[categoria] = anterior);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar a ordem: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoOrdem = false);
    }
  }

  /// Escolhe uma foto da galeria/câmera e envia pela Cloud Function
  /// salvarFotoProduto (só admin). Devolve a URL pública ou null.
  Future<String?> _enviarFoto(ImageSource origem) async {
    final foto = await ImagePicker().pickImage(
      source: origem,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 80,
    );
    if (foto == null) return null;
    final bytes = await foto.readAsBytes();
    final nome = foto.name.toLowerCase();
    final contentType = nome.endsWith('.png')
        ? 'image/png'
        : nome.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    final resultado = await FirebaseFunctions.instanceFor(
            region: 'southamerica-east1')
        .httpsCallable('salvarFotoProduto')
        .call({'imagemBase64': base64Encode(bytes), 'contentType': contentType});
    return (resultado.data as Map)['url'] as String?;
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
    String? imagemUrl = data?['imagem_url'] as String?;
    var enviandoFoto = false;
    final categoriaOriginal = data?['categoria'] as String?;
    var destaque = data?['destaque'] as bool? ?? false;
    var isCombo = data?['combo'] as bool? ?? false;
    final itensCombo = ((data?['itensCombo'] as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Lista plana de produtos existentes pra montar o combo (exclui outros
    // combos e, ao editar, o próprio item — não faz sentido um combo se
    // conter ou conter outro combo).
    final produtosDisponiveis = _porCategoria.values
        .expand((lista) => lista)
        .where((d) => d.id != item?.id && (d.data() as Map)['combo'] != true)
        .toList();

    Future<void> adicionarItemAoCombo(StateSetter setSheetState) async {
      final escolhido = await showDialog<QueryDocumentSnapshot>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Adicionar item', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: produtosDisponiveis.length,
              itemBuilder: (_, i) {
                final p = produtosDisponiveis[i].data() as Map<String, dynamic>;
                return ListTile(
                  title: Text(p['nome'] as String? ?? ''),
                  onTap: () => Navigator.pop(ctx, produtosDisponiveis[i]),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9E9E9E))),
            ),
          ],
        ),
      );
      if (escolhido == null) return;
      final nomeEscolhido = (escolhido.data() as Map)['nome'] as String;
      setSheetState(() {
        final existente = itensCombo.indexWhere((e) => e['nome'] == nomeEscolhido);
        if (existente >= 0) {
          itensCombo[existente]['qty'] = (itensCombo[existente]['qty'] as num) + 1;
        } else {
          itensCombo.add({'nome': nomeEscolhido, 'qty': 1});
        }
      });
    }

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
                const SizedBox(height: 16),
                // Foto do produto (aparece no cardápio e na home do cliente)
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 84,
                        height: 84,
                        color: const Color(0xFFF5F0E8),
                        child: enviandoFoto
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Color(0xFFC8A96E)),
                                ),
                              )
                            : imagemUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imagemUrl!, fit: BoxFit.cover)
                                : const Icon(Icons.photo_outlined,
                                    size: 32, color: Color(0xFFC8A96E)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton.icon(
                            onPressed: enviandoFoto
                                ? null
                                : () async {
                                    final origem = await showModalBottomSheet<ImageSource>(
                                      context: ctx,
                                      builder: (c) => SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: const Icon(Icons.photo_library_outlined),
                                              title: const Text('Escolher da galeria'),
                                              onTap: () => Navigator.pop(c, ImageSource.gallery),
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.photo_camera_outlined),
                                              title: const Text('Tirar foto'),
                                              onTap: () => Navigator.pop(c, ImageSource.camera),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    if (origem == null) return;
                                    setSheetState(() => enviandoFoto = true);
                                    try {
                                      final url = await _enviarFoto(origem);
                                      if (url != null) {
                                        setSheetState(() => imagemUrl = url);
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Não foi possível enviar a foto. Tente de novo.')),
                                        );
                                      }
                                    } finally {
                                      if (ctx.mounted) {
                                        setSheetState(() => enviandoFoto = false);
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.add_a_photo_outlined,
                                size: 18, color: Color(0xFFC8A96E)),
                            label: Text(
                              imagemUrl == null ? 'Adicionar foto' : 'Trocar foto',
                              style: const TextStyle(
                                  color: Color(0xFFC8A96E), fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (imagemUrl != null && !enviandoFoto)
                            TextButton.icon(
                              onPressed: () => setSheetState(() => imagemUrl = null),
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Color(0xFFE53935)),
                              label: const Text('Remover foto',
                                  style: TextStyle(color: Color(0xFFE53935))),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Em destaque na home'),
                  subtitle: const Text('Aparece na seção "Em destaque" da tela inicial'),
                  value: destaque,
                  activeThumbColor: const Color(0xFFC8A96E),
                  onChanged: (v) => setSheetState(() => destaque = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('É um combo'),
                  subtitle: const Text('Reúne outros produtos já cadastrados por um preço fixo'),
                  value: isCombo,
                  activeThumbColor: const Color(0xFFC8A96E),
                  onChanged: (v) => setSheetState(() => isCombo = v),
                ),
                if (isCombo) ...[
                  const SizedBox(height: 8),
                  ...itensCombo.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text('${e['qty']}x ${e['nome']}')),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Color(0xFFE53935)),
                              onPressed: () =>
                                  setSheetState(() => itensCombo.remove(e)),
                            ),
                          ],
                        ),
                      )),
                  TextButton.icon(
                    onPressed: produtosDisponiveis.isEmpty
                        ? null
                        : () => adicionarItemAoCombo(setSheetState),
                    icon: const Icon(Icons.add, size: 18, color: Color(0xFFC8A96E)),
                    label: const Text('Adicionar item ao combo',
                        style: TextStyle(color: Color(0xFFC8A96E), fontWeight: FontWeight.w600)),
                  ),
                ],
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
                      if (enviandoFoto) return; // espera a foto terminar de subir
                      if (isCombo && itensCombo.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Adicione ao menos um item ao combo.')),
                        );
                        return;
                      }

                      final tempo = int.tryParse(tempoController.text.trim());

                      final novoData = <String, dynamic>{
                        'nome': nome,
                        'preco': preco,
                        'categoria': categoria,
                        'disponivel': disponivel,
                        'destaque': destaque,
                        'combo': isCombo,
                      };
                      if (tempo != null) {
                        novoData['tempoEstimadoMin'] = tempo;
                      }
                      if (isCombo) {
                        novoData['itensCombo'] = itensCombo;
                      }
                      if (imagemUrl != null) novoData['imagem_url'] = imagemUrl;
                      // Produto novo, ou que mudou de categoria, entra no fim
                      // da lista da categoria de destino.
                      if (item == null || categoria != categoriaOriginal) {
                        novoData['ordem'] = _porCategoria[categoria]?.length ?? 0;
                      }

                      try {
                        if (item == null) {
                          await db.collection('cardapio').add(novoData);
                        } else {
                          if (tempo == null) {
                            novoData['tempoEstimadoMin'] = FieldValue.delete();
                          }
                          if (!isCombo) {
                            novoData['itensCombo'] = FieldValue.delete();
                          }
                          if (imagemUrl == null) {
                            novoData['imagem_url'] = FieldValue.delete();
                          }
                          await item.reference.update(novoData);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _carregar();
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Erro ao salvar: $e')),
                          );
                        }
                      }
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
      try {
        await item.reference.delete();
        _carregar();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir: $e')),
          );
        }
      }
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
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12, left: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.drag_indicator,
                                    size: 16, color: Color(0xFF9E9E9E)),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Abra a categoria e segure ≡ para arrastar os produtos. A ordem das categorias fica em Categorias.',
                                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                                  ),
                                ),
                                if (_salvandoOrdem)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Color(0xFFC8A96E)),
                                  ),
                              ],
                            ),
                          ),
                          ..._ordemCategorias.map((categoria) {
                          final itens = _porCategoria[categoria]!;
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
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: itens.length,
                                  onReorder: (de, para) =>
                                      _reordenarProdutos(categoria, de, para),
                                  itemBuilder: (context, index) {
                                  final item = itens[index];
                                  final data = item.data() as Map<String, dynamic>;
                                  final nome = data['nome'] as String? ?? '';
                                  final preco = (data['preco'] as num?)?.toDouble() ?? 0;
                                  final disponivel = data['disponivel'] as bool? ?? true;
                                  final destaque = data['destaque'] as bool? ?? false;
                                  final combo = data['combo'] as bool? ?? false;
                                  final override = data['tempoEstimadoMin'] as num?;
                                  return ReorderableDelayedDragStartListener(
                                    key: ValueKey('prod-${item.id}'),
                                    index: index,
                                    child: ListTile(
                                    leading: ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(Icons.drag_indicator,
                                          color: Color(0xFFC8A96E)),
                                    ),
                                    title: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(nome,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: disponivel
                                                    ? const Color(0xFF1A1A1A)
                                                    : const Color(0xFFBBBBBB),
                                                decoration: disponivel
                                                    ? null
                                                    : TextDecoration.lineThrough,
                                              )),
                                        ),
                                        if (destaque) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.star,
                                              size: 14, color: Color(0xFFC8A96E)),
                                        ],
                                        if (combo) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.inventory_2_outlined,
                                              size: 14, color: Color(0xFFC8A96E)),
                                        ],
                                      ],
                                    ),
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
                                    ),
                                  );
                                  },
                                ),
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
                          }),
                        ],
                      ),
                    ),
    );
  }
}
