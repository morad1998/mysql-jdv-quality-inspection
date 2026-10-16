import { HttpError } from './errors.ts';

/** HTTP ETag header value for a MySQL document ETag (a hex string). */
export function formatEtag(etag: string): string {
  return `"${etag}"`;
}

/**
 * Reads If-Match. Only one strong ETag is accepted: no '*', no list, no weak 'W/' prefix.
 * Missing header: 428. Present but not usable: 400.
 */
export function readIfMatch(header: string | undefined): string {
  if (header === undefined || header.trim() === '') {
    throw new HttpError(428, 'IF_MATCH_REQUIRED', 'Send the ETag you read in an If-Match header.');
  }
  const match = /^"([0-9a-fA-F]{8,128})"$/.exec(header.trim());
  if (!match || match[1] === undefined) {
    throw new HttpError(400, 'INVALID_IF_MATCH', 'If-Match must hold exactly one ETag in quotes, as returned by the API.');
  }
  return match[1].toLowerCase();
}
