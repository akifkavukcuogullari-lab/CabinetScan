/**
 * Unit tests for voice-agent/lib/distance.ts — determineZone()
 *
 * The determineZone function is a pure function with no external dependencies.
 * We inline it here for testing in the Vitest/Node environment.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Inlined pure function from voice-agent/lib/distance.ts
// --------------------------------------------------------------------------

function determineZone(
  distanceMiles: number,
  thresholdMiles: number
): 'near' | 'far' {
  return distanceMiles <= thresholdMiles ? 'near' : 'far'
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('determineZone()', () => {
  it('returns "near" when distance is less than threshold', () => {
    expect(determineZone(10, 30)).toBe('near')
  })

  it('returns "near" when distance is well below threshold', () => {
    expect(determineZone(1, 100)).toBe('near')
  })

  it('returns "far" when distance is greater than threshold', () => {
    expect(determineZone(50, 30)).toBe('far')
  })

  it('returns "far" when distance is slightly above threshold', () => {
    expect(determineZone(30.01, 30)).toBe('far')
  })

  it('returns "near" when distance exactly equals threshold (edge case)', () => {
    expect(determineZone(30, 30)).toBe('near')
  })

  it('returns "near" when distance is zero', () => {
    expect(determineZone(0, 30)).toBe('near')
  })

  it('returns "near" when threshold is very large', () => {
    expect(determineZone(999, 1000)).toBe('near')
  })

  it('returns "far" when threshold is very small', () => {
    expect(determineZone(5, 1)).toBe('far')
  })

  it('handles fractional distances correctly', () => {
    expect(determineZone(29.99, 30)).toBe('near')
    expect(determineZone(30.001, 30)).toBe('far')
  })

  it('handles threshold of zero', () => {
    expect(determineZone(0, 0)).toBe('near')
    expect(determineZone(0.01, 0)).toBe('far')
  })
})
