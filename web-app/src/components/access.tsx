'use client';

import { useStore } from '@/data/store';
import type { CardAccessRow } from '@/domain/types';
import { daysBetween, g } from '@/domain/logic';
import { Button, InitialAvatar } from './ui';
import { useToast } from './toast';

export function activityLabel(iso: string | null): string {
  if (!iso) return 'פעילות לא ידועה';
  const d = daysBetween(new Date(iso), new Date());
  if (d <= 0) return 'פעיל היום';
  if (d === 1) return 'פעיל אתמול';
  if (d < 7) return `לפני ${d} ימים`;
  if (d < 14) return 'לפני שבוע';
  return `לפני ${Math.floor(d / 7)} שבועות`;
}

export function detailsLine(count: number | null, last: string | null): string {
  return [count != null ? `${count} אנשים במאגר` : null, activityLabel(last)].filter(Boolean).join(' · ');
}

/** One matchmaker, one action — `MatchmakerFriendRow`. */
export function AccessRow({ row }: { row: CardAccessRow }) {
  const { setAccess, togglePrivateFor, personal } = useStore();
  const toast = useToast();
  const hasLooking = !!personal.privateLooking?.trim();
  return (
    <div className="flex items-center gap-3 px-5 py-3.5">
      <InitialAvatar name={row.matchmakerName} seed={row.matchmakerUid} size={40} />
      <div className="min-w-0 flex-1">
        <div className="truncate text-[15px] font-bold text-heading">{row.matchmakerName}</div>
        <div className="truncate text-[12px] text-muted">{detailsLine(row.databaseCount, row.lastActiveAt)}</div>
        {row.status === 'approved' && (
          <div className="mt-0.5 text-[12px] font-semibold text-dating">
            רואה את הכרטיס{row.seesPrivateLooking ? g(' · ו״מה אני {מחפש|מחפשת}״', personal.card.gender) : ''}
          </div>
        )}
      </div>
      {row.status === 'pending' && (
        <div className="flex gap-2">
          <Button
            size="sm"
            variant="primary"
            onClick={() => {
              setAccess(row.matchmakerUid, 'approved');
              toast(`${row.matchmakerName} יכול/ה לראות עכשיו את הכרטיס שלך`);
            }}
          >
            לאשר
          </Button>
          <Button size="sm" onClick={() => setAccess(row.matchmakerUid, 'declined')}>
            לא עכשיו
          </Button>
        </div>
      )}
      {row.status === 'approved' && (
        <div className="flex items-center gap-2">
          {hasLooking && (
            <label className="flex items-center gap-1.5 text-[12px] text-muted">
              <input type="checkbox" checked={row.seesPrivateLooking} onChange={() => togglePrivateFor(row.matchmakerUid)} />
              {g('מה אני {מחפש|מחפשת}', personal.card.gender)}
            </label>
          )}
          <Button
            size="sm"
            variant="danger"
            onClick={() => {
              setAccess(row.matchmakerUid, 'declined');
              toast('הגישה בוטלה', { label: 'ביטול', run: () => setAccess(row.matchmakerUid, 'approved') });
            }}
          >
            ביטול גישה
          </Button>
        </div>
      )}
      {row.status === 'declined' && (
        <Button size="sm" onClick={() => setAccess(row.matchmakerUid, 'approved')}>
          לתת גישה
        </Button>
      )}
    </div>
  );
}
