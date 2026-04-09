/**
 * Unit tests for voice-agent/lib/template.ts
 *
 * Since the source file uses Deno-style imports (../types/index.ts),
 * we inline the pure functions here to test them in the Vitest/Node environment.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Inlined pure functions from voice-agent/lib/template.ts
// --------------------------------------------------------------------------

function interpolate(
  template: string,
  vars: Record<string, string | number | null | undefined>
): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    const val = vars[key]
    return val != null ? String(val) : ''
  })
}

interface TriggerPayload {
  customer: {
    first_name: string
    last_name: string
    phone_normalized: string
    email: string | null
    customer_type: 'homeowner' | 'contractor'
    address_line1: string | null
    city: string | null
    state: string | null
    zip_code: string | null
    id: string
  }
  end_client: {
    first_name: string | null
    last_name: string | null
    phone: string | null
    email: string | null
    address: string | null
  }
  project: {
    name: string
    reference_number: string
    notes: string | null
    status: string
    submitted_at: string
  }
  showroom: {
    name: string
    phone: string | null
    email: string | null
    address_line1: string | null
    city: string | null
    state: string | null
    postal_code: string | null
    showroom_code: string
  }
  project_id: string
  showroom_id: string
  triggered_by: string
}

function buildTemplateVariables(
  payload: TriggerPayload,
  distance?: {
    distanceMiles: number
    distanceKm: number
    driveTimeMinutes: number
    zone: string
  } | null
): Record<string, string> {
  const { customer, end_client, project, showroom } = payload

  const showroomAddress = [
    showroom.address_line1,
    showroom.city,
    showroom.state,
    showroom.postal_code,
  ]
    .filter(Boolean)
    .join(', ')

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
    end_client_first_name: end_client?.first_name || '',
    end_client_last_name: end_client?.last_name || '',
    end_client_phone: end_client?.phone || '',
    end_client_email: end_client?.email || '',
    end_client_address: end_client?.address || '',
    project_name: project.name || '',
    reference_number: project.reference_number || '',
    project_notes: project.notes || '',
    project_status: project.status || '',
    submitted_at: submittedDate,
    showroom_name: showroom.name || '',
    showroom_phone: showroom.phone || '',
    showroom_email: showroom.email || '',
    showroom_address: showroomAddress,
    showroom_city: showroom.city || '',
    showroom_state: showroom.state || '',
    showroom_code: showroom.showroom_code || '',
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

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

function makePayload(overrides: Partial<TriggerPayload> = {}): TriggerPayload {
  return {
    project_id: 'proj-1',
    showroom_id: 'sr-1',
    triggered_by: 'test',
    customer: {
      id: 'cust-1',
      first_name: 'John',
      last_name: 'Doe',
      phone_normalized: '+15551234567',
      email: 'john@example.com',
      customer_type: 'homeowner',
      address_line1: '123 Main St',
      city: 'Springfield',
      state: 'IL',
      zip_code: '62701',
    },
    end_client: {
      first_name: null,
      last_name: null,
      phone: null,
      email: null,
      address: null,
    },
    project: {
      name: 'Kitchen Remodel',
      reference_number: 'CS-001',
      notes: 'Modern style',
      status: 'submitted',
      submitted_at: '2025-01-15T10:30:00Z',
    },
    showroom: {
      name: 'Acme Cabinets',
      phone: '+15559876543',
      email: 'info@acme.com',
      address_line1: '456 Oak Ave',
      city: 'Chicago',
      state: 'IL',
      postal_code: '60601',
      showroom_code: 'ACME01',
    },
    ...overrides,
  }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('interpolate()', () => {
  it('replaces known variables', () => {
    const result = interpolate('Hi {{name}}, ref {{ref}}', {
      name: 'John',
      ref: 'CS-001',
    })
    expect(result).toBe('Hi John, ref CS-001')
  })

  it('handles null values by replacing with empty string', () => {
    const result = interpolate('Hello {{name}}, phone: {{phone}}', {
      name: 'Jane',
      phone: null,
    })
    expect(result).toBe('Hello Jane, phone: ')
  })

  it('handles undefined values by replacing with empty string', () => {
    const result = interpolate('Hello {{name}}, phone: {{phone}}', {
      name: 'Jane',
      phone: undefined,
    })
    expect(result).toBe('Hello Jane, phone: ')
  })

  it('replaces unknown {{tokens}} with empty string', () => {
    const result = interpolate('Hello {{unknown_var}}!', {})
    expect(result).toBe('Hello !')
  })

  it('handles template with no variables', () => {
    const result = interpolate('No variables here.', { name: 'John' })
    expect(result).toBe('No variables here.')
  })

  it('handles numeric values by converting to string', () => {
    const result = interpolate('Distance: {{miles}} mi', { miles: 12.5 })
    expect(result).toBe('Distance: 12.5 mi')
  })

  it('handles empty template string', () => {
    const result = interpolate('', { name: 'John' })
    expect(result).toBe('')
  })

  it('handles multiple occurrences of the same variable', () => {
    const result = interpolate('{{name}} and {{name}}', { name: 'Alice' })
    expect(result).toBe('Alice and Alice')
  })
})

describe('buildTemplateVariables()', () => {
  it('maps all customer fields correctly', () => {
    const vars = buildTemplateVariables(makePayload())
    expect(vars.customer_first_name).toBe('John')
    expect(vars.customer_last_name).toBe('Doe')
    expect(vars.customer_phone).toBe('+15551234567')
    expect(vars.customer_email).toBe('john@example.com')
    expect(vars.customer_type).toBe('homeowner')
    expect(vars.customer_address).toBe('123 Main St')
    expect(vars.customer_city).toBe('Springfield')
    expect(vars.customer_state).toBe('IL')
    expect(vars.customer_zip).toBe('62701')
  })

  it('formats full name from first + last', () => {
    const vars = buildTemplateVariables(makePayload())
    expect(vars.customer_full_name).toBe('John Doe')
  })

  it('formats full name with only first name when last is empty', () => {
    const payload = makePayload()
    payload.customer.last_name = ''
    const vars = buildTemplateVariables(payload)
    expect(vars.customer_full_name).toBe('John')
  })

  it('formats submitted_at as readable date', () => {
    const vars = buildTemplateVariables(makePayload())
    expect(vars.submitted_at).toContain('January')
    expect(vars.submitted_at).toContain('2025')
    expect(vars.submitted_at).toContain('Wednesday')
  })

  it('returns empty submitted_at when not provided', () => {
    const payload = makePayload()
    payload.project.submitted_at = ''
    const vars = buildTemplateVariables(payload)
    expect(vars.submitted_at).toBe('')
  })

  it('maps showroom fields and builds address', () => {
    const vars = buildTemplateVariables(makePayload())
    expect(vars.showroom_name).toBe('Acme Cabinets')
    expect(vars.showroom_phone).toBe('+15559876543')
    expect(vars.showroom_address).toBe('456 Oak Ave, Chicago, IL, 60601')
    expect(vars.showroom_code).toBe('ACME01')
  })

  it('maps distance fields when provided', () => {
    const vars = buildTemplateVariables(makePayload(), {
      distanceMiles: 15.2,
      distanceKm: 24.5,
      driveTimeMinutes: 22,
      zone: 'near',
    })
    expect(vars.distance_miles).toBe('15.2')
    expect(vars.distance_km).toBe('24.5')
    expect(vars.drive_time).toBe('22 min')
    expect(vars.distance_zone).toBe('near')
  })

  it('returns empty distance fields when distance is null', () => {
    const vars = buildTemplateVariables(makePayload(), null)
    expect(vars.distance_miles).toBe('')
    expect(vars.distance_km).toBe('')
    expect(vars.drive_time).toBe('')
    expect(vars.distance_zone).toBe('')
  })

  it('maps project fields correctly', () => {
    const vars = buildTemplateVariables(makePayload())
    expect(vars.project_name).toBe('Kitchen Remodel')
    expect(vars.reference_number).toBe('CS-001')
    expect(vars.project_notes).toBe('Modern style')
    expect(vars.project_status).toBe('submitted')
  })
})
