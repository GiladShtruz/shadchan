'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useMemo, useState } from 'react';
import { BellRing, Heart, HeartCrack, Lightbulb, Plus, Search, Send, Sparkles, Trash2, X } from 'lucide-react';
import { useStore } from '@/data/store';
import type { MatchStatus } from '@/domain/enums';
import type { MatchIdea, Person } from '@/domain/types';
import {
  IDEA_CATEGORY_LABEL,
  ageOf,
  chatTime,
  fullName,
  ideaCategory,
  matchStateColor,
  matchStateWord,
  matchesBasic,
  pausesMatches,
  phoneToWhatsApp,
  proposalTab,
  relativeDays,
  religiousLabel,
  shortDate,
  sidesOf,
  spanLabel,
  stageLabel,
  summaryLine,
  type IdeaCategory,
} from '@/domain/logic';
import { Avatar, Button, Empty, Modal, StatusTag, WhatsAppIcon, cx, genderColor } from '@/components/ui';
import { useToast } from '@/components/toast';

interface Row {
  m: MatchIdea;
  male?: Person;
  female?: Person;
  cat: Exclude<IdeaCategory, 'all'>;
  paused: boolean;
}

const CAT_COLOR: Record<IdeaCategory, string> = {
  all: 'var(--c-heading)',
  open: 'var(--c-male)',
  waiting: 'var(--c-copper)',
  dating: 'var(--c-female)',
  closed: 'var(--c-muted)',
};

function IdeasScreen() {
  const store = useStore();
  const toast = useToast();
  const router = useRouter();
  const params = useSearchParams();
  const selectedId = params.get('id');
  const view = params.get('view');
  const [cat, setCat] = useState<IdeaCategory>((params.get('cat') as IdeaCategory) || 'all');
  const [q, setQ] = useState('');
  const [creating, setCreating] = useState(params.get('new') === '1');

  useEffect(() => {
    if (params.get('new') === '1') setCreating(true);
  }, [params]);

  const setParam = (patch: Record<string, string | null>) => {
    const next = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(patch)) {
      if (v == null) next.delete(k);
      else next.set(k, v);
    }
    router.replace(`/ideas?${next.toString()}`, { scroll: false });
  };

  const rows = useMemo<Row[]>(() => {
    const out: Row[] = [];
    for (const m of store.db.matches) {
      const { male, female } = sidesOf(m, store.byId);
      const tab = proposalTab(m, male, female);
      if (!tab) continue;
      out.push({ m, male, female, cat: ideaCategory(tab), paused: !!((male && pausesMatches(male)) || (female && pausesMatches(female))) });
    }
    const now = Date.now();
    const due = (r: Row) => (r.m.reminderDate && new Date(r.m.reminderDate).getTime() <= now && r.cat !== 'closed' ? 0 : 1);
    return out.sort((a, b) => due(a) - due(b) || b.m.updatedAt.localeCompare(a.m.updatedAt));
  }, [store.db.matches, store.byId]);

  const counts = useMemo(() => {
    const c: Record<IdeaCategory, number> = { all: 0, open: 0, waiting: 0, dating: 0, closed: 0 };
    for (const r of rows) {
      c[r.cat] += 1;
      if (r.cat !== 'closed') c.all += 1;
    }
    return c;
  }, [rows]);

  const shown = rows.filter((r) => {
    if (cat === 'all' ? r.cat === 'closed' : r.cat !== cat) return false;
    const t = q.trim();
    if (!t) return true;
    return (r.male && fullName(r.male).includes(t)) || (r.female && fullName(r.female).includes(t));
  });

  const selected = rows.find((r) => r.m.id === selectedId);

  return (
    <div className="flex h-full flex-col">
      <header className="flex flex-wrap items-center gap-3 border-b border-outline px-6 py-4">
        <h1 className="text-[22px] font-extrabold text-heading">הרעיונות שלי</h1>
        <div className="relative ms-2 w-[280px]">
          <Search size={16} className="pointer-events-none absolute start-3 top-1/2 -translate-y-1/2 text-muted" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="חיפוש לפי שם" className="h-10 w-full rounded-xl border border-outline bg-page ps-9 pe-3 text-[14px] outline-none focus:border-primary" />
        </div>
        <div className="ms-auto flex gap-2">
          <Button onClick={() => setParam({ view: view === 'suggested' ? null : 'suggested', id: null })} className={cx(view === 'suggested' && '!border-primary !bg-primary-light')}>
            <Sparkles size={16} /> רעיונות שהמאגר מציע
          </Button>
          <Button variant="copper" onClick={() => setCreating(true)}>
            <Plus size={16} /> רעיון חדש
          </Button>
        </div>
      </header>

      {view === 'suggested' ? (
        <SuggestedPairs />
      ) : (
        <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_420px]">
          <div className="min-h-0 overflow-y-auto px-6 py-5 scroll-thin">
            <div className="mb-5 grid grid-cols-5 gap-2">
              {(['all', 'open', 'waiting', 'dating', 'closed'] as IdeaCategory[]).map((c) => (
                <button
                  key={c}
                  onClick={() => setCat(c)}
                  className={cx('rounded-2xl border-2 bg-page px-3 py-2.5 text-center transition', cat === c ? 'shadow-sm' : 'border-outline hover:bg-oat')}
                  style={cat === c ? { borderColor: CAT_COLOR[c] } : undefined}
                >
                  <div className="text-[13px] font-bold" style={{ color: CAT_COLOR[c] }}>
                    {IDEA_CATEGORY_LABEL[c]}
                  </div>
                  <div className="text-[22px] font-extrabold text-heading">{counts[c]}</div>
                </button>
              ))}
            </div>

            {shown.length === 0 ? (
              <Empty title={q ? 'לא נמצאו רעיונות' : 'אין כאן רעיונות'}>
                <button className="font-semibold text-copper-ink hover:underline" onClick={() => setCreating(true)}>
                  פתיחת רעיון חדש
                </button>
              </Empty>
            ) : (
              <div className="grid gap-3 2xl:grid-cols-2">
                {shown.map((r) => (
                  <IdeaCard key={r.m.id} row={r} active={r.m.id === selectedId} onClick={() => setParam({ id: r.m.id })} />
                ))}
              </div>
            )}
          </div>
          <div className="min-h-0 border-r border-outline bg-cream/40">
            {selected ? <IdeaPanel row={selected} onClose={() => setParam({ id: null })} /> : <Empty title="בחרו רעיון כדי לראות את הפעולות והיומן" />}
          </div>
        </div>
      )}

      <Modal open={creating} onClose={() => { setCreating(false); setParam({ new: null, with: null }); }} title="רעיון חדש" width={760}>
        <CreateIdea
          initialWith={params.get('with')}
          onDone={(m) => {
            setCreating(false);
            setParam({ new: null, with: null, id: m?.id ?? null, view: null });
            if (m) {
              setCat('all');
              toast('הרעיון נפתח');
            }
          }}
        />
      </Modal>
    </div>
  );
}

function Side({ p, align }: { p?: Person; align: 'start' | 'end' }) {
  if (!p) return <div className="flex-1 text-[13px] text-muted">—</div>;
  return (
    <div className={cx('flex min-w-0 flex-1 items-center gap-2.5', align === 'end' && 'flex-row-reverse text-end')}>
      <Avatar person={p} size={44} />
      <div className="min-w-0">
        <div className="truncate text-[15px] font-bold" style={{ color: genderColor(p.gender) }}>
          {p.firstName} {p.lastName}
        </div>
        <div className="truncate text-[12px] text-muted">{[ageOf(p), religiousLabel(p)].filter(Boolean).join(' · ')}</div>
        <StatusTag status={p.profileStatus} gender={p.gender} className="!text-[11px]" />
      </div>
    </div>
  );
}

function IdeaCard({ row, active, onClick }: { row: Row; active: boolean; onClick: () => void }) {
  const { m, male, female, paused } = row;
  const color = matchStateColor(m.status, paused);
  const due = m.reminderDate && new Date(m.reminderDate) <= new Date() && row.cat !== 'closed';
  return (
    <button
      onClick={onClick}
      className={cx('card relative block w-full overflow-hidden p-4 text-start transition hover:-translate-y-0.5', active && 'ring-2')}
      style={{ ['--tw-ring-color' as string]: color, borderInlineStart: `4px solid ${genderColor('male')}`, borderInlineEnd: `4px solid ${genderColor('female')}` }}
    >
      {due && (
        <span className="absolute top-2 start-2 inline-flex items-center gap-1 rounded-full bg-copper px-2 py-0.5 text-[11px] font-bold text-white">
          <BellRing size={11} /> תזכורת
        </span>
      )}
      <div className="flex items-center gap-2 pt-1">
        <Side p={male} align="start" />
        {m.status === 'dated' ? <HeartCrack size={20} className="shrink-0 text-female" /> : <Heart size={20} className="shrink-0" style={{ color }} fill={m.status === 'dating' || m.status === 'married' ? 'currentColor' : 'none'} />}
        <Side p={female} align="end" />
      </div>
      <div className="mt-3 flex items-center justify-between border-t border-outline pt-2.5 text-[13px]">
        <span className="flex items-center gap-1.5 font-bold" style={{ color }}>
          <span className="h-2 w-2 rounded-full" style={{ background: color }} />
          סטטוס: {matchStateWord(m, paused)}
          {m.waitingReason && row.cat === 'waiting' && <span className="font-normal text-muted">· {m.waitingReason}</span>}
        </span>
        <span className="truncate text-muted">
          {m.status === 'dating' && m.datingStartedAt ? `יוצאים כבר ${spanLabel(m.datingStartedAt)}` : row.cat === 'open' ? stageLabel(m, male, female) : shortDate(m.updatedAt)}
        </span>
      </div>
    </button>
  );
}

const MENU: { status: MatchStatus; label: string; color: string; reason?: string }[] = [
  { status: 'idea', label: 'רעיון פתוח', color: 'var(--c-male)' },
  { status: 'checking', label: 'בבדיקה', color: 'var(--c-male)' },
  { status: 'dating', label: 'מתחילים לצאת', color: 'var(--c-female)' },
  { status: 'unavailable', label: 'העברה להמתנה', color: 'var(--c-copper)' },
  { status: 'rejected', label: 'סגירת רעיון', color: 'var(--c-muted)' },
  { status: 'dated', label: 'נפרדו', color: 'var(--c-muted)' },
  { status: 'married', label: 'מזל טוב! חתונה', color: 'var(--c-dating)' },
];

function IdeaPanel({ row, onClose }: { row: Row; onClose: () => void }) {
  const store = useStore();
  const toast = useToast();
  const { m, male, female } = row;
  const [text, setText] = useState('');
  const [reasonFor, setReasonFor] = useState<MatchStatus | null>(null);
  const [reason, setReason] = useState('');
  const journal = useMemo(() => store.db.matchNotes.filter((n) => n.matchId === m.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)), [store.db.matchNotes, m.id]);

  const ask = (side: 'male' | 'female') => {
    const to = side === 'male' ? male : female;
    const of = side === 'male' ? female : male;
    const wa = phoneToWhatsApp(to?.phone ?? null);
    if (wa && of?.description) window.open(`https://wa.me/${wa}?text=${encodeURIComponent(of.description)}`, '_blank', 'noreferrer');
    else if (wa) window.open(`https://wa.me/${wa}`, '_blank', 'noreferrer');
    store.markAsked(m.id, side);
    toast(`נרשם ביומן: הכרטיס של ${of?.firstName} נשלח ל${to?.firstName}`);
  };

  const choose = (s: MatchStatus) => {
    if (s === 'unavailable' || s === 'rejected') {
      setReasonFor(s);
      setReason('');
      return;
    }
    const before = m.status;
    store.setMatchStatus(m.id, s);
    toast(s === 'married' ? 'מזל טוב! 💍' : 'הסטטוס עודכן', { label: 'ביטול', run: () => store.setMatchStatus(m.id, before) });
  };

  const live = row.cat !== 'closed';
  return (
    <div className="flex h-full flex-col" key={m.id}>
      <div className="flex items-center justify-between border-b border-outline px-5 py-3">
        <div className="text-[16px] font-extrabold text-heading">
          {male?.firstName} & {female?.firstName}
        </div>
        <button aria-label="סגירה" className="rounded-lg p-1.5 text-muted hover:bg-oat" onClick={onClose}>
          <X size={18} />
        </button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4 scroll-thin">
        <div className="grid grid-cols-2 gap-2">
          {[male, female].map((p) =>
            p ? (
              <Link key={p.id} href={`/people?id=${p.id}`} className="card flex flex-col items-center gap-1.5 p-3 text-center hover:bg-oat">
                <Avatar person={p} size={52} />
                <div className="text-[14px] font-bold" style={{ color: genderColor(p.gender) }}>
                  {fullName(p)}
                </div>
                <div className="text-[12px] text-muted">{summaryLine(p)}</div>
              </Link>
            ) : null,
          )}
        </div>

        <div className="mt-4">
          <div className="mb-1.5 text-[12px] font-bold text-muted">סטטוס</div>
          <div className="flex flex-wrap gap-1.5">
            {MENU.map((it) => {
              const current = it.status === m.status;
              return (
                <button
                  key={it.status}
                  onClick={() => !current && choose(it.status)}
                  className={cx('h-8 rounded-full border px-3 text-[13px] font-bold', current ? 'text-white' : 'bg-page hover:bg-oat')}
                  style={current ? { background: it.color, borderColor: it.color } : { color: it.color, borderColor: 'var(--c-outline)' }}
                >
                  {it.label}
                </button>
              );
            })}
          </div>
          {reasonFor && (
            <form
              className="fade-up mt-3 rounded-xl bg-page p-3"
              onSubmit={(e) => {
                e.preventDefault();
                store.setMatchStatus(m.id, reasonFor, reason.trim() || undefined);
                setReasonFor(null);
                toast(reasonFor === 'rejected' ? 'הרעיון עבר לארכיון' : 'הרעיון הועבר להמתנה');
              }}
            >
              <div className="mb-2 text-[13px] font-bold text-heading">{reasonFor === 'rejected' ? 'מה הייתה הסיבה שהרעיון לא התקדם?' : 'למה הרעיון בהמתנה?'}</div>
              <div className="mb-2 flex flex-wrap gap-1.5">
                {(reasonFor === 'rejected' ? [`${male?.firstName} לא רצה`, `${female?.firstName} לא רצתה`, 'שניהם לא רצו'] : [`${male?.firstName} בהפסקה`, `${female?.firstName} בהפסקה`, 'מחכים לתשובה מהמשפחה']).map((r) => (
                  <button type="button" key={r} onClick={() => setReason(r)} className={cx('h-7 rounded-full border px-2.5 text-[12px]', reason === r ? 'border-primary bg-primary-light font-bold' : 'border-outline')}>
                    {r}
                  </button>
                ))}
              </div>
              <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="או במילים שלך…" className="h-9 w-full rounded-lg border border-outline px-3 text-[13px] outline-none focus:border-primary" />
              <div className="mt-2 flex justify-end gap-2">
                <Button size="sm" type="button" onClick={() => setReasonFor(null)}>
                  ביטול
                </Button>
                <Button size="sm" variant="primary" type="submit">
                  אישור
                </Button>
              </div>
            </form>
          )}
        </div>

        {live && (
          <div className="mt-4 rounded-2xl border border-outline bg-page p-4">
            <div className="text-[15px] font-extrabold text-heading">יאללה לקדם</div>
            <div className="mb-3 text-[13px] text-muted">{stageLabel(m, male, female)}</div>
            <div className="grid grid-cols-2 gap-2">
              {(['male', 'female'] as const).map((side) => {
                const p = side === 'male' ? male : female;
                const done = side === 'male' ? m.askedMaleAt : m.askedFemaleAt;
                return (
                  <button
                    key={side}
                    onClick={() => ask(side)}
                    className="flex h-11 items-center justify-center gap-2 rounded-xl border border-outline text-[14px] font-bold hover:bg-oat"
                    style={{ color: genderColor(p?.gender) }}
                  >
                    <WhatsAppIcon size={15} /> {done ? `${p?.firstName} ✓` : `לשאול את ${p?.firstName}`}
                  </button>
                );
              })}
            </div>
            <div className="mt-3 flex items-center justify-between border-t border-outline pt-3 text-[13px]">
              <span className="flex items-center gap-1.5 text-muted">
                <BellRing size={14} />
                {m.reminderDate ? `תזכורת ב־${shortDate(m.reminderDate)} (${relativeDays(m.reminderDate)})` : 'אין תזכורת'}
              </span>
              <div className="flex gap-1">
                {[7, 30].map((d) => (
                  <button
                    key={d}
                    className="rounded-lg px-2 py-1 font-semibold text-copper-ink hover:bg-oat"
                    onClick={() => {
                      store.setReminder(m.id, new Date(Date.now() + d * 86400000).toISOString());
                      toast(`תזכורת נקבעה ${d === 7 ? 'לעוד שבוע' : 'לעוד חודש'}`);
                    }}
                  >
                    {d === 7 ? 'עוד שבוע' : 'עוד חודש'}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        <div className="mt-5">
          <div className="mb-2 text-[15px] font-extrabold text-heading">יומן הרעיון</div>
          <form
            className="mb-3 flex gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              if (!text.trim()) return;
              store.addMatchNote(m.id, text.trim());
              setText('');
            }}
          >
            <input value={text} onChange={(e) => setText(e.target.value)} placeholder="מה קרה? כתיבה ליומן…" className="h-10 flex-1 rounded-xl border border-outline bg-page px-3 text-[14px] outline-none focus:border-primary" />
            <Button variant="primary" type="submit" disabled={!text.trim()}>
              <Send size={15} />
            </Button>
          </form>
          <ol className="flex flex-col gap-2.5 border-s-2 border-outline ps-4">
            {journal.map((n) => (
              <li key={n.id} className="relative">
                <span className={cx('absolute -start-[23px] top-1.5 h-2.5 w-2.5 rounded-full border-2', n.isAutomatic ? 'border-primary bg-page' : 'border-copper bg-copper')} />
                <p className={cx('text-[14px]', n.isAutomatic ? 'text-muted' : 'font-semibold text-body')}>
                  {n.text} <span className="text-[11px] font-normal text-muted">· {chatTime(n.createdAt)}</span>
                </p>
              </li>
            ))}
          </ol>
        </div>

        <div className="mt-6 border-t border-outline pt-4">
          <Button
            size="sm"
            variant="danger"
            onClick={() => {
              store.deleteMatch(m.id);
              onClose();
              toast('הרעיון נמחק');
            }}
          >
            <Trash2 size={14} /> מחיקת הרעיון
          </Button>
        </div>
      </div>
    </div>
  );
}

function PersonPicker({ label, list, value, onPick }: { label: string; list: Person[]; value: Person | null; onPick: (p: Person | null) => void }) {
  const [q, setQ] = useState('');
  const shown = list.filter((p) => !q.trim() || fullName(p).includes(q.trim())).slice(0, 40);
  return (
    <div className="flex min-h-0 flex-col rounded-2xl border border-outline">
      <div className="border-b border-outline p-3">
        <div className="mb-2 text-[14px] font-extrabold text-heading">{label}</div>
        {value ? (
          <div className="flex items-center gap-2.5">
            <Avatar person={value} size={36} />
            <div className="flex-1 text-[15px] font-bold" style={{ color: genderColor(value.gender) }}>
              {fullName(value)}
            </div>
            <Button size="sm" variant="ghost" onClick={() => onPick(null)}>
              החלפה
            </Button>
          </div>
        ) : (
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="חיפוש…" className="h-9 w-full rounded-lg border border-outline px-3 text-[14px] outline-none focus:border-primary" />
        )}
      </div>
      {!value && (
        <div className="h-[300px] overflow-y-auto p-1 scroll-thin">
          {shown.map((p) => (
            <button key={p.id} onClick={() => onPick(p)} className="flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-start hover:bg-oat">
              <Avatar person={p} size={30} ring={false} />
              <span className="flex-1 text-[14px] font-semibold" style={{ color: genderColor(p.gender) }}>
                {fullName(p)}
              </span>
              <span className="text-[12px] text-muted">{summaryLine(p)}</span>
            </button>
          ))}
          {shown.length === 0 && <p className="p-4 text-center text-[13px] text-muted">אין תוצאות</p>}
        </div>
      )}
    </div>
  );
}

function CreateIdea({ initialWith, onDone }: { initialWith: string | null; onDone: (m: MatchIdea | null) => void }) {
  const store = useStore();
  const pre = initialWith ? store.byId.get(initialWith) : undefined;
  const [male, setMale] = useState<Person | null>(pre?.gender === 'male' ? pre : null);
  const [female, setFemale] = useState<Person | null>(pre?.gender === 'female' ? pre : null);
  const free = store.visiblePeople.filter((p) => p.profileStatus !== 'mazelTov');
  const source = male ?? female;
  const fits = (p: Person) => (source ? matchesBasic(source, p) : true);
  const men = free.filter((p) => p.gender === 'male').sort((a, b) => Number(fits(b)) - Number(fits(a)));
  const women = free.filter((p) => p.gender === 'female').sort((a, b) => Number(fits(b)) - Number(fits(a)));
  const exists = male && female && store.db.matches.find((m) => [m.personAId, m.personBId].includes(male.id) && [m.personAId, m.personBId].includes(female.id));
  return (
    <div>
      <div className="grid grid-cols-2 gap-3">
        <PersonPicker label="הבחור" list={men} value={male} onPick={setMale} />
        <PersonPicker label="הבחורה" list={women} value={female} onPick={setFemale} />
      </div>
      {exists && <p className="mt-3 rounded-xl bg-soft-yellow/60 px-3 py-2 text-[13px] text-copper-ink">כבר קיים רעיון בין שניהם. אפשר לפתוח אותו במקום ליצור חדש.</p>}
      <div className="mt-4 flex justify-end gap-2">
        <Button onClick={() => onDone(null)}>ביטול</Button>
        {exists ? (
          <Button variant="primary" onClick={() => onDone(exists)}>
            לרעיון הקיים
          </Button>
        ) : (
          <Button variant="copper" disabled={!male || !female} onClick={() => male && female && onDone(store.createMatch(male.id, female.id))}>
            <Lightbulb size={16} /> פתיחת רעיון
          </Button>
        )}
      </div>
    </div>
  );
}

/** "רעיונות שהמאגר מציע לך" — pairs the database finds in itself. */
function SuggestedPairs() {
  const store = useStore();
  const toast = useToast();
  const router = useRouter();
  const [skipped, setSkipped] = useState<string[]>([]);
  const pairs = useMemo(() => {
    const paired = new Set(store.db.matches.flatMap((m) => [`${m.personAId}|${m.personBId}`, `${m.personBId}|${m.personAId}`]));
    const men = store.visiblePeople.filter((p) => p.gender === 'male' && p.profileStatus === 'available');
    const women = store.visiblePeople.filter((p) => p.gender === 'female' && p.profileStatus === 'available');
    const used = new Map<string, number>();
    const out: [Person, Person][] = [];
    for (const man of men) {
      for (const w of women) {
        if (paired.has(`${man.id}|${w.id}`)) continue;
        if ((used.get(w.id) ?? 0) >= 2 || (used.get(man.id) ?? 0) >= 2) continue;
        if (!matchesBasic(man, w) || !matchesBasic(w, man)) continue;
        out.push([man, w]);
        used.set(w.id, (used.get(w.id) ?? 0) + 1);
        used.set(man.id, (used.get(man.id) ?? 0) + 1);
      }
    }
    return out;
  }, [store.db.matches, store.visiblePeople]);
  const shown = pairs.filter(([a, b]) => !skipped.includes(`${a.id}|${b.id}`)).slice(0, 12);

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-6 py-6 scroll-thin">
      <h2 className="text-center text-[20px] font-extrabold text-heading">רעיונות שהמאגר מציע לך</h2>
      <p className="mb-6 text-center text-[14px] text-muted">המאגר שלך מציע רעיונות לזוגות שיכולים להתאים לפי גיל וסגנון דתי</p>
      {shown.length === 0 && <Empty title="אין כרגע רעיונות חדשים">הוסיפו עוד חברים למאגר, ורעיונות חדשים יופיעו כאן.</Empty>}
      <div className="mx-auto grid max-w-[1000px] gap-3 md:grid-cols-2">
        {shown.map(([a, b]) => (
          <div key={`${a.id}|${b.id}`} className="card p-4" style={{ borderInlineStart: `4px solid ${genderColor('male')}`, borderInlineEnd: `4px solid ${genderColor('female')}` }}>
            <div className="flex items-center gap-2">
              <Side p={a} align="start" />
              <Heart size={18} className="text-primary" />
              <Side p={b} align="end" />
            </div>
            <div className="mt-3 flex justify-center gap-2 border-t border-outline pt-3">
              <Button
                size="sm"
                variant="primary"
                onClick={() => {
                  const m = store.createMatch(a.id, b.id);
                  if (!m) return;
                  toast(`נפתח רעיון: ${a.firstName} & ${b.firstName}`, { label: 'לרעיון', run: () => router.replace(`/ideas?id=${m.id}`) });
                }}
              >
                <Lightbulb size={14} /> פתיחת רעיון
              </Button>
              <Button
                size="sm"
                onClick={() => {
                  const key = `${a.id}|${b.id}`;
                  setSkipped((s) => [...s, key]);
                  toast('הרעיון הוסר', { label: 'ביטול', run: () => setSkipped((s) => s.filter((x) => x !== key)) });
                }}
              >
                לא מתאים
              </Button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function IdeasPage() {
  return (
    <Suspense>
      <IdeasScreen />
    </Suspense>
  );
}
