'use client';

import type { ReactNode } from 'react';
import { useStore } from '@/data/store';
import { Empty } from '@/components/ui';

/** The personal area needs a card; without one there is nothing to show yet. */
export default function PersonalLayout({ children }: { children: ReactNode }) {
  const { personal, liveStatus } = useStore();
  if (personal) return <>{children}</>;
  if (liveStatus === 'connecting') return <Empty title="טוען…" />;
  return (
    <Empty title="עוד אין לך כרטיס אישי">
      את הכרטיס האישי יוצרים באפליקציה, באזור האישי. ברגע שייווצר הוא יופיע כאן.
    </Empty>
  );
}
