import { useEffect, useState } from 'react';
import {
  collection, onSnapshot, addDoc, updateDoc, deleteDoc, doc, query, orderBy,
} from 'firebase/firestore';
import { db } from './firebase';
import { Spinner } from './App';

const PRESET_COLORS = [
  'C8A96E', 'E07B54', '5C8D89', '7B6FA0', '4A90D9',
  'D4A843', '6B8F71', 'C65D7B', '4A7B9D', '8B4513',
];

const EMPTY_FORM = { nome: '', subtitulo: '', cor: 'C8A96E' };

// ─── Modal ──────────────────────────────────────────────────────────────────

function Modal({ title, onClose, children }) {
  return (
    <div style={ms.overlay} onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={ms.box}>
        <div style={ms.head}>
          <span style={ms.title}>{title}</span>
          <button style={ms.closeBtn} onClick={onClose}>✕</button>
        </div>
        <div style={ms.body}>{children}</div>
      </div>
    </div>
  );
}

const ms = {
  overlay: { position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100, padding: 16 },
  box: { background: '#fff', borderRadius: 20, width: '100%', maxWidth: 440, boxShadow: '0 20px 60px rgba(0,0,0,0.2)' },
  head: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '20px 24px', borderBottom: '1px solid #EEEEEE' },
  title: { fontSize: 17, fontWeight: 700 },
  closeBtn: { background: 'none', border: 'none', fontSize: 18, cursor: 'pointer', color: '#9E9E9E', lineHeight: 1 },
  body: { padding: 24 },
};

// ─── Partner Form ────────────────────────────────────────────────────────────

function PartnerForm({ initial, partnerId, onSave, onClose }) {
  const [form, setForm] = useState(initial ? { nome: initial.nome || '', subtitulo: initial.subtitulo || '', cor: initial.cor || 'C8A96E' } : EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  function set(f, v) { setForm(p => ({ ...p, [f]: v })); }

  async function handleSave() {
    if (!form.nome.trim()) { setError('Nome é obrigatório.'); return; }
    setSaving(true);
    setError('');
    try {
      const cor = form.cor.replace('#', '');
      if (partnerId) {
        await updateDoc(doc(db, 'parceiros', partnerId), { nome: form.nome.trim(), subtitulo: form.subtitulo.trim(), cor });
      } else {
        // new partner gets ordem = max + 1
        await addDoc(collection(db, 'parceiros'), { nome: form.nome.trim(), subtitulo: form.subtitulo.trim(), cor, ordem: Date.now() });
      }
      onSave();
    } catch (e) {
      setError('Erro ao salvar: ' + e.message);
      setSaving(false);
    }
  }

  const previewColor = `#${form.cor.replace('#', '')}`;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Preview card */}
      <div style={{ ...pf.previewCard, background: previewColor }}>
        <div style={pf.previewIcon}><span style={{ fontSize: 22 }}>🏪</span></div>
        <div>
          <p style={pf.previewNome}>{form.nome || 'Nome do parceiro'}</p>
          <p style={pf.previewSub}>{form.subtitulo || 'Subtítulo'}</p>
        </div>
      </div>

      <div>
        <label style={pf.label}>Nome *</label>
        <input style={pf.input} value={form.nome} onChange={e => set('nome', e.target.value)} placeholder="Ex: Padaria Aurora" />
      </div>
      <div>
        <label style={pf.label}>Subtítulo</label>
        <input style={pf.input} value={form.subtitulo} onChange={e => set('subtitulo', e.target.value)} placeholder="Ex: Pães e bolos artesanais" />
      </div>

      <div>
        <label style={pf.label}>Cor do card</label>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 10 }}>
          {PRESET_COLORS.map(c => (
            <div
              key={c}
              onClick={() => set('cor', c)}
              style={{
                width: 28, height: 28, borderRadius: 8, cursor: 'pointer',
                background: `#${c}`,
                outline: form.cor.replace('#', '') === c ? `3px solid #1A1A1A` : '3px solid transparent',
                outlineOffset: 2,
              }}
            />
          ))}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <input
            style={{ ...pf.input, width: 140, fontFamily: 'monospace' }}
            value={form.cor}
            onChange={e => set('cor', e.target.value.replace('#', ''))}
            placeholder="C8A96E"
            maxLength={6}
          />
          <span style={{ fontSize: 12, color: '#9E9E9E' }}>Hex sem #</span>
        </div>
      </div>

      {error && <p style={{ color: '#E53935', fontSize: 13 }}>{error}</p>}

      <div style={{ display: 'flex', gap: 12, marginTop: 4 }}>
        <button style={pf.cancelBtn} onClick={onClose}>Cancelar</button>
        <button style={pf.saveBtn} onClick={handleSave} disabled={saving}>
          {saving ? <Spinner size={18} color="#fff" /> : (partnerId ? 'Salvar' : 'Adicionar')}
        </button>
      </div>
    </div>
  );
}

const pf = {
  previewCard: { borderRadius: 14, padding: '16px 20px', display: 'flex', alignItems: 'center', gap: 14 },
  previewIcon: { width: 44, height: 44, borderRadius: '50%', background: 'rgba(255,255,255,0.2)', display: 'flex', alignItems: 'center', justifyContent: 'center' },
  previewNome: { color: '#fff', fontWeight: 800, fontSize: 15 },
  previewSub: { color: 'rgba(255,255,255,0.8)', fontSize: 12, marginTop: 2 },
  label: { display: 'block', fontSize: 12, fontWeight: 600, color: '#1A1A1A', marginBottom: 6 },
  input: { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1.5px solid #EEEEEE', fontSize: 14, color: '#1A1A1A', outline: 'none', background: '#FAFAFA' },
  cancelBtn: { flex: 1, padding: 11, borderRadius: 12, border: '1.5px solid #EEEEEE', background: '#fff', fontSize: 14, fontWeight: 600, cursor: 'pointer' },
  saveBtn: { flex: 2, padding: 11, borderRadius: 12, border: 'none', background: '#C8A96E', color: '#fff', fontSize: 14, fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 },
};

// ─── Main Page ───────────────────────────────────────────────────────────────

export default function Parceiros() {
  const [partners, setPartners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);
  const [reordering, setReordering] = useState(false);

  useEffect(() => {
    const q = query(collection(db, 'parceiros'), orderBy('ordem'));
    return onSnapshot(q, snap => {
      setPartners(snap.docs.map(d => ({ id: d.id, ...d.data() })));
      setLoading(false);
    });
  }, []);

  async function movePartner(idx, dir) {
    const swapIdx = idx + dir;
    if (swapIdx < 0 || swapIdx >= partners.length) return;
    setReordering(true);
    const a = partners[idx];
    const b = partners[swapIdx];
    await updateDoc(doc(db, 'parceiros', a.id), { ordem: b.ordem });
    await updateDoc(doc(db, 'parceiros', b.id), { ordem: a.ordem });
    setReordering(false);
  }

  async function deletePartner() {
    await deleteDoc(doc(db, 'parceiros', selected.id));
    setModal(null);
    setSelected(null);
  }

  return (
    <div style={s.page}>
      <div style={s.header}>
        <div>
          <h1 style={s.title}>Parceiros</h1>
          <span style={s.sub}>Carrossel exibido na tela inicial do app</span>
        </div>
        <button style={s.addBtn} onClick={() => { setSelected(null); setModal('add'); }}>
          + Novo parceiro
        </button>
      </div>

      {loading ? (
        <div style={s.loadingWrap}><Spinner /></div>
      ) : partners.length === 0 ? (
        <div style={s.empty}>Nenhum parceiro cadastrado. Adicione o primeiro!</div>
      ) : (
        <div style={s.list}>
          {partners.map((p, idx) => {
            const color = `#${p.cor || 'C8A96E'}`;
            return (
              <div key={p.id} style={s.row}>
                {/* Color swatch */}
                <div style={{ ...s.swatch, background: color }} />

                {/* Preview mini card */}
                <div style={{ ...s.miniCard, background: color }}>
                  <span style={s.miniName}>{p.nome}</span>
                  <span style={s.miniSub}>{p.subtitulo}</span>
                </div>

                {/* Order buttons */}
                <div style={s.orderBtns}>
                  <button style={s.orderBtn} disabled={idx === 0 || reordering}
                    onClick={() => movePartner(idx, -1)}>▲</button>
                  <span style={s.orderNum}>{idx + 1}</span>
                  <button style={s.orderBtn} disabled={idx === partners.length - 1 || reordering}
                    onClick={() => movePartner(idx, 1)}>▼</button>
                </div>

                {/* Actions */}
                <div style={{ display: 'flex', gap: 8 }}>
                  <button style={s.editBtn} onClick={() => { setSelected(p); setModal('edit'); }}>Editar</button>
                  <button style={s.delBtn} onClick={() => { setSelected(p); setModal('delete'); }}>✕</button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {modal === 'add' && (
        <Modal title="Novo parceiro" onClose={() => setModal(null)}>
          <PartnerForm onSave={() => setModal(null)} onClose={() => setModal(null)} />
        </Modal>
      )}

      {modal === 'edit' && selected && (
        <Modal title="Editar parceiro" onClose={() => setModal(null)}>
          <PartnerForm
            initial={selected}
            partnerId={selected.id}
            onSave={() => { setModal(null); setSelected(null); }}
            onClose={() => setModal(null)}
          />
        </Modal>
      )}

      {modal === 'delete' && selected && (
        <div style={ms.overlay} onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div style={{ ...ms.box, maxWidth: 360 }}>
            <div style={ms.head}>
              <span style={ms.title}>Excluir parceiro</span>
              <button style={ms.closeBtn} onClick={() => setModal(null)}>✕</button>
            </div>
            <div style={ms.body}>
              <p style={{ fontSize: 14, color: '#9E9E9E', marginBottom: 20 }}>
                Deseja excluir <strong>"{selected.nome}"</strong>? Ele será removido do carrossel.
              </p>
              <div style={{ display: 'flex', gap: 12 }}>
                <button style={pf.cancelBtn} onClick={() => setModal(null)}>Cancelar</button>
                <button style={{ ...pf.saveBtn, background: '#E53935' }} onClick={deletePartner}>Excluir</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const s = {
  page: { padding: '32px 28px' },
  header: { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 },
  title: { fontSize: 24, fontWeight: 800, color: '#1A1A1A' },
  sub: { fontSize: 13, color: '#9E9E9E' },
  addBtn: { padding: '10px 20px', background: '#C8A96E', color: '#fff', border: 'none', borderRadius: 12, fontWeight: 700, fontSize: 14, cursor: 'pointer' },
  loadingWrap: { display: 'flex', justifyContent: 'center', marginTop: 60 },
  empty: { color: '#9E9E9E', textAlign: 'center', padding: '60px 0', fontSize: 14 },
  list: { display: 'flex', flexDirection: 'column', gap: 10 },
  row: { background: '#fff', borderRadius: 14, padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 16, boxShadow: '0 1px 4px rgba(0,0,0,0.05)' },
  swatch: { width: 14, height: 48, borderRadius: 4, flexShrink: 0 },
  miniCard: { borderRadius: 10, padding: '8px 14px', flex: 1, minWidth: 0 },
  miniName: { display: 'block', color: '#fff', fontWeight: 800, fontSize: 14 },
  miniSub: { display: 'block', color: 'rgba(255,255,255,0.8)', fontSize: 12, marginTop: 2 },
  orderBtns: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 },
  orderBtn: { background: 'none', border: '1px solid #EEEEEE', borderRadius: 6, width: 26, height: 22, cursor: 'pointer', fontSize: 11, color: '#9E9E9E', display: 'flex', alignItems: 'center', justifyContent: 'center' },
  orderNum: { fontSize: 12, fontWeight: 700, color: '#C8A96E' },
  editBtn: { padding: '6px 14px', borderRadius: 8, border: '1.5px solid #EEEEEE', background: '#fff', fontSize: 12, fontWeight: 600, cursor: 'pointer' },
  delBtn: { padding: '6px 10px', borderRadius: 8, border: '1.5px solid #FFEBEE', background: '#FFEBEE', fontSize: 12, fontWeight: 700, cursor: 'pointer', color: '#E53935' },
};
