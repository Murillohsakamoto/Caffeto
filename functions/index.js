const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

// O banco do Caffeto não é o "(default)", é o banco nomeado "caffeto"
// (ver firebase.json -> firestore.database). Por isso especificamos aqui.
const db = admin.firestore();
db.settings({ databaseId: "caffeto" });

// Segredos do Mercado Pago. Configurar com:
// firebase functions:secrets:set MP_ACCESS_TOKEN
// firebase functions:secrets:set MP_WEBHOOK_SECRET
// (o segredo do webhook fica no painel MP: Suas integrações > sua app >
// Webhooks > detalhes do webhook > "Assinatura secreta")
const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");
const MP_WEBHOOK_SECRET = defineSecret("MP_WEBHOOK_SECRET");

// Secret Manager não aceita valor vazio, então usamos esse marcador até o
// segredo de verdade (painel MP > Webhooks > detalhes > "Assinatura
// secreta") ser configurado.
const WEBHOOK_SECRET_PENDENTE = "PENDENTE_CONFIGURAR";

const MP_API = "https://api.mercadopago.com";
const WEBHOOK_URL =
  "https://southamerica-east1-caffeto-a12fe.cloudfunctions.net/mercadopagoWebhook";

// Pedido pode gerar um novo pagamento quando está aguardando ou quando a
// tentativa anterior foi recusada/cancelada.
const STATUS_PODE_PAGAR = ["Aguardando pagamento", "Pagamento recusado"];

/**
 * Nunca confia no `total` gravado no pedido: recalcula a partir do preço
 * real de cada item no cardápio agora. Isso fecha a brecha de um cliente
 * adulterado (ou uma escrita direta no Firestore) criar um pedido com
 * itens de preço cheio mas um total inventado.
 */
async function calcularTotalReal(itens) {
  if (!Array.isArray(itens) || itens.length === 0) {
    throw new HttpsError("failed-precondition", "Pedido sem itens.");
  }

  const nomes = [...new Set(itens.map((i) => i.nome))];
  const buscas = await Promise.all(
    nomes.map((nome) =>
      db.collection("cardapio").where("nome", "==", nome).limit(1).get()
    )
  );

  const precoPorNome = {};
  buscas.forEach((snap, i) => {
    if (snap.empty) {
      throw new HttpsError(
        "failed-precondition",
        `O item "${nomes[i]}" não existe mais no cardápio.`
      );
    }
    precoPorNome[nomes[i]] = Number(snap.docs[0].data().preco);
  });

  return itens.reduce(
    (soma, item) => soma + precoPorNome[item.nome] * Number(item.qty),
    0
  );
}

/**
 * Confere que o horário de retirada escolhido realmente existe na grade
 * cadastrada pelo admin e está ativo.
 */
async function validarHorarioRetirada(horarioRetirada) {
  if (!horarioRetirada) {
    throw new HttpsError(
      "failed-precondition",
      "Pedido sem horário de retirada."
    );
  }
  const doc = await db.collection("horarios_retirada").doc(horarioRetirada).get();
  if (!doc.exists || doc.data().ativo !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Horário de retirada indisponível. Escolha outro horário."
    );
  }
}

/**
 * Ao trocar de método de pagamento (Pix <-> Cartão) para o mesmo pedido,
 * cancela a tentativa anterior antes de liberar a nova — sem isso, as duas
 * ficam pagáveis ao mesmo tempo e o cliente pode ser cobrado em dobro.
 * Se a tentativa anterior já tiver sido aprovada, bloqueia a troca (o
 * pedido já foi pago).
 */
async function encerrarTentativaAnterior(pedido, accessToken) {
  if (pedido.metodoPagamento !== "PIX" || !pedido.mercadoPagoPaymentId) {
    // Método anterior era cartão (uma preference, nunca virou pagamento) ou
    // não havia tentativa alguma — nada para checar/cancelar na API do MP.
    return;
  }

  const resp = await fetch(
    `${MP_API}/v1/payments/${pedido.mercadoPagoPaymentId}`,
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );
  const pagamentoAnterior = await resp.json();

  if (resp.ok && pagamentoAnterior.status === "approved") {
    throw new HttpsError("failed-precondition", "Este pedido já foi pago.");
  }

  if (resp.ok && ["pending", "in_process"].includes(pagamentoAnterior.status)) {
    const cancelResp = await fetch(
      `${MP_API}/v1/payments/${pedido.mercadoPagoPaymentId}`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({ status: "cancelled" }),
      }
    );
    if (!cancelResp.ok) {
      logger.warn(
        `Não foi possível cancelar o Pix ${pedido.mercadoPagoPaymentId} ao trocar de método`,
        await cancelResp.json().catch(() => null)
      );
    }
  }
}

/**
 * FUNÇÃO 1 — Criar pagamento Pix
 * Chamada pelo app Flutter (via cloud_functions) quando o cliente
 * escolhe pagar com Pix.
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

    if (pedido.userId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Esse pedido não pertence a este usuário."
      );
    }

    if (!STATUS_PODE_PAGAR.includes(pedido.status)) {
      throw new HttpsError(
        "failed-precondition",
        "Este pedido não está aguardando pagamento."
      );
    }

    await validarHorarioRetirada(pedido.horarioRetirada);

    const accessToken = MP_ACCESS_TOKEN.value();

    // Troca de método (cartão -> pix): cancela/checa a tentativa anterior e
    // abre uma nova "revisão" de pagamento, com uma idempotency key nova.
    let revisao = pedido.pagamentoRevisao || 0;
    if (pedido.metodoPagamento && pedido.metodoPagamento !== "PIX") {
      await encerrarTentativaAnterior(pedido, accessToken);
      revisao += 1;
    }

    const userRecord = await admin.auth().getUser(uid);
    const payerEmail = userRecord.email || "cliente@caffeto.app";

    const total = await calcularTotalReal(pedido.itens);
    if (Math.abs(total - Number(pedido.total)) > 0.01) {
      logger.warn(
        `Total divergente no pedido ${pedidoId}: recebido ${pedido.total}, real ${total}. Usando o valor real.`
      );
    }

    const body = {
      transaction_amount: total,
      description: `Pedido Caffeto #${pedidoId}`,
      payment_method_id: "pix",
      external_reference: pedidoId,
      notification_url: WEBHOOK_URL,
      payer: { email: payerEmail },
    };

    const resp = await fetch(`${MP_API}/v1/payments`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
        // Retentativas do mesmo app reusam a mesma revisão -> mesma key ->
        // Mercado Pago devolve o mesmo pagamento, sem duplicar.
        "X-Idempotency-Key": `pix-${pedidoId}-r${revisao}`,
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

    await pedidoRef.update({
      status: "Aguardando pagamento",
      total,
      mercadoPagoPaymentId: payment.id,
      mercadoPagoPreferenceId: admin.firestore.FieldValue.delete(),
      metodoPagamento: "PIX",
      pagamentoRevisao: revisao,
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

    if (!STATUS_PODE_PAGAR.includes(pedido.status)) {
      throw new HttpsError(
        "failed-precondition",
        "Este pedido não está aguardando pagamento."
      );
    }

    await validarHorarioRetirada(pedido.horarioRetirada);

    const accessToken = MP_ACCESS_TOKEN.value();

    // Troca de método (pix -> cartão): cancela o Pix pendente antes de abrir
    // o checkout do cartão, senão os dois ficam pagáveis ao mesmo tempo.
    let revisao = pedido.pagamentoRevisao || 0;
    if (pedido.metodoPagamento && pedido.metodoPagamento !== "CARTAO") {
      await encerrarTentativaAnterior(pedido, accessToken);
      revisao += 1;
    }

    const userRecord = await admin.auth().getUser(uid);
    const payerEmail = userRecord.email || "cliente@caffeto.app";

    const total = await calcularTotalReal(pedido.itens);
    if (Math.abs(total - Number(pedido.total)) > 0.01) {
      logger.warn(
        `Total divergente no pedido ${pedidoId}: recebido ${pedido.total}, real ${total}. Usando o valor real.`
      );
    }

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
      notification_url: WEBHOOK_URL,
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
        "X-Idempotency-Key": `card-pref-${pedidoId}-r${revisao}`,
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
      status: "Aguardando pagamento",
      total,
      mercadoPagoPreferenceId: preference.id,
      mercadoPagoPaymentId: admin.firestore.FieldValue.delete(),
      metodoPagamento: "CARTAO",
      pagamentoRevisao: revisao,
    });

    return { checkoutUrl };
  }
);

/**
 * Valida a assinatura do webhook do Mercado Pago (header x-signature),
 * conforme https://www.mercadopago.com.br/developers -> Webhooks ->
 * "Validando a origem das notificações". Sem isso, qualquer pessoa que
 * souber/adivinhar um payment id pode chamar essa URL diretamente.
 */
function assinaturaValida(req, secret) {
  const signatureHeader = req.headers["x-signature"];
  const requestId = req.headers["x-request-id"];
  if (!signatureHeader || !requestId) return false;

  const partes = {};
  for (const parte of signatureHeader.split(",")) {
    const [chave, valor] = parte.split("=");
    if (chave && valor) partes[chave.trim()] = valor.trim();
  }
  const { ts, v1 } = partes;
  if (!ts || !v1) return false;

  const dataId = String(
    req.body?.data?.id || req.query?.["data.id"] || ""
  ).toLowerCase();
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const hmac = crypto.createHmac("sha256", secret).update(manifest).digest("hex");

  const bufA = Buffer.from(hmac);
  const bufB = Buffer.from(v1);
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * FUNÇÃO 3 — Webhook do Mercado Pago
 * O Mercado Pago chama essa URL toda vez que o status de um pagamento muda.
 * NUNCA confiamos no conteúdo do POST em si — sempre consultamos a API
 * do Mercado Pago de volta para confirmar o status real (evita fraude).
 * Só confirma o "OK" depois de processar (se der erro, devolve 5xx pra o
 * Mercado Pago tentar de novo mais tarde, em vez de perder a notificação).
 */
exports.mercadopagoWebhook = onRequest(
  { secrets: [MP_ACCESS_TOKEN, MP_WEBHOOK_SECRET], region: "southamerica-east1" },
  async (req, res) => {
    try {
      const webhookSecret = MP_WEBHOOK_SECRET.value();
      if (webhookSecret && webhookSecret !== WEBHOOK_SECRET_PENDENTE) {
        if (!assinaturaValida(req, webhookSecret)) {
          logger.error("Assinatura do webhook do Mercado Pago inválida.");
          res.status(401).send("Invalid signature");
          return;
        }
      } else {
        logger.warn(
          "MP_WEBHOOK_SECRET não configurado — pulando verificação de assinatura do webhook."
        );
      }

      const type = req.body?.type || req.query?.type;
      const paymentId = req.body?.data?.id || req.query?.["data.id"];

      if (type !== "payment" || !paymentId) {
        res.status(200).send("OK");
        return;
      }

      const resp = await fetch(`${MP_API}/v1/payments/${paymentId}`, {
        headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN.value()}` },
      });
      const payment = await resp.json();

      if (!resp.ok) {
        logger.error("Erro ao consultar pagamento", payment);
        res.status(502).send("Erro ao consultar pagamento");
        return;
      }

      const pedidoId = payment.external_reference;
      if (!pedidoId) {
        logger.error("Pagamento sem external_reference", paymentId);
        res.status(200).send("OK");
        return;
      }

      const pedidoRef = db.collection("pedidos").doc(pedidoId);
      const pedidoSnap = await pedidoRef.get();

      if (!pedidoSnap.exists) {
        logger.error(`Pedido ${pedidoId} não encontrado`);
        res.status(200).send("OK");
        return;
      }

      const pedidoAtual = pedidoSnap.data();

      if (payment.status === "approved") {
        // Já processado antes (reentrega da mesma notificação) — no-op.
        if (pedidoAtual.status === "Aguardando preparo") {
          res.status(200).send("OK");
          return;
        }

        // Esse pagamento aprovado não é o que o pedido está esperando agora
        // (ex: o cliente trocou de método e essa é uma tentativa antiga) e o
        // pedido já não está mais aguardando pagamento -> possível cobrança
        // duplicada. Não mexe no pedido; fica só o alerta pra checar manual.
        if (
          pedidoAtual.mercadoPagoPaymentId &&
          String(pedidoAtual.mercadoPagoPaymentId) !== String(payment.id) &&
          !STATUS_PODE_PAGAR.includes(pedidoAtual.status)
        ) {
          logger.error(
            `ALERTA: pedido ${pedidoId} recebeu pagamento aprovado ${payment.id} mas já ` +
              `estava com status "${pedidoAtual.status}" e paymentId ${pedidoAtual.mercadoPagoPaymentId}. ` +
              "Possível cobrança duplicada — checar manualmente no painel do Mercado Pago."
          );
          res.status(200).send("OK");
          return;
        }

        await pedidoRef.update({
          status: "Aguardando preparo",
          pagoEm: admin.firestore.FieldValue.serverTimestamp(),
          mercadoPagoPaymentId: payment.id,
          // A confirmação real de como foi pago vem do próprio Mercado Pago,
          // não de qual aba o cliente deixou selecionada por último no app.
          metodoPagamento: payment.payment_method_id === "pix" ? "PIX" : "CARTAO",
        });

        logger.info(`Pedido ${pedidoId} confirmado e enviado à cozinha`);
        res.status(200).send("OK");
        return;
      }

      if (["rejected", "cancelled"].includes(payment.status)) {
        // Só marca como recusado se for a tentativa que o pedido está
        // esperando agora — assim o cancelamento de uma tentativa antiga
        // (de quando o cliente trocou de método) não derruba um pedido que
        // já está sendo pago de outro jeito.
        if (
          pedidoAtual.status === "Aguardando pagamento" &&
          String(pedidoAtual.mercadoPagoPaymentId) === String(payment.id)
        ) {
          await pedidoRef.update({ status: "Pagamento recusado" });
          logger.info(
            `Pedido ${pedidoId} com pagamento ${payment.status} — status atualizado`
          );
        }
        res.status(200).send("OK");
        return;
      }

      logger.info(`Pagamento ${paymentId} com status ${payment.status}, nada a fazer`);
      res.status(200).send("OK");
    } catch (err) {
      logger.error("Erro no webhook do Mercado Pago", err);
      // 5xx faz o Mercado Pago reenviar a notificação mais tarde, em vez de
      // considerar entregue e desistir.
      res.status(500).send("Erro interno");
    }
  }
);
