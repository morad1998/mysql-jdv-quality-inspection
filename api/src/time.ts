/**
 * A UTC timestamp in the form MySQL writes inside documents: 'YYYY-MM-DD HH:MM:SS.ffffff'.
 * Truncated to whole seconds, never rounded: the card tables use DATETIME without fractional seconds, so the API sends
 * exactly the value the column keeps.
 */
export function mysqlDatetime(date: Date = new Date()): string {
  const whole = new Date(Math.floor(date.getTime() / 1000) * 1000);
  return whole.toISOString().replace('T', ' ').replace('Z', '') + '000';
}
