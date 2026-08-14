import { useEffect, useRef, useState } from 'react';
import {
  collection, onSnapshot, addDoc, updateDoc, deleteDoc, doc,
} from 'firebase/firestore';
import { ref as storageRef, uploadBytes, getDownloadURL } from 'firebase/storage';
import { db, storage } from './firebase';
import { Spinner } from './App';

const CATEGORIAS = ['Café', 'Gelado', 'Suco', 'Sobremesa', 'Salgado', 'Sanduíche', 'Refeição', 'Outro'];

const EMPTY_FORM = { nome: '', preco: '', categoria: 'Café', disponivel: true, destaque: false };

// ─── Modal ─────────────────────────────────────────────────────────────────

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
  box: { background: '#fff', borderRadius: 20, width: '100%', maxWidth: 480, maxHeight: '90vh', display: 'flex', flexDirection: 'column', boxShadow: '0 20px 60px rgba(0,0,0,0.2)' },
  head: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '20px 24px', borderBottom: '1px solid #EEEEEE' },
  title: { fontSize: 17, fontWeight: 700 },
  closeBtn: { background: 'none', border: 'none', fontSize: 18, cursor: 'pointer', color: '#9E9E9E', lineHeight: 1 },
  body: { padding: '24px', overflowY: 'auto' },
};

// ─── Product Form ──────────────────────────────────────────────────────────

function ProductForm({ initial, productId, onSave, onClose }) {
  const [form, setForm] = useState(initial || EMPTY_FORM);
  const [imgFile, setImgFile] = useState(null);
  const [imgPreview, setImgPreview] = useState(initial?.imagem_url || '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef();

  function set(field, val) { setForm(f => ({ ...f, [field]: val })); }

  function onFileChange(e) {
    const file = e.target.files[0];
    if (!file) return;
    setImgFile(file);
    setImgPreview(URL.createObjectURL(file));
  }

  async function handleSave() {
    if (!form.nome.trim()) { setError('Nome é obrigatório.'); return; }
    const preco = parseFloat(form.preco);
    if (isNaN(preco) || preco <= 0) { setError('Preço inválido.'); return; }
    setSaving(true);
    setError('');
    try {
      const data = {
        nome: form.nome.trim(),
        preco,
        categoria: form.categoria,
        disponivel: form.disponivel,
        destaque: form.destaque,
      };

      let docId = productId;
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
      {/* Image upload */}
      <div style={fs.imgArea} onClick={() => fileRef.current.click()}>
        {imgPreview
          ? <img src={imgPreview} alt="" style={fs.imgPreview} />
          : <div style={fs.imgPlaceholder}>
              <span style={{ fontSize: 32 }}>📷</span>
              <span style={{ fontSize: 13, color: '#9E9E9E' }}>Clique para adicionar imagem</span>
            </div>
        }
        <input ref={fileRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={onFileChange} />
      </div>

      <div>
        <label style={fs.label}>Nome do produto *</label>
        <input style={fs.input} value={form.nome} onChange={e => set('nome', e.target.value)} placeholder="Ex: Café Latte" />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
        <div>
          <label style={fs.label}>Preço (R$) *</label>
          <input style={fs.input} type="number" min="0" step="0.01" value={form.preco}
            onChange={e => set('preco', e.target.value)} placeholder="0,00" />
        </div>
        <div>
          <label style={fs.label}>Categoria</label>
          <select style={fs.select} value={form.categoria} onChange={e => set('categoria', e.target.value)}>
            {CATEGORIAS.map(c => <option key={c}>{c}</option>)}
          </select>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 24 }}>
        <label style={fs.toggle}>
          <input type="checkbox" checked={form.disponivel} onChange={e => set('disponivel', e.target.checked)} />
          <span>Disponível no app</span>
        </label>
        <label style={fs.toggle}>
          <input type="checkbox" checked={form.destaque} onChange={e => set('destaque', e.target.checked)} />
          <span>⭐ Em destaque</span>
        </label>
      </div>

      {error && <p style={{ color: '#E53935', fontSize: 13 }}>{error}</p>}

      <div style={{ display: 'flex', gap: 12, marginTop: 4 }}>
        <button style={fs.cancelBtn} onClick={onClose}>Cancelar</button>
        <button style={fs.saveBtn} onClick={handleSave} disabled={saving}>
          {saving ? <Spinner size={18} color="#fff" /> : (productId ? 'Salvar alterações' : 'Adicionar produto')}
        </button>
      </div>
    </div>
  );
}

const fs = {
  imgArea: {
    border: '2px dashed #EEEEEE', borderRadius: 12, cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    height: 140, overflow: 'hidden', background: '#FAFAFA', transition: 'border-color 0.2s',
  },
  imgPreview: { width: '100%', height: '100%', objectFit: 'cover' },
  imgPlaceholder: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 },
  label: { display: 'block', fontSize: 12, fontWeight: 600, color: '#1A1A1A', marginBottom: 6 },
  input: { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1.5px solid #EEEEEE', fontSize: 14, color: '#1A1A1A', outline: 'none', background: '#FAFAFA' },
  select: { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1.5px solid #EEEEEE', fontSize: 14, color: '#1A1A1A', outline: 'none', background: '#FAFAFA' },
  toggle: { display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer', userSelect: 'none' },
  cancelBtn: { flex: 1, padding: '11px', borderRadius: 12, border: '1.5px solid #EEEEEE', background: '#fff', fontSize: 14, fontWeight: 600, cursor: 'pointer', color: '#1A1A1A' },
  saveBtn: { flex: 2, padding: '11px', borderRadius: 12, border: 'none', background: '#C8A96E', color: '#fff', fontSize: 14, fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 },
};

// ─── Confirm Delete ─────────────────────────────────────────────────────────

function ConfirmModal({ msg, onConfirm, onClose }) {
  const [loading, setLoading] = useState(false);
  return (
    <Modal title="Confirmar exclusão" onClose={onClose}>
      <p style={{ fontSize: 14, color: '#9E9E9E', marginBottom: 20 }}>{msg}</p>
      <div style={{ display: 'flex', gap: 12 }}>
        <button style={fs.cancelBtn} onClick={onClose}>Cancelar</button>
        <button
          style={{ ...fs.saveBtn, background: '#E53935' }}
          onClick={async () => { setLoading(true); await onConfirm(); }}
          disabled={loading}
        >
          {loading ? <Spinner size={18} color="#fff" /> : 'Excluir'}
        </button>
      </div>
    </Modal>
  );
}

// ─── Toggle Switch ──────────────────────────────────────────────────────────

function Toggle({ checked, onChange, color = '#C8A96E' }) {
  return (
    <div
      onClick={onChange}
      style={{
        width: 36, height: 20, borderRadius: 10, cursor: 'pointer',
        background: checked ? color : '#E0E0E0', position: 'relative',
        transition: 'background 0.2s', flexShrink: 0,
      }}
    >
      <div style={{
        width: 14, height: 14, borderRadius: '50%', background: '#fff',
        position: 'absolute', top: 3, left: checked ? 19 : 3,
        transition: 'left 0.2s', boxShadow: '0 1px 3px rgba(0,0,0,0.2)',
      }} />
    </div>
  );
}

// ─── Main Page ──────────────────────────────────────────────────────────────

export default function Cardapio() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [catFilter, setCatFilter] = useState('');
  const [search, setSearch] = useState('');
  const [modal, setModal] = useState(null); // null | 'add' | 'edit' | 'delete'
  const [selected, setSelected] = useState(null);
  const [toggling, setToggling] = useState({});

  useEffect(() => {
    return onSnapshot(collection(db, 'cardapio'), snap => {
      const all = snap.docs
        .filter(d => d.data().tipo !== 'combo')
        .map(d => ({ id: d.id, ...d.data() }))
        .sort((a, b) => (a.nome || '').localeCompare(b.nome || ''));
      setProducts(all);
      setLoading(false);
    });
  }, []);

  const cats = [...new Set(products.map(p => p.categoria).filter(Boolean))].sort();

  const filtered = products.filter(p => {
    const matchCat = !catFilter || p.categoria === catFilter;
    const matchSearch = !search || p.nome?.toLowerCase().includes(search.toLowerCase());
    return matchCat && matchSearch;
  });

  async function toggleField(product, field) {
    const key = `${product.id}-${field}`;
    setToggling(t => ({ ...t, [key]: true }));
    await updateDoc(doc(db, 'cardapio', product.id), { [field]: !product[field] });
    setToggling(t => { const n = { ...t }; delete n[key]; return n; });
  }

  function openEdit(p) { setSelected(p); setModal('edit'); }
  function openDelete(p) { setSelected(p); setModal('delete'); }

  async function confirmDelete() {
    await deleteDoc(doc(db, 'cardapio', selected.id));
    setModal(null);
    setSelected(null);
  }

  return (
    <div style={ps.page}>
      <div style={ps.header}>
        <div>
          <h1 style={ps.title}>Cardápio</h1>
          <span style={ps.sub}>{products.length} produtos cadastrados</span>
        </div>
        <button style={ps.addBtn} onClick={() => { setSelected(null); setModal('add'); }}>
          + Novo produto
        </button>
      </div>

      {/* Filters */}
      <div style={ps.filters}>
        <input
          style={ps.search}
          placeholder="Buscar produto..."
          value={search}
          onChange={e => setSearch(e.target.value)}
        />
        <div style={ps.cats}>
          <button style={{ ...ps.catBtn, ...(catFilter === '' ? ps.catActive : {}) }}
            onClick={() => setCatFilter('')}>Todos</button>
          {cats.map(c => (
            <button key={c} style={{ ...ps.catBtn, ...(catFilter === c ? ps.catActive : {}) }}
              onClick={() => setCatFilter(c)}>{c}</button>
          ))}
        </div>
      </div>

      {loading ? (
        <div style={ps.loadingWrap}><Spinner /></div>
      ) : filtered.length === 0 ? (
        <div style={ps.empty}>Nenhum produto encontrado.</div>
      ) : (
        <div style={ps.list}>
          {filtered.map(p => (
            <div key={p.id} style={ps.row}>
              {/* Image */}
              <div style={ps.imgWrap}>
                {p.imagem_url
                  ? <img src={p.imagem_url} alt={p.nome} style={ps.img} />
                  : <span style={{ fontSize: 20 }}>☕</span>
                }
              </div>

              {/* Info */}
              <div style={{ flex: 1, minWidth: 0 }}>
                <p style={ps.nome}>{p.nome}</p>
                <p style={ps.cat}>{p.categoria}</p>
              </div>

              {/* Price */}
              <span style={ps.preco}>
                R$ {Number(p.preco || 0).toFixed(2).replace('.', ',')}
              </span>

              {/* Disponivel */}
              <div style={ps.toggleGroup}>
                <span style={ps.toggleLabel}>Disponível</span>
                <Toggle
                  checked={!!p.disponivel}
                  onChange={() => toggleField(p, 'disponivel')}
                />
              </div>

              {/* Destaque */}
              <div style={ps.toggleGroup}>
                <span style={ps.toggleLabel}>⭐ Destaque</span>
                <Toggle
                  checked={!!p.destaque}
                  onChange={() => toggleField(p, 'destaque')}
                  color="#FF9800"
                />
              </div>

              {/* Actions */}
              <div style={{ display: 'flex', gap: 8 }}>
                <button style={ps.editBtn} onClick={() => openEdit(p)}>Editar</button>
                <button style={ps.delBtn} onClick={() => openDelete(p)}>✕</button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Modals */}
      {modal === 'add' && (
        <Modal title="Novo produto" onClose={() => setModal(null)}>
          <ProductForm onSave={() => setModal(null)} onClose={() => setModal(null)} />
        </Modal>
      )}

      {modal === 'edit' && selected && (
        <Modal title="Editar produto" onClose={() => setModal(null)}>
          <ProductForm
            initial={selected}
            productId={selected.id}
            onSave={() => { setModal(null); setSelected(null); }}
            onClose={() => setModal(null)}
          />
        </Modal>
      )}

      {modal === 'delete' && selected && (
        <ConfirmModal
          msg={`Deseja excluir "${selected.nome}"? Esta ação não pode ser desfeita.`}
          onConfirm={confirmDelete}
          onClose={() => setModal(null)}
        />
      )}
    </div>
  );
}

const ps = {
  page: { padding: '32px 28px' },
  header: { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 },
  title: { fontSize: 24, fontWeight: 800, color: '#1A1A1A' },
  sub: { fontSize: 13, color: '#9E9E9E' },
  addBtn: { padding: '10px 20px', background: '#C8A96E', color: '#fff', border: 'none', borderRadius: 12, fontWeight: 700, fontSize: 14, cursor: 'pointer', flexShrink: 0 },
  filters: { display: 'flex', flexDirection: 'column', gap: 12, marginBottom: 20 },
  search: { padding: '10px 16px', borderRadius: 12, border: '1.5px solid #EEEEEE', fontSize: 14, outline: 'none', background: '#fff', width: '100%', maxWidth: 360 },
  cats: { display: 'flex', gap: 8, flexWrap: 'wrap' },
  catBtn: { padding: '6px 14px', borderRadius: 20, border: '1.5px solid #EEEEEE', background: '#fff', fontSize: 13, cursor: 'pointer', fontWeight: 500, color: '#9E9E9E' },
  catActive: { background: '#F5F0E8', borderColor: '#C8A96E', color: '#C8A96E', fontWeight: 700 },
  loadingWrap: { display: 'flex', justifyContent: 'center', marginTop: 60 },
  empty: { color: '#9E9E9E', textAlign: 'center', padding: '60px 0', fontSize: 14 },
  list: { display: 'flex', flexDirection: 'column', gap: 8 },
  row: {
    background: '#fff', borderRadius: 14, padding: '12px 16px',
    display: 'flex', alignItems: 'center', gap: 16,
    boxShadow: '0 1px 4px rgba(0,0,0,0.05)',
  },
  imgWrap: {
    width: 48, height: 48, borderRadius: 10, background: '#F5F0E8',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    overflow: 'hidden', flexShrink: 0,
  },
  img: { width: '100%', height: '100%', objectFit: 'cover' },
  nome: { fontSize: 14, fontWeight: 700, color: '#1A1A1A', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' },
  cat: { fontSize: 12, color: '#9E9E9E', marginTop: 2 },
  preco: { fontSize: 14, fontWeight: 800, color: '#C8A96E', flexShrink: 0, minWidth: 80, textAlign: 'right' },
  toggleGroup: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, flexShrink: 0 },
  toggleLabel: { fontSize: 10, color: '#9E9E9E', fontWeight: 500 },
  editBtn: { padding: '6px 14px', borderRadius: 8, border: '1.5px solid #EEEEEE', background: '#fff', fontSize: 12, fontWeight: 600, cursor: 'pointer', color: '#1A1A1A' },
  delBtn: { padding: '6px 10px', borderRadius: 8, border: '1.5px solid #FFEBEE', background: '#FFEBEE', fontSize: 12, fontWeight: 700, cursor: 'pointer', color: '#E53935' },
};
