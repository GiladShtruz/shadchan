'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { PenLine } from 'lucide-react';
import { useStore } from '@/data/store';
import { REGION_LABEL, maritalLabel } from '@/domain/enums';
import { ageOf, fullName, religiousLabel } from '@/domain/logic';
import { PersonForm } from '@/components/person-form';
import { PageHeader } from '@/components/shell';
import { Avatar, Button, PaperCard } from '@/components/ui';
import { useToast } from '@/components/toast';

function CardScreen() {
  const { personal, updatePersonalCard } = useStore();
  const toast = useToast();
  const router = useRouter();
  const editing = useSearchParams().get('edit') === '1';
  const card = personal.card;

  if (editing) {
    return (
      <div className="mx-auto max-w-[760px]">
        <PageHeader title="עריכת הכרטיס שלי" subtitle="כל שינוי מגיע מעצמו לשדכנים שנתת להם גישה" />
        <div className="px-8 pb-10">
          <div className="card p-6">
            <PersonForm
              ownerCard
              initial={card}
              onCancel={() => router.replace('/me/card')}
              onSave={(d) => {
                updatePersonalCard({ ...d, manualAgeUpdatedAt: new Date().toISOString() });
                toast('הכרטיס נשמר');
                router.replace('/me/card');
              }}
            />
          </div>
        </div>
      </div>
    );
  }

  const facts = [
    ['גיל', ageOf(card)],
    ['סגנון דתי', religiousLabel(card)],
    ['עיר', card.city],
    ['אזור', card.region ? REGION_LABEL[card.region] : null],
    ['גובה', card.heightCm ? `${card.heightCm} ס״מ` : null],
    ['מצב משפחתי', card.maritalStatus ? maritalLabel(card.maritalStatus, card.gender) : null],
  ].filter(([, v]) => v != null && v !== '');

  return (
    <div className="mx-auto max-w-[760px]">
      <PageHeader
        title="הכרטיס שלי"
        subtitle="כך השדכנים שאישרת רואים אותך"
        actions={
          <Button variant="primary" onClick={() => router.replace('/me/card?edit=1')}>
            <PenLine size={16} /> עריכה
          </Button>
        }
      />
      <div className="px-8 pb-10">
        <PaperCard accent="var(--c-female)" className="p-7">
          <div className="flex flex-col items-center text-center">
            <Avatar person={card} size={120} />
            <h2 className="mt-3 text-[26px] font-extrabold text-female">{fullName(card)}</h2>
          </div>
          <div className="mt-5 grid grid-cols-3 gap-2">
            {facts.map(([label, value]) => (
              <div key={String(label)} className="rounded-xl bg-page px-3 py-2 text-center">
                <div className="text-[12px] text-muted">{label}</div>
                <div className="text-[15px] font-bold text-heading">{value}</div>
              </div>
            ))}
          </div>
          <p className="mt-6 whitespace-pre-line text-[16px] leading-relaxed text-body">{card.description}</p>
        </PaperCard>
      </div>
    </div>
  );
}

export default function MyCardPage() {
  return (
    <Suspense>
      <CardScreen />
    </Suspense>
  );
}
