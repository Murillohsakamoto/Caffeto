import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'cozinha_screen.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  List<Map<String, String>> _enderecos = [];
  bool _uploadingPhoto = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _carregarEnderecos();
  }

  Future<void> _carregarEnderecos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    if (!mounted) return;
    if (doc.exists) {
      final data = doc.data()!;
      final list = ((data['enderecos'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
      setState(() {
        _enderecos = list;
        _isAdmin = data['admin'] == true;
      });
    }
  }

  Future<void> _salvarEnderecos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .set({'enderecos': _enderecos}, SetOptions(merge: true));
  }

  Future<void> _uploadFoto(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (image == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final ref = FirebaseStorage.instance.ref('avatars/$uid.jpg');
      await ref.putFile(File(image.path));
      final url = await ref.getDownloadURL();
      await FirebaseAuth.instance.currentUser!.updatePhotoURL(url);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) _showSnack('Erro ao atualizar foto. Tente novamente.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    // authStateChanges em CaffetoApp cuida da navegação
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Perfil',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // AVATAR
            GestureDetector(
              onTap: _uploadingPhoto ? null : _editarFoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFFF5F0E8),
                    child: _uploadingPhoto
                        ? const CircularProgressIndicator(
                            color: Color(0xFFC8A96E), strokeWidth: 2)
                        : user.photoURL != null
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: user.photoURL!,
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      const CircularProgressIndicator(
                                          color: Color(0xFFC8A96E),
                                          strokeWidth: 2),
                                  errorWidget: (_, _, _) => const Icon(
                                    Icons.person,
                                    size: 48,
                                    color: Color(0xFFC8A96E),
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                size: 48,
                                color: Color(0xFFC8A96E),
                              ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFFC8A96E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user.displayName ?? 'Cliente Caffeto',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
              ),
            ),
            Text(
              user.email ?? '',
              style: const TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
            ),

            const SizedBox(height: 24),

            _buildOption(Icons.person_outline, 'Meus Dados',
                onTap: _editarDados),
            _buildOption(Icons.lock_outline, 'Alterar Senha',
                onTap: _alterarSenha),
            _buildOption(Icons.receipt_long_outlined, 'Meus Pedidos',
                onTap: _verPedidos),
            _buildOption(Icons.location_on_outlined, 'Meus Endereços',
                onTap: _gerenciarEnderecos),
            _buildOption(Icons.notifications_outlined, 'Notificações',
                onTap: () {}),
            _buildOption(Icons.help_outline, 'Ajuda', onTap: () {}),
            if (_isAdmin)
              _buildOption(
                Icons.soup_kitchen_outlined,
                'Modo Cozinha',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CozinhaScreen()),
                ),
                highlight: true,
              ),

            const SizedBox(height: 16),
            const Divider(color: Color(0xFFEEEEEE)),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFC8A96E)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.logout, color: Color(0xFFC8A96E)),
                label: const Text(
                  'Sair',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC8A96E),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(IconData icon, String label,
      {required VoidCallback onTap, bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFFC8A96E).withValues(alpha: 0.12)
              : const Color(0xFFF5F0E8),
          borderRadius: BorderRadius.circular(16),
          border: highlight
              ? Border.all(color: const Color(0xFFC8A96E), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFC8A96E), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: highlight
                      ? const Color(0xFFC8A96E)
                      : const Color(0xFF1A1A1A),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9E9E9E)),
          ],
        ),
      ),
    );
  }

  // ── FOTO ──────────────────────────────────────────────────────────────
  void _editarFoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Foto de Perfil',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            _sheetOption(Icons.camera_alt, 'Tirar foto', () {
              Navigator.pop(context);
              _uploadFoto(ImageSource.camera);
            }),
            _sheetOption(Icons.photo_library, 'Escolher da galeria', () {
              Navigator.pop(context);
              _uploadFoto(ImageSource.gallery);
            }),
            if (FirebaseAuth.instance.currentUser?.photoURL != null)
              _sheetOption(Icons.delete_outline, 'Remover foto', () async {
                Navigator.pop(context);
                await FirebaseAuth.instance.currentUser!.updatePhotoURL(null);
                if (mounted) setState(() {});
              }),
          ],
        ),
      ),
    );
  }

  // ── DADOS ─────────────────────────────────────────────────────────────
  void _editarDados() {
    final nomeController = TextEditingController(
        text: FirebaseAuth.instance.currentUser?.displayName ?? '');
    showModalBottomSheet(
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
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Meus Dados',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            _inputField(nomeController, 'Nome completo',
                Icons.person_outline,
                textCapitalization: TextCapitalization.words),
            const SizedBox(height: 8),
            Text(
              FirebaseAuth.instance.currentUser?.email ?? '',
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final nome = nomeController.text.trim();
                  if (nome.isEmpty) return;
                  await FirebaseAuth.instance.currentUser!
                      .updateDisplayName(nome);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {});
                    _showSnack('Dados atualizados!');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8A96E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: const Text('Salvar',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SENHA ─────────────────────────────────────────────────────────────
  void _alterarSenha() {
    final providers = FirebaseAuth.instance.currentUser!.providerData
        .map((p) => p.providerId)
        .toList();
    if (!providers.contains('password')) {
      _showSnack('Sua conta usa o Google. Altere a senha pelo Google.');
      return;
    }

    final senhaAtualController = TextEditingController();
    final novaSenhaController = TextEditingController();
    final confirmarController = TextEditingController();

    showModalBottomSheet(
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
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Alterar Senha',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            _inputField(senhaAtualController, 'Senha atual',
                Icons.lock_outline,
                obscure: true),
            const SizedBox(height: 12),
            _inputField(
                novaSenhaController, 'Nova senha', Icons.lock_outline,
                obscure: true),
            const SizedBox(height: 12),
            _inputField(confirmarController, 'Confirmar nova senha',
                Icons.lock_outline,
                obscure: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final nova = novaSenhaController.text;
                  final confirmar = confirmarController.text;
                  if (nova != confirmar) {
                    _showSnack('As senhas não coincidem.');
                    return;
                  }
                  if (nova.length < 6) {
                    _showSnack(
                        'A nova senha deve ter pelo menos 6 caracteres.');
                    return;
                  }
                  try {
                    final user = FirebaseAuth.instance.currentUser!;
                    final cred = EmailAuthProvider.credential(
                      email: user.email!,
                      password: senhaAtualController.text,
                    );
                    await user.reauthenticateWithCredential(cred);
                    await user.updatePassword(nova);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) _showSnack('Senha alterada com sucesso!');
                  } on FirebaseAuthException catch (e) {
                    if (e.code == 'wrong-password' ||
                        e.code == 'invalid-credential') {
                      _showSnack('Senha atual incorreta.');
                    } else {
                      _showSnack('Erro ao alterar senha. Tente novamente.');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC8A96E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: const Text('Alterar',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PEDIDOS ───────────────────────────────────────────────────────────
  void _verPedidos() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text('Meus Pedidos',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  // Requer índice composto em (userId, criadoEm desc)
                  // O Firebase mostrará um link para criar automaticamente
                  future: FirebaseFirestore.instance
                      .collection('pedidos')
                      .where('userId', isEqualTo: uid)
                      .orderBy('criadoEm', descending: true)
                      .limit(20)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFC8A96E)),
                      );
                    }
                    if (snapshot.hasError ||
                        !snapshot.hasData ||
                        snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'Nenhum pedido encontrado',
                          style: TextStyle(
                              color: Color(0xFF9E9E9E), fontSize: 14),
                        ),
                      );
                    }

                    final pedidos = snapshot.data!.docs;
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: pedidos.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        final data = pedidos[index].data()
                            as Map<String, dynamic>;
                        final itens =
                            (data['itens'] as List<dynamic>? ?? [])
                                .map((i) =>
                                    '${i['nome']} x${i['qty']}')
                                .join(', ');
                        final total =
                            (data['total'] as num? ?? 0).toDouble();
                        final status =
                            data['status'] as String? ?? 'Em preparo';
                        final ts = data['criadoEm'] as Timestamp?;
                        final date = ts != null
                            ? '${ts.toDate().day.toString().padLeft(2, '0')}/${ts.toDate().month.toString().padLeft(2, '0')}/${ts.toDate().year}'
                            : '--';
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F0E8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '#${pedidos[index].id.substring(0, 6).toUpperCase()}',
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
                                      color: _statusColor(status)
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(20),
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
                              Text(
                                itens,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF9E9E9E)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(date,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF9E9E9E))),
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
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Entregue':
        return const Color(0xFF4CAF50);
      case 'Cancelado':
        return const Color(0xFFE53935);
      case 'Pronto':
        return const Color(0xFF2196F3);
      default:
        return const Color(0xFFF59300);
    }
  }

  // ── ENDEREÇOS ─────────────────────────────────────────────────────────
  void _gerenciarEnderecos() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Meus Endereços',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  GestureDetector(
                    onTap: () => _adicionarEndereco(setModalState),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC8A96E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '+ Adicionar',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._enderecos.map(
                (e) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0E8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          color: Color(0xFFC8A96E), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e['label']!,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            Text(e['address']!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF9E9E9E))),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setModalState(() => _enderecos.remove(e));
                          setState(() {});
                          _salvarEnderecos();
                        },
                        child: const Icon(Icons.delete_outline,
                            color: Color(0xFF9E9E9E), size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _adicionarEndereco(StateSetter setModalState) {
    final labelController = TextEditingController();
    final addressController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Novo Endereço',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _inputField(
                labelController, 'Rótulo (ex: Casa)', Icons.label_outline),
            const SizedBox(height: 12),
            _inputField(addressController, 'Endereço completo',
                Icons.location_on_outlined),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF9E9E9E))),
          ),
          ElevatedButton(
            onPressed: () {
              final label = labelController.text.trim();
              final address = addressController.text.trim();
              if (label.isEmpty || address.isEmpty) return;
              setModalState(() {
                _enderecos.add({'label': label, 'address': address});
              });
              setState(() {});
              _salvarEnderecos();
              Navigator.pop(context);
              _showSnack('Endereço adicionado!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8A96E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Salvar',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────
  Widget _inputField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xFFC8A96E)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _sheetOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F0E8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFC8A96E)),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFC8A96E),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
