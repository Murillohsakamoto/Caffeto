const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

// O banco do Caffeto não é o "(default)", é o banco nomeado "caffeto"
// (ver firebase.json -> firestore.database). Por isso especificamos aqui.
const db = admin.firestore();
db.settings({ databaseId: "caffeto" });

// Segredo do Mercado Pago. Configurar com:
// firebase functions:secrets:set MP_ACCESS_TOKEN
const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

const MP_API = "https://api.mercadopago.com";

/**
 * FUNÇÃO 1 — Criar pagamento Pix
 * Chamada pelo app Flutter (via cloud_functions) quando o cliente
 * escolhe pagar com Pix. NUNCA confia no valor enviado pelo app:
 * busca o total real do pedido direto no Firestore.
 */
exports.criarPagamentoPix = onCall(
  { secrets: [MP_ACCESS_TOKEN], region: "southamerica-east1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "É preciso estar logado.");
    }

    const { pedidoId } = request.data;
    if (!pedidoId || typeof pedidoId !== "string") {
      throw new HttpsError("invalid-argument", "pedidoId é obrigatório.");
    }

    const pedidoRef = db.collection("pedidos").doc(pedidoId);
    const pedidoSnap = await pedidoRef.get();

    if (!pedidoSnap.exists) {
      throw new HttpsError("not-found", "Pedido não encontrado.");
    }

    const pedido = pedidoSnap.data();

    // Garante que o pedido é do próprio usuário que está pagando
    if (pedido.userId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Esse pedido não pertence a este usuário."
      );
    }

    if (pedido.status !== "Aguardando pagamento") {
      throw new HttpsError(
        "failed-precondition",
        "Este pedido não está aguardando pagamento."
      );
    }

    // Busca e-mail do usuário para o pagador (Mercado Pago exige um e-mail)
    const userRecord = await admin.auth().getUser(uid);
    const payerEmail = userRecord.email || "cliente@caffeto.app";

    const total = Number(pedido.total);
    if (!total || total <= 0) {
      throw new HttpsError("failed-precondition", "Total do pedido inválido.");
    }

    const webhookUrl =
      "https://southamerica-east1-caffeto-a12fe.cloudfunctions.net/mercadopagoWebhook";

    const body = {
      transaction_amount: total,
      description: `Pedido Caffeto #${pedidoId}`,
      payment_method_id: "pix",
      external_reference: pedidoId,
      notification_url: webhookUrl,
      payer: { email: payerEmail },
    };

    const resp = await fetch(`${MP_API}/v1/payments`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${MP_ACCESS_TOKEN.value()}`,
        // Evita criar pagamento duplicado se o app chamar 2x
        "X-Idempotency-Key": `pix-${pedidoId}`,
      },
      body: JSON.stringify(body),
    });

    const payment = await resp.json();

    if (!resp.ok) {
      logger.error("Erro ao criar pagamento Pix", payment);
      throw new HttpsError(
        "internal",
        payment?.message || "Erro ao gerar pagamento Pix."
      );
    }

    const pixData = payment.point_of_interaction?.transaction_data;

    if (!pixData?.qr_code) {
      logger.error("Resposta do Mercado Pago sem QR Code", payment);
      throw new HttpsError("internal", "Mercado Pago não retornou o QR Code.");
    }

    // Salva o ID do pagamento no pedido para o webhook conseguir localizar
    await pedidoRef.update({
      mercadoPagoPaymentId: payment.id,
      metodoPagamento: "PIX",
    });

    return {
      paymentId: payment.id,
      qrCode: pixData.qr_code, // "copia e cola"
      qrCodeBase64: pixData.qr_code_base64, // imagem do QR Code
      expiraEm: payment.date_of_expiration,
    };
  }
);

/**
 * FUNÇÃO 2 — Criar pagamento com cartão (Checkout Pro)
 * Chamada pelo app Flutter quando o cliente escolhe pagar com cartão.
 * Diferente do Pix, não tokenizamos o cartão no app: criamos uma
 * "preference" e devolvemos o link de pagamento hospedado pelo próprio
 * Mercado Pago, que cuida de identificar a bandeira, validar o cartão
 * e é PCI compliant por padrão. O webhook (função 3) confirma o pagamento
 * do mesmo jeito que confirma o Pix.
 */
exports.criarPreferenciaCartao = onCall(
  { secrets: [MP_ACCESS_TOKEN], region: "southamerica-east1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "É preciso estar logado.");
    }

    const { pedidoId } = request.data;
    if (!pedidoId || typeof pedidoId !== "string") {
      throw new HttpsError("invalid-argument", "pedidoId é obrigatório.");
    }

    const pedidoRef = db.collection("pedidos").doc(pedidoId);
    const pedidoSnap = await pedidoRef.get();

    if (!pedidoSnap.exists) {
      throw new HttpsError("not-found", "Pedido não encontrado.");
    }

    const pedido = pedidoSnap.data();

    if (pedido.userId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Esse pedido não pertence a este usuário."
      );
    }

    if (pedido.status !== "Aguardando pagamento") {
      throw new HttpsError(
        "failed-precondition",
        "Este pedido não está aguardando pagamento."
      );
    }

    const userRecord = await admin.auth().getUser(uid);
    const payerEmail = userRecord.email || "cliente@caffeto.app";

    const total = Number(pedido.total);
    if (!total || total <= 0) {
      throw new HttpsError("failed-precondition", "Total do pedido inválido.");
    }

    const webhookUrl =
      "https://southamerica-east1-caffeto-a12fe.cloudfunctions.net/mercadopagoWebhook";

    const accessToken = MP_ACCESS_TOKEN.value();

    const body = {
      items: [
        {
          title: `Pedido Caffeto #${pedidoId}`,
          quantity: 1,
          unit_price: total,
          currency_id: "BRL",
        },
      ],
      payer: { email: payerEmail },
      external_reference: pedidoId,
      notification_url: webhookUrl,
      payment_methods: {
        // Pix já tem fluxo próprio no app; aqui só cartão, sem parcelamento.
        installments: 1,
        excluded_payment_types: [
          { id: "ticket" },
          { id: "bank_transfer" },
          { id: "atm" },
          { id: "digital_wallet" },
        ],
      },
    };

    const resp = await fetch(`${MP_API}/checkout/preferences`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
        "X-Idempotency-Key": `card-pref-${pedidoId}`,
      },
      body: JSON.stringify(body),
    });

    const preference = await resp.json();

    if (!resp.ok) {
      logger.error("Erro ao criar preferência de pagamento com cartão", preference);
      throw new HttpsError(
        "internal",
        preference?.message || "Erro ao gerar pagamento com cartão."
      );
    }

    // Token de teste (TEST-...) precisa do link de sandbox; produção usa o normal.
    const checkoutUrl = accessToken.startsWith("TEST-")
      ? preference.sandbox_init_point
      : preference.init_point;

    if (!checkoutUrl) {
      logger.error("Preferência sem init_point", preference);
      throw new HttpsError(
        "internal",
        "Mercado Pago não retornou o link de pagamento."
      );
    }

    await pedidoRef.update({
      mercadoPagoPreferenceId: preference.id,
      metodoPagamento: "CARTAO",
    });

    return { checkoutUrl };
  }
);

/**
 * FUNÇÃO 3 — Webhook do Mercado Pago
 * O Mercado Pago chama essa URL toda vez que o status de um pagamento muda.
 * NUNCA confiamos no conteúdo do POST em si — sempre consultamos a API
 * do Mercado Pago de volta para confirmar o status real (evita fraude).
 */
exports.mercadopagoWebhook = onRequest(
  { secrets: [MP_ACCESS_TOKEN], region: "southamerica-east1" },
  async (req, res) => {
    // Responde rápido para o Mercado Pago não achar que falhou e reenviar
    res.status(200).send("OK");

    try {
      const type = req.body?.type || req.query?.type;
      const paymentId = req.body?.data?.id || req.query?.["data.id"];

      if (type !== "payment" || !paymentId) {
        return;
      }

      // Consulta o status real do pagamento (nunca confia só na notificação)
      const resp = await fetch(`${MP_API}/v1/payments/${paymentId}`, {
        headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN.value()}` },
      });
      const payment = await resp.json();

      if (!resp.ok) {
        logger.error("Erro ao consultar pagamento", payment);
        return;
      }

      if (payment.status !== "approved") {
        logger.info(`Pagamento ${paymentId} com status ${payment.status}`);
        return;
      }

      const pedidoId = payment.external_reference;
      if (!pedidoId) {
        logger.error("Pagamento aprovado sem external_reference", paymentId);
        return;
      }

      const pedidoRef = db.collection("pedidos").doc(pedidoId);
      const pedidoSnap = await pedidoRef.get();

      if (!pedidoSnap.exists) {
        logger.error(`Pedido ${pedidoId} não encontrado`);
        return;
      }

      // Evita processar o mesmo pagamento aprovado duas vezes
      if (pedidoSnap.data().status === "Aguardando preparo") {
        return;
      }

      await pedidoRef.update({
        status: "Aguardando preparo",
        pagoEm: admin.firestore.FieldValue.serverTimestamp(),
        mercadoPagoPaymentId: payment.id,
      });

      logger.info(`Pedido ${pedidoId} confirmado e enviado à cozinha`);
    } catch (err) {
      logger.error("Erro no webhook do Mercado Pago", err);
    }
  }
);
