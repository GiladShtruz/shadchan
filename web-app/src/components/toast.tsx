'use client';

import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react';

/** `AppToast`: one quiet message at the bottom, gone by itself, one at a time. */

interface ToastState {
  text: string;
  actionLabel?: string;
  onAction?: () => void;
  key: number;
}

type Show = (text: string, action?: { label: string; run: () => void }, options?: { priority?: boolean }) => void;

const Ctx = createContext<Show>(() => {});

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<ToastState | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // A priority message (e.g. "this is read-only") is not replaced by the
  // success message the same click goes on to show.
  const lockedUntil = useRef(0);

  const show = useCallback<Show>((text, action, options) => {
    if (!options?.priority && Date.now() < lockedUntil.current) return;
    if (options?.priority) lockedUntil.current = Date.now() + 1500;
    if (timer.current) clearTimeout(timer.current);
    setToast({ text, actionLabel: action?.label, onAction: action?.run, key: Date.now() });
    timer.current = setTimeout(() => setToast(null), action ? 4000 : options?.priority ? 4500 : 2600);
  }, []);

  return (
    <Ctx.Provider value={show}>
      {children}
      {toast && (
        <div className="pointer-events-none fixed inset-x-0 bottom-6 z-[100] flex justify-center px-4">
          <div
            key={toast.key}
            role="status"
            className="fade-up pointer-events-auto flex items-center gap-4 rounded-2xl border border-outline bg-cream px-5 py-3 text-[15px] font-semibold text-heading shadow-lg"
          >
            <span>{toast.text}</span>
            {toast.actionLabel && (
              <button
                className="font-bold text-copper-ink hover:underline"
                onClick={() => {
                  toast.onAction?.();
                  setToast(null);
                }}
              >
                {toast.actionLabel}
              </button>
            )}
          </div>
        </div>
      )}
    </Ctx.Provider>
  );
}

export const useToast = () => useContext(Ctx);
