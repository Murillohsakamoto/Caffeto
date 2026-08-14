import { useEffect, useRef, useState } from 'react';
import {
  collection, onSnapshot, addDoc, updateDoc, deleteDoc, doc,
} from 'firebase/firestore';
import { ref as storageRef, uploadBytes, getDownloadURL } from 'firebase/storage';
import { db, storage } from './firebase';
import { Spinner } from './App';

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
  box: { background: '#fff', borderRadius: 20, width: '100%', maxWidth: 520, maxHeight: '90vh', display: 'flex', flexDirection: 'column', boxShadow: '0 20px 60px rgba(0,0,0,0.2)' },
  head: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '20px 24px', borderBottom: '1px solid #EEEEEE', flexShrink: 0 },
  title: { fontSize: 17, fontWeight: 700 },
  closeBtn: { background: 'none', border: 'none', fontSize: 18, cursor: 'pointer', color: '#9E9E9E', lineHeight: 1 },
  body: { padding: 24, overflowY: 'auto' },
};

// ─── Combo Form ──────────────────────────────────────────────────────────────

function ComboForm({ initial, comboId, allProducts, onSave, onClose }) {
  const [nome, setNome] = useState(initial?.nome || '');
  const [preco, setPreco] = useState(initial?.preco?.toString() || '');
  const [disponivel, setDisponivel] = useState(initial?.disponivel ?? true);
  const [destaque, setDestaque] = useState(initial?.destaque ?? false);
  const [itens, setItens] = useState(initial?.itensCombo || ['']);
  const [imgFile, setImgFile] = useState(null);
  const [imgPreview, setImgPreview] = useState(initial?.imagem_url || '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef();

  function addItem() { setItens(i => [...i, '']); }
  function removeItem(idx) { setItens(i => i.filter((_, j) => j !== idx)); }
  function setItem(idx, val) { setItens(i => i.map((v, j) => j === idx ? val : v)); }

  function onFileChange(e) {
    const file = e.target.files[0];
    if (!file) return;
    setImgFile(file);
    setImgPreview(URL.createObjectURL(file));
  }

  async function handleSave() {
    if (!nome.trim()) { setError('Nome é obrigatório.'); return; }
    const precoNum = parseFloat(preco);
    if (isNaN(precoNum) || precoNum <= 0) { setError('Preço inválido.'); return; }
    const itensFiltrados = itens.map(i => i.trim()).filter(Boolean);
    if (itensFiltrados.length === 0) { setError('Adicione ao menos um item ao combo.'); return; }

    setSaving(true);
    setError('');
    try {
      const data = {
        nome: nome.trim(),
        preco: precoNum,
        categoria: 'Combo',
        tipo: 'combo',
        itensCombo: itensFiltrados,
        disponivel,
        destaque,
      };

      let docId = comboId;
      if (!docId) {
        const ref = await addDoc(collection(db, 'cardapio'), data);
        docId = ref.id;
      } else {
        await updateDoc(doc(db, 'cardapio', docId), data);
      }

      if (imgFile) {
        const sRef = storageRef(storage, `cardapio/${docId}`);
        await uploadBytes(sRef, imgFile);
        const url = await getDownloadURL(sRef);
        await updateDoc(doc(db, 'cardapio', docId), { imagem_url: url });
      }

      onSave();
    } catch (e) {
      setError('Erro ao salvar: ' + e.message);
      setSaving(false);
    }
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Image */}
      <div style={cf.imgArea} onClick={() => fileRef.current.click()}>
        {imgPreview
          ? <img src={imgPreview} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          : <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
              <span style={{ fontSize: 32 }}>🎁</span>
              <span style={{ fontSize: 13, color: '#9E9E9E' }}>Imagem do combo</span>
            </div>
        }
        <input ref={fileRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={onFileChange} />
      </div>

      <div>
        <label style={cf.label}>Nome do combo *</label>
        <input style={cf.input} value={nome} onChange={e => setNome(e.target.value)} placeholder="Ex: Café da Manhã Completo" />
      </div>

      <div>
        <label style={cf.label}>Preço (R$) *</label>
        <input style={{ ...cf.input, maxWidth: 160 }} type="number" min="0" step="0.01"
          value={preco} onChange={e => setPreco(e.target.value)} placeholder="0,00" />
      </div>

      {/* Itens do combo */}
      <div>
        <label style={cf.label}>Itens incluídos no combo *</label>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {itens.map((item, idx) => (
            <div key={idx} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <input
                style={{ ...cf.input, flex: 1 }}
                value={item}
                onChange={e => setItem(idx, e.target.value)}
                placeholder={`Item ${idx + 1} (ex: Café Espresso)`}
              />
              <button
                style={cf.removeItemBtn}
                onClick={() => removeItem(idx)}
                disabled={itens.length === 1}
              >✕</button>
            </div>
          ))}
          <button style={cf.addItemBtn} onClick={addItem}>+ Adicionar item</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 24 }}>
        <label style={cf.toggle}>
          <input type="checkbox" checked={disponivel} onChange={e => setDisponivel(e.target.checked)} />
          <span>Disponível no app</span>
        </label>
        <label style={cf.toggle}>
          <input type="checkbox" checked={destaque} onChange={e => setDestaque(e.target.checked)} />
          <span>⭐ Em destaque</span>
        </label>
      </div>

      {error && <p style={{ color: '#E53935', fontSize: 13 }}>{error}</p>}

      <div style={{ display: 'flex', gap: 12, marginTop: 4 }}>
        <button style={cf.cancelBtn} onClick={onClose}>Cancelar</button>
        <button style={cf.saveBtn} onClick={handleSave} disabled={saving}>
          {saving ? <Spinner size={18} color="#fff" /> : (comboId ? 'Salvar combo' : 'Criar combo')}
        </button>
      </div>
    </div>
  );
}

const cf = {
  imgArea: {
    border: '2px dashed #EEEEEE', borderRadius: 12, cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    height: 130, overflow: 'hidden', background: '#FAFAFA',
  },
  label: { display: 'block', fontSize: 12, fontWeight: 600, color: '#1A1A1A', marginBottom: 6 },
  input: { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1.5px solid #EEEEEE', fontSize: 14, color: '#1A1A1A', outline: 'none', background: '#FAFAFA' },
  removeItemBtn: { width: 34, height: 38, border: '1.5px solid #FFEBEE', borderRadius: 8, background: '#FFEBEE', color: '#E53935', fontSize: 12, cursor: 'pointer', flexShrink: 0 },
  addItemBtn: { padding: '8px 14px', border: '1.5px dashed #C8A96E', borderRadius: 10, background: 'transparent', color: '#C8A96E', fontSize: 13, fontWeight: 600, cursor: 'pointer' },
  toggle: { display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer', userSelect: 'none' },
  cancelBtn: { flex: 1, padding: 11, borderRadius: 12, border: '1.5px solid #EEEEEE', background: '#fff', fontSize: 14, fontWeight: 600, cursor: 'pointer' },
  saveBtn: { flex: 2, padding: 11, borderRadius: 12, border: 'none', background: '#C8A96E', color: '#fff', fontSize: 14, fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 },
};

// ─── Main Page ───────────────────────────────────────────────────────────────

export default function Combos() {
  const [combos, setCombos] = useState([]);
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    return onSnapshot(collection(db, 'cardapio'), snap => {
      const all = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      setCombos(all.filter(p => p.tipo === 'combo').sort((a, b) => (a.nome || '').localeCompare(b.nome || '')));
      setProducts(all.filter(p => p.tipo !== 'combo'));
      setLoading(false);
    });
  }, []);

  async function deleteCombo() {
    await deleteDoc(doc(db, 'cardapio', selected.id));
    setModal(null);
    setSelected(null);
  }

  async function toggleField(combo, field) {
    await updateDoc(doc(db, 'cardapio', combo.id), { [field]: !combo[field] });
  }

  return (
    <div style={s.page}>
      <div style={s.header}>
        <div>
          <h1 style={s.title}>Combos</h1>
          <span style={s.sub}>Crie conjuntos de produtos com preço especial</span>
        </div>
        <button style={s.addBtn} onClick={() => { setSelected(null); setModal('add'); }}>
          + Novo combo
        </button>
      </div>

      {loading ? (
        <div style={s.loadingWrap}><Spinner /></div>
      ) : combos.length === 0 ? (
        <div style={s.emptyBox}>
          <span style={{ fontSize: 48 }}>🎁</span>
          <p style={s.emptyTitle}>Nenhum combo criado</p>
          <p style={s.emptySub}>Crie combos para oferecer produtos agrupados com preço especial.</p>
          <button style={s.addBtn} onClick={() => { setSelected(null); setModal('add'); }}>
            + Criar primeiro combo
          </button>
        </div>
      ) : (
        <div style={s.grid}>
          {combos.map(c => (
            <div key={c.id} style={s.card}>
              {/* Image */}
              <div style={s.imgWrap}>
                {c.imagem_url
                  ? <img src={c.imagem_url} alt={c.nome} style={s.img} />
                  : <span style={{ fontSize: 32 }}>🎁</span>
                }
              </div>

              <div style={s.cardBody}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <p style={s.nome}>{c.nome}</p>
                  <span style={s.preco}>R$ {Number(c.preco || 0).toFixed(2).replace('.', ',')}</span>
                </div>

                {/* Items list */}
                <div style={s.itensList}>
                  {(c.itensCombo || []).map((item, i) => (
                    <span key={i} style={s.itemChip}>{item}</span>
                  ))}
                </div>

                {/* Status toggles */}
                <div style={{ display: 'flex', gap: 12, marginTop: 12 }}>
                  <button
                    style={{ ...s.statusChip, background: c.disponivel ? '#E8F5E9' : '#F5F5F5', color: c.disponivel ? '#4CAF50' : '#9E9E9E' }}
                    onClick={() => toggleField(c, 'disponivel')}
                  >
                    {c.disponivel ? '✓ Disponível' : '✗ Indisponível'}
                  </button>
                  <button
                    style={{ ...s.statusChip, background: c.destaque ? '#FFF8E1' : '#F5F5F5', color: c.destaque ? '#FF9800' : '#9E9E9E' }}
                    onClick={() => toggleField(c, 'destaque')}
                  >
                    {c.destaque ? '⭐ Destaque' : '☆ Destaque'}
                  </button>
                </div>

                {/* Actions */}
                <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                  <button style={s.editBtn} onClick={() => { setSelected(c); setModal('edit'); }}>Editar</button>
                  <button style={s.delBtn} onClick={() => { setSelected(c); setModal('delete'); }}>Excluir</button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {modal === 'add' && (
        <Modal title="Novo combo" onClose={() => setModal(null)}>
          <ComboForm allProducts={products} onSave={() => setModal(null)} onClose={() => setModal(null)} />
        </Modal>
      )}

      {modal === 'edit' && selected && (
        <Modal title="Editar combo" onClose={() => setModal(null)}>
          <ComboForm
            initial={selected}
            comboId={selected.id}
            allProducts={products}
            onSave={() => { setModal(null); setSelected(null); }}
            onClose={() => setModal(null)}
          />
        </Modal>
      )}

      {modal === 'delete' && selected && (
        <div style={ms.overlay} onClick={e => e.target === e.currentTarget && setModal(null)}>
          <div style={{ ...ms.box, maxWidth: 360 }}>
            <div style={ms.head}>
              <span style={ms.title}>Excluir combo</span>
              <button style={ms.closeBtn} onClick={() => setModal(null)}>✕</button>
            </div>
            <div style={ms.body}>
              <p style={{ fontSize: 14, color: '#9E9E9E', marginBottom: 20 }}>
                Deseja excluir o combo <strong>"{selected.nome}"</strong>?
              </p>
              <div style={{ display: 'flex', gap: 12 }}>
                <button style={cf.cancelBtn} onClick={() => setModal(null)}>Cancelar</button>
                <button style={{ ...cf.saveBtn, background: '#E53935' }} onClick={deleteCombo}>Excluir</button>
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
  emptyBox: { background: '#fff', borderRadius: 20, padding: '48px 32px', textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, boxShadow: '0 2px 8px rgba(0,0,0,0.05)' },
  emptyTitle: { fontSize: 18, fontWeight: 700 },
  emptySub: { fontSize: 14, color: '#9E9E9E', maxWidth: 320 },
  grid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 16 },
  card: { background: '#fff', borderRadius: 16, overflow: 'hidden', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' },
  imgWrap: { height: 140, background: '#F5F0E8', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  img: { width: '100%', height: '100%', objectFit: 'cover' },
  cardBody: { padding: '16px' },
  nome: { fontSize: 15, fontWeight: 700, color: '#1A1A1A' },
  preco: { fontSize: 15, fontWeight: 800, color: '#C8A96E', flexShrink: 0 },
  itensList: { display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 10 },
  itemChip: { fontSize: 11, padding: '4px 10px', background: '#F5F0E8', color: '#C8A96E', borderRadius: 20, fontWeight: 600 },
  statusChip: { fontSize: 12, padding: '4px 10px', borderRadius: 20, border: 'none', cursor: 'pointer', fontWeight: 600 },
  editBtn: { flex: 1, padding: '7px', borderRadius: 8, border: '1.5px solid #EEEEEE', background: '#fff', fontSize: 13, fontWeight: 600, cursor: 'pointer' },
  delBtn: { flex: 1, padding: '7px', borderRadius: 8, border: '1.5px solid #FFEBEE', background: '#FFEBEE', fontSize: 13, fontWeight: 600, cursor: 'pointer', color: '#E53935' },
};
