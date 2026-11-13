'use client';

import { useEffect, useState } from 'react';
import { getDownloadURL, ref } from 'firebase/storage';
import { fb } from './firebase';

/**
 * A person's photo from Cloud Storage. Records carry basenames only; the
 * account's files sit under `users/{uid}/photos/` (a couple's under
 * `coupleFiles/{operation}/photos/`). Resolved once per file per session, and
 * only when the face is actually on screen.
 */
const cache = new Map<string, Promise<string | null>>();

export function photoUrl(root: string, basename: string): Promise<string | null> {
  const key = `${root}/${basename}`;
  let hit = cache.get(key);
  if (!hit) {
    hit = getDownloadURL(ref(fb().storage, key)).catch(() => null);
    cache.set(key, hit);
  }
  return hit;
}

export function usePhotoUrl(root: string | null, basename: string | null | undefined, visible: boolean): string | null {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (!root || !basename || !visible) return;
    let live = true;
    photoUrl(root, basename).then((u) => live && setUrl(u));
    return () => {
      live = false;
    };
  }, [root, basename, visible]);
  return root && basename ? url : null;
}
