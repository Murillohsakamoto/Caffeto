import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

/// Tela de admin: grade fixa de horários de retirada, que se repete
/// todo dia. O cliente escolhe um desses horários na sacola.
class HorariosRetiradaScreen extends StatefulWidget {
  const HorariosRetiradaScreen({super.key});

  @override
  State<HorariosRetiradaScreen> createState() =>
      _HorariosRetiradaScreenState();
}

class _HorariosRetiradaScreenState extends State<HorariosRetiradaScreen> {
  Future<void> _adicionarHorario() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (hora == null) return;

    final horaStr =
        '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

    await db.collection('horarios_retirada').doc(horaStr).set({
      'hora': horaStr,
      'ativo': true,
    });
  }

  Future<void> _alternarAtivo(String docId, bool ativo) async {
    await db
        .collection('horarios_retirada')
        .doc(docId)
        .update({'ativo': ativo});
  }

  Future<void> _remover(String docId) async {
    await db.collection('horarios_retirada').doc(docId).delete();
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
          'Horários de retirada',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _adicionarHorario,
        backgroundColor: const Color(0xFFC8A96E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('horarios_retirada')
            .orderBy('hora')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFC8A96E)),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nenhum horário cadastrado ainda.\nToque no + para adicionar o primeiro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final hora = data['hora'] as String? ?? doc.id;
              final ativo = data['ativo'] == true;

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0E8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule,
                        color: ativo
                            ? const Color(0xFFC8A96E)
                            : const Color(0xFFBBBBBB)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hora,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ativo
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                    Switch(
                      value: ativo,
                      activeThumbColor: const Color(0xFFC8A96E),
                      onChanged: (v) => _alternarAtivo(doc.id, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Color(0xFFE53935)),
                      onPressed: () => _remover(doc.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
