'use client';

import { useRouter } from 'next/navigation';
import { ChevronLeft, CloudCheck, Download, FileSpreadsheet, KeyRound, LifeBuoy, LogOut, Shield, SlidersHorizontal, Trash2, UserRound } from 'lucide-react';
import { useStore } from '@/data/store';
import { useToast } from '@/components/toast';
import { PageHeader } from '@/components/shell';
import { PaperCard } from '@/components/ui';

function Row({ icon, title, subtitle, onClick, danger }: { icon: React.ReactNode; title: string; subtitle?: string; onClick?: () => void; danger?: boolean }) {
  return (
    <button onClick={onClick} className="flex w-full items-center gap-4 px-5 py-3.5 text-start hover:bg-oat/70">
      <span className={danger ? 'flex h-9 w-9 items-center justify-center rounded-xl bg-[#fbeceb] text-[#b3412e]' : 'flex h-9 w-9 items-center justify-center rounded-xl bg-primary-light text-male'}>{icon}</span>
      <div className="flex-1">
        <div className={danger ? 'text-[15px] font-bold text-[#b3412e]' : 'text-[15px] font-bold text-heading'}>{title}</div>
        {subtitle && <div className="text-[13px] text-muted">{subtitle}</div>}
      </div>
      <ChevronLeft size={18} className="text-muted" />
    </button>
  );
}

export default function SettingsPage() {
  const { db, session, signOut } = useStore();
  const toast = useToast();
  const router = useRouter();
  const soon = () => toast('יפעל עם החשבון האמיתי, בשלב הבא');

  const exportJson = () => {
    const blob = new Blob([JSON.stringify({ version: 2, ...db }, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'shadchan-demo-backup.json';
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="mx-auto max-w-[760px]">
      <PageHeader title="הגדרות" />
      <div className="flex flex-col gap-5 px-8 pb-10">
        <PaperCard accent="var(--c-copper)" className="divide-y divide-outline">
          <Row icon={<UserRound size={18} />} title="השם שלי" subtitle={`${db.profile.firstName} ${db.profile.lastName}`} onClick={soon} />
          <Row icon={<SlidersHorizontal size={18} />} title="סינון אוטומטי בהתאמות" subtitle="טווחי גיל וסגנונות דתיים שהמאגר מציע" onClick={soon} />
        </PaperCard>
        <PaperCard accent="var(--c-male)" className="divide-y divide-outline">
          <Row icon={<CloudCheck size={18} />} title="סנכרון המאגר" subtitle={session.method === 'demo' ? 'נתוני דוגמה — לא מסונכרן' : 'מסונכרן עם האפליקציה'} />
          <Row icon={<Download size={18} />} title="ייצוא גיבוי (JSON)" subtitle="אותו פורמט כמו הגיבוי באפליקציה" onClick={exportJson} />
          <Row icon={<FileSpreadsheet size={18} />} title="ייצוא לאקסל" onClick={soon} />
          <Row icon={<Shield size={18} />} title="פרטיות" subtitle="מה נשמר ואיפה" onClick={soon} />
        </PaperCard>
        <PaperCard accent="var(--c-female)" className="divide-y divide-outline">
          <Row icon={<KeyRound size={18} />} title="החשבון שלי" subtitle="דרכי כניסה, שינוי סיסמה" onClick={soon} />
          <Row icon={<LifeBuoy size={18} />} title="שליחת תקלה או רעיון" onClick={soon} />
          <Row
            icon={<LogOut size={18} />}
            title="התנתקות"
            onClick={() => {
              signOut();
              router.replace('/login');
            }}
          />
          <Row icon={<Trash2 size={18} />} title="מחיקת החשבון והנתונים" danger onClick={soon} />
        </PaperCard>
      </div>
    </div>
  );
}
