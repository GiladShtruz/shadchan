'use client';

import { useRouter } from 'next/navigation';
import { BellRing, IdCard, LifeBuoy, ShieldCheck, Undo2 } from 'lucide-react';
import { useStore } from '@/data/store';
import type { AppNotification } from '@/domain/types';
import { chatTime } from '@/domain/logic';
import { Avatar, Button, Empty, cx } from '@/components/ui';
import { PageHeader } from '@/components/shell';

const ICON: Record<AppNotification['kind'], React.ReactNode> = {
  reminder: <BellRing size={18} />,
  cardCreated: <IdCard size={18} />,
  accessApproved: <ShieldCheck size={18} />,
  accessRequest: <ShieldCheck size={18} />,
  support: <LifeBuoy size={18} />,
  statusEvent: <Undo2 size={18} />,
};

export default function NotificationsPage() {
  const { notifications, markAllRead, markRead, byId } = useStore();
  const router = useRouter();
  const sorted = [...notifications].sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  const open = (n: AppNotification) => {
    markRead(n.id);
    if (n.matchId) router.push(`/ideas?id=${n.matchId}`);
    else if (n.personId) router.push(`/people?id=${n.personId}`);
  };

  return (
    <div className="mx-auto max-w-[820px]">
      <PageHeader
        title="התראות"
        subtitle="תזכורות שהגיעו, עדכונים על כרטיסים אישיים ותשובות מהתמיכה — הכל במקום אחד"
        actions={
          <Button size="sm" onClick={markAllRead}>
            סימון הכל כנקרא
          </Button>
        }
      />
      <div className="px-8 pb-10">
        {sorted.length === 0 ? (
          <Empty title="אין התראות חדשות" />
        ) : (
          <div className="card divide-y divide-outline overflow-hidden">
            {sorted.map((n) => {
              const person = n.personId ? byId.get(n.personId) : undefined;
              return (
                <button key={n.id} onClick={() => open(n)} className={cx('flex w-full items-center gap-4 px-5 py-4 text-start transition hover:bg-oat/70', !n.read && 'bg-primary-light/35')}>
                  {person ? (
                    <Avatar person={person} size={42} />
                  ) : (
                    <span className="flex h-[42px] w-[42px] items-center justify-center rounded-full bg-sand text-copper-ink">{ICON[n.kind]}</span>
                  )}
                  <div className="min-w-0 flex-1">
                    <p className={cx('text-[15px]', n.read ? 'text-body' : 'font-bold text-heading')}>{n.title}</p>
                    {n.subtitle && <p className="text-[13px] text-muted">{n.subtitle}</p>}
                  </div>
                  <span className="shrink-0 text-[12px] text-muted">{chatTime(n.createdAt)}</span>
                  {!n.read && <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-copper" />}
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
