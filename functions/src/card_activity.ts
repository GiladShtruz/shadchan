/** The fewest words of card text a live card carries. */
export const MIN_CARD_WORDS = 20;

/** Whitespace-separated words, counted as the client and the rules count them. */
export function cardWordCount(text: unknown): number {
  if (typeof text !== 'string') return 0;
  const trimmed = text.trim();
  return trimmed.length === 0 ? 0 : trimmed.split(/\s+/u).length;
}

/**
 * A card is live only with at least one photo **and** at least
 * [MIN_CARD_WORDS] words of text. Seeded names and defaults never turn an
 * empty draft into a published card, and neither does a photo alone or a
 * paragraph alone: until both are there nobody is told about the card,
 * nobody lists it, and nobody may ask for access to it.
 * Mirrors `PersonalCardCodec.isActive` and `activeCard` in `firestore.rules`.
 */
export function isActiveCard(
  data: Record<string, unknown> | undefined,
): boolean {
  if (!data || data.deleted === true) return false;
  return (
    Array.isArray(data.photoPaths) &&
    data.photoPaths.length > 0 &&
    cardWordCount(data.description) >= MIN_CARD_WORDS
  );
}
