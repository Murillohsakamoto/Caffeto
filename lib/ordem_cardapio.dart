/// Ordem do cardápio definida pelo admin (arrastar e soltar): categorias e
/// produtos guardam um campo `ordem` (0, 1, 2…). Itens sem `ordem` ainda
/// (cadastrados antes da função existir) vão pro fim, em ordem alfabética,
/// pra lista nunca "pular" de lugar sozinha.
library;

/// Ordena nomes de categoria pelo `ordem` salvo em `categorias/{nome}`.
List<String> ordenarCategorias(
  Iterable<String> nomes,
  Map<String, num> ordemPorNome,
) {
  final lista = nomes.toSet().toList();
  lista.sort((a, b) {
    final oa = ordemPorNome[a];
    final ob = ordemPorNome[b];
    if (oa != null && ob != null) return oa.compareTo(ob);
    if (oa != null) return -1;
    if (ob != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return lista;
}

/// Compara dois produtos (mapas do Firestore) pelo campo `ordem`, com
/// desempate pelo nome.
int compararProdutos(Map<String, dynamic> a, Map<String, dynamic> b) {
  final oa = a['ordem'] as num?;
  final ob = b['ordem'] as num?;
  if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
  if (oa != null && ob == null) return -1;
  if (oa == null && ob != null) return 1;
  final na = (a['nome'] as String? ?? '').toLowerCase();
  final nb = (b['nome'] as String? ?? '').toLowerCase();
  return na.compareTo(nb);
}
