import { useEffect, useState } from 'react';
import { onAuthStateChanged } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import Login from './Login';
import Layout from './Layout';

export function Spinner({ size = 32, color = '#C8A96E' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      style={{ animation: 'spin 0.8s linear infinite' }}>
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
      <circle cx="12" cy="12" r="10" stroke={color} strokeWidth="3" strokeOpacity="0.2" />
      <path d="M12 2a10 10 0 0 1 10 10" stroke={color} strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

export default function App() {
  const [state, setState] = useState('loading');

  useEffect(() => {
    return onAuthStateChanged(auth, async (user) => {
      if (!user) { setState('login'); return; }
      try {
        const snap = await getDoc(doc(db, 'usuarios', user.uid));
        setState(snap.exists() && snap.data().master === true ? 'admin' : 'denied');
      } catch {
        setState('denied');
      }
    });
  }, []);

  if (state === 'loading') {
    return (
      <div style={s.center}>
        <Spinner size={40} />
      </div>
    );
  }

  if (state === 'denied') {
    return (
      <div style={s.center}>
        <div style={s.deniedBox}>
          <span style={{ fontSize: 48 }}>🔒</span>
          <p style={{ fontSize: 18, fontWeight: 700, marginTop: 16 }}>Acesso restrito</p>
          <p style={{ fontSize: 14, color: '#9E9E9E', marginTop: 8 }}>Sua conta não tem permissão de administrador.</p>
          <button style={s.logoutBtn} onClick={() => auth.signOut()}>Sair</button>
        </div>
      </div>
    );
  }

  if (state === 'login') return <Login />;
  return <Layout />;
}

const s = {
  center: {
    minHeight: '100vh', display: 'flex', alignItems: 'center',
    justifyContent: 'center', background: '#F5F0E8',
  },
  deniedBox: {
    background: '#fff', borderRadius: 20, padding: '40px 32px',
    textAlign: 'center', boxShadow: '0 4px 24px rgba(0,0,0,0.08)',
    maxWidth: 320, width: '100%',
  },
  logoutBtn: {
    marginTop: 24, padding: '10px 28px', background: '#C8A96E',
    color: '#fff', border: 'none', borderRadius: 24,
    fontWeight: 700, fontSize: 14, cursor: 'pointer',
  },
};
