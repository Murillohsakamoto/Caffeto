import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  _PaymentMethod _method = _PaymentMethod.pix;
  bool _confirming = false;
  bool _success = false;

  int _pixSecondsLeft = 300;
  Timer? _pixTimer;

  final _cardNumberController = TextEditingController();
  final _cardNameController = TextEditingController();
  final _cardExpController = TextEditingController();
  final _cardCvvController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startPixTimer();
  }

  void _startPixTimer() {
    _pixTimer?.cancel();
    _pixTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_pixSecondsLeft > 0) _pixSecondsLeft--;
      });
    });
  }

  @override
  void dispose() {
    _pixTimer?.cancel();
    _cardNumberController.dispose();
    _cardNameController.dispose();
    _cardExpController.dispose();
    _cardCvvController.dispose();
    super.dispose();
  }

  Future<void> _confirmarPagamento() async {
    setState(() => _confirming = true);
    try {
      await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.orderId)
          .update({
        'status': 'Aguardando preparo',
        'pagoEm': FieldValue.serverTimestamp(),
        'metodoPagamento':
            _method == _PaymentMethod.pix ? 'PIX' : 'Cartão',
      });
      _pixTimer?.cancel();
      if (mounted) setState(() => _success = true);
    } catch (_) {
      if (mounted) {
        setState(() => _confirming = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Erro ao confirmar pagamento. Tente novamente.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) return _buildSuccess();

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
            _buildConfirmButton(),
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

  Widget _buildMethodTab(
      String label, _PaymentMethod method, IconData icon) {
    final isSelected = _method == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _method = method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
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
                color: isSelected
                    ? Colors.white
                    : const Color(0xFF9E9E9E),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF9E9E9E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPixSection() {
    final minutes =
        (_pixSecondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds =
        (_pixSecondsLeft % 60).toString().padLeft(2, '0');
    final expired = _pixSecondsLeft == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            expired ? 'QR Code expirado' : 'Escaneie o QR Code',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            expired
                ? 'Gere um novo código para continuar'
                : 'Abra seu banco e escaneie para pagar',
            style:
                const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
          ),
          const SizedBox(height: 24),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: expired
                  ? const Color(0xFFF5F0E8)
                  : Colors.white,
              border: Border.all(
                  color: const Color(0xFFEEEEEE), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Icon(
                Icons.qr_code_2,
                size: expired ? 80 : 130,
                color: expired
                    ? const Color(0xFFD9D9D9)
                    : const Color(0xFF1A1A1A),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!expired) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F0E8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Expira em $minutes:$seconds',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () {
                setState(() => _pixSecondsLeft = 300);
                _startPixTimer();
              },
              icon: const Icon(Icons.refresh,
                  color: Color(0xFFC8A96E)),
              label: const Text(
                'Gerar novo código',
                style: TextStyle(
                    color: Color(0xFFC8A96E),
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  const ClipboardData(text: 'caffeto@pagamentos.com.br'));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Chave PIX copiada!'),
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
                      'caffeto@pagamentos.com.br',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF9E9E9E)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy,
                      size: 18, color: Color(0xFFC8A96E)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildCardInput(
            controller: _cardNumberController,
            hint: 'Número do cartão',
            icon: Icons.credit_card,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _buildCardInput(
            controller: _cardNameController,
            hint: 'Nome impresso no cartão',
            icon: Icons.person_outline,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCardInput(
                  controller: _cardExpController,
                  hint: 'MM/AA',
                  icon: Icons.calendar_today_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCardInput(
                  controller: _cardCvvController,
                  hint: 'CVV',
                  icon: Icons.lock_outline,
                  keyboardType: TextInputType.number,
                  obscure: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 14, color: Color(0xFF9E9E9E)),
              SizedBox(width: 6),
              Text(
                'Pagamento seguro e criptografado',
                style:
                    TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscure = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              color: Color(0xFF9E9E9E), fontSize: 14),
          prefixIcon:
              Icon(icon, color: const Color(0xFFC8A96E), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    final label = _method == _PaymentMethod.pix
        ? 'Já realizei o pagamento'
        : 'Pagar R\$ ${widget.total.toStringAsFixed(2).replaceAll('.', ',')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _confirming ? null : _confirmarPagamento,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC8A96E),
            disabledBackgroundColor: const Color(0xFFE0C99A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)),
            elevation: 0,
          ),
          child: _confirming
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
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
                  'Seu pedido foi recebido e está sendo preparado. Fique de olho no status!',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
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
