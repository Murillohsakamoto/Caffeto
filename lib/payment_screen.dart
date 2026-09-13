import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

enum _PaymentMethod { pix, card }

const _prazoRetirada = Duration(minutes: 20);
const _statusPosPagamento = ['Aguardando preparo', 'Em preparo', 'Pronto', 'Entregue'];

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
  _PaymentMethod _method = _PaymentMethod.pix;

  bool _loadingPix = false;
  String? _pixQrCodeBase64;
  String? _pixCopiaECola;
  String? _erro;

  bool _loadingCard = false;
  String? _cardCheckoutUrl;
  String? _erroCard;

  StreamSubscription<DocumentSnapshot>? _pedidoSub;
  Timer? _ticker;
  bool _pago = false;
  bool _pagamentoRecusado = false;
  Map<String, dynamic> _pedidoData = {};

  @override
  void initState() {
    super.initState();
    _gerarPagamentoPix();
    _escutarStatusDoPedido();
    // Atualiza o contador de retirada periodicamente enquanto o pedido
    // estiver "Pronto" e essa tela aberta.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pedidoSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  /// Escuta o pedido no Firestore em tempo real. Quando o webhook do
  /// Mercado Pago confirmar o pagamento, a Cloud Function muda o status
  /// para "Aguardando preparo" e essa tela reage automaticamente —
  /// não existe botão de "confirmar pagamento" manual, porque quem
  /// confirma é o Mercado Pago, nunca o app. Continua escutando depois
  /// disso pra acompanhar o pedido até a cozinha marcar como pronto.
  void _escutarStatusDoPedido() {
    _pedidoSub = FirebaseFirestore.instance
        .collection('pedidos')
        .doc(widget.orderId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null || !mounted) return;
      final status = data['status'] as String?;
      setState(() {
        _pedidoData = data;
        if (_statusPosPagamento.contains(status)) {
          _pago = true;
          _pagamentoRecusado = false;
        } else if (status == 'Pagamento recusado') {
          _pagamentoRecusado = true;
        }
      });
    });
  }

  /// Depois de um pagamento recusado/cancelado, tenta de novo gerando um
  /// pagamento novo pro método atualmente selecionado.
  Future<void> _tentarNovamente() async {
    setState(() {
      _pagamentoRecusado = false;
      _pixQrCodeBase64 = null;
      _pixCopiaECola = null;
      _cardCheckoutUrl = null;
    });
    if (_method == _PaymentMethod.pix) {
      await _gerarPagamentoPix();
    } else {
      await _gerarPagamentoCartao();
    }
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
        _erro = e.message ?? 'Não foi possível gerar o Pix.';
      });
    } catch (_) {
      setState(() {
        _loadingPix = false;
        _erro = 'Não foi possível gerar o Pix. Verifique sua conexão.';
      });
    }
  }

  /// Cria a preferência de pagamento com cartão (Checkout Pro) e guarda o
  /// link de pagamento hospedado pelo Mercado Pago. Não coletamos dados de
  /// cartão dentro do app: quem identifica a bandeira, valida o cartão e
  /// cumpre PCI compliance é a própria página da Mercado Pago.
  Future<void> _gerarPagamentoCartao() async {
    setState(() {
      _loadingCard = true;
      _erroCard = null;
    });
    try {
      final callable =
          FirebaseFunctions.instanceFor(region: 'southamerica-east1')
              .httpsCallable('criarPreferenciaCartao');

      final result = await callable.call({'pedidoId': widget.orderId});
      final data = result.data as Map;

      setState(() {
        _cardCheckoutUrl = data['checkoutUrl'] as String?;
        _loadingCard = false;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _loadingCard = false;
        _erroCard = e.message ?? 'Não foi possível gerar o pagamento.';
      });
    } catch (_) {
      setState(() {
        _loadingCard = false;
        _erroCard =
            'Não foi possível gerar o pagamento. Verifique sua conexão.';
      });
    }
  }

  Future<void> _abrirCheckoutCartao() async {
    final url = _cardCheckoutUrl;
    if (url == null) return;
    final abriu =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!abriu && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o pagamento.')),
      );
    }
  }

  void _selecionarMetodo(_PaymentMethod method) {
    if (_method == method) return;
    setState(() => _method = method);
    // Sempre gera de novo ao trocar de método: o backend cancela a tentativa
    // anterior (evita cobrar duas vezes) e devolve um pagamento novo.
    if (method == _PaymentMethod.card) {
      _gerarPagamentoCartao();
    } else {
      _gerarPagamentoPix();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pago) return _buildSuccess();
    if (_pagamentoRecusado) return _buildPagamentoRecusado();

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
                  : _buildCardSection(),
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
          _buildMethodTab('PIX', _PaymentMethod.pix, Icons.qr_code_2),
          const SizedBox(width: 12),
          _buildMethodTab('Cartão', _PaymentMethod.card, Icons.credit_card),
        ],
      ),
    );
  }

  Widget _buildMethodTab(String label, _PaymentMethod method, IconData icon) {
    final isSelected = _method == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selecionarMetodo(method),
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
                'Aguardando confirmação do pagamento...',
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
                    content: const Text('Código Pix copiado!'),
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

  Widget _buildCardSection() {
    if (_loadingCard) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
      );
    }

    if (_erroCard != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text(
                _erroCard!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9E9E9E)),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _gerarPagamentoCartao,
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
          const Icon(Icons.credit_card, size: 56, color: Color(0xFFC8A96E)),
          const SizedBox(height: 20),
          const Text(
            'Pagamento seguro pelo Mercado Pago',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Você será levado para uma página segura para digitar os dados do cartão',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _abrirCheckoutCartao,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC8A96E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              child: const Text(
                'Pagar com cartão',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
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
                'Aguardando confirmação do pagamento...',
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
            'Assim que o pagamento for aprovado, o pedido segue direto pra cozinha.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
          ),
        ],
      ),
    );
  }

  Widget _buildPagamentoRecusado() {
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
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 60,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pagamento não aprovado',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'O Mercado Pago recusou ou cancelou esse pagamento. Você não foi cobrado — pode tentar de novo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _tentarNovamente,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC8A96E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Tentar novamente',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text(
                    'Voltar ao início',
                    style: TextStyle(color: Color(0xFF9E9E9E)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({IconData icon, String titulo, String subtitulo}) _infoParaStatus(
      String status) {
    switch (status) {
      case 'Em preparo':
        return (
          icon: Icons.soup_kitchen_outlined,
          titulo: 'Preparando seu pedido...',
          subtitulo: 'A cozinha já começou. Avisamos quando estiver pronto.',
        );
      case 'Pronto':
        return (
          icon: Icons.shopping_bag_outlined,
          titulo: 'Pedido pronto!',
          subtitulo: 'Pode retirar no balcão.',
        );
      case 'Entregue':
        return (
          icon: Icons.done_all,
          titulo: 'Pedido entregue',
          subtitulo: 'Obrigado por pedir na Caffeto!',
        );
      default:
        return (
          icon: Icons.check_circle_outline,
          titulo: 'Pedido confirmado!',
          subtitulo:
              'Pagamento aprovado. Seu pedido já foi enviado para a cozinha!',
        );
    }
  }

  Widget? _buildContadorRetirada(String status) {
    final horario = _pedidoData['horarioRetirada'] as String?;
    final prontoEm = _pedidoData['prontoEm'] as Timestamp?;
    if (status != 'Pronto' || prontoEm == null) {
      if (horario == null) return null;
      return Text(
        'Retirada às $horario',
        style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
      );
    }

    final restante = prontoEm.toDate().add(_prazoRetirada).difference(
          DateTime.now(),
        );
    final atrasado = restante.isNegative;
    final texto = atrasado
        ? 'Já passou ${restante.abs().inMinutes}min do prazo de retirada'
        : 'Retire em até ${restante.inMinutes}min';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: (atrasado ? const Color(0xFFE53935) : const Color(0xFFC8A96E))
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: atrasado ? const Color(0xFFE53935) : const Color(0xFFC8A96E),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    final status = _pedidoData['status'] as String? ?? 'Aguardando preparo';
    final info = _infoParaStatus(status);
    final contador = _buildContadorRetirada(status);

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
                  child: Icon(
                    info.icon,
                    size: 60,
                    color: const Color(0xFFC8A96E),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  info.titulo,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  info.subtitulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
                ),
                if (contador != null) ...[
                  const SizedBox(height: 16),
                  contador,
                ],
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
                      'Voltar ao início',
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
