'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useMemo, useState } from 'react';
import { ArrowDownUp, Columns3, Coffee, Search, Star, Table2, UserPlus } from 'lucide-react';
import { useStore } from '@/data/store';
import {
  PROFILE_STATUSES,
  REGIONS_SELECTABLE,
  REGION_LABEL,
  RELIGIOUS_LABEL,
  RELIGIOUS_LEVELS_GLOBAL,
  maritalLabel,
  profileStatusLabel,
  type Gender,
  type ProfileStatus,
  type Region,
  type ReligiousLevel,
} from '@/domain/enums';
import type { Person } from '@/domain/types';
import { ageOf, fullName, g, phoneToWhatsApp, religiousLabel, suggestionsFor, summaryLine } from '@/domain/logic';
import { Avatar, Button, Chip, Empty, Modal, StatusTag, WhatsAppIcon, cx, genderColor } from '@/components/ui';
import { PersonCardPane, PersonSidePane } from '@/components/person-detail';
import { PersonForm } from '@/components/person-form';
import { useToast } from '@/components/toast';

type View = 'panes' | 'table' | 'think';
type Sort = 'updated' | 'name' | 'age' | 'created';

interface Filters {
  gender: Gender | 'all';
  statuses: ProfileStatus[];
  levels: ReligiousLevel[];
  regions: Region[];
  favorites: boolean;
}

const EMPTY: Filters = { gender: 'all', statuses: [], levels: [], regions: [], favorites: false };

function toggle<T>(arr: T[], v: T): T[] {
  return arr.includes(v) ? arr.filter((x) => x !== v) : [...arr, v];
}

function PeopleScreen() {
  const store = useStore();
  const toast = useToast();
  const router = useRouter();
  const params = useSearchParams();
  const view = (params.get('view') as View) || 'panes';
  const selectedId = params.get('id');
  const sideTab = params.get('tab') === 'suggestions' ? 'suggestions' : 'ideas';
  const [q, setQ] = useState('');
  const [filters, setFilters] = useState<Filters>(EMPTY);
  const [sort, setSort] = useState<Sort>('updated');
  const [showFilters, setShowFilters] = useState(false);
  const [adding, setAdding] = useState(params.get('new') === '1');

  useEffect(() => {
    if (params.get('new') === '1') setAdding(true);
  }, [params]);

  const setParam = (patch: Record<string, string | null>) => {
    const next = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(patch)) {
      if (v == null) next.delete(k);
      else next.set(k, v);
    }
    router.replace(`/people?${next.toString()}`, { scroll: false });
  };

  const list = useMemo(() => {
    const term = q.trim();
    const filtered = store.visiblePeople.filter((p) => {
      if (term && !(fullName(p).includes(term) || (p.city ?? '').includes(term) || (p.description ?? '').includes(term) || p.tags.some((t) => t.includes(term)))) return false;
      if (filters.gender !== 'all' && p.gender !== filters.gender) return false;
      if (filters.statuses.length && !filters.statuses.includes(p.profileStatus)) return false;
      if (filters.levels.length && (!p.religiousLevel || !filters.levels.includes(p.religiousLevel))) return false;
      if (filters.regions.length && (!p.region || !filters.regions.includes(p.region))) return false;
      if (filters.favorites && !p.isFavorite) return false;
      return true;
    });
    const by: Record<Sort, (a: Person, b: Person) => number> = {
      updated: (a, b) => b.updatedAt.localeCompare(a.updatedAt),
      created: (a, b) => b.createdAt.localeCompare(a.createdAt),
      name: (a, b) => fullName(a).localeCompare(fullName(b), 'he'),
      age: (a, b) => (ageOf(a) ?? 999) - (ageOf(b) ?? 999),
    };
    return filtered.sort(by[sort]);
  }, [store.visiblePeople, q, filters, sort]);

  const selected = selectedId ? store.byId.get(selectedId) : undefined;
  useEffect(() => {
    if (view === 'panes' && !selectedId && list[0]) setParam({ id: list[0].id });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, selectedId, list.length]);

  const activeFilters = (filters.gender !== 'all' ? 1 : 0) + filters.statuses.length + filters.levels.length + filters.regions.length + (filters.favorites ? 1 : 0);

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center gap-3 border-b border-outline px-6 py-4">
        <h1 className="text-[22px] font-extrabold text-heading">המאגר שלי</h1>
        <span className="rounded-full bg-oat px-2.5 py-0.5 text-[13px] font-bold text-muted">{list.length.toLocaleString('he-IL')}</span>
        <div className="relative ms-2 w-[300px]">
          <Search size={16} className="pointer-events-none absolute start-3 top-1/2 -translate-y-1/2 text-muted" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="חיפוש לפי שם, עיר, תגית או טקסט בכרטיס"
            className="h-10 w-full rounded-xl border border-outline bg-page ps-9 pe-3 text-[14px] outline-none focus:border-primary"
          />
        </div>
        <Button onClick={() => setShowFilters((s) => !s)} className={cx(activeFilters > 0 && '!border-primary !bg-primary-light')}>
          סינון{activeFilters > 0 && ` · ${activeFilters}`}
        </Button>
        <label className="flex items-center gap-1.5 text-[13px] text-muted">
          <ArrowDownUp size={15} />
          <select value={sort} onChange={(e) => setSort(e.target.value as Sort)} className="h-10 rounded-xl border border-outline bg-page px-2 text-[14px] text-body outline-none">
            <option value="updated">עודכנו לאחרונה</option>
            <option value="created">נוספו לאחרונה</option>
            <option value="name">לפי שם</option>
            <option value="age">לפי גיל</option>
          </select>
        </label>

        <div className="ms-auto flex items-center gap-2">
          <div className="flex rounded-xl border border-outline bg-page p-0.5">
            {(
              [
                ['panes', <Columns3 key="p" size={16} />, 'כרטיס'],
                ['table', <Table2 key="t" size={16} />, 'טבלה'],
                ['think', <Coffee key="c" size={16} />, 'עוצרים לחשוב'],
              ] as const
            ).map(([v, icon, label]) => (
              <button
                key={v}
                onClick={() => setParam({ view: v === 'panes' ? null : v })}
                className={cx('flex h-9 items-center gap-1.5 rounded-lg px-3 text-[13px]', view === v ? 'bg-primary-light font-bold text-heading' : 'text-muted hover:bg-oat')}
              >
                {icon}
                {label}
              </button>
            ))}
          </div>
          <Button variant="primary" onClick={() => setAdding(true)}>
            <UserPlus size={16} /> הוספת חבר
          </Button>
        </div>
      </header>

      {showFilters && (
        <div className="fade-up flex flex-wrap items-start gap-x-8 gap-y-3 border-b border-outline bg-cream/60 px-6 py-4">
          <FilterGroup label="מגדר">
            {(['all', 'male', 'female'] as const).map((gv) => (
              <Chip key={gv} active={filters.gender === gv} onClick={() => setFilters((f) => ({ ...f, gender: gv }))}>
                {gv === 'all' ? 'הכל' : gv === 'male' ? 'בחורים' : 'בחורות'}
              </Chip>
            ))}
          </FilterGroup>
          <FilterGroup label="סטטוס">
            {PROFILE_STATUSES.map((s) => (
              <Chip key={s} active={filters.statuses.includes(s)} onClick={() => setFilters((f) => ({ ...f, statuses: toggle(f.statuses, s) }))}>
                {profileStatusLabel(s, 'male')}
              </Chip>
            ))}
          </FilterGroup>
          <FilterGroup label="סגנון דתי">
            {RELIGIOUS_LEVELS_GLOBAL.map((l) => (
              <Chip key={l} active={filters.levels.includes(l)} onClick={() => setFilters((f) => ({ ...f, levels: toggle(f.levels, l) }))}>
                {RELIGIOUS_LABEL[l]}
              </Chip>
            ))}
          </FilterGroup>
          <FilterGroup label="אזור">
            {REGIONS_SELECTABLE.map((r) => (
              <Chip key={r} active={filters.regions.includes(r)} onClick={() => setFilters((f) => ({ ...f, regions: toggle(f.regions, r) }))}>
                {REGION_LABEL[r]}
              </Chip>
            ))}
          </FilterGroup>
          <FilterGroup label="עוד">
            <Chip active={filters.favorites} onClick={() => setFilters((f) => ({ ...f, favorites: !f.favorites }))}>
              <Star size={13} /> מועדפים
            </Chip>
          </FilterGroup>
          {activeFilters > 0 && (
            <button className="self-end text-[13px] font-semibold text-copper-ink hover:underline" onClick={() => setFilters(EMPTY)}>
              ניקוי הסינון
            </button>
          )}
        </div>
      )}

      <div className="min-h-0 flex-1">
        {view === 'panes' && (
          <div className="grid h-full grid-cols-[300px_minmax(0,1fr)_340px] gap-0">
            <div className="min-h-0 overflow-y-auto border-l border-outline scroll-thin">
              {list.length === 0 && <Empty title="לא נמצאו חברים">נסו לשנות את החיפוש או הסינון</Empty>}
              {list.map((p) => (
                <button
                  key={p.id}
                  onClick={() => setParam({ id: p.id })}
                  className={cx('flex w-full items-center gap-3 border-b border-outline/60 px-4 py-3 text-start transition', p.id === selectedId ? 'bg-primary-light/70' : 'hover:bg-oat/70')}
                >
                  <Avatar person={p} size={40} />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-1.5">
                      <span className="truncate text-[15px] font-bold" style={{ color: genderColor(p.gender) }}>
                        {fullName(p)}
                      </span>
                      {p.isFavorite && <Star size={12} className="shrink-0 fill-copper text-copper" />}
                    </div>
                    <div className="truncate text-[12px] text-muted">{summaryLine(p)}</div>
                  </div>
                  <StatusTag status={p.profileStatus} gender={p.gender} className="!text-[12px]" />
                </button>
              ))}
            </div>
            <div className="min-h-0 overflow-y-auto p-6 scroll-thin">
              {selected ? (
                <PersonCardPane person={selected} onOpenSuggestions={() => setParam({ tab: 'suggestions' })} onDeleted={() => setParam({ id: null })} />
              ) : (
                <Empty title="בחרו חבר מהרשימה" />
              )}
            </div>
            <div className="min-h-0 border-r border-outline p-4">
              {selected && <PersonSidePane person={selected} tab={sideTab} onTab={(t) => setParam({ tab: t === 'ideas' ? null : t })} />}
            </div>
          </div>
        )}

        {view === 'table' && <PeopleTable people={list} onOpen={(id) => setParam({ view: null, id })} />}
        {view === 'think' && <ThinkView people={list} onOpen={(id, tab) => setParam({ view: null, id, tab: tab ?? null })} />}
      </div>

      <Modal open={adding} onClose={() => { setAdding(false); setParam({ new: null }); }} title="הוספת חבר למאגר" width={680}>
        <PersonForm
          onCancel={() => {
            setAdding(false);
            setParam({ new: null });
          }}
          onSave={(d) => {
            const p = store.addPerson({ ...d, manualAgeUpdatedAt: new Date().toISOString() });
            setAdding(false);
            if (!p) return;
            setParam({ new: null, id: p.id, view: null });
            toast(g('{נוסף|נוספה} למאגר!', p.gender), { label: 'לראות התאמות', run: () => setParam({ id: p.id, tab: 'suggestions', new: null }) });
          }}
        />
      </Modal>
    </div>
  );
}

function FilterGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="mb-1.5 text-[12px] font-bold text-muted">{label}</div>
      <div className="flex flex-wrap gap-1.5">{children}</div>
    </div>
  );
}

type Col = 'name' | 'age' | 'level' | 'city' | 'height' | 'marital' | 'status' | 'updated';

function PeopleTable({ people, onOpen }: { people: Person[]; onOpen: (id: string) => void }) {
  const toast = useToast();
  const [checked, setChecked] = useState<string[]>([]);
  const [col, setCol] = useState<Col>('updated');
  const [asc, setAsc] = useState(false);

  const value = (p: Person, c: Col): string | number => {
    switch (c) {
      case 'name':
        return fullName(p);
      case 'age':
        return ageOf(p) ?? 999;
      case 'level':
        return religiousLabel(p) ?? 'ת';
      case 'city':
        return p.city ?? 'ת';
      case 'height':
        return p.heightCm ?? 999;
      case 'marital':
        return p.maritalStatus ?? 'z';
      case 'status':
        return p.profileStatus;
      case 'updated':
        return p.updatedAt;
    }
  };
  const rows = [...people].sort((a, b) => {
    const va = value(a, col);
    const vb = value(b, col);
    const r = typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb), 'he');
    return asc ? r : -r;
  });

  const head = (c: Col, label: string) => (
    <th className="sticky top-0 z-10 bg-cream px-3 py-2.5 text-start text-[13px] font-bold text-muted">
      <button
        className={cx('hover:text-heading', col === c && 'text-heading')}
        onClick={() => {
          if (col === c) setAsc(!asc);
          else {
            setCol(c);
            setAsc(c !== 'updated');
          }
        }}
      >
        {label}
        {col === c && (asc ? ' ↑' : ' ↓')}
      </button>
    </th>
  );

  const all = rows.length > 0 && checked.length === rows.length;
  return (
    <div className="flex h-full flex-col">
      {checked.length > 0 && (
        <div className="fade-up flex items-center gap-3 border-b border-outline bg-primary-light/60 px-6 py-2.5 text-[14px]">
          <span className="font-bold text-heading">נבחרו {checked.length}</span>
          <Button size="sm" onClick={() => toast(`${checked.length} בקשות פרטים יפתחו בוואטסאפ אחת אחרי השנייה`)}>
            <WhatsAppIcon size={14} /> בקשת פרטים בוואטסאפ
          </Button>
          <Button size="sm" variant="ghost" onClick={() => setChecked([])}>
            ניקוי הבחירה
          </Button>
        </div>
      )}
      <div className="min-h-0 flex-1 overflow-auto scroll-thin">
        <table className="w-full border-collapse">
          <thead>
            <tr className="border-b border-outline">
              <th className="sticky top-0 z-10 w-10 bg-cream px-3">
                <input type="checkbox" checked={all} onChange={() => setChecked(all ? [] : rows.map((r) => r.id))} aria-label="בחירת הכל" />
              </th>
              {head('name', 'שם')}
              {head('age', 'גיל')}
              {head('level', 'סגנון דתי')}
              {head('city', 'עיר')}
              {head('height', 'גובה')}
              {head('marital', 'מצב משפחתי')}
              {head('status', 'סטטוס')}
              <th className="sticky top-0 z-10 bg-cream px-3 py-2.5 text-start text-[13px] font-bold text-muted">טלפון</th>
              {head('updated', 'עודכן')}
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => {
              const wa = phoneToWhatsApp(p.phone);
              return (
                <tr key={p.id} className={cx('border-b border-outline/60 hover:bg-oat/60', checked.includes(p.id) && 'bg-primary-light/40')}>
                  <td className="px-3">
                    <input type="checkbox" checked={checked.includes(p.id)} onChange={() => setChecked((c) => toggle(c, p.id))} aria-label={`בחירת ${fullName(p)}`} />
                  </td>
                  <td className="px-3 py-2">
                    <button onClick={() => onOpen(p.id)} className="flex items-center gap-2.5 text-start">
                      <Avatar person={p} size={30} ring={false} />
                      <span className="font-bold hover:underline" style={{ color: genderColor(p.gender) }}>
                        {fullName(p)}
                      </span>
                    </button>
                  </td>
                  <td className="px-3 text-[14px]">{ageOf(p) ?? '—'}</td>
                  <td className="px-3 text-[14px]">{religiousLabel(p) ?? '—'}</td>
                  <td className="px-3 text-[14px]">{p.city ?? '—'}</td>
                  <td className="px-3 text-[14px]">{p.heightCm ?? '—'}</td>
                  <td className="px-3 text-[14px]">{p.maritalStatus ? maritalLabel(p.maritalStatus, p.gender) : '—'}</td>
                  <td className="px-3">
                    <StatusTag status={p.profileStatus} gender={p.gender} />
                  </td>
                  <td className="px-3 text-[14px]">
                    {wa ? (
                      <a href={`https://wa.me/${wa}`} target="_blank" rel="noreferrer" dir="ltr" className="inline-flex items-center gap-1 text-[#1a8f4b] hover:underline">
                        <WhatsAppIcon size={13} /> {p.phone}
                      </a>
                    ) : (
                      '—'
                    )}
                  </td>
                  <td className="px-3 text-[13px] text-muted">{new Date(p.updatedAt).toLocaleDateString('he-IL')}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/** "עוצרים רגע לחשוב על חברים" — ten free friends, three matches each. */
function ThinkView({ people, onOpen }: { people: Person[]; onOpen: (id: string, tab?: 'suggestions') => void }) {
  const store = useStore();
  const [offset, setOffset] = useState(0);
  const free = people.filter((p) => p.profileStatus === 'available');
  const page = free.slice(offset, offset + 10);
  return (
    <div className="mx-auto max-w-[920px] overflow-y-auto px-6 py-6">
      <h2 className="text-center text-[20px] font-extrabold text-heading">עוצרים רגע לחשוב על חברים</h2>
      <p className="mb-6 text-center text-[14px] text-muted">{g('חברים שלך שישמחו {שתחשוב|שתחשבי} עליהם', store.db.profile.gender)}</p>
      <div className="flex flex-col gap-3">
        {page.map((p) => {
          const top = suggestionsFor(p, store.visiblePeople, store.db.matches).slice(0, 3);
          return (
            <div key={p.id} className="card flex items-center gap-4 p-4">
              <button onClick={() => onOpen(p.id)} className="flex w-[220px] items-center gap-3 text-start">
                <Avatar person={p} size={48} />
                <div className="min-w-0">
                  <div className="truncate text-[16px] font-bold" style={{ color: genderColor(p.gender) }}>
                    {fullName(p)}
                  </div>
                  <div className="truncate text-[12px] text-muted">{summaryLine(p)}</div>
                </div>
              </button>
              <div className="flex flex-1 items-center gap-2">
                {top.length === 0 && <span className="text-[13px] text-muted">אין כרגע התאמות</span>}
                {top.map((c) => (
                  <button key={c.id} onClick={() => onOpen(c.id)} className="flex items-center gap-2 rounded-full border border-outline bg-page py-1 ps-1 pe-3 hover:border-primary">
                    <Avatar person={c} size={28} ring={false} />
                    <span className="text-[13px] font-semibold" style={{ color: genderColor(c.gender) }}>
                      {c.firstName}
                    </span>
                  </button>
                ))}
              </div>
              <Button size="sm" variant="ghost" onClick={() => onOpen(p.id, 'suggestions')}>
                לכל ההתאמות
              </Button>
            </div>
          );
        })}
      </div>
      {free.length > offset + 10 && (
        <div className="mt-5 text-center">
          <Button onClick={() => setOffset((o) => o + 10)}>חברים נוספים</Button>
        </div>
      )}
    </div>
  );
}

export default function PeoplePage() {
  return (
    <Suspense>
      <PeopleScreen />
    </Suspense>
  );
}
