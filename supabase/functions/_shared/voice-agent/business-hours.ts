// Helpers for business hours scheduling (10 AM - 6 PM, Mon-Sat) in showroom timezone

const BUSINESS_START = 10 // 10 AM
const BUSINESS_END = 18 // 6 PM

interface LocalTime {
  year: number
  month: number // 0-indexed
  day: number
  hour: number
  minute: number
  weekday: string
  hourDecimal: number
  isSunday: boolean
}

function getLocalTime(date: Date, timezone: string): LocalTime {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    hour: 'numeric', minute: 'numeric', hour12: false,
    weekday: 'short', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(date)

  const hour = parseInt(parts.find(p => p.type === 'hour')?.value || '0')
  const minute = parseInt(parts.find(p => p.type === 'minute')?.value || '0')
  const weekday = parts.find(p => p.type === 'weekday')?.value || ''
  const year = parseInt(parts.find(p => p.type === 'year')?.value || '2026')
  const month = parseInt(parts.find(p => p.type === 'month')?.value || '1') - 1
  const day = parseInt(parts.find(p => p.type === 'day')?.value || '1')

  return {
    year, month, day, hour, minute, weekday,
    hourDecimal: hour + minute / 60,
    isSunday: weekday === 'Sun',
  }
}

// Convert a local-time intent (year/month/day/hour/min in given timezone) to a UTC Date
function localToUtc(year: number, month: number, day: number, hour: number, minute: number, timezone: string): Date {
  // Use a noon-of-day reference to compute the timezone offset (avoids DST edge cases)
  const utcRef = new Date(Date.UTC(year, month, day, 12, 0))
  const tzNoonHour = parseInt(
    new Intl.DateTimeFormat('en-US', { timeZone: timezone, hour: 'numeric', hour12: false })
      .formatToParts(utcRef)
      .find(p => p.type === 'hour')?.value || '12'
  )
  const offsetHours = tzNoonHour - 12 // positive if ahead of UTC
  const tentative = new Date(Date.UTC(year, month, day, hour, minute))
  tentative.setHours(tentative.getHours() - offsetHours)
  return tentative
}

/**
 * Returns a Date (UTC) representing the next business day at a random time
 * between 10 AM and 6 PM in the showroom timezone.
 */
export function getNextBusinessDayTime(timezone: string, fromDate: Date = new Date()): Date {
  const local = getLocalTime(fromDate, timezone)

  let daysToAdd = 1
  // If currently Saturday (any time), next business day is Monday
  if (local.weekday === 'Sat') {
    daysToAdd = 2
  }
  // Random time between BUSINESS_START and BUSINESS_END (in minutes)
  const randomMinutes = BUSINESS_START * 60 + Math.floor(Math.random() * (BUSINESS_END - BUSINESS_START) * 60)
  const randomHour = Math.floor(randomMinutes / 60)
  const randomMin = randomMinutes % 60

  return localToUtc(local.year, local.month, local.day + daysToAdd, randomHour, randomMin, timezone)
}

/**
 * Returns true if the current time in the given timezone is within business hours (10 AM - 6 PM, Mon-Sat).
 */
export function isWithinBusinessHours(timezone: string, date: Date = new Date()): boolean {
  const local = getLocalTime(date, timezone)
  if (local.isSunday) return false
  return local.hourDecimal >= BUSINESS_START && local.hourDecimal < BUSINESS_END
}

/**
 * Returns a Date (UTC) for the next valid business time, with random spread if outside hours.
 * If currently within business hours: returns now (or fromDate).
 * If outside: returns next business day random time.
 */
export function getNextValidBusinessTime(timezone: string, fromDate: Date = new Date()): Date {
  if (isWithinBusinessHours(timezone, fromDate)) {
    return fromDate
  }
  const local = getLocalTime(fromDate, timezone)
  // Before 10 AM today and not Sunday → today at random time
  if (!local.isSunday && local.hourDecimal < BUSINESS_START) {
    const randomMinutes = BUSINESS_START * 60 + Math.floor(Math.random() * (BUSINESS_END - BUSINESS_START) * 60)
    const randomHour = Math.floor(randomMinutes / 60)
    const randomMin = randomMinutes % 60
    return localToUtc(local.year, local.month, local.day, randomHour, randomMin, timezone)
  }
  // After hours or Sunday → next business day
  return getNextBusinessDayTime(timezone, fromDate)
}
