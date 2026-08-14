import { useState } from 'react';
import { signOut } from 'firebase/auth';
import { auth } from './firebase';
import Dashboard from './Dashboard';
import Cardapio from './Cardapio';
import Parceiros from './Parceiros';
import Combos from './Combos';

const NAV = [
  { key: 'dashboard', label: 'Dashboard', icon: <GridIcon /> },
  { key: 'cardapio',  label: 'Cardápio',  icon: <MenuIcon /> },
  { key: 'parceiros', label: 'Parceiros', icon: <StoreIcon /> },
  { key: 'combos',    label: 'Combos',    icon: <GiftIcon /> },
];

const PAGES = { dashboard: Dashboard, cardapio: Cardapio, parceiros: Parceiros, combos: Combos };

export default function Layout() {
  const [page, setPage] = useState('dashboard');
  const Page = PAGES[page];

  return (
    <div style={s.shell}>
      {/* Sidebar */}
      <aside style={s.sidebar}>
        <div style={s.sideTop}>
          <div style={s.logoBadge}><CoffeeIcon /></div>
          <span style={s.brand}>caffeto</span>
          <span style={s.adminTag}>Admin</span>
        </div>

        <nav style={s.nav}>
          {NAV.map(item => (
            <button
              key={item.key}
              style={{ ...s.navBtn, ...(page === item.key ? s.navActive : {}) }}
              onClick={() => setPage(item.key)}
            >
              <span style={{ ...s.navIcon, color: page === item.key ? '#C8A96E' : '#9E9E9E' }}>
                {item.icon}
              </span>
              <span style={{ color: page === item.key ? '#1A1A1A' : '#9E9E9E', fontWeight: page === item.key ? 700 : 500 }}>
                {item.label}
              </span>
            </button>
          ))}
        </nav>

        <button style={s.logoutBtn} onClick={() => signOut(auth)}>
          <LogoutIcon />
          Sair
        </button>
      </aside>

      {/* Content */}
      <main style={s.content}>
        <Page />
      </main>
    </div>
  );
}

// ─── Icons ─────────────────────────────────────────────────────────────────

function CoffeeIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path d="M17 8h1a4 4 0 0 1 0 8h-1M3 8h14v9a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V8z"
        stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M6 2v2M10 2v2M14 2v2" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function GridIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
      <rect x="3" y="3" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="2" />
      <rect x="14" y="3" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="2" />
      <rect x="3" y="14" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="2" />
      <rect x="14" y="14" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="2" />
    </svg>
  );
}

function MenuIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
      <path d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 5a2 2 0 0 0 2 2h2a2 2 0 0 0 2-2M9 5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2"
        stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function StoreIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
      <path d="M9 22V12h6v10" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
    </svg>
  );
}

function GiftIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
      <rect x="3" y="8" width="18" height="13" rx="2" stroke="currentColor" strokeWidth="2" />
      <path d="M21 8H3M12 8V21M12 8S8 8 8 5s4-3 4 0c0-3 4-3 4 0s-4 3-4 3z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function LogoutIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

// ─── Styles ────────────────────────────────────────────────────────────────

const s = {
  shell: { display: 'flex', minHeight: '100vh' },
  sidebar: {
    width: 220, background: '#fff', borderRight: '1px solid #EEEEEE',
    display: 'flex', flexDirection: 'column', padding: '24px 16px',
    position: 'sticky', top: 0, height: '100vh', flexShrink: 0,
  },
  sideTop: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, marginBottom: 32 },
  logoBadge: { width: 48, height: 48, background: '#C8A96E', borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center' },
  brand: { fontSize: 18, fontWeight: 800, color: '#1A1A1A', letterSpacing: '-0.3px' },
  adminTag: { fontSize: 11, color: '#9E9E9E', background: '#F5F0E8', padding: '2px 10px', borderRadius: 20, fontWeight: 500 },
  nav: { display: 'flex', flexDirection: 'column', gap: 4, flex: 1 },
  navBtn: {
    display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px',
    borderRadius: 12, border: 'none', background: 'transparent',
    cursor: 'pointer', width: '100%', textAlign: 'left', fontSize: 14, transition: 'background 0.15s',
  },
  navActive: { background: '#F5F0E8' },
  navIcon: { display: 'flex', flexShrink: 0 },
  logoutBtn: {
    display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px',
    borderRadius: 12, border: '1.5px solid #EEEEEE', background: 'transparent',
    cursor: 'pointer', color: '#9E9E9E', fontSize: 13, fontWeight: 600,
  },
  content: { flex: 1, overflow: 'auto', background: '#F5F0E8', minHeight: '100vh' },
};
