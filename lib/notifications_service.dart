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
      final token = await _messaging.getToken();
      if (token != null) await _salvarToken(user.uid, token);
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
}
