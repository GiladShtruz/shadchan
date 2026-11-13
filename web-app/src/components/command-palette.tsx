'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Lightbulb, Plus, Search, UserPlus, Bell, Trophy } from 'lucide-react';
import { useStore } from '@/data/store';
import { fullName, sidesOf, summaryLine } from '@/domain/logic';
import { MATCH_STATE_LABEL } from '@/domain/enums';
import { Avatar, cx } from './ui';

interface Item {
  key: string;
  group: 'אנשים' | 'רעיונות' | 'פעולות';
  label: string;
  hint?: string;
  icon: React.ReactNode;
  run: () => void;
}

/** ⌘K — one search over people, ideas and actions, grouped. */
export function CommandPalette({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { visiblePeople, db, byId } = useStore();
  const router = useRouter();
  const [q, setQ] = useState('');
  const [index, setIndex] = useState(0);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setQ('');
      setIndex(0);
      setTimeout(() => input.current?.focus(), 0);
    }
  }, [open]);

  const items = useMemo<Item[]>(() => {
    const term = q.trim();
    const go = (href: string) => () => {
      router.push(href);
      onClose();
    };
    const actions: Item[] = ([
      { key: 'a-add', group: 'פעולות', label: 'הוספת חבר למאגר', icon: <UserPlus size={17} />, run: go('/people?new=1') },
      { key: 'a-idea', group: 'פעולות', label: 'פתיחת רעיון חדש', icon: <Plus size={17} />, run: go('/ideas?new=1') },
      { key: 'a-notif', group: 'פעולות', label: 'התראות', icon: <Bell size={17} />, run: go('/notifications') },
      { key: 'a-comm', group: 'פעולות', label: 'פעילות וקהילה', icon: <Trophy size={17} />, run: go('/community') },
    ] as Item[]).filter((a) => !term || a.label.includes(term));
    if (!term) return actions;
    const people: Item[] = visiblePeople
      .filter((p) => fullName(p).includes(term) || (p.city ?? '').includes(term) || (p.phone ?? '').replace(/\D/g, '').includes(term.replace(/\D/g, '') || '§'))
      .slice(0, 8)
      .map((p) => ({
        key: `p-${p.id}`,
        group: 'אנשים',
        label: fullName(p),
        hint: summaryLine(p),
        icon: <Avatar person={p} size={26} ring={false} />,
        run: go(`/people?id=${p.id}`),
      }));
    const ideas: Item[] = db.matches
      .map((m) => ({ m, s: sidesOf(m, byId) }))
      .filter(({ s }) => (s.male && fullName(s.male).includes(term)) || (s.female && fullName(s.female).includes(term)))
      .slice(0, 6)
      .map(({ m, s }) => ({
        key: `m-${m.id}`,
        group: 'רעיונות',
        label: `${s.male?.firstName ?? '?'} & ${s.female?.firstName ?? '?'}`,
        hint: MATCH_STATE_LABEL[m.status],
        icon: <Lightbulb size={17} />,
        run: go(`/ideas?id=${m.id}`),
      }));
    return [...people, ...ideas, ...actions];
  }, [q, visiblePeople, db.matches, byId, router, onClose]);

  if (!open) return null;

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') onClose();
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setIndex((i) => Math.min(items.length - 1, i + 1));
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      setIndex((i) => Math.max(0, i - 1));
    }
    if (e.key === 'Enter') items[index]?.run();
  };

  let lastGroup = '';
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-[rgb(33_29_23/0.25)] pt-[12vh]" onMouseDown={onClose}>
      <div className="fade-up w-full max-w-[600px] overflow-hidden rounded-2xl bg-page shadow-2xl" onMouseDown={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-3 border-b border-outline px-4">
          <Search size={18} className="text-muted" />
          <input
            ref={input}
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setIndex(0);
            }}
            onKeyDown={onKey}
            placeholder="חיפוש חבר, רעיון או פעולה…"
            className="h-14 flex-1 bg-transparent text-[16px] outline-none placeholder:text-muted"
          />
          <span className="kbd">Esc</span>
        </div>
        <div className="max-h-[420px] overflow-y-auto p-2 scroll-thin">
          {items.length === 0 && <p className="px-3 py-8 text-center text-[14px] text-muted">לא נמצאו תוצאות</p>}
          {items.map((it, i) => {
            const header = it.group !== lastGroup;
            lastGroup = it.group;
            return (
              <div key={it.key}>
                {header && <div className="px-3 pt-3 pb-1 text-[12px] font-bold text-muted">{it.group}</div>}
                <button
                  onMouseEnter={() => setIndex(i)}
                  onClick={it.run}
                  className={cx('flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-start', i === index && 'bg-oat')}
                >
                  <span className="flex w-7 justify-center text-muted">{it.icon}</span>
                  <span className="flex-1 text-[15px] font-semibold text-heading">{it.label}</span>
                  {it.hint && <span className="text-[13px] text-muted">{it.hint}</span>}
                </button>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
