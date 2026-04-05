// Google Maps Distance Matrix utility for Voice Agent
// Pattern follows /supabase/functions/_shared/email.ts

import { supabaseAdmin } from '../../supabase/functions/_shared/supabase.ts'

interface CalculateDistanceOptions {
  customerAddress: string
  showroomAddress: string
}

interface DistanceData {
  distanceMiles: number
  distanceKm: number
  driveTimeMinutes: number
}

/**
 * Fetch a platform setting by key from the platform_settings table.
 * Returns null if not found.
 */
async function getPlatformSetting(key: string): Promise<string | null> {
  const { data, error } = await supabaseAdmin
    .from('platform_settings')
    .select('value')
    .eq('key', key)
    .single()

  if (error || !data) {
    console.error(`[VOICE_DISTANCE] Failed to read platform_settings key "${key}":`, error?.message)
    return null
  }

  return data.value
}

/**
 * Calculate driving distance and time between two addresses using the
 * Google Maps Distance Matrix API.
 *
 * Reads credentials from platform_settings:
 *   - google_maps_api_key
 *
 * Returns distance in miles/km and drive time in minutes.
 * Returns null on any error (missing addresses, API failure, no route found).
 *
 * NOTE: Does not determine zone (near/far). Use determineZone() separately.
 */
export async function calculateDistance(
  options: CalculateDistanceOptions
): Promise<DistanceData | null> {
  const { customerAddress, showroomAddress } = options

  // 1. Validate addresses
  if (!customerAddress || !customerAddress.trim()) {
    console.log('[VOICE_DISTANCE] Customer address is empty, skipping distance calculation')
    return null
  }

  if (!showroomAddress || !showroomAddress.trim()) {
    console.log('[VOICE_DISTANCE] Showroom address is empty, skipping distance calculation')
    return null
  }

  console.log('[VOICE_DISTANCE] Calculating distance', {
    from: customerAddress,
    to: showroomAddress,
  })

  try {
    // 2. Read Google Maps API key
    const apiKey = await getPlatformSetting('google_maps_api_key')

    if (!apiKey) {
      console.error('[VOICE_DISTANCE] google_maps_api_key not configured in platform_settings')
      return null
    }

    // 3. Call Distance Matrix API
    const params = new URLSearchParams({
      origins: customerAddress,
      destinations: showroomAddress,
      units: 'imperial',
      key: apiKey,
    })

    const url = `https://maps.googleapis.com/maps/api/distancematrix/json?${params.toString()}`

    const response = await fetch(url)
    const data = await response.json()

    console.log('[VOICE_DISTANCE] Google Maps API response status:', data.status)

    if (data.status !== 'OK') {
      console.error('[VOICE_DISTANCE] Distance Matrix API error:', data.status, data.error_message)
      return null
    }

    // 4. Parse the first result element
    const element = data.rows?.[0]?.elements?.[0]

    if (!element || element.status !== 'OK') {
      console.error('[VOICE_DISTANCE] No valid route found, element status:', element?.status)
      return null
    }

    // 5. Convert values
    // distance.value is in meters
    const distanceMeters = element.distance.value
    const distanceMiles = Math.round((distanceMeters / 1609.34) * 100) / 100
    const distanceKm = Math.round((distanceMeters / 1000) * 100) / 100

    // duration.value is in seconds
    const durationSeconds = element.duration.value
    const driveTimeMinutes = Math.round(durationSeconds / 60)

    console.log('[VOICE_DISTANCE] Distance calculated', {
      distanceMiles,
      distanceKm,
      driveTimeMinutes,
      rawDistanceText: element.distance.text,
      rawDurationText: element.duration.text,
    })

    return {
      distanceMiles,
      distanceKm,
      driveTimeMinutes,
    }
  } catch (error) {
    console.error('[VOICE_DISTANCE] Unexpected error calculating distance:', error)
    return null
  }
}

/**
 * Determine whether a customer is "near" or "far" from the showroom
 * based on a configurable distance threshold in miles.
 */
export function determineZone(
  distanceMiles: number,
  thresholdMiles: number
): 'near' | 'far' {
  return distanceMiles <= thresholdMiles ? 'near' : 'far'
}
