/** Seeded names and defaults never turn an empty draft into a published card. */
export function isActiveCard(
  data: Record<string, unknown> | undefined,
): boolean {
  if (!data || data.deleted === true) return false;
  return (
    (Array.isArray(data.photoPaths) && data.photoPaths.length > 0) ||
    (typeof data.description === 'string' &&
      [...data.description.trim()].length >= 30)
  );
}
