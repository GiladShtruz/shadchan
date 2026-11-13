'use client';

import { useState } from 'react';
import { useStore } from '@/data/store';
import { AccessRow, detailsLine } from '@/components/access';
import { PageHeader } from '@/components/shell';
import { Button, Empty, InitialAvatar, cx } from '@/components/ui';
import { useToast } from '@/components/toast';

export default function MyMatchmakers() {
  const { personal, setAccess, updatePersonal } = useStore();
  const toast = useToast();
  const approved = personal.access.filter((a) => a.status === 'approved');
  const others = personal.access.filter((a) => a.status === 'pending' || a.status === 'declined');
  const [tab, setTab] = useState<'approved' | 'grant'>(approved.length ? 'approved' : 'grant');

  return (
    <div className="mx-auto max-w-[820px]">
      <PageHeader title="השדכנים שלי" subtitle="מי רואה את הכרטיס שלך, ומי עוד יכול לעזור" />
      <div className="px-8 pb-10">
        <div className="mb-4 flex gap-1 rounded-xl border border-outline bg-page p-1">
          {(
            [
              ['approved', `אישרתי גישה · ${approved.length}`],
              ['grant', `אפשר לתת גישה · ${others.length + personal.helpers.length}`],
            ] as const
          ).map(([k, label]) => (
            <button key={k} onClick={() => setTab(k)} className={cx('h-10 flex-1 rounded-lg text-[14px]', tab === k ? 'bg-primary-light font-bold text-heading' : 'text-muted hover:bg-oat')}>
              {label}
            </button>
          ))}
        </div>

        <div className="card divide-y divide-outline overflow-hidden">
          {tab === 'approved' && (approved.length ? approved.map((r) => <AccessRow key={r.matchmakerUid} row={r} />) : <Empty title="עוד לא נתת גישה לאף שדכן" />)}
          {tab === 'grant' && (
            <>
              {others.map((r) => (
                <AccessRow key={r.matchmakerUid} row={r} />
              ))}
              {personal.helpers.map((h) => (
                <div key={h.uid} className="flex items-center gap-3 px-5 py-3.5">
                  <InitialAvatar name={h.name} seed={h.uid} size={40} />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[15px] font-bold text-heading">{h.name}</div>
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
              {others.length + personal.helpers.length === 0 && <Empty title="אין כרגע שדכנים נוספים" />}
            </>
          )}
        </div>

        <div className="card mt-6 flex items-center justify-between gap-4 p-5">
          <div>
            <div className="text-[15px] font-bold text-heading">שדכנים יכולים לבקש גישה לכרטיס</div>
            <div className="text-[13px] text-muted">כשכבוי, הכרטיס שלך לא נראה לשדכנים שלא אישרת</div>
          </div>
          <button
            role="switch"
            aria-checked={personal.acceptsRequests}
            onClick={() => updatePersonal({ acceptsRequests: !personal.acceptsRequests })}
            className={cx('relative h-7 w-12 rounded-full transition', personal.acceptsRequests ? 'bg-male' : 'bg-outline')}
          >
            <span className={cx('absolute top-1 h-5 w-5 rounded-full bg-white shadow transition-all', personal.acceptsRequests ? 'start-6' : 'start-1')} />
          </button>
        </div>
      </div>
    </div>
  );
}
