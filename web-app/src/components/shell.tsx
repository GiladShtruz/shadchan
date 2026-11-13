'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import {
  Bell,
  Home,
  Lightbulb,
  LogOut,
  Search,
  Settings,
  Trophy,
  UserRound,
  Users,
  ArrowLeftRight,
  ShieldCheck,
  IdCard,
} from 'lucide-react';
import { useStore } from '@/data/store';
import { g } from '@/domain/logic';
import { cx } from './ui';
import { CommandPalette } from './command-palette';

interface NavItem {
  href: string;
  label: string;
  icon: ReactNode;
  badge?: number;
  exact?: boolean;
}

export function AppShell({ children }: { children: ReactNode }) {
  const { session, db, unreadCount, signOut, personal } = useStore();
  const router = useRouter();
  const pathname = usePathname();
  const [paletteOpen, setPaletteOpen] = useState(false);
  const personalArea = pathname.startsWith('/me');

  useEffect(() => {
    if (!session.signedIn) router.replace('/login');
  }, [session.signedIn, router]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k' && !window.location.pathname.startsWith('/me')) {
        e.preventDefault();
        setPaletteOpen((o) => !o);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  if (!session.signedIn) return null;

  const pending = personal.access.filter((a) => a.status === 'pending').length;
  const nav: NavItem[] = personalArea
    ? [
        { href: '/me', label: 'בית', icon: <Home size={19} />, exact: true },
        { href: '/me/card', label: 'הכרטיס שלי', icon: <IdCard size={19} /> },
        { href: '/me/matchmakers', label: 'השדכנים שלי', icon: <ShieldCheck size={19} />, badge: pending },
      ]
    : [
        { href: '/', label: 'בית', icon: <Home size={19} />, exact: true },
        { href: '/people', label: 'המאגר שלי', icon: <Users size={19} /> },
        { href: '/ideas', label: 'הרעיונות שלי', icon: <Lightbulb size={19} /> },
        { href: '/notifications', label: 'התראות', icon: <Bell size={19} />, badge: unreadCount },
        { href: '/community', label: 'פעילות וקהילה', icon: <Trophy size={19} /> },
        { href: '/settings', label: 'הגדרות', icon: <Settings size={19} /> },
      ];

  const isActive = (item: NavItem) => (item.exact ? pathname === item.href : pathname.startsWith(item.href));
  const name = `${db.profile.firstName} ${db.profile.lastName}`;

  return (
    <div className="flex h-dvh overflow-hidden bg-page">
      <aside className="flex w-[244px] shrink-0 flex-col border-l border-outline bg-cream/60">
        <div className="flex items-center gap-2.5 px-5 pt-5 pb-4">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo-mark.png" alt="" className="h-6 w-6" />
          </span>
          <div className="leading-tight">
            <div className="text-[20px] font-extrabold text-heading">שדכן</div>
            <div className="text-[12px] text-muted">{personalArea ? 'האזור האישי' : g('אזור {השדכן|השדכנית}', db.profile.gender)}</div>
          </div>
        </div>

        {!personalArea && (
        <button
          onClick={() => setPaletteOpen(true)}
          className="mx-4 mb-4 flex h-10 items-center gap-2 rounded-xl border border-outline bg-page px-3 text-[14px] text-muted hover:border-primary"
        >
          <Search size={16} />
          <span className="flex-1 text-start">חיפוש בכל המאגר…</span>
          <span className="kbd">Ctrl K</span>
        </button>
        )}

        <nav className="flex flex-col gap-0.5 px-3">
          {nav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={cx(
                'flex h-11 items-center gap-3 rounded-xl px-3 text-[15px] transition',
                isActive(item) ? 'bg-primary-light font-bold text-heading' : 'text-body hover:bg-oat',
              )}
            >
              <span className={isActive(item) ? 'text-male' : 'text-muted'}>{item.icon}</span>
              <span className="flex-1">{item.label}</span>
              {!!item.badge && (
                <span className="min-w-[22px] rounded-full bg-copper px-1.5 text-center text-[12px] font-bold leading-[20px] text-white">
                  {item.badge}
                </span>
              )}
            </Link>
          ))}
        </nav>

        <div className="mx-4 mt-5">
          <Link
            href={personalArea ? '/' : '/me'}
            className="flex items-center gap-2.5 rounded-xl border border-outline bg-page px-3 py-2.5 text-[14px] font-semibold text-copper-ink hover:border-copper"
          >
            <ArrowLeftRight size={16} />
            {personalArea ? g('למעבר לאזור {השדכן|השדכנית}', db.profile.gender) : 'למעבר לאזור האישי'}
          </Link>
        </div>

        <div className="mt-auto border-t border-outline px-4 py-4">
          <div className="flex items-center gap-2.5">
            <span className="flex h-9 w-9 items-center justify-center rounded-full bg-female-soft text-female">
              <UserRound size={18} />
            </span>
            <div className="min-w-0 flex-1 leading-tight">
              <div className="truncate text-[14px] font-bold text-heading">{name}</div>
              <div className="truncate text-[12px] text-muted">
                {session.method === 'demo' ? 'חשבון לדוגמה' : session.email ?? 'מחובר'}
              </div>
            </div>
            <button
              aria-label="התנתקות"
              title="התנתקות"
              onClick={() => {
                signOut();
                router.replace('/login');
              }}
              className="rounded-lg p-2 text-muted hover:bg-oat"
            >
              <LogOut size={17} />
            </button>
          </div>
          <div className="mt-3 flex items-center gap-1.5 text-[12px] text-muted">
            <span className="h-2 w-2 rounded-full bg-[#5f9a5b]" />
            {session.method === 'demo' ? 'נתוני דוגמה · השינויים לא נשמרים' : 'מסונכרן עם האפליקציה'}
          </div>
        </div>
      </aside>

      <main className="min-w-0 flex-1 overflow-y-auto scroll-thin">{children}</main>

      <CommandPalette open={paletteOpen} onClose={() => setPaletteOpen(false)} />
    </div>
  );
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="flex flex-wrap items-end justify-between gap-4 px-8 pt-7 pb-5">
      <div>
        <h1 className="text-[26px] font-extrabold text-heading">{title}</h1>
        {subtitle && <p className="mt-1 text-[14px] text-muted">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </header>
  );
}

