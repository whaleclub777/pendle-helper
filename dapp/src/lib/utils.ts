export function formatTime(timestamp: number | string | Date) {
  // TODO: human time
  const date = new Date(timestamp)
  return date.toLocaleString()
}
