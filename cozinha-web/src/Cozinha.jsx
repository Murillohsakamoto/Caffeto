import { useEffect, useRef, useState } from 'react';
import { signOut } from 'firebase/auth';
import { collection, onSnapshot, orderBy, query, where, updateDoc, doc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from './firebase';
import { Spinner } from './App';

const STATUS = {
  aguardando: 'Aguardando preparo',
  emPreparo: 'Em preparo',
  pronto: 'Pronto',
};

const COLUMN_META = [
  {
    key: 'aguardando',
    label: 'Aguardando',
    status: STATUS.aguardando,
    color: '#FF9800',
    bg: '#FFF8F0',
    icon: '⏳',
  },
  {
    key: 'emPreparo',
    label: 'Em preparo',
    status: STATUS.emPreparo,
    color: '#2196F3',
    bg: '#F0F7FF',
    icon: '☕',
  },
  {
    key: 'pronto',
    label: 'Prontos',
    status: STATUS.pronto,
    color: '#4CAF50',
    bg: '#F0FFF4',
    icon: '✅',
  },
];

function playNotification() {
  try {
    const ctx = new AudioContext();
    const notes = [660, 880];
    notes.forEach((freq, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.type = 'sine';
      osc.frequency.value = freq;
      const t = ctx.currentTime + i * 0.18;
      gain.gain.setValueAtTime(0.25, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + 0.3);
      osc.start(t);
      osc.stop(t + 0.3);
    });
  } catch {
    // AudioContext not available — silent fail
  }
}

function formatTime(ts) {
  if (!ts) return '--:--';
  const d = ts.toDate ? ts.toDate() : new Date(ts.seconds * 1000);
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

function formatPrice(val) {
  return `R$ ${Number(val || 0)
    .toFixed(2)
    .replace('.', ',')}`;
}

function shortId(id) {
  return id.substring(0, 6).toUpperCase();
}

// ─── Order Card ────────────────────────────────────────────────────────────

function OrderCard({ doc: orderDoc, columnColor }) {
  const [updating, setUpdating] = useState(false);
  const { id, data } = orderDoc;
  const status = data.status ?? '';
  const itens = data.itens ?? [];
  const total = data.total ?? 0;
  const metodo = data.metodoPagamento ?? '';
  const hora = formatTime(data.criadoEm);

  async function advance() {
    const next =
      status === STATUS.aguardando ? STATUS.emPreparo :
      status === STATUS.emPreparo ? STATUS.pronto : null;
    if (!next) return;
    setUpdating(true);
    try {
      const update = { status: next };
      if (next === STATUS.emPreparo) update.iniciadoEm = serverTimestamp();
      if (next === STATUS.pronto) update.prontoEm = serverTimestamp();
      await updateDoc(doc(db, 'pedidos', id), update);
    } catch {
      setUpdating(false);
    }
  }

  const btnLabel =
    status === STATUS.aguardando ? 'Iniciar preparo' :
    status === STATUS.emPreparo ? 'Marcar como pronto' : null;

  const btnColor =
    status === STATUS.aguardando ? '#2196F3' :
    status === STATUS.emPreparo ? '#4CAF50' : null;

  return (
    <div style={cs.card}>
      {/* Card header */}
      <div style={{ ...cs.cardHead, background: `${columnColor}18` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ ...cs.dot, background: columnColor }} />
          <span style={cs.orderId}>Pedido #{shortId(id)}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={cs.time}>{hora}</span>
          {metodo && (
            <span style={cs.metodoBadge}>{metodo}</span>
          )}
        </div>
      </div>

      {/* Items */}
      <div style={cs.cardBody}>
        <div style={cs.itemList}>
          {itens.map((item, i) => (
            <div key={i} style={cs.itemRow}>
              <span style={cs.qty}>{item.qty}x</span>
              <span style={cs.itemName}>{item.nome}</span>
            </div>
          ))}
        </div>

        <div style={cs.divider} />

        <div style={cs.totalRow}>
          <span style={cs.totalLabel}>Total pago</span>
          <span style={cs.totalValue}>{formatPrice(total)}</span>
        </div>

        {/* Action button */}
        {btnLabel && (
          <button
            style={{ ...cs.actionBtn, background: updating ? '#E0E0E0' : btnColor }}
            onClick={advance}
            disabled={updating}
          >
            {updating ? <Spinner size={18} color="#fff" /> : btnLabel}
          </button>
        )}
      </div>
    </div>
  );
}

// ─── Column ────────────────────────────────────────────────────────────────

function Column({ meta, orders }) {
  return (
    <div style={col.wrap}>
      <div style={col.header}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={col.icon}>{meta.icon}</span>
          <span style={col.label}>{meta.label}</span>
        </div>
        <span style={{ ...col.badge, background: meta.color, color: '#fff' }}>
          {orders.length}
        </span>
      </div>

      <div style={col.body}>
        {orders.length === 0 ? (
          <div style={col.empty}>
            <span style={col.emptyIcon}>—</span>
            <span style={col.emptyText}>Nenhum pedido</span>
          </div>
        ) : (
          orders.map((o) => (
            <OrderCard key={o.id} doc={o} columnColor={meta.color} />
          ))
        )}
      </div>
    </div>
  );
}

// ─── Main Screen ───────────────────────────────────────────────────────────

export default function Cozinha() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const prevIdsRef = useRef(new Set());

  useEffect(() => {
    const q = query(
      collection(db, 'pedidos'),
      where('status', 'in', [STATUS.aguardando, STATUS.emPreparo, STATUS.pronto]),
      orderBy('criadoEm', 'asc')
    );

    const unsub = onSnapshot(q, (snap) => {
      const docs = snap.docs.map((d) => ({ id: d.id, data: d.data() }));

      // Play sound for genuinely new orders in 'Aguardando preparo'
      const currentAguardando = new Set(
        docs.filter((d) => d.data.status === STATUS.aguardando).map((d) => d.id)
      );
      let hasNew = false;
      currentAguardando.forEach((id) => {
        if (!prevIdsRef.current.has(id)) hasNew = true;
      });
      if (hasNew && prevIdsRef.current.size > 0) playNotification();
      prevIdsRef.current = currentAguardando;

      setOrders(docs);
      setLoading(false);
    });

    return unsub;
  }, []);

  const grouped = {
    aguardando: orders.filter((o) => o.data.status === STATUS.aguardando),
    emPreparo: orders.filter((o) => o.data.status === STATUS.emPreparo),
    pronto: orders.filter((o) => o.data.status === STATUS.pronto),
  };

  const totalAtivos = grouped.aguardando.length + grouped.emPreparo.length;

  return (
    <div style={sc.page}>
      {/* Top bar */}
      <header style={sc.header}>
        <div style={sc.headerLeft}>
          <div style={sc.logoBadge}>
            <CoffeeIcon />
          </div>
          <div>
            <span style={sc.brand}>caffeto</span>
            <span style={sc.subtitle}>Modo Cozinha</span>
          </div>
        </div>

        <div style={sc.headerCenter}>
          {COLUMN_META.slice(0, 2).map((m) => (
            <div key={m.key} style={{ ...sc.pill, background: `${m.color}1A`, border: `1px solid ${m.color}40` }}>
              <span style={{ ...sc.pillDot, background: m.color }} />
              <span style={{ color: m.color, fontWeight: 700, fontSize: 13 }}>
                {grouped[m.key].length} {m.label.toLowerCase()}
              </span>
            </div>
          ))}
          {totalAtivos === 0 && (
            <span style={sc.allClear}>✓ Cozinha livre</span>
          )}
        </div>

        <button style={sc.logoutBtn} onClick={() => signOut(auth)}>
          Sair
        </button>
      </header>

      {/* Body */}
      {loading ? (
        <div style={sc.loadingWrap}>
          <Spinner size={40} />
          <span style={sc.loadingText}>Carregando pedidos...</span>
        </div>
      ) : (
        <main style={sc.kanban}>
          {COLUMN_META.map((meta) => (
            <Column key={meta.key} meta={meta} orders={grouped[meta.key]} />
          ))}
        </main>
      )}
    </div>
  );
}

// ─── Icons ─────────────────────────────────────────────────────────────────

function CoffeeIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path
        d="M17 8h1a4 4 0 0 1 0 8h-1M3 8h14v9a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V8z"
        stroke="#fff"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M6 2v2M10 2v2M14 2v2" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

// ─── Styles ────────────────────────────────────────────────────────────────

const sc = {
  page: {
    minHeight: '100vh',
    display: 'flex',
    flexDirection: 'column',
    background: '#F5F0E8',
  },
  header: {
    background: '#fff',
    borderBottom: '1px solid #EEEEEE',
    padding: '12px 24px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 16,
    position: 'sticky',
    top: 0,
    zIndex: 10,
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
  },
  logoBadge: {
    width: 40,
    height: 40,
    background: '#C8A96E',
    borderRadius: 12,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  brand: {
    display: 'block',
    fontSize: 17,
    fontWeight: 800,
    color: '#1A1A1A',
    letterSpacing: '-0.3px',
  },
  subtitle: {
    display: 'block',
    fontSize: 11,
    color: '#9E9E9E',
    fontWeight: 500,
  },
  headerCenter: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    flex: 1,
    justifyContent: 'center',
  },
  pill: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    padding: '5px 12px',
    borderRadius: 20,
    fontSize: 13,
  },
  pillDot: {
    width: 7,
    height: 7,
    borderRadius: '50%',
  },
  allClear: {
    fontSize: 13,
    fontWeight: 600,
    color: '#4CAF50',
  },
  logoutBtn: {
    padding: '7px 18px',
    background: 'transparent',
    border: '1.5px solid #EEEEEE',
    borderRadius: 20,
    fontSize: 13,
    fontWeight: 600,
    fontFamily: 'Inter, sans-serif',
    color: '#9E9E9E',
    cursor: 'pointer',
    transition: 'border-color 0.2s',
  },
  kanban: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: 16,
    padding: '20px 24px',
    flex: 1,
    alignItems: 'start',
  },
  loadingWrap: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  loadingText: {
    fontSize: 14,
    color: '#9E9E9E',
  },
};

const col = {
  wrap: {
    display: 'flex',
    flexDirection: 'column',
    gap: 0,
    minHeight: 200,
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 12,
    padding: '0 4px',
  },
  icon: { fontSize: 18 },
  label: {
    fontSize: 15,
    fontWeight: 700,
    color: '#1A1A1A',
  },
  badge: {
    fontSize: 12,
    fontWeight: 700,
    padding: '2px 9px',
    borderRadius: 20,
    minWidth: 28,
    textAlign: 'center',
  },
  body: {
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
  },
  empty: {
    background: '#fff',
    borderRadius: 16,
    padding: '28px 16px',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 6,
    border: '1.5px dashed #EEEEEE',
  },
  emptyIcon: { fontSize: 28, color: '#DDDDDD' },
  emptyText: { fontSize: 13, color: '#BBBBBB', fontWeight: 500 },
};

const cs = {
  card: {
    background: '#fff',
    borderRadius: 16,
    boxShadow: '0 2px 12px rgba(0,0,0,0.06)',
    overflow: 'hidden',
  },
  cardHead: {
    padding: '10px 14px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: '50%',
    flexShrink: 0,
  },
  orderId: {
    fontSize: 14,
    fontWeight: 800,
    color: '#1A1A1A',
  },
  time: {
    fontSize: 12,
    color: '#9E9E9E',
  },
  metodoBadge: {
    fontSize: 11,
    fontWeight: 600,
    color: '#9E9E9E',
    background: '#F5F5F5',
    padding: '2px 8px',
    borderRadius: 20,
  },
  cardBody: {
    padding: '12px 14px 14px',
  },
  itemList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
  },
  itemRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
  },
  qty: {
    width: 30,
    height: 30,
    background: '#F5F0E8',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 10,
    fontWeight: 800,
    color: '#C8A96E',
    flexShrink: 0,
    lineHeight: '30px',
    textAlign: 'center',
  },
  itemName: {
    fontSize: 13,
    fontWeight: 600,
    color: '#1A1A1A',
  },
  divider: {
    height: 1,
    background: '#EEEEEE',
    margin: '12px 0',
  },
  totalRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  totalLabel: {
    fontSize: 12,
    color: '#9E9E9E',
  },
  totalValue: {
    fontSize: 15,
    fontWeight: 800,
    color: '#C8A96E',
  },
  actionBtn: {
    width: '100%',
    marginTop: 12,
    padding: '10px',
    border: 'none',
    borderRadius: 20,
    fontSize: 13,
    fontWeight: 700,
    fontFamily: 'Inter, sans-serif',
    color: '#fff',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    transition: 'opacity 0.2s',
  },
};
