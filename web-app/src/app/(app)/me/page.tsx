'use client';

import Link from 'next/link';
import { Eye, Mic, PenLine, Share2 } from 'lucide-react';
import { usePersonal, useStore } from '@/data/store';
import { PROFILE_STATUSES, profileStatusLabel } from '@/domain/enums';
import { fullName, g, longDate, summaryLine } from '@/domain/logic';
import { AccessRow, detailsLine } from '@/components/access';
import { Avatar, Button, InitialAvatar, PaperCard, SectionTitle, cx } from '@/components/ui';
import { useToast } from '@/components/toast';

export default function PersonalHome() {
  const { setPersonalStatus, setAccess } = useStore();
  const personal = usePersonal();
  const toast = useToast();
  const card = personal.card;
  const gender = card.gender;
  const approved = personal.access.filter((a) => a.status === 'approved');
  const pending = personal.access.filter((a) => a.status === 'pending');

  return (
    <div className="mx-auto max-w-[1100px] px-8 py-7">
      <h1 className="text-[28px] font-extrabold text-heading">
        שלום, <span className="text-copper">{card.firstName}</span>
      </h1>
      <p className="mt-1 text-[15px] text-muted">
        נתת גישה ל־{approved.length} חברים שלך · עוד {personal.helpers.length} חברים שלך משדכים בשדכן
      </p>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_380px]">
        <div className="flex flex-col gap-6">
          <PaperCard accent="var(--c-female)" className="p-6">
            <div className="flex items-start gap-5">
              <Avatar person={card} size={92} />
              <div className="min-w-0 flex-1">
                <div className="text-[13px] font-bold text-muted">הכרטיס שלי</div>
                <h2 className="text-[22px] font-extrabold text-female">{fullName(card)}</h2>
                <p className="text-[14px] text-muted">{summaryLine(card)}</p>
                <p className="mt-3 line-clamp-3 text-[15px] leading-relaxed text-body">{card.description}</p>
              </div>
            </div>
            <div className="mt-5 flex flex-wrap gap-2">
              <Link href="/me/card">
                <Button variant="primary">
                  <Eye size={16} /> צפייה בכרטיס המלא
                </Button>
              </Link>
              <Link href="/me/card?edit=1">
                <Button>
                  <PenLine size={16} /> עריכת הכרטיס
                </Button>
              </Link>
              <Button variant="ghost" onClick={() => navigator.clipboard?.writeText(card.description ?? '').then(() => toast('הכרטיס הועתק'))}>
                <Share2 size={16} /> שיתוף
              </Button>
            </div>
            <p className="mt-3 text-[12px] text-muted">עודכן לאחרונה {longDate(card.updatedAt)}</p>
          </PaperCard>

          <PaperCard className="p-5">
            <div className="mb-3 text-[15px] font-extrabold text-heading">הסטטוס שלי</div>
            <div className="flex gap-2">
              {PROFILE_STATUSES.filter((s) => s !== 'mazelTov').map((s) => (
                <button
                  key={s}
                  onClick={() => {
                    setPersonalStatus(s);
                    toast(`הסטטוס עודכן ל${profileStatusLabel(s, gender)} · השדכנים יראו את זה מעצמם`);
                  }}
                  className={cx('h-11 flex-1 rounded-xl border-2 text-[15px] font-bold transition', card.profileStatus === s ? 'border-female bg-female-soft text-female' : 'border-outline bg-page text-muted hover:bg-oat')}
                >
                  {profileStatusLabel(s, gender)}
                </button>
              ))}
            </div>
          </PaperCard>

          <PaperCard accent="var(--c-copper)" className="p-5">
            <div className="text-[15px] font-extrabold text-heading">{g('מה אני {מחפש|מחפשת}', gender)}</div>
            <p className="mb-3 text-[13px] text-muted">{g('רק שדכנים {שתבחר|שתבחרי} יראו את זה. לא נכנס לכרטיס שנשלח.', gender)}</p>
            {personal.privateLooking ? (
              <p className="rounded-xl bg-page p-4 text-[15px] leading-relaxed text-body">{personal.privateLooking}</p>
            ) : (
              <div className="flex gap-2">
                <Button>
                  <PenLine size={16} /> כתיבה
                </Button>
                <Button>
                  <Mic size={16} /> הקלטה
                </Button>
              </div>
            )}
          </PaperCard>
        </div>

        <aside className="flex flex-col gap-6">
          {pending.length > 0 && (
            <section>
              <SectionTitle>בקשות גישה</SectionTitle>
              <div className="card divide-y divide-outline overflow-hidden">
                {pending.map((r) => (
                  <AccessRow key={r.matchmakerUid} row={r} />
                ))}
              </div>
            </section>
          )}

          <section>
            <SectionTitle action={<Link href="/me/matchmakers" className="text-[13px] font-semibold text-copper-ink hover:underline">לכל השדכנים</Link>}>
              {g('{יכולים|יכולים} לחשוב {עליך|עלייך}', gender)}
            </SectionTitle>
            <div className="card p-4">
              <div className="flex -space-x-2 space-x-reverse">
                {approved.map((a) => (
                  <InitialAvatar key={a.matchmakerUid} name={a.matchmakerName} seed={a.matchmakerUid} size={40} />
                ))}
              </div>
              <p className="mt-3 text-[14px] text-body">{approved.length} שדכנים רואים את הכרטיס שלך ומקבלים כל עדכון בו מעצמם.</p>
            </div>
          </section>

          <section>
            <SectionTitle>חברים שלך שמשדכים בשדכן</SectionTitle>
            <div className="card divide-y divide-outline overflow-hidden">
              {personal.helpers.map((h) => (
                <div key={h.uid} className="flex items-center gap-3 px-5 py-3">
                  <InitialAvatar name={h.name} seed={h.uid} size={36} />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[14px] font-bold text-heading">{h.name}</div>
                    <div className="truncate text-[12px] text-muted">{detailsLine(h.databaseCount, h.lastActiveAt)}</div>
                  </div>
                  <Button
                    size="sm"
                    variant="primary"
                    onClick={() => {
                      setAccess(h.uid, 'approved');
                      toast(`${h.name} יכול/ה לראות עכשיו את הכרטיס שלך`);
                    }}
                  >
                    לתת גישה
                  </Button>
                </div>
              ))}
              {personal.helpers.length === 0 && <p className="px-5 py-6 text-center text-[13px] text-muted">כל החברים שמשדכים כבר קיבלו גישה</p>}
            </div>
          </section>
        </aside>
      </div>
    </div>
  );
}
