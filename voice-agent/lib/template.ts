// Template interpolation utilities for Voice Agent
// Used to resolve {{variable}} tokens in SMS templates and system prompts

import type { VoiceAgentTriggerPayload } from '../types/index.ts'

/**
 * Replace all {{variable_name}} tokens in a template string.
 * Unknown or null/undefined variables resolve to empty string.
 *
 * @example
 * interpolate('Hi {{name}}, ref {{ref}}', { name: 'John', ref: 'CS-001' })
 * // => 'Hi John, ref CS-001'
 */
export function interpolate(
  template: string,
  vars: Record<string, string | number | null | undefined>
): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    const val = vars[key]
    return val != null ? String(val) : ''
  })
}

/**
 * Build the full template variables map from a trigger payload and optional
 * distance data. Returns a flat Record<string, string> suitable for passing
 * to interpolate().
 *
 * Covers: customer, end_client, project, showroom, and distance variables.
 */
export function buildTemplateVariables(
  payload: VoiceAgentTriggerPayload,
  distance?: {
    distanceMiles: number
    distanceKm: number
    driveTimeMinutes: number
    zone: string
  } | null
): Record<string, string> {
  const { customer, end_client, project, showroom } = payload

  // Build full showroom address from parts
  const showroomAddress = [
    showroom.address_line1,
    showroom.city,
    showroom.state,
    showroom.postal_code,
  ]
    .filter(Boolean)
    .join(', ')

  // Format submitted_at as a human-readable date string
  const submittedDate = project.submitted_at
    ? new Date(project.submitted_at).toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : ''

  return {
    // Customer variables
    customer_first_name: customer.first_name || '',
    customer_last_name: customer.last_name || '',
    customer_full_name: [customer.first_name, customer.last_name]
      .filter(Boolean)
      .join(' '),
    customer_phone: customer.phone_normalized || '',
    customer_email: customer.email || '',
    customer_type: customer.customer_type || 'homeowner',
    customer_address: customer.address_line1 || '',
    customer_city: customer.city || '',
    customer_state: customer.state || '',
    customer_zip: customer.zip_code || '',

    // End Client variables (may be null if customer_type is homeowner)
    end_client_first_name: end_client?.first_name || '',
    end_client_last_name: end_client?.last_name || '',
    end_client_phone: end_client?.phone || '',
    end_client_email: end_client?.email || '',
    end_client_address: end_client?.address || '',

    // Project variables
    project_name: project.name || '',
    reference_number: project.reference_number || '',
    project_notes: project.notes || '',
    project_status: project.status || '',
    submitted_at: submittedDate,

    // Showroom variables
    showroom_name: showroom.name || '',
    showroom_phone: showroom.phone || '',
    showroom_email: showroom.email || '',
    showroom_address: showroomAddress,
    showroom_city: showroom.city || '',
    showroom_state: showroom.state || '',
    showroom_code: showroom.showroom_code || '',

    // Distance variables
    distance_miles:
      distance?.distanceMiles != null ? String(distance.distanceMiles) : '',
    distance_km:
      distance?.distanceKm != null ? String(distance.distanceKm) : '',
    drive_time:
      distance?.driveTimeMinutes != null
        ? `${distance.driveTimeMinutes} min`
        : '',
    distance_zone: distance?.zone || '',
  }
}
