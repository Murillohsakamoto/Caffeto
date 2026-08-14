import { useEffect, useState } from 'react';
import { collection, onSnapshot, query, where, Timestamp } from 'firebase/firestore';
import { db } from './firebase';
import { Spinner } from './App';

function todayStart() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return Timestamp.fromDate(d);
}

function formatPrice(v) {
  return `R$ ${Number(v || 0).toFixed(2).replace('.', ',')}`;
}

export default function Dashboard() {
  const [pedidos, setPedidos] = useState([]);
  const [prodCount, setProdCount] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(collection(db, 'pedidos'), where('criadoEm', '>=', todayStart()));
    const unsub1 = onSnapshot(q, snap => {
      setPedidos(snap.docs.map(d => ({ id: d.id, ...d.data() })));
      setLoading(false);
    });
    const unsub2 = onSnapshot(collection(db, 'cardapio'), snap => {
      setProdCount(snap.size);
    });
    return () => { unsub1(); unsub2(); };
  }, []);

  const receitaHoje = pedidos
    .filter(p => p.status !== 'Cancelado')
    .reduce((acc, p) => acc + (p.total || 0), 0);

  const emAndamento = pedidos.filter(p =>
    p.status === 'Aguardando preparo' || p.status === 'Em preparo'
  ).length;

  const prontos = pedidos.filter(p => p.status === 'Pronto' || p.status === 'Entregue').length;

  const cards = [
    { label: 'Pedidos hoje', value: pedidos.length, color: '#C8A96E', icon: '📋' },
    { label: 'Receita hoje', value: formatPrice(receitaHoje), color: '#4CAF50', icon: '💰' },
    { label: 'Em andamento', value: emAndamento, color: '#2196F3', icon: '⏳' },
    { label: 'Concluídos', value: prontos, color: '#9E9E9E', icon: '✅' },
    { label: 'Produtos cadastrados', value: prodCount, color: '#FF9800', icon: '🍽️' },
  ];

  return (
    <div style={s.page}>
      <div style={s.header}>
        <h1 style={s.title}>Dashboard</h1>
        <span style={s.sub}>Resumo do dia de hoje</span>
      </div>

      {loading ? (
        <div style={s.loadingWrap}><Spinner /></div>
      ) : (
        <>
          <div style={s.grid}>
            {cards.map(c => (
              <div key={c.label} style={s.card}>
                <div style={{ ...s.iconWrap, background: `${c.color}18` }}>
                  <span style={{ fontSize: 22 }}>{c.icon}</span>
                </div>
                <p style={{ ...s.cardValue, color: c.color }}>{c.value}</p>
                <p style={s.cardLabel}>{c.label}</p>
              </div>
            ))}
          </div>

          <div style={s.section}>
            <h2 style={s.sectionTitle}>Pedidos de hoje</h2>
            {pedidos.length === 0 ? (
              <div style={s.empty}>Nenhum pedido hoje ainda.</div>
            ) : (
              <div style={s.table}>
                <div style={s.tableHead}>
                  <span>Pedido</span><span>Itens</span><span>Total</span><span>Status</span><span>Horário</span>
                </div>
                {[...pedidos]
                  .sort((a, b) => (b.criadoEm?.seconds || 0) - (a.criadoEm?.seconds || 0))
                  .map(p => {
                    const hora = p.criadoEm?.toDate
                      ? p.criadoEm.toDate().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
                      : '--:--';
                    const statusColor = {
                      'Aguardando preparo': '#FF9800',
                      'Em preparo': '#2196F3',
                      'Pronto': '#4CAF50',
                      'Entregue': '#4CAF50',
                      'Cancelado': '#E53935',
                    }[p.status] || '#9E9E9E';
                    return (
                      <div key={p.id} style={s.tableRow}>
                        <span style={{ fontWeight: 700 }}>#{p.id.slice(0, 6).toUpperCase()}</span>
                        <span style={{ color: '#9E9E9E' }}>{(p.itens || []).length} item(s)</span>
                        <span style={{ fontWeight: 700, color: '#C8A96E' }}>{formatPrice(p.total)}</span>
                        <span>
                          <span style={{ ...s.badge, background: `${statusColor}18`, color: statusColor }}>
                            {p.status}
                          </span>
                        </span>
                        <span style={{ color: '#9E9E9E' }}>{hora}</span>
                      </div>
                    );
                  })}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

const s = {
  page: { padding: '32px 28px', maxWidth: 960, margin: '0 auto' },
  header: { marginBottom: 28 },
  title: { fontSize: 24, fontWeight: 800, color: '#1A1A1A' },
  sub: { fontSize: 13, color: '#9E9E9E' },
  loadingWrap: { display: 'flex', justifyContent: 'center', marginTop: 80 },
  grid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))', gap: 16, marginBottom: 32 },
  card: { background: '#fff', borderRadius: 16, padding: '20px 16px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)', display: 'flex', flexDirection: 'column', gap: 8 },
  iconWrap: { width: 44, height: 44, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center' },
  cardValue: { fontSize: 24, fontWeight: 800 },
  cardLabel: { fontSize: 12, color: '#9E9E9E', fontWeight: 500 },
  section: { background: '#fff', borderRadius: 16, padding: 24, boxShadow: '0 2px 8px rgba(0,0,0,0.05)' },
  sectionTitle: { fontSize: 16, fontWeight: 700, marginBottom: 16 },
  empty: { color: '#9E9E9E', fontSize: 14, textAlign: 'center', padding: '24px 0' },
  table: { display: 'flex', flexDirection: 'column', gap: 1 },
  tableHead: {
    display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 2fr 1fr',
    padding: '8px 12px', fontSize: 11, fontWeight: 700, color: '#9E9E9E',
    textTransform: 'uppercase', letterSpacing: 0.5,
  },
  tableRow: {
    display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 2fr 1fr',
    padding: '12px', fontSize: 13, alignItems: 'center',
    borderTop: '1px solid #F5F5F5',
  },
  badge: { padding: '3px 10px', borderRadius: 20, fontSize: 11, fontWeight: 600 },
};
