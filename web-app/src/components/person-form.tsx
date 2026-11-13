'use client';

import { useState } from 'react';
import {
  MARITAL_STATUSES,
  REGIONS_SELECTABLE,
  REGION_LABEL,
  RELIGIOUS_LABEL,
  RELIGIOUS_LEVELS_GLOBAL,
  maritalLabel,
  type Gender,
  type MaritalStatus,
  type Region,
  type ReligiousLevel,
} from '@/domain/enums';
import type { Person } from '@/domain/types';
import { ageOf } from '@/domain/logic';
import { Button, Chip, cx } from './ui';

export type PersonDraft = Pick<
  Person,
  'firstName' | 'lastName' | 'gender' | 'manualAge' | 'religiousLevel' | 'city' | 'region' | 'heightCm' | 'maritalStatus' | 'phone' | 'description' | 'tags' | 'inquiryContactName'
>;

const field = 'h-11 w-full rounded-xl border border-outline bg-page px-3.5 text-[15px] outline-none focus:border-primary';

function Label({ children, required }: { children: React.ReactNode; required?: boolean }) {
  return (
    <span className="mb-1.5 block text-[13px] font-bold text-heading">
      {children}
      {required && <span className="text-copper"> *</span>}
    </span>
  );
}

/** The full card editor — the web counterpart of `PersonExtendedEditScreen`. */
export function PersonForm({ initial, onSave, onCancel, ownerCard }: { initial?: Person; onSave: (d: PersonDraft) => void; onCancel: () => void; ownerCard?: boolean }) {
  const [d, setD] = useState<PersonDraft>({
    firstName: initial?.firstName ?? '',
    lastName: initial?.lastName ?? '',
    gender: initial?.gender ?? 'unknown',
    manualAge: initial ? ageOf(initial) : null,
    religiousLevel: initial?.religiousLevel ?? null,
    city: initial?.city ?? '',
    region: initial?.region ?? null,
    heightCm: initial?.heightCm ?? null,
    maritalStatus: initial?.maritalStatus ?? null,
    phone: initial?.phone ?? '',
    description: initial?.description ?? '',
    tags: initial?.tags ?? [],
    inquiryContactName: initial?.inquiryContactName ?? '',
  });
  const [tagInput, setTagInput] = useState('');
  const [tried, setTried] = useState(false);
  const set = <K extends keyof PersonDraft>(k: K, v: PersonDraft[K]) => setD((x) => ({ ...x, [k]: v }));

  const missing = !d.firstName.trim() || d.gender === 'unknown' || d.manualAge == null || !d.religiousLevel;

  return (
    <form
      className="flex flex-col gap-5"
      onSubmit={(e) => {
        e.preventDefault();
        setTried(true);
        if (missing) return;
        onSave({ ...d, firstName: d.firstName.trim(), lastName: d.lastName?.trim() || null, city: d.city?.trim() || null, phone: d.phone?.trim() || null, description: d.description?.trim() || null, inquiryContactName: d.inquiryContactName?.trim() || null });
      }}
    >
      <div className="grid grid-cols-2 gap-3">
        <label>
          <Label required>שם פרטי</Label>
          <input className={cx(field, tried && !d.firstName.trim() && 'border-[#c0504d]')} value={d.firstName} onChange={(e) => set('firstName', e.target.value)} autoFocus />
        </label>
        <label>
          <Label>שם משפחה</Label>
          <input className={field} value={d.lastName ?? ''} onChange={(e) => set('lastName', e.target.value)} />
        </label>
      </div>

      <div>
        <Label required>מגדר</Label>
        <div className="flex gap-2">
          {(['male', 'female'] as Gender[]).map((gv) => (
            <Chip key={gv} active={d.gender === gv} color={gv === 'female' ? 'var(--c-female)' : 'var(--c-male)'} onClick={() => set('gender', gv)}>
              {gv === 'male' ? 'זכר' : 'נקבה'}
            </Chip>
          ))}
        </div>
        {tried && d.gender === 'unknown' && <p className="mt-1 text-[12px] text-[#c0504d]">יש לבחור מגדר</p>}
      </div>

      <div className="grid grid-cols-3 gap-3">
        <label>
          <Label required>גיל</Label>
          <input type="number" min={15} max={99} className={cx(field, tried && d.manualAge == null && 'border-[#c0504d]')} value={d.manualAge ?? ''} onChange={(e) => set('manualAge', e.target.value ? Number(e.target.value) : null)} />
        </label>
        <label>
          <Label>גובה (ס״מ)</Label>
          <input type="number" min={120} max={220} className={field} value={d.heightCm ?? ''} onChange={(e) => set('heightCm', e.target.value ? Number(e.target.value) : null)} />
        </label>
        <label>
          <Label>עיר</Label>
          <input className={field} value={d.city ?? ''} onChange={(e) => set('city', e.target.value)} />
        </label>
      </div>

      <div>
        <Label required>סגנון דתי</Label>
        <div className="flex flex-wrap gap-2">
          {RELIGIOUS_LEVELS_GLOBAL.map((l: ReligiousLevel) => (
            <Chip key={l} active={d.religiousLevel === l} onClick={() => set('religiousLevel', l)}>
              {RELIGIOUS_LABEL[l]}
            </Chip>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-5">
        <div>
          <Label>אזור בארץ</Label>
          <div className="flex flex-wrap gap-2">
            {REGIONS_SELECTABLE.map((r: Region) => (
              <Chip key={r} active={d.region === r} onClick={() => set('region', d.region === r ? null : r)}>
                {REGION_LABEL[r]}
              </Chip>
            ))}
          </div>
        </div>
        <div>
          <Label>מצב משפחתי</Label>
          <div className="flex flex-wrap gap-2">
            {MARITAL_STATUSES.map((m: MaritalStatus) => (
              <Chip key={m} active={d.maritalStatus === m} onClick={() => set('maritalStatus', d.maritalStatus === m ? null : m)}>
                {maritalLabel(m, d.gender)}
              </Chip>
            ))}
          </div>
        </div>
      </div>

      {!ownerCard && (
        <div className="grid grid-cols-2 gap-3">
          <label>
            <Label>{d.gender === 'female' ? 'הטלפון של החברה' : 'הטלפון של החבר'}</Label>
            <input dir="ltr" className={cx(field, 'text-end')} value={d.phone ?? ''} onChange={(e) => set('phone', e.target.value)} />
          </label>
          <label>
            <Label>איש קשר להעברת ההצעה</Label>
            <input className={field} value={d.inquiryContactName ?? ''} onChange={(e) => set('inquiryContactName', e.target.value)} />
          </label>
        </div>
      )}

      <label>
        <Label>כרטיסייה לשליחה</Label>
        <textarea
          rows={6}
          className="w-full rounded-xl border border-outline bg-page px-3.5 py-3 text-[15px] leading-relaxed outline-none focus:border-primary"
          value={d.description ?? ''}
          onChange={(e) => set('description', e.target.value)}
          placeholder="הדבק כרטיסייה כאן"
        />
      </label>

      {!ownerCard && (
        <div>
          <Label>תגיות</Label>
          <div className="flex flex-wrap items-center gap-2">
            {d.tags.map((t) => (
              <Chip key={t} active onClick={() => set('tags', d.tags.filter((x) => x !== t))}>
                {t} ✕
              </Chip>
            ))}
            <input
              className="h-8 w-40 rounded-full border border-outline bg-page px-3 text-[13px] outline-none focus:border-primary"
              placeholder="תגית חדשה + Enter"
              value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  const t = tagInput.trim();
                  if (t && !d.tags.includes(t)) set('tags', [...d.tags, t]);
                  setTagInput('');
                }
              }}
            />
          </div>
        </div>
      )}

      <div className="flex justify-end gap-2 border-t border-outline pt-4">
        <Button type="button" onClick={onCancel}>
          ביטול
        </Button>
        <Button type="submit" variant="primary">
          שמירה
        </Button>
      </div>
    </form>
  );
}
