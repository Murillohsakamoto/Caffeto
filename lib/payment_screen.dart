import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

enum _PaymentMethod { pix, card }

class PaymentScreen extends StatefulWidget {
  final String orderId;
  final double total;

  const PaymentScreen({
    super.key,
    required this.orderId,
    required this.total,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _PaymentMethod _method = _PaymentMethod.pix;

  bool _loadingPix = false;
  String? _pixQrCodeBase64;
  String? _pixCopiaECola;
  String? _erro;

  StreamSubscription<DocumentSnapshot>? _pedidoSub;
  bool _pago = false;

  @override
  void initState() {
    super.initState();
    _gerarPagamentoPix();
    _escutarStatusDoPedido();
  }

  @override
  void dispose() {
    _pedidoSub?.cancel();
    super.dispose();
  }

  /// Escuta o pedido no Firestore em tempo real. Quando o webhook do
  /// Mercado Pago confirmar o pagamento, a Cloud Function muda o status
  /// para "Aguardando preparo" e essa tela reage automaticamente â€”
  /// nÃ£o existe botÃ£o de "confirmar pagamento" manual, porque quem
  /// confirma Ã© o Mercado Pago, nunca o app.
  void _escutarStatusDoPedido() {
    _pedidoSub = FirebaseFirestore.instance
        .collection('pedidos')
        .doc(widget.orderId)
        .snapshots()
        .listen((snap) {
      final status = snap.data()?['status'];
      if (status == 'Aguardando preparo' && mounted) {
        setState(() => _pago = true);
      }
    });
  }

  Future<void> _gerarPagamentoPix() async {
    setState(() {
      _loadingPix = true;
      _erro = null;
    });
    try {
      final callable =
          FirebaseFunctions.instanceFor(region: 'southamerica-east1')
              .httpsCallable('criarPagamentoPix');

      final result = await callable.call({'pedidoId': widget.orderId});
      final data = result.data as Map;

      setState(() {
        _pixQrCodeBase64 = data['qrCodeBase64'] as String?;
        _pixCopiaECola = data['qrCode'] as String?;
        _loadingPix = false;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _loadingPix = false;
        _erro = e.message ?? 'NÃ£o foi possÃ­vel gerar o Pix.';
      });
    } catch (_) {
      setState(() {
        _loadingPix = false;
        _erro = 'NÃ£o foi possÃ­vel gerar o Pix. Verifique sua conexÃ£o.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pago) return _buildSuccess();

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
          'Pagamento',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTotal(),
            _buildMethodSelector(),
            Expanded(
              child: _method == _PaymentMethod.pix
                  ? _buildPixSection()
                  : _buildCardEmBreve(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotal() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total do pedido',
            style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
          ),
          Text(
            'R\$ ${widget.total.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFFC8A96E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildMethodTab('PIX', _PaymentMethod.pix, Icons.qr_code_2, true),
          const SizedBox(width: 12),
          _buildMethodTab(
              'CartÃ£o (em breve)', _PaymentMethod.card, Icons.credit_card, false),
        ],
      ),
    );
  }

  Widget _buildMethodTab(
      String label, _PaymentMethod method, IconData icon, bool enabled) {
    final isSelected = _method == method;
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFC8A96E)
                : const Color(0xFFF5F0E8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardEmBreve() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Pagamento por cartÃ£o chega em breve.\nPor enquanto, pague com Pix.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
        ),
      ),
    );
  }

  Widget _buildPixSection() {
    if (_loadingPix) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
      );
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9E9E9E)),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _gerarPagamentoPix,
                icon: const Icon(Icons.refresh, color: Color(0xFFC8A96E)),
                label: const Text(
                  'Tentar novamente',
                  style: TextStyle(
                      color: Color(0xFFC8A96E), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const Text(
            'Escaneie o QR Code',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Abra seu banco e escaneie para pagar',
            style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
          ),
          const SizedBox(height: 24),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFEEEEEE), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _pixQrCodeBase64 != null
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(base64Decode(_pixQrCodeBase64!)),
                  )
                : const Icon(Icons.qr_code_2,
                    size: 130, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFC8A96E),
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Aguardando confirmaÃ§Ã£o do pagamento...',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Assim que o Pix cair, o pedido segue direto pra cozinha.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
          ),
          const SizedBox(height: 24),
          if (_pixCopiaECola != null)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _pixCopiaECola!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('CÃ³digo Pix copiado!'),
                    backgroundColor: const Color(0xFFC8A96E),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_outlined,
                        color: Color(0xFFC8A96E), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Pix copia e cola',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 18, color: Color(0xFFC8A96E)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F0E8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 60,
                    color: Color(0xFFC8A96E),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pedido confirmado!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pagamento aprovado. Seu pedido jÃ¡ foi enviado para a cozinha!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC8A96E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Voltar ao inÃ­cio',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

