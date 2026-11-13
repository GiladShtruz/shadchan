'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { Copy, Heart, Lightbulb, Pencil, Phone, Send, Star, Trash2, X } from 'lucide-react';
import { useStore } from '@/data/store';
import { PROFILE_STATUSES, REGION_LABEL, maritalLabel, profileStatusLabel, type ProfileStatus } from '@/domain/enums';
import type { Person } from '@/domain/types';
import {
  ageOf,
  chatTime,
  fullName,
  g,
  longDate,
  matchStateColor,
  matchStateWord,
  pausesMatches,
  phoneToWhatsApp,
  proposalTab,
  religiousLabel,
  suggestionsFor,
  summaryLine,
} from '@/domain/logic';
import { Avatar, Button, Empty, Modal, StatusTag, WhatsAppIcon, cx, genderColor } from './ui';
import { PersonForm } from './person-form';
import { useToast } from './toast';

function Fact({ label, value }: { label: string; value: React.ReactNode }) {
  if (value == null || value === '') return null;
  return (
    <div className="rounded-xl bg-page px-3 py-2">
      <div className="text-[12px] text-muted">{label}</div>
      <div className="text-[14px] font-bold text-heading">{value}</div>
    </div>
  );
}

export function StatusMenu({ person, onPick }: { person: Person; onPick: (s: ProfileStatus) => void }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <button onClick={() => setOpen((o) => !o)} className="rounded-full border border-outline bg-page px-3 py-1 hover:border-primary">
        <StatusTag status={person.profileStatus} gender={person.gender} />
      </button>
      {open && (
        <div className="absolute top-full z-20 mt-1 w-40 overflow-hidden rounded-xl border border-outline bg-page shadow-lg" onMouseLeave={() => setOpen(false)}>
          {PROFILE_STATUSES.map((s) => (
            <button
              key={s}
              className={cx('block w-full px-3 py-2 text-start hover:bg-oat', s === person.profileStatus && 'bg-oat')}
              onClick={() => {
                onPick(s);
                setOpen(false);
              }}
            >
              <StatusTag status={s} gender={person.gender} />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** The middle pane: one friend's card, in their own colour. */
export function PersonCardPane({ person, onOpenSuggestions, onDeleted }: { person: Person; onOpenSuggestions: () => void; onDeleted: () => void }) {
  const store = useStore();
  const toast = useToast();
  const [editing, setEditing] = useState(false);
  const [note, setNote] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const accent = genderColor(person.gender);
  const wa = phoneToWhatsApp(person.phone);

  const notes = useMemo(
    () => store.db.personNotes.filter((n) => n.personId === person.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
    [store.db.personNotes, person.id],
  );
  const history = useMemo(
    () => store.db.personEvents.filter((e) => e.personId === person.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 6),
    [store.db.personEvents, person.id],
  );

  const setStatus = (s: ProfileStatus) => {
    const before = person.profileStatus;
    store.setProfileStatus(person.id, s);
    const moved = s === 'busy' || s === 'onBreak' ? store.db.matches.filter((m) => (m.personAId === person.id || m.personBId === person.id) && (m.status === 'idea' || m.status === 'checking')).length : 0;
    toast(moved ? `${profileStatusLabel(s, person.gender)} · ${moved} רעיונות עברו להמתנה` : `הסטטוס עודכן ל${profileStatusLabel(s, person.gender)}`, {
      label: 'ביטול',
      run: () => store.setProfileStatus(person.id, before),
    });
  };

  return (
    <div className="fade-up" key={person.id}>
      <div className="card overflow-hidden">
        <div className="h-1.5" style={{ background: accent }} />
        <div className="p-6">
          <div className="flex items-start gap-5">
            <Avatar person={person} size={84} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h2 className="truncate text-[24px] font-extrabold" style={{ color: accent }}>
                  {fullName(person)}
                </h2>
                <button aria-label="מועדף" onClick={() => store.toggleFavorite(person.id)} className="text-copper">
                  <Star size={19} fill={person.isFavorite ? 'currentColor' : 'none'} />
                </button>
              </div>
              <p className="mt-0.5 text-[15px] text-muted">{summaryLine(person) || 'אין עדיין פרטים'}</p>
              <div className="mt-2.5 flex flex-wrap items-center gap-2">
                <StatusMenu person={person} onPick={setStatus} />
                {person.cardOwnerUid && (
                  <span className="rounded-full bg-primary-light px-2.5 py-1 text-[12px] font-bold text-heading">כרטיס אישי מסונכרן</span>
                )}
                {person.tags.map((t) => (
                  <span key={t} className="rounded-full bg-sand px-2.5 py-1 text-[12px] font-semibold text-copper-ink">
                    {t}
                  </span>
                ))}
              </div>
            </div>
            <div className="flex gap-1">
              <button aria-label="עריכה" title="עריכה" onClick={() => setEditing(true)} className="rounded-lg p-2 text-muted hover:bg-oat">
                <Pencil size={18} />
              </button>
              <button aria-label="מחיקה" title="מחיקה" onClick={() => setConfirmDelete(true)} className="rounded-lg p-2 text-muted hover:bg-oat">
                <Trash2 size={18} />
              </button>
            </div>
          </div>

          <div className="mt-5 flex flex-wrap gap-2">
            <a
              href={wa ? `https://wa.me/${wa}` : undefined}
              target="_blank"
              rel="noreferrer"
              aria-disabled={!wa}
              className={cx('inline-flex h-10 items-center gap-2 rounded-xl px-4 text-[14px] font-bold text-white', wa ? 'bg-[#1faa59] hover:brightness-110' : 'pointer-events-none bg-[#9bb9a6]')}
            >
              <WhatsAppIcon /> {wa ? `WhatsApp ל${person.firstName}` : 'אין מספר'}
            </a>
            <Button variant="primary" onClick={onOpenSuggestions} style={{ background: accent }}>
              <Heart size={16} /> התאמות
            </Button>
            <Link href={`/ideas?new=1&with=${person.id}`}>
              <Button>
                <Lightbulb size={16} /> הוספת רעיון
              </Button>
            </Link>
          </div>

          <div className="mt-5 grid grid-cols-2 gap-2 sm:grid-cols-3">
            <Fact label="גיל" value={ageOf(person)} />
            <Fact label="סגנון דתי" value={religiousLabel(person)} />
            <Fact label="גובה" value={person.heightCm ? `${person.heightCm} ס״מ` : null} />
            <Fact label="מצב משפחתי" value={person.maritalStatus ? maritalLabel(person.maritalStatus, person.gender) : null} />
            <Fact label="אזור" value={person.region ? REGION_LABEL[person.region] : null} />
            <Fact
              label="טלפון"
              value={
                person.phone ? (
                  <span dir="ltr" className="inline-flex items-center gap-1">
                    <Phone size={13} /> {person.phone}
                  </span>
                ) : null
              }
            />
            <Fact label="איש קשר להעברת ההצעה" value={person.inquiryContactName} />
          </div>
        </div>
      </div>

      <div className="card mt-4 p-5">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[15px] font-extrabold text-heading">כרטיסייה לשליחה</h3>
          {person.description && (
            <div className="flex gap-1">
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  navigator.clipboard?.writeText(person.description ?? '').then(() => toast('הכרטיס הועתק'));
                }}
              >
                <Copy size={14} /> העתקה
              </Button>
              {wa && (
                <a href={`https://wa.me/?text=${encodeURIComponent(person.description)}`} target="_blank" rel="noreferrer">
                  <Button size="sm" variant="ghost">
                    <Send size={14} /> שיתוף
                  </Button>
                </a>
              )}
            </div>
          )}
        </div>
        {person.description ? (
          <p className="whitespace-pre-line text-[15px] leading-relaxed text-body">{person.description}</p>
        ) : (
          <div className="flex items-center justify-between gap-3 rounded-xl bg-page p-4">
            <p className="text-[14px] text-muted">{g('עוד אין כרטיס. אפשר לבקש {ממנו|ממנה} פרטים בוואטסאפ, או לכתוב אותו כאן.', person.gender)}</p>
            <Button size="sm" onClick={() => setEditing(true)}>
              כתיבת כרטיס
            </Button>
          </div>
        )}
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-2">
        <div className="card p-5">
          <h3 className="mb-3 text-[15px] font-extrabold text-heading">הערות אישיות · לעיניך בלבד</h3>
          <form
            className="mb-3 flex gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              if (!note.trim()) return;
              store.addPersonNote(person.id, note.trim());
              setNote('');
            }}
          >
            <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="כתיבת הערה…" className="h-10 flex-1 rounded-xl border border-outline bg-page px-3 text-[14px] outline-none focus:border-primary" />
            <Button variant="primary" type="submit" disabled={!note.trim()}>
              <Send size={15} />
            </Button>
          </form>
          <div className="flex max-h-60 flex-col gap-2 overflow-y-auto scroll-thin">
            {notes.length === 0 && <p className="text-[13px] text-muted">אין עדיין הערות</p>}
            {notes.map((n) => (
              <div key={n.id} className="rounded-xl bg-page px-3 py-2">
                <p className="text-[14px] text-body">{n.text}</p>
                <p className="mt-1 text-[11px] text-muted">{chatTime(n.createdAt)}</p>
              </div>
            ))}
          </div>
        </div>
        <div className="card p-5">
          <h3 className="mb-3 text-[15px] font-extrabold text-heading">היסטוריה</h3>
          {history.length === 0 && <p className="text-[13px] text-muted">אין עדיין היסטוריה</p>}
          <ol className="flex flex-col gap-3 border-s-2 border-outline ps-4">
            {history.map((e) => (
              <li key={e.id} className="relative">
                <span className="absolute -start-[23px] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-page" style={{ background: accent }} />
                <p className="text-[14px] text-body">{e.text}</p>
                <p className="text-[11px] text-muted">{longDate(e.createdAt)}</p>
              </li>
            ))}
          </ol>
        </div>
      </div>

      <Modal open={editing} onClose={() => setEditing(false)} title={`עריכה · ${fullName(person)}`} width={680}>
        <PersonForm
          initial={person}
          onCancel={() => setEditing(false)}
          onSave={(d) => {
            store.updatePerson(person.id, { ...d, manualAgeUpdatedAt: new Date().toISOString() });
            setEditing(false);
            toast('הכרטיס עודכן');
          }}
        />
      </Modal>

      <Modal open={confirmDelete} onClose={() => setConfirmDelete(false)} title={`למחוק את ${person.firstName}?`}>
        <p className="text-[15px] text-body">
          {g('הכרטיס, ההערות וכל הרעיונות {שלו|שלה} יימחקו מהמאגר.', person.gender)}
        </p>
        <div className="mt-5 flex justify-end gap-2">
          <Button onClick={() => setConfirmDelete(false)}>ביטול</Button>
          <Button
            variant="danger"
            onClick={() => {
              store.deletePerson(person.id);
              setConfirmDelete(false);
              onDeleted();
              toast(`${person.firstName} נמחק/ה מהמאגר`);
            }}
          >
            מחיקה
          </Button>
        </div>
      </Modal>
    </div>
  );
}

/** The left pane: every idea for this friend, and the automatic matches. */
export function PersonSidePane({ person, tab, onTab }: { person: Person; tab: 'ideas' | 'suggestions'; onTab: (t: 'ideas' | 'suggestions') => void }) {
  const store = useStore();
  const toast = useToast();
  const [dismissed, setDismissed] = useState<string[]>([]);

  const ideas = useMemo(
    () =>
      store.db.matches
        .filter((m) => m.personAId === person.id || m.personBId === person.id)
        .map((m) => {
          const otherId = m.personAId === person.id ? m.personBId : m.personAId;
          const other = store.byId.get(otherId);
          const t = proposalTab(m, store.byId.get(m.personAId), store.byId.get(m.personBId));
          return { m, other, t };
        })
        .sort((a, b) => b.m.updatedAt.localeCompare(a.m.updatedAt)),
    [store.db.matches, store.byId, person.id],
  );

  const suggestions = useMemo(() => {
    const list = suggestionsFor(person, store.visiblePeople, store.db.matches);
    return [...list.filter((p) => !dismissed.includes(p.id)), ...list.filter((p) => dismissed.includes(p.id))];
  }, [person, store.visiblePeople, store.db.matches, dismissed]);

  return (
    <div className="card flex h-full min-h-0 flex-col">
      <div className="flex gap-1 border-b border-outline p-2">
        {(
          [
            ['ideas', `רעיונות · ${ideas.length}`],
            ['suggestions', `התאמות · ${suggestions.length}`],
          ] as const
        ).map(([key, label]) => (
          <button
            key={key}
            onClick={() => onTab(key)}
            className={cx('h-9 flex-1 rounded-lg text-[14px]', tab === key ? 'bg-page font-bold text-heading shadow-sm' : 'text-muted hover:bg-oat')}
          >
            {label}
          </button>
        ))}
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto p-2 scroll-thin">
        {tab === 'ideas' &&
          (ideas.length === 0 ? (
            <Empty title="אין עדיין רעיונות">
              <button className="font-semibold text-copper-ink hover:underline" onClick={() => onTab('suggestions')}>
                לראות התאמות מהמאגר
              </button>
            </Empty>
          ) : (
            ideas.map(({ m, other }) =>
              other ? (
                <Link key={m.id} href={`/ideas?id=${m.id}`} className="flex items-center gap-3 rounded-xl px-2.5 py-2.5 hover:bg-oat">
                  <Avatar person={other} size={36} />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[14px] font-bold" style={{ color: genderColor(other.gender) }}>
                      {fullName(other)}
                    </div>
                    <div className="truncate text-[12px] text-muted">{summaryLine(other)}</div>
                  </div>
                  <span className="flex items-center gap-1.5 text-[12px] font-bold" style={{ color: matchStateColor(m.status, pausesMatches(other) || pausesMatches(person)) }}>
                    <span className="h-2 w-2 rounded-full" style={{ background: matchStateColor(m.status, pausesMatches(other) || pausesMatches(person)) }} />
                    {matchStateWord(m, pausesMatches(other) || pausesMatches(person))}
                  </span>
                </Link>
              ) : null,
            )
          ))}
        {tab === 'suggestions' &&
          (suggestions.length === 0 ? (
            <Empty title="אין כרגע התאמות">{g('נסו להוסיף עוד חברים, או להשלים {לו|לה} גיל וסגנון דתי.', person.gender)}</Empty>
          ) : (
            suggestions.map((c) => {
              const isDismissed = dismissed.includes(c.id);
              return (
                <div key={c.id} className={cx('flex items-center gap-3 rounded-xl px-2.5 py-2', isDismissed && 'opacity-50')}>
                  <Link href={`/people?id=${c.id}`}>
                    <Avatar person={c} size={36} />
                  </Link>
                  <div className="min-w-0 flex-1">
                    <Link href={`/people?id=${c.id}`} className="block truncate text-[14px] font-bold hover:underline" style={{ color: genderColor(c.gender) }}>
                      {fullName(c)}
                    </Link>
                    <div className="truncate text-[12px] text-muted">
                      {[ageOf(c), religiousLabel(c)].filter(Boolean).join(' · ')}
                      {pausesMatches(c) && ` · ${profileStatusLabel(c.profileStatus, c.gender)}`}
                    </div>
                  </div>
                  {isDismissed ? (
                    <Button size="sm" variant="ghost" onClick={() => setDismissed((d) => d.filter((x) => x !== c.id))}>
                      החזרה
                    </Button>
                  ) : (
                    <>
                      <button
                        title="פתיחת רעיון"
                        aria-label="פתיחת רעיון"
                        className="rounded-lg bg-primary-light p-2 text-male hover:brightness-95"
                        onClick={() => {
                          const m = store.createMatch(person.id, c.id);
                          toast(`נפתח רעיון: ${person.firstName} & ${c.firstName}`, { label: 'לרעיון', run: () => (window.location.href = `/ideas?id=${m.id}`) });
                        }}
                      >
                        <Lightbulb size={16} />
                      </button>
                      <button
                        title="לא מתאים"
                        aria-label="לא מתאים"
                        className="rounded-lg bg-oat p-2 text-muted hover:text-body"
                        onClick={() => {
                          setDismissed((d) => [...d, c.id]);
                          toast(`${c.firstName} הועבר/ה לסוף הרשימה`, { label: 'ביטול', run: () => setDismissed((d) => d.filter((x) => x !== c.id)) });
                        }}
                      >
                        <X size={16} />
                      </button>
                    </>
                  )}
                </div>
              );
            })
          ))}
      </div>
    </div>
  );
}

