import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
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

    try {
      await db.collection('categorias').doc(categoria).set({
        'nome': categoria,
        'tempoEstimadoMin': novo,
      });
      if (mounted) setState(() => _tempoPorCategoria[categoria] = novo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    }
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
    var destaque = data?['destaque'] as bool? ?? false;
    var isCombo = data?['combo'] as bool? ?? false;
    final itensCombo = ((data?['itensCombo'] as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    String? imagemUrlAtual = data?['imagem_url'] as String?;
    XFile? imagemEscolhida;

    Future<void> escolherImagem(StateSetter setSheetState) async {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (image == null) return;
      setSheetState(() => imagemEscolhida = image);
    }

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
                Center(
                  child: GestureDetector(
                    onTap: () => escolherImagem(setSheetState),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F0E8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (imagemEscolhida != null)
                            FutureBuilder<Uint8List>(
                              future: imagemEscolhida!.readAsBytes(),
                              builder: (_, snap) => snap.hasData
                                  ? Image.memory(snap.data!, fit: BoxFit.cover)
                                  : const SizedBox.shrink(),
                            )
                          else if (imagemUrlAtual != null)
                            CachedNetworkImage(
                              imageUrl: imagemUrlAtual,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Color(0xFFC8A96E)),
                            )
                          else
                            const Icon(Icons.add_a_photo_outlined,
                                color: Color(0xFFC8A96E), size: 32),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFC8A96E),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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

                      try {
                        DocumentReference itemRef;
                        if (item == null) {
                          itemRef = await db.collection('cardapio').add(novoData);
                        } else {
                          itemRef = item.reference;
                          if (tempo == null) {
                            novoData['tempoEstimadoMin'] = FieldValue.delete();
                          }
                          if (!isCombo) {
                            novoData['itensCombo'] = FieldValue.delete();
                          }
                          await itemRef.update(novoData);
                        }

                        if (imagemEscolhida != null) {
                          final bytes = await imagemEscolhida!.readAsBytes();
                          await FirebaseFunctions.instanceFor(
                                  region: 'southamerica-east1')
                              .httpsCallable('atualizarImagemCardapio')
                              .call({
                            'itemId': itemRef.id,
                            'imagemBase64': base64Encode(bytes),
                          });
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
                                  final destaque = data['destaque'] as bool? ?? false;
                                  final combo = data['combo'] as bool? ?? false;
                                  final override = data['tempoEstimadoMin'] as num?;
                                  return ListTile(
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
