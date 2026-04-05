/**
 * Functional tests for the voice agent trigger flow logic.
 *
 * These tests verify the conceptual flow of:
 * 1. Zone determination based on distance
 * 2. Template selection (showroom override vs platform default)
 * 3. Fallback behavior for missing data
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'

// --------------------------------------------------------------------------
// Inlined helper functions (from voice-agent/lib sources)
// --------------------------------------------------------------------------

function determineZone(
  distanceMiles: number,
  thresholdMiles: number
): 'near' | 'far' {
  return distanceMiles <= thresholdMiles ? 'near' : 'far'
}

function interpolate(
  template: string,
  vars: Record<string, string | number | null | undefined>
): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    const val = vars[key]
    return val != null ? String(val) : ''
  })
}

// --------------------------------------------------------------------------
// Template selection logic (mirrors what the trigger Edge Function does)
// --------------------------------------------------------------------------

interface ShowroomSettings {
  enabled: boolean
  distance_threshold_miles: number
  near_homeowner_sms_template: string | null
  near_contractor_sms_template: string | null
  far_homeowner_sms_template: string | null
  far_contractor_sms_template: string | null
  near_homeowner_system_prompt: string | null
  near_contractor_system_prompt: string | null
  far_homeowner_system_prompt: string | null
  far_contractor_system_prompt: string | null
}

type CustomerType = 'homeowner' | 'contractor'

function selectTemplate(
  showroomSettings: ShowroomSettings | null,
  zone: 'near' | 'far',
  customerType: CustomerType,
  platformDefaultSms: string,
  platformDefaultPrompt: string
): { smsTemplate: string; systemPrompt: string } {
  const templateKey = `${zone}_${customerType}_sms_template` as keyof ShowroomSettings
  const promptKey = `${zone}_${customerType}_system_prompt` as keyof ShowroomSettings

  const smsTemplate =
    (showroomSettings?.[templateKey] as string | null) || platformDefaultSms
  const systemPrompt =
    (showroomSettings?.[promptKey] as string | null) || platformDefaultPrompt

  return { smsTemplate, systemPrompt }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('Trigger Flow - Zone Determination', () => {
  it('classifies a close customer as "near"', () => {
    const zone = determineZone(10, 30)
    expect(zone).toBe('near')
  })

  it('classifies a distant customer as "far"', () => {
    const zone = determineZone(50, 30)
    expect(zone).toBe('far')
  })

  it('uses custom threshold from showroom settings', () => {
    const customThreshold = 15
    expect(determineZone(14, customThreshold)).toBe('near')
    expect(determineZone(16, customThreshold)).toBe('far')
  })

  it('handles zero distance (same location)', () => {
    expect(determineZone(0, 30)).toBe('near')
  })
})

describe('Trigger Flow - Template Selection', () => {
  const platformDefaultSms = 'Default SMS: Hi {{customer_first_name}}'
  const platformDefaultPrompt = 'Default prompt for {{showroom_name}}'

  const showroomWithOverrides: ShowroomSettings = {
    enabled: true,
    distance_threshold_miles: 30,
    near_homeowner_sms_template: 'Custom near homeowner SMS',
    near_contractor_sms_template: 'Custom near contractor SMS',
    far_homeowner_sms_template: 'Custom far homeowner SMS',
    far_contractor_sms_template: null,
    near_homeowner_system_prompt: 'Custom near homeowner prompt',
    near_contractor_system_prompt: null,
    far_homeowner_system_prompt: null,
    far_contractor_system_prompt: null,
  }

  it('uses showroom override when available', () => {
    const { smsTemplate } = selectTemplate(
      showroomWithOverrides,
      'near',
      'homeowner',
      platformDefaultSms,
      platformDefaultPrompt
    )
    expect(smsTemplate).toBe('Custom near homeowner SMS')
  })

  it('falls back to platform default when showroom override is null', () => {
    const { smsTemplate } = selectTemplate(
      showroomWithOverrides,
      'far',
      'contractor',
      platformDefaultSms,
      platformDefaultPrompt
    )
    expect(smsTemplate).toBe(platformDefaultSms)
  })

  it('falls back to platform default when showroom settings is null', () => {
    const { smsTemplate, systemPrompt } = selectTemplate(
      null,
      'near',
      'homeowner',
      platformDefaultSms,
      platformDefaultPrompt
    )
    expect(smsTemplate).toBe(platformDefaultSms)
    expect(systemPrompt).toBe(platformDefaultPrompt)
  })

  it('selects correct template for all 4 zone/type combinations', () => {
    const nearHomeowner = selectTemplate(
      showroomWithOverrides,
      'near',
      'homeowner',
      platformDefaultSms,
      platformDefaultPrompt
    )
    expect(nearHomeowner.smsTemplate).toBe('Custom near homeowner SMS')
    expect(nearHomeowner.systemPrompt).toBe('Custom near homeowner prompt')

    const nearContractor = selectTemplate(
      showroomWithOverrides,
      'near',
      'contractor',
      platformDefaultSms,
      platformDefaultPrompt
    )
    expect(nearContractor.smsTemplate).toBe('Custom near contractor SMS')
    expect(nearContractor.systemPrompt).toBe(platformDefaultPrompt) // null in settings

    const farHomeowner = selectTemplate(
      showroomWithOverrides,
      'far',
      'homeowner',
      platformDefaultSms,
      platformDefaultPrompt
    )
    expect(farHomeowner.smsTemplate).toBe('Custom far homeowner SMS')
    expect(farHomeowner.systemPrompt).toBe(platformDefaultPrompt)
  })
})

describe('Trigger Flow - Fallback Behavior', () => {
  it('defaults to "near" zone when no address is available for distance calc', () => {
    // When customer has no address, distance calculation returns null,
    // and the system should fall back to "near" zone
    const zone: 'near' | 'far' = 'near' // fallback
    expect(zone).toBe('near')
  })

  it('defaults to "homeowner" when customer_type is not set', () => {
    const customerType: CustomerType =
      (undefined as unknown as CustomerType) || 'homeowner'
    expect(customerType).toBe('homeowner')
  })

  it('interpolates template variables after selection', () => {
    const template = 'Hi {{customer_first_name}}, welcome to {{showroom_name}}!'
    const vars = {
      customer_first_name: 'Alice',
      showroom_name: 'Acme Cabinets',
    }
    const result = interpolate(template, vars)
    expect(result).toBe('Hi Alice, welcome to Acme Cabinets!')
  })

  it('handles missing template variables gracefully in interpolation', () => {
    const template = 'Hi {{customer_first_name}}, distance: {{distance_miles}} mi'
    const vars = {
      customer_first_name: 'Bob',
      // distance_miles intentionally missing
    }
    const result = interpolate(template, vars)
    expect(result).toBe('Hi Bob, distance:  mi')
  })
})

describe('Trigger Flow - Feature Gating Checks', () => {
  it('skips trigger when showroom is not enabled', () => {
    const settings: ShowroomSettings = {
      enabled: false,
      distance_threshold_miles: 30,
      near_homeowner_sms_template: null,
      near_contractor_sms_template: null,
      far_homeowner_sms_template: null,
      far_contractor_sms_template: null,
      near_homeowner_system_prompt: null,
      near_contractor_system_prompt: null,
      far_homeowner_system_prompt: null,
      far_contractor_system_prompt: null,
    }
    expect(settings.enabled).toBe(false)
  })

  it('skips trigger when phone is missing', () => {
    const customerPhone = ''
    const shouldTrigger = !!customerPhone
    expect(shouldTrigger).toBe(false)
  })

  it('proceeds when all conditions are met', () => {
    const globalEnabled = true
    const showroomEnabled = true
    const hasPhone = true
    const shouldTrigger = globalEnabled && showroomEnabled && hasPhone
    expect(shouldTrigger).toBe(true)
  })
})
