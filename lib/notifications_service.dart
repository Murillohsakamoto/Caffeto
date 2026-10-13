import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'main.dart';

/// Registra o token FCM do dispositivo em usuarios/{uid}.fcmTokens (array,
/// suporta várias sessões/aparelhos por conta) sempre que alguém loga, e
/// mantém atualizado se o token for renovado. A Cloud Function
/// `notificarPedidoPronto` usa esses tokens pra avisar o cliente quando o
/// pedido fica pronto pra retirar.
///
/// Web fica de fora por enquanto: FCM no navegador exige uma VAPID key e um
/// service worker próprios, configuração separada da de Android/iOS.
class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  final _messaging = FirebaseMessaging.instance;
  bool _inicializado = false;

  Future<void> inicializar(GlobalKey<ScaffoldMessengerState> messengerKey) async {
    if (_inicializado || kIsWeb) return;
    _inicializado = true;

    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      // Permissão negada ou indisponível na plataforma — segue sem push.
      return;
    }

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final token = await _messaging.getToken();
        if (token != null) await _salvarToken(user.uid, token);
      } catch (e) {
        // iPhone sem push configurado (apns-token-not-set) ou sem internet:
        // segue sem push, não pode quebrar o login.
        debugPrint('Não foi possível registrar o token de push: $e');
      }
    });

    _messaging.onTokenRefresh.listen((token) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _salvarToken(uid, token);
    });

    // Com o app aberto o sistema não mostra a notificação sozinho — quem
    // decide o que fazer é o app. Aqui só um aviso simples na tela atual.
    FirebaseMessaging.onMessage.listen((message) {
      final texto = message.notification?.body ?? message.notification?.title;
      if (texto == null) return;
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: const Color(0xFFC8A96E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
  }

  Future<void> _salvarToken(String uid, String token) async {
    await db.collection('usuarios').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
      },
      SetOptions(merge: true),
    );
  }

  /// Sai da conta removendo antes o token FCM deste aparelho do perfil do
  /// usuário atual. O token é do aparelho, não da conta — se não limpar,
  /// a próxima pessoa que logar nesse mesmo aparelho (ex: família
  /// compartilhando um tablet) continua recebendo push dos pedidos da
  /// conta anterior também. Precisa rodar isso ANTES do signOut: depois
  /// que a sessão cai, as regras do Firestore não deixam mais escrever
  /// no perfil do usuário que acabou de sair.
  ///
  /// A limpeza do token é "melhor esforço": se falhar (ex: no iPhone sem
  /// push configurado o getToken() lança apns-token-not-set, ou está sem
  /// internet), a pessoa TEM que sair mesmo assim. Antes, qualquer erro
  /// aqui interrompia a função e o botão "Sair" parecia não fazer nada.
  Future<void> signOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && !kIsWeb) {
      try {
        final token =
            await _messaging.getToken().timeout(const Duration(seconds: 5));
        if (token != null) {
          await db.collection('usuarios').doc(uid).update({
            'fcmTokens': FieldValue.arrayRemove([token]),
          }).timeout(const Duration(seconds: 5));
        }
      } catch (e) {
        debugPrint('Não foi possível limpar o token de push no logout: $e');
      }
    }
    await FirebaseAuth.instance.signOut();
  }
}
