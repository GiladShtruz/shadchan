'use client';

import { useState } from 'react';
import { useStore } from '@/data/store';
import { demoCommunity, demoLeaderboard, demoTips } from '@/data/demo';
import type { CommunityWindow } from '@/domain/types';
import { g } from '@/domain/logic';
import { Chip, PaperCard, SectionTitle, cx } from '@/components/ui';
import { PageHeader } from '@/components/shell';

const WINDOWS: [CommunityWindow, string][] = [
  ['week', 'השבוע'],
  ['month', 'החודש'],
  ['all', 'כל הזמנים'],
];

const SCORING = [
  ['חבר שנוסף למאגר', 1],
  ['רעיון שנפתח', 1],
  ['זוג שהתחיל לצאת', 5],
  ['אירוסין / חתונה', 50],
] as const;

export default function CommunityPage() {
  const { db, mode } = useStore();
  const [win, setWin] = useState<CommunityWindow>('all');
  const data = demoCommunity[win];
  const t = data.totals;
  if (mode === 'live') {
    return (
      <div className="mx-auto max-w-[760px]">
        <PageHeader title="פעילות וקהילה" />
        <div className="px-8">
          <PaperCard accent="var(--c-copper)" className="p-6">
            <p className="text-[16px] font-bold text-heading">נתוני הקהילה יתחברו בשלב הבא</p>
            <p className="mt-1 text-[14px] text-muted">בינתיים אפשר לראות את הדירוג ואת פעילות הקהילה באפליקציה.</p>
          </PaperCard>
        </div>
      </div>
    );
  }

  const figures = [
    ['נקודות פעילות', t.points, 'var(--c-copper)'],
    ['חברים נוספו', t.friends, 'var(--c-male)'],
    ['רעיונות נפתחו', t.ideas, 'var(--c-copper)'],
    ['זוגות יצאו', t.couples, 'var(--c-primary)'],
    ['חתונות', t.engagements, 'var(--c-female)'],
    [win === 'all' ? 'שדכנים בקהילה' : 'שדכנים חדשים', t.newMatchmakers, 'var(--c-heading)'],
  ] as const;

  return (
    <div className="mx-auto max-w-[1100px]">
      <PageHeader
        title="פעילות וקהילה"
        subtitle="הנקודות שלך ושל כל שדכני הקהילה. שמות החברים במאגר לא יוצאים מהחשבון שלך — רק מספרים."
        actions={
          <div className="flex gap-1.5">
            {WINDOWS.map(([w, label]) => (
              <Chip key={w} active={win === w} color="var(--c-copper)" onClick={() => setWin(w)}>
                {label}
              </Chip>
            ))}
          </div>
        }
      />
      <div className="grid gap-6 px-8 pb-10 lg:grid-cols-[1fr_360px]">
        <div className="flex flex-col gap-6">
          <PaperCard accent="var(--c-copper)" className="p-6">
            <div className="flex items-center gap-6">
              <div>
                <div className="text-[13px] font-bold text-muted">הפעילות שלך</div>
                <div className="text-[44px] font-extrabold leading-none text-copper">{data.me.toLocaleString('he-IL')}</div>
                <div className="mt-1 text-[13px] text-muted">נקודות פעילות</div>
              </div>
              <p className="flex-1 text-[15px] text-body">
                {data.me > 0 ? g('כל הכבוד! כל חבר שנוסף וכל רעיון שנפתח {מקרב|מקרבת} עוד זוג לחופה.', db.profile.gender) : 'עוד לא נרשמה פעילות בתקופה הזו.'}
              </p>
            </div>
          </PaperCard>

          <section>
            <SectionTitle>פעילות הקהילה</SectionTitle>
            <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
              {figures.map(([label, value, color]) => (
                <PaperCard key={label} accent={color} className="px-5 pt-4 pb-5">
                  <div className="text-[28px] font-extrabold leading-none" style={{ color }}>
                    {value.toLocaleString('he-IL')}
                  </div>
                  <div className="mt-1.5 text-[13px] font-semibold text-muted">{label}</div>
                </PaperCard>
              ))}
            </div>
          </section>

          <section>
            <SectionTitle>איך נספרות הנקודות</SectionTitle>
            <div className="card divide-y divide-outline">
              {SCORING.map(([label, pts]) => (
                <div key={label} className="flex items-center justify-between px-5 py-3 text-[15px]">
                  <span>{label}</span>
                  <span className="font-extrabold text-copper">+{pts}</span>
                </div>
              ))}
            </div>
          </section>
        </div>

        <aside className="flex flex-col gap-6">
          <section>
            <SectionTitle>דירוג השדכנים · {WINDOWS.find(([w]) => w === win)?.[1]}</SectionTitle>
            <PaperCard accent="var(--c-female)" className="py-2">
              {demoLeaderboard.map((r, i) => (
                <div key={r.uid} className={cx('flex items-center gap-3 px-5 py-2.5', r.isMe && 'bg-female-soft/60')}>
                  <span className="w-6 text-center text-[14px] font-extrabold text-muted">{i + 1}</span>
                  <span className={cx('flex-1 text-[15px]', r.isMe ? 'font-extrabold text-heading' : 'font-semibold')}>
                    {r.name}
                    {r.isMe && g(' ({אתה|את})', db.profile.gender)}
                  </span>
                  <span className="text-[14px] font-bold text-body">{Math.round(r.points * (win === 'all' ? 1 : win === 'month' ? 0.12 : 0.03)).toLocaleString('he-IL')}</span>
                </div>
              ))}
            </PaperCard>
          </section>
          <section>
            <SectionTitle>טיפים מהקהילה</SectionTitle>
            <div className="flex flex-col gap-3">
              {demoTips.map((tip) => (
                <div key={tip.id} className="card p-4">
                  <p className="text-[14px] leading-relaxed text-body">“{tip.text}”</p>
                  {tip.authorName && <p className="mt-1.5 text-[12px] text-muted">— {tip.authorName}</p>}
                </div>
              ))}
            </div>
          </section>
        </aside>
      </div>
    </div>
  );
}
