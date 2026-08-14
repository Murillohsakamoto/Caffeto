import { useState } from 'react';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from './firebase';
import { Spinner } from './App';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  async function handleLogin(e) {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      await signInWithEmailAndPassword(auth, email, password);
    } catch (err) {
      const map = {
        'auth/invalid-credential': 'E-mail ou senha incorretos.',
        'auth/user-not-found': 'Usuário não encontrado.',
        'auth/wrong-password': 'Senha incorreta.',
        'auth/too-many-requests': 'Muitas tentativas. Tente novamente mais tarde.',
      };
      setError(map[err.code] || 'Erro ao entrar. Tente novamente.');
      setLoading(false);
    }
  }

  return (
    <div style={s.page}>
      <div style={s.card}>
        <div style={s.logoWrap}>
          <div style={s.badge}><CoffeeIcon /></div>
          <span style={s.brand}>caffeto</span>
          <span style={s.role}>Painel Admin</span>
        </div>
        <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column' }}>
          <label style={s.label}>E-mail</label>
          <input style={s.input} type="email" placeholder="seu@email.com"
            value={email} onChange={e => setEmail(e.target.value)} required />
          <label style={{ ...s.label, marginTop: 16 }}>Senha</label>
          <input style={s.input} type="password" placeholder="••••••••"
            value={password} onChange={e => setPassword(e.target.value)} required />
          {error && <p style={s.error}>{error}</p>}
          <button style={s.btn} type="submit" disabled={loading}>
            {loading ? <Spinner size={20} color="#fff" /> : 'Entrar no painel'}
          </button>
        </form>
      </div>
    </div>
  );
}

function CoffeeIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none">
      <path d="M17 8h1a4 4 0 0 1 0 8h-1M3 8h14v9a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V8z"
        stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M6 2v2M10 2v2M14 2v2" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

const s = {
  page: { minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#F5F0E8', padding: 16 },
  card: { background: '#fff', borderRadius: 24, padding: '40px 32px 36px', width: '100%', maxWidth: 380, boxShadow: '0 8px 40px rgba(0,0,0,0.10)' },
  logoWrap: { display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 32, gap: 8 },
  badge: { width: 64, height: 64, background: '#C8A96E', borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center' },
  brand: { fontSize: 24, fontWeight: 800, color: '#1A1A1A', letterSpacing: '-0.5px' },
  role: { fontSize: 13, color: '#9E9E9E', fontWeight: 500, background: '#F5F0E8', padding: '3px 12px', borderRadius: 20 },
  label: { fontSize: 13, fontWeight: 600, color: '#1A1A1A', marginBottom: 6 },
  input: { padding: '12px 14px', borderRadius: 12, border: '1.5px solid #EEEEEE', fontSize: 14, color: '#1A1A1A', outline: 'none', background: '#FAFAFA' },
  error: { marginTop: 12, fontSize: 13, color: '#E53935', textAlign: 'center', fontWeight: 500 },
  btn: { marginTop: 24, padding: 14, background: '#C8A96E', color: '#fff', border: 'none', borderRadius: 14, fontSize: 15, fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 },
};
