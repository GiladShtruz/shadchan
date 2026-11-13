'use client';

import Link from 'next/link';
import { useMemo } from 'react';
import { BellRing, ChevronLeft, Clock3, IdCard, Lightbulb, Sparkles } from 'lucide-react';
import { useStore } from '@/data/store';
import { demoCommunity, demoTips } from '@/data/demo';
import { daysBetween, g, proposalTab, relativeDays, sidesOf, stageLabel, suggestionsFor } from '@/domain/logic';
import { Avatar, PaperCard, SectionTitle, cx } from '@/components/ui';

function greeting(): string {
  const h = new Date().getHours();
  if (h < 5) return 'לילה טוב';
  if (h < 12) return 'בוקר טוב';
  if (h < 17) return 'צהריים טובים';
  if (h < 22) return 'ערב טוב';
  return 'לילה טוב';
}

interface Row {
  key: string;
  href: string;
  faces: React.ReactNode;
  title: string;
  line: string;
  icon: React.ReactNode;
  tier: number;
}

export default function HomePage() {
  const { db, byId, visiblePeople, notifications, mode } = useStore();
  const gender = db.profile.gender;

  const figures = useMemo(() => {
    const couples = db.matches.filter((m) => m.datingStartedAt || ['dating', 'dated', 'married'].includes(m.status)).length;
    return [
      { label: 'חברים', value: visiblePeople.length, color: 'var(--c-male)', href: '/people' },
      { label: 'רעיונות', value: db.matches.length, color: 'var(--c-copper)', href: '/ideas' },
      { label: 'זוגות יצאו', value: couples, color: 'var(--c-primary)', href: '/ideas?cat=dating' },
      { label: 'חתונות', value: db.matches.filter((m) => m.status === 'married').length, color: 'var(--c-female)', href: '/ideas?cat=closed' },
    ];
  }, [db.matches, visiblePeople.length]);

  /** `HomeBoardSection.actionTier`: due → next step → card friends → stale → pairs. */
  const rows = useMemo<Row[]>(() => {
    const out: Row[] = [];
    const now = new Date();
    for (const m of db.matches) {
      const { male, female } = sidesOf(m, byId);
      if (!male || !female) continue;
      const tab = proposalTab(m, male, female);
      if (!tab || tab === 'rejected' || tab === 'dated' || tab === 'weddings') continue;
      const faces = (
        <span className="flex -space-x-2 space-x-reverse">
          <Avatar person={male} size={34} />
          <Avatar person={female} size={34} />
        </span>
      );
      const title = `${male.firstName} & ${female.firstName}`;
      if (m.reminderDate && new Date(m.reminderDate) <= now) {
        out.push({ key: `r-${m.id}`, href: `/ideas?id=${m.id}`, faces, title, line: m.reminderNote ?? `הגיע הזמן לבדוק מה קורה (${relativeDays(m.reminderDate)})`, icon: <BellRing size={15} />, tier: 0 });
        continue;
      }
      const idle = daysBetween(new Date(m.updatedAt), now);
      if (tab === 'open' && idle >= 7) {
        out.push({ key: `s-${m.id}`, href: `/ideas?id=${m.id}`, faces, title, line: `כבר ${idle} ימים בלי עדכון`, icon: <Clock3 size={15} />, tier: 3 });
      } else if (tab === 'open') {
        out.push({ key: `n-${m.id}`, href: `/ideas?id=${m.id}`, faces, title, line: stageLabel(m, male, female), icon: <Lightbulb size={15} />, tier: 1 });
      }
    }
    for (const p of visiblePeople.filter((x) => x.cardOwnerUid).slice(0, 2)) {
      out.push({ key: `c-${p.id}`, href: `/people?id=${p.id}`, faces: <Avatar person={p} size={34} />, title: `${p.firstName} ${p.lastName ?? ''}`, line: g('{הוסיף|הוסיפה} כרטיס אישי · אפשר לבקש גישה', p.gender), icon: <IdCard size={15} />, tier: 2 });
    }
    const source = visiblePeople.find((p) => p.profileStatus === 'available' && p.gender === 'male');
    if (source) {
      const c = suggestionsFor(source, visiblePeople, db.matches)[0];
      if (c)
        out.push({
          key: `pair-${source.id}-${c.id}`,
          href: `/people?id=${source.id}&tab=suggestions`,
          faces: (
            <span className="flex -space-x-2 space-x-reverse">
              <Avatar person={source} size={34} />
              <Avatar person={c} size={34} />
            </span>
          ),
          title: `${source.firstName} & ${c.firstName}`,
          line: 'רעיון שהמאגר מציע לך',
          icon: <Sparkles size={15} />,
          tier: 4,
        });
    }
    return out.sort((a, b) => a.tier - b.tier).slice(0, 8);
  }, [db.matches, byId, visiblePeople]);

  const week = demoCommunity.week;
  // Actions since Sunday: friends added and ideas opened this week.
  const actionsThisWeek = useMemo(() => {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    start.setDate(start.getDate() - start.getDay());
    const since = start.toISOString();
    return visiblePeople.filter((p) => p.createdAt >= since).length + db.matches.filter((m) => m.createdAt >= since).length;
  }, [visiblePeople, db.matches]);
  const weeklyGoal = 5;
  const tip = demoTips[new Date().getDate() % demoTips.length];
  const unread = notifications.filter((n) => !n.read).length;

  return (
    <div className="mx-auto max-w-[1180px] px-8 py-7">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-[28px] font-extrabold text-heading">
            {greeting()}, <span className="text-copper">{db.profile.firstName}</span>
          </h1>
          <p className="mt-1 text-[15px] text-muted">
            {unread > 0 ? `יש לך ${unread} התראות חדשות` : 'הכל מעודכן. זה זמן טוב לחשוב על החברים.'}
          </p>
        </div>
        <div className="flex gap-2">
          <Link href="/people?new=1" className="flex h-11 items-center gap-2 rounded-xl border border-outline bg-page px-4 text-[14px] font-bold text-male hover:bg-oat">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/add_friends_art.png" alt="" className="h-7 w-7 object-contain" /> הוספת חברים
          </Link>
          <Link href="/ideas?new=1" className="flex h-11 items-center gap-2 rounded-xl bg-copper px-4 text-[14px] font-bold text-white hover:brightness-105">
            <Lightbulb size={17} /> הוספת רעיון
          </Link>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
        {figures.map((f) => (
          <Link key={f.label} href={f.href}>
            <PaperCard accent={f.color} className="px-5 pt-4 pb-5 transition hover:-translate-y-0.5">
              <div className="text-[32px] font-extrabold leading-none" style={{ color: f.color }}>
                {f.value.toLocaleString('he-IL')}
              </div>
              <div className="mt-1.5 text-[14px] font-semibold text-muted">{f.label}</div>
            </PaperCard>
          </Link>
        ))}
      </div>

      <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_340px]">
        <div>
          <SectionTitle action={<Link href="/notifications" className="text-[13px] font-semibold text-copper-ink hover:underline">לכל ההתראות</Link>}>
            מה עושים עכשיו?
          </SectionTitle>
          <div className="card divide-y divide-outline overflow-hidden">
            {rows.length === 0 && <p className="px-5 py-10 text-center text-muted">אין כרגע משהו שמחכה לך.</p>}
            {rows.map((r) => (
              <Link key={r.key} href={r.href} className="flex items-center gap-4 px-5 py-3.5 transition hover:bg-oat/70">
                {r.faces}
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[15px] font-bold text-heading">{r.title}</div>
                  <div className={cx('mt-0.5 flex items-center gap-1.5 truncate text-[13px]', r.tier === 0 ? 'text-copper-ink font-semibold' : 'text-muted')}>
                    {r.icon}
                    {r.line}
                  </div>
                </div>
                <ChevronLeft size={18} className="text-muted" />
              </Link>
            ))}
          </div>

          <div className="mt-6 grid gap-4 sm:grid-cols-2">
            <Link href="/people?view=think">
              <PaperCard accent="var(--c-copper)" className="flex items-center gap-4 p-5 transition hover:-translate-y-0.5">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src="/think_coffee_art.png" alt="" className="h-14 w-14 object-contain" />
                <div>
                  <div className="text-[16px] font-extrabold text-heading">עוצרים רגע לחשוב על חברים</div>
                  <div className="text-[13px] text-muted">{g('חברים שלך שישמחו {שתחשוב|שתחשבי} עליהם', gender)}</div>
                </div>
              </PaperCard>
            </Link>
            <Link href="/ideas?view=suggested">
              <PaperCard accent="var(--c-male)" className="flex items-center gap-4 p-5 transition hover:-translate-y-0.5">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src="/idea_envelope_art.png" alt="" className="h-14 w-14 object-contain" />
                <div>
                  <div className="text-[16px] font-extrabold text-heading">רעיונות שהמאגר מציע לך</div>
                  <div className="text-[13px] text-muted">זוגות שיכולים להתאים לפי גיל וסגנון דתי</div>
                </div>
              </PaperCard>
            </Link>
          </div>
        </div>

        <aside className="flex flex-col gap-5">
          <PaperCard accent="var(--c-primary)" className="p-5">
            <div className="flex items-baseline justify-between">
              <span className="text-[15px] font-extrabold text-heading">השבוע</span>
              <span className="text-[14px] font-bold text-male">
                {actionsThisWeek}/{weeklyGoal} פעולות
              </span>
            </div>
            <div className="mt-3 h-2.5 overflow-hidden rounded-full bg-sand">
              <div className="h-full rounded-full bg-male" style={{ width: `${Math.min(1, actionsThisWeek / weeklyGoal) * 100}%` }} />
            </div>
            <p className="mt-2 text-[13px] text-muted">
              {actionsThisWeek >= weeklyGoal
                ? 'הגעת ליעד השבועי. כל הכבוד!'
                : weeklyGoal - actionsThisWeek === 1
                  ? 'עוד פעולה אחת ליעד השבועי'
                  : `עוד ${weeklyGoal - actionsThisWeek} פעולות ליעד השבועי`}
            </p>
          </PaperCard>

          {mode === 'demo' && (
          <PaperCard accent="var(--c-copper)" className="p-5">
            <div className="text-[15px] font-extrabold text-heading">השבוע בשדכן</div>
            <div className="mt-3 grid grid-cols-2 gap-3">
              <div className="rounded-xl bg-page p-3 text-center">
                <div className="text-[24px] font-extrabold text-copper">{week.me}</div>
                <div className="text-[12px] text-muted">הנקודות שלי</div>
              </div>
              <div className="rounded-xl bg-page p-3 text-center">
                <div className="text-[24px] font-extrabold text-male">{week.totals.points.toLocaleString('he-IL')}</div>
                <div className="text-[12px] text-muted">כל הקהילה</div>
              </div>
            </div>
            <p className="mt-3 text-[14px] text-body">
              <span className="font-bold">{week.totals.couples}</span> זוגות התחילו לצאת השבוע ·{' '}
              <span className="font-bold">{week.totals.newMatchmakers}</span> שדכנים חדשים הצטרפו
            </p>
            <Link href="/community" className="mt-3 inline-block text-[13px] font-semibold text-copper-ink hover:underline">
              לפעילות הקהילה
            </Link>
          </PaperCard>
          )}

          <PaperCard accent="var(--c-female)" className="p-5">
            <div className="text-[13px] font-bold text-muted">{g('טיפ ל{שדכן|שדכנית}', gender)}</div>
            <p className="mt-2 text-[15px] leading-relaxed text-heading">“{tip.text}”</p>
            {tip.authorName && <p className="mt-2 text-[12px] text-muted">— {tip.authorName}</p>}
          </PaperCard>
        </aside>
      </div>
    </div>
  );
}
