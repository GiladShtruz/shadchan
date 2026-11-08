/**
 * "בעיות בולטות" — the administrators' early warning.
 *
 * Computed with the dashboard (`admin_stats.ts`) every few hours. Each rule
 * compares a figure with the same figure a little earlier and raises an alert
 * only on a clear break, with a floor on the numbers involved so that a quiet
 * night on a small app does not page anybody. A new alert also lands in each
 * administrator's notifications (kind `adminAlert`, pushed).
 *
 * Like everything on the dashboard, an alert carries counts only.
 */

export interface AdminAlert {
  code: string;
  severity: 'high' | 'medium';
  title: string;
  detail: string;
}

/** One device's `contacts` block from `accountHealth/{uid}.devices`. */
export interface ContactsDevice {
  appVersion?: string;
  readAt?: number;
  failedAt?: number;
  failure?: string;
  permission?: string;
  suitable?: number;
  deviceCount?: number;
}

export interface ContactsBlock {
  devices: number;
  readers7: number;
  failing7: number;
  failurePercent: number;
  blocked: number;
  denied: number;
  topFailure: string;
  versions: { version: string; devices: number; medianSuitable: number }[];
}

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** "1.0.21+64" or "1.0.21 (64)" → [1, 0, 21, 64], for ordering versions. */
function versionParts(version: string): number[] {
  return version
    .split(/\D+/)
    .filter((p) => p.length > 0)
    .map((p) => Number.parseInt(p, 10));
}

export function compareVersions(a: string, b: string): number {
  const pa = versionParts(a);
  const pb = versionParts(b);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

/** Folds every device's contacts report into counts. */
export function contactsBlock(devices: ContactsDevice[], now: number): ContactsBlock {
  const recent = devices.filter(
    (d) => (d.readAt ?? 0) >= now - 30 * DAY || (d.failedAt ?? 0) >= now - 30 * DAY,
  );
  const readers7 = recent.filter((d) => (d.readAt ?? 0) >= now - 7 * DAY);
  const failing7 = recent.filter(
    (d) => (d.failedAt ?? 0) >= now - 7 * DAY && (d.readAt ?? 0) < (d.failedAt ?? 0),
  );
  const failures = new Map<string, number>();
  for (const d of failing7) {
    const code = d.failure ?? 'unknown';
    failures.set(code, (failures.get(code) ?? 0) + 1);
  }
  const topFailure = [...failures.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? '';

  const byVersion = new Map<string, number[]>();
  for (const d of recent) {
    if (!d.appVersion || typeof d.suitable !== 'number' || (d.readAt ?? 0) < now - 30 * DAY) continue;
    const list = byVersion.get(d.appVersion) ?? [];
    list.push(d.suitable);
    byVersion.set(d.appVersion, list);
  }
  const versions = [...byVersion.entries()]
    .map(([version, values]) => ({ version, devices: values.length, medianSuitable: median(values) }))
    .sort((a, b) => compareVersions(b.version, a.version))
    .slice(0, 6);

  const attempted = readers7.length + failing7.length;
  return {
    devices: recent.length,
    readers7: readers7.length,
    failing7: failing7.length,
    failurePercent: attempted ? Math.round((failing7.length / attempted) * 100) : 0,
    blocked: recent.filter((d) => d.permission === 'blocked').length,
    denied: recent.filter((d) => d.permission === 'denied').length,
    topFailure,
    versions,
  };
}

export interface AlertInputs {
  now: number;
  contacts: ContactsBlock;
  /** The raw per-device reports, for the per-version comparison. */
  contactDevices: ContactsDevice[];
  dau: number;
  /** DAU in the daily snapshots of the last week, oldest first. */
  dauHistory: number[];
  new7: number;
  newPrev7: number;
  pending: number;
  pendingWeekAgo: number | null;
  /** When the hourly reminders job last ran (ms), or null if never. */
  remindersLastRunAt: number | null;
}

export function computeAlerts(input: AlertInputs): AdminAlert[] {
  const alerts: AdminAlert[] = [];
  const c = input.contacts;

  if (c.failing7 >= 3 && c.failurePercent >= 20) {
    alerts.push({
      code: 'contacts_failing',
      severity: 'high',
      title: 'טעינת אנשי קשר נכשלת',
      detail:
        `${c.failing7} מכשירים (${c.failurePercent}%) נכשלו בקריאת אנשי הקשר בשבוע האחרון` +
        (c.topFailure ? ` · סוג השגיאה הנפוץ: ${c.topFailure}` : ''),
    });
  }

  // The newest version finds far fewer contacts than the versions before it.
  const versions = [...new Set(input.contactDevices.map((d) => d.appVersion).filter((v): v is string => !!v))]
    .sort(compareVersions);
  const newest = versions[versions.length - 1];
  if (newest && versions.length > 1) {
    const fresh = (d: ContactsDevice) =>
      typeof d.suitable === 'number' && (d.readAt ?? 0) >= input.now - 30 * DAY;
    const mine = input.contactDevices.filter((d) => d.appVersion === newest && fresh(d)).map((d) => d.suitable!);
    const others = input.contactDevices.filter((d) => d.appVersion !== newest && fresh(d)).map((d) => d.suitable!);
    const m = median(mine);
    const o = median(others);
    if (mine.length >= 3 && others.length >= 3 && o >= 20 && m < o * 0.5) {
      alerts.push({
        code: 'contacts_version_drop',
        severity: 'high',
        title: `גרסה ${newest} מוצאת פחות אנשי קשר`,
        detail: `חציון אנשי הקשר המתאימים בגרסה החדשה ${Math.round(m)}, לעומת ${Math.round(o)} בגרסאות הקודמות`,
      });
    }
  }

  const dauAvg = input.dauHistory.length
    ? input.dauHistory.reduce((a, b) => a + b, 0) / input.dauHistory.length
    : 0;
  if (input.dauHistory.length >= 3 && dauAvg >= 10 && input.dau < dauAvg * 0.5) {
    alerts.push({
      code: 'dau_drop',
      severity: 'medium',
      title: 'ירידה חדה בפעילים היום',
      detail: `${input.dau} פעילים ב־24 השעות האחרונות, לעומת ממוצע של ${Math.round(dauAvg)} בשבוע שעבר`,
    });
  }

  if (input.newPrev7 >= 10 && input.new7 < input.newPrev7 * 0.4) {
    alerts.push({
      code: 'signups_drop',
      severity: 'medium',
      title: 'ירידה בהרשמות',
      detail: `${input.new7} משתמשים חדשים השבוע, לעומת ${input.newPrev7} בשבוע שלפניו`,
    });
  }

  if (input.pendingWeekAgo !== null && input.pending >= 20 && input.pending >= input.pendingWeekAgo * 2) {
    alerts.push({
      code: 'pending_requests_pile',
      severity: 'medium',
      title: 'בקשות גישה מצטברות',
      detail: `${input.pending} בקשות גישה ממתינות, לעומת ${input.pendingWeekAgo} לפני שבוע`,
    });
  }

  if (input.remindersLastRunAt !== null && input.remindersLastRunAt < input.now - 3 * HOUR) {
    const hours = Math.floor((input.now - input.remindersLastRunAt) / HOUR);
    alerts.push({
      code: 'reminders_stale',
      severity: 'high',
      title: 'התזכורות מהשרת לא רצות',
      detail: `התזכורות לא נשלחו כבר ${hours} שעות. מכשירים יחזרו לתזמן תזכורות בעצמם אחרי 6 שעות.`,
    });
  }

  return alerts;
}

/** The alerts in [next] that were not in [previous] — the ones to tell about. */
export function newAlerts(previous: AdminAlert[] | undefined, next: AdminAlert[]): AdminAlert[] {
  const seen = new Set((previous ?? []).map((a) => a.code));
  return next.filter((a) => !seen.has(a.code));
}
