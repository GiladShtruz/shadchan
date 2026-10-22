/** Pure migration planner. Inputs are immutable archives; retries are idempotent. */
export type RecordData = Record<string, any>;
export type Database = Record<string, Record<string, RecordData>>;
export const recordCollections = [
  'people',
  'personNotes',
  'personEvents',
  'matches',
  'matchNotes',
  'matchStatusEvents',
] as const;
export const sharedSetting = (key: string): boolean =>
  [
    'home.board',
    'home.boardSeen',
    'home.boardAllHidden',
    'tagLibrary',
    'tags.',
    'suggestionDismiss',
    'cardSyncRemote.',
    'deletedIdeas',
  ].some((p) => key.startsWith(p));
export function normalizedPhone(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  let phone = raw.replace(/\D/g, '');
  if (phone.startsWith('00')) phone = phone.slice(2);
  if (phone.startsWith('0')) phone = '972' + phone.slice(1);
  return phone.length >= 8 ? phone : null;
}
export function mergeRecord(a: RecordData, b: RecordData): RecordData {
  const out = { ...a };
  const conflicts = { ...a._mergeConflicts };
  for (const [key, value] of Object.entries(b)) {
    if (key === 'id' || key.startsWith('_')) continue;
    if (
      out[key] == null ||
      out[key] === '' ||
      (Array.isArray(out[key]) && out[key].length === 0)
    )
      out[key] = value;
    else if (Array.isArray(value) && Array.isArray(out[key]))
      out[key] = [...new Set([...out[key], ...value])];
    else if (
      value != null &&
      value !== '' &&
      JSON.stringify(out[key]) !== JSON.stringify(value)
    ) {
      // Both versions remain inspectable; never silently overwrite conflicting text.
      conflicts[key] = [
        ...new Set([...(conflicts[key] ?? []), out[key], value]),
      ];
      if (['description', 'notes'].includes(key))
        out[key] = `${out[key]}\n\n${value}`;
    }
  }
  out._mergeConflicts = conflicts;
  out._sources = [...new Set([...(a._sources ?? []), ...(b._sources ?? [])])];
  return out;
}
function mergeValue(a: any, b: any): any {
  if (a == null) return b;
  if (b == null) return a;
  if (Array.isArray(a) && Array.isArray(b))
    return [
      ...new Map([...a, ...b].map((v) => [JSON.stringify(v), v])).values(),
    ];
  if (
    typeof a === 'object' &&
    typeof b === 'object' &&
    !Array.isArray(a) &&
    !Array.isArray(b)
  ) {
    const out = { ...a };
    for (const [k, v] of Object.entries(b)) out[k] = mergeValue(out[k], v);
    return out;
  }
  if (typeof a === 'number' && typeof b === 'number') return Math.max(a, b);
  return a;
}
function remapValue(value: any, ids: Record<string, string>): any {
  if (Array.isArray(value)) return value.map((v) => remapValue(v, ids));
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [
        remapValue(k, ids),
        remapValue(v, ids),
      ]),
    );
  if (typeof value === 'string') {
    if (ids[value]) return ids[value];
    for (const [from, to] of Object.entries(ids))
      value = value
        .split(':' + from)
        .join(':' + to)
        .split('.' + from)
        .join('.' + to);
  }
  return value;
}
function decodeSetting(value: string): { value: any; nested: boolean } {
  let result = JSON.parse(value);
  const nested = typeof result === 'string';
  if (nested) {
    try {
      result = JSON.parse(result);
    } catch {
      return { value: result, nested: false };
    }
  }
  return { value: result, nested };
}

export function mergeDatabases(sources: { uid: string; data: Database }[]): {
  data: Database;
  ids: Record<string, Record<string, string>>;
  possibleDuplicates: string[][];
} {
  const data: Database = Object.fromEntries(
    [...recordCollections, 'settings'].map((c) => [c, {}]),
  );
  const ids: Record<string, Record<string, string>> = {};
  const phones = new Map<string, string>();
  const possibleDuplicates: string[][] = [];
  const names = new Map<string, string>();
  for (const { uid, data: source } of sources) {
    ids[uid] = {};
    for (const [oldId, raw] of Object.entries(source.people ?? {})) {
      if (raw._deleted) continue;
      const phone = normalizedPhone(raw.phone);
      const id = (phone && phones.get(phone)) || `${uid}__${oldId}`;
      ids[uid][oldId] = id;
      const person = {
        ...raw,
        id,
        _sources: [uid],
        _actorUid: raw._actorUid ?? uid,
        _authorUid: raw._authorUid ?? uid,
      };
      data.people[id] = data.people[id]
        ? mergeRecord(data.people[id], person)
        : person;
      if (phone) phones.set(phone, id);
      const name = `${raw.firstName ?? ''} ${raw.lastName ?? ''}`.trim();
      const previousNameId = names.get(name);
      if (
        name &&
        previousNameId &&
        previousNameId !== id &&
        (!phone || !normalizedPhone(data.people[previousNameId]?.phone))
      ) {
        possibleDuplicates.push([previousNameId, id]);
      }
      if (name) names.set(name, id);
    }
  }
  for (const { uid, data: source } of sources) {
    const matches: Record<string, string> = {};
    for (const oldId of Object.keys(source.matches ?? {}))
      matches[oldId] = `${uid}__${oldId}`;
    for (const collection of recordCollections.filter((c) => c !== 'people')) {
      for (const [oldId, raw] of Object.entries(source[collection] ?? {})) {
        if (raw._deleted) continue;
        const id = `${uid}__${oldId}`;
        const value: RecordData = {
          ...raw,
          id,
          _sources: [uid],
          _actorUid: raw._actorUid ?? uid,
          _authorUid: raw._authorUid ?? uid,
        };
        for (const field of [
          'personId',
          'personAId',
          'personBId',
          'relatedPersonId',
        ])
          if (value[field])
            value[field] = ids[uid][value[field]] ?? value[field];
        for (const field of ['matchId', 'relatedMatchId'])
          if (value[field])
            value[field] = matches[value[field]] ?? value[field];
        if (collection === 'matches') {
          // Kept per account separately by migration/runtime, never shared.
          delete value.reminderDate;
          delete value.reminderNote;
        }
        data[collection][id] = value;
      }
    }
    for (const [oldId, value] of Object.entries(source.settings ?? {})) {
      if (!sharedSetting(value.k ?? '')) continue;
      const mapping = { ...ids[uid], ...matches };
      const key = remapValue(value.k, mapping);
      const id = encodeURIComponent(key);
      try {
        const incoming = decodeSetting(value.v);
        let merged = remapValue(incoming.value, mapping);
        if (data.settings[id])
          merged = mergeValue(decodeSetting(data.settings[id].v).value, merged);
        data.settings[id] = {
          ...value,
          k: key,
          v: JSON.stringify(incoming.nested ? JSON.stringify(merged) : merged),
        };
      } catch {
        // Preserve malformed legacy settings and both originals in the immutable archives.
        data.settings[id || oldId] ??= { ...value };
      }
    }
  }
  return { data, ids, possibleDuplicates };
}
export function splitDatabase(data: Database, uid: string): Database {
  const out: Database = Object.fromEntries(
    [...recordCollections, 'settings'].map((c) => [c, {}]),
  );
  const owned = new Set(
    Object.entries(data.people ?? {})
      .filter(([, p]) => !p._deleted && p._sources?.includes(uid))
      .map(([id]) => id),
  );
  const needed = new Set(owned);
  const ideas = new Set<string>();
  for (const [id, idea] of Object.entries(data.matches ?? {})) {
    if (
      !idea._deleted &&
      (owned.has(idea.personAId) || owned.has(idea.personBId))
    ) {
      ideas.add(id);
      needed.add(idea.personAId);
      needed.add(idea.personBId);
      out.matches[id] = { ...idea };
    }
  }
  for (const id of needed)
    if (data.people[id]) out.people[id] = { ...data.people[id] };
  for (const collection of ['personNotes', 'personEvents'])
    for (const [id, value] of Object.entries(data[collection] ?? {})) {
      if (needed.has(value.personId)) out[collection][id] = { ...value };
    }
  for (const collection of ['matchNotes', 'matchStatusEvents'])
    for (const [id, value] of Object.entries(data[collection] ?? {})) {
      if (ideas.has(value.matchId)) out[collection][id] = { ...value };
    }
  // Shared board/settings may contain IDs from the other half; only shared tag definitions travel.
  for (const [id, value] of Object.entries(data.settings ?? {}))
    if ((value.k ?? '').startsWith('tags.') || value.k === 'tagLibrary')
      out.settings[id] = { ...value };
  return out;
}
