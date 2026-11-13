'use client';

import { useEffect, useRef, useState, type ButtonHTMLAttributes, type ReactNode, type RefObject } from 'react';
import { useStore } from '@/data/store';
import { usePhotoUrl } from '@/data/photos';
import { X } from 'lucide-react';
import { profileStatusLabel, type Gender, type ProfileStatus } from '@/domain/enums';
import type { Person } from '@/domain/types';
import { fullName } from '@/domain/logic';

export function cx(...parts: (string | false | null | undefined)[]): string {
  return parts.filter(Boolean).join(' ');
}

export const genderColor = (g: Gender | null | undefined) =>
  g === 'female' ? 'var(--c-female)' : g === 'male' ? 'var(--c-male)' : 'var(--c-muted)';

const PASTELS = [
  { bg: '#efdde4', ink: '#a9748a' },
  { bg: '#d7e4ea', ink: '#5f7f8c' },
  { bg: '#dde3cf', ink: '#6f7a55' },
  { bg: '#ddd7e7', ink: '#7a6e93' },
  { bg: '#e6d4c0', ink: '#a96b49' },
  { bg: '#efe0b8', ink: '#8a7333' },
];

function pastel(seed: string) {
  let h = 0;
  for (const ch of seed) h = (h * 31 + ch.charCodeAt(0)) & 0x7fffffff;
  return PASTELS[h % PASTELS.length];
}

/** True once [ref] has scrolled into view (and stays true). */
function useSeen<T extends Element>(): [RefObject<T | null>, boolean] {
  const ref = useRef<T>(null);
  const [seen, setSeen] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el || seen) return;
    if (typeof IntersectionObserver === 'undefined') {
      setSeen(true);
      return;
    }
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        setSeen(true);
        io.disconnect();
      }
    }, { rootMargin: '200px' });
    io.observe(el);
    return () => io.disconnect();
  }, [seen]);
  return [ref, seen];
}

/**
 * A face: the person's first photo when there is one (live data only), else
 * the fixed default per gender, ringed in the person's own colour.
 */
export function Avatar({ person, size = 40, ring = true }: { person: Pick<Person, 'id' | 'firstName' | 'gender'> & { photos?: string[] }; size?: number; ring?: boolean }) {
  const { photoRoot } = useStore();
  const [ref, seen] = useSeen<HTMLSpanElement>();
  const photo = usePhotoUrl(photoRoot, person.photos?.[0], seen);
  const fallback = person.gender === 'female' ? '/avatar-female.webp' : person.gender === 'male' ? '/avatar-male.webp' : null;
  const src = photo ?? fallback;
  if (!src) {
    const p = pastel(person.id);
    return (
      <span
        ref={ref}
        className="inline-flex shrink-0 items-center justify-center rounded-full font-bold"
        style={{ width: size, height: size, background: p.bg, color: p.ink, fontSize: size * 0.42 }}
      >
        {person.firstName.slice(0, 1)}
      </span>
    );
  }
  return (
    <span ref={ref} className="inline-flex shrink-0">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={src}
        alt=""
        width={size}
        height={size}
        className="shrink-0 rounded-full bg-oat object-cover"
        style={{ width: size, height: size, boxShadow: ring ? `0 0 0 2px var(--c-page), 0 0 0 3.5px ${genderColor(person.gender)}` : undefined }}
      />
    </span>
  );
}

export function InitialAvatar({ name, seed, size = 36 }: { name: string; seed: string; size?: number }) {
  const p = pastel(seed);
  return (
    <span
      className="inline-flex shrink-0 items-center justify-center rounded-full font-bold"
      style={{ width: size, height: size, background: p.bg, color: p.ink, fontSize: size * 0.42 }}
    >
      {name.trim().slice(0, 1)}
    </span>
  );
}

const STATUS_DOT: Record<ProfileStatus, string> = {
  available: '#5f9a5b',
  busy: '#c0504d',
  onBreak: '#9b7650',
  mazelTov: '#c1845b',
};

/** `ProfileStatusTag`: the word in the person's colour, the state in a dot. */
export function StatusTag({ status, gender, className }: { status: ProfileStatus; gender: Gender; className?: string }) {
  return (
    <span className={cx('inline-flex items-center gap-1.5 text-[13px] font-semibold', className)} style={{ color: genderColor(gender) }}>
      <span className="h-2 w-2 rounded-full" style={{ background: STATUS_DOT[status] }} />
      {profileStatusLabel(status, gender)}
    </span>
  );
}

export function PersonName({ person, className }: { person: Person; className?: string }) {
  return (
    <span className={cx('font-bold', className)} style={{ color: genderColor(person.gender) }}>
      {fullName(person)}
    </span>
  );
}

type Variant = 'primary' | 'copper' | 'outline' | 'ghost' | 'danger';

export function Button({
  variant = 'outline',
  size = 'md',
  className,
  children,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: 'sm' | 'md' }) {
  const v: Record<Variant, string> = {
    primary: 'bg-male text-white hover:brightness-110 border-transparent',
    copper: 'bg-copper text-white hover:brightness-105 border-transparent',
    outline: 'bg-page text-body border-outline hover:bg-oat',
    ghost: 'bg-transparent text-heading border-transparent hover:bg-oat',
    danger: 'bg-page text-[#b3412e] border-outline hover:bg-[#fbeceb]',
  };
  return (
    <button
      type="button"
      className={cx(
        'inline-flex items-center justify-center gap-2 rounded-xl border font-semibold transition disabled:cursor-not-allowed disabled:opacity-50',
        size === 'sm' ? 'h-8 px-3 text-[13px]' : 'h-10 px-4 text-[14px]',
        v[variant],
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  );
}

/** `HomePaperCard`: cream, soft shadow, one accent rule along the foot. */
export function PaperCard({ accent, className, children }: { accent?: string; className?: string; children: ReactNode }) {
  return (
    <section className={cx('card relative overflow-hidden', className)}>
      {children}
      {accent && <span className="absolute inset-x-5 bottom-0 h-[3px] rounded-full" style={{ background: accent }} />}
    </section>
  );
}

export function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between gap-3">
      <h2 className="text-[17px] font-extrabold text-heading">{children}</h2>
      {action}
    </div>
  );
}

export function Chip({ active, onClick, children, color }: { active?: boolean; onClick?: () => void; children: ReactNode; color?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={!!active}
      className={cx(
        'inline-flex h-8 items-center gap-1.5 rounded-full border px-3 text-[13px] whitespace-nowrap transition',
        active ? 'font-bold' : 'border-outline bg-page text-body hover:bg-oat',
      )}
      style={active ? { borderColor: color ?? 'var(--c-primary)', background: color ? `color-mix(in srgb, ${color} 14%, white)` : 'var(--c-primary-light)', color: color ?? 'var(--c-heading)' } : undefined}
    >
      {children}
    </button>
  );
}

export function Modal({ open, onClose, title, children, width = 480 }: { open: boolean; onClose: () => void; title: string; children: ReactNode; width?: number }) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgb(33_29_23/0.28)] p-4" onMouseDown={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="fade-up max-h-[88vh] w-full overflow-auto rounded-2xl bg-page p-6 shadow-2xl scroll-thin"
        style={{ maxWidth: width }}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-[19px] font-extrabold text-heading">{title}</h3>
          <button aria-label="סגירה" className="rounded-lg p-1.5 text-muted hover:bg-oat" onClick={onClose}>
            <X size={18} />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 py-14 text-center">
      <p className="text-[16px] font-bold text-heading">{title}</p>
      {children && <div className="max-w-sm text-[14px] text-muted">{children}</div>}
    </div>
  );
}

export function WhatsAppIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden fill="currentColor">
      <path d="M12.04 2C6.58 2 2.13 6.45 2.13 11.91c0 1.75.46 3.45 1.32 4.95L2.05 22l5.25-1.38a9.9 9.9 0 0 0 4.74 1.21h.01c5.46 0 9.91-4.45 9.91-9.91 0-2.65-1.03-5.14-2.9-7.01A9.82 9.82 0 0 0 12.04 2Zm5.8 14.03c-.24.68-1.42 1.3-1.95 1.35-.5.05-.98.24-3.3-.69-2.8-1.1-4.58-3.97-4.72-4.15-.14-.18-1.12-1.49-1.12-2.85 0-1.35.71-2.02.96-2.29.25-.28.55-.35.73-.35l.53.01c.17 0 .4-.06.62.48.24.56.8 1.94.87 2.08.07.14.12.3.02.48-.09.18-.14.3-.28.46l-.42.49c-.14.14-.28.29-.12.57.16.28.72 1.19 1.55 1.92 1.07.95 1.97 1.24 2.25 1.38.28.14.44.12.6-.07.17-.19.7-.81.89-1.09.18-.28.37-.23.62-.14.25.09 1.6.76 1.87.9.28.14.46.21.53.32.07.12.07.66-.17 1.34Z" />
    </svg>
  );
}
