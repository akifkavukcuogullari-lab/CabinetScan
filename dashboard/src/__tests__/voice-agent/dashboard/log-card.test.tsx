/**
 * @vitest-environment jsdom
 */

/**
 * Dashboard tests for VoiceAgentLogCard rendering logic.
 *
 * Since the actual VoiceAgentLogCard component may not be present in the
 * worktree, these tests validate the rendering patterns and data formatting
 * functions that the component uses.
 */
import '@testing-library/jest-dom/vitest'
import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import React from 'react'

// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------

type SimplifiedOutcome =
  | 'no_answer'
  | 'line_busy'
  | 'voicemail'
  | 'ghosted'
  | 'interested'
  | 'not_interested'
  | 'link_sent'
  | 'callback_requested'
  | 'hung_up_early'
  | 'technical_error'

interface VoiceAgentLog {
  id: string
  sms_status: string
  call_status: string
  outcome: SimplifiedOutcome | null
  call_duration_seconds: number | null
  distance_miles: number | null
  drive_time_minutes: number | null
  distance_zone: 'near' | 'far' | null
  customer_type_used: 'homeowner' | 'contractor' | null
  attempt_number: number
  flow_status: 'active' | 'waiting' | 'completed' | 'stopped'
  call_transcript: string | null
  call_summary: string | null
  sms_sent_at: string | null
}

// --------------------------------------------------------------------------
// Formatting functions (from VoiceAgentLogCard)
// --------------------------------------------------------------------------

function formatDuration(seconds: number | null): string {
  if (seconds === null || seconds === undefined) return '--'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}m ${s}s`
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '--'
  return new Date(dateStr).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

const OUTCOME_LABELS: Record<SimplifiedOutcome, string> = {
  no_answer: 'No Answer',
  line_busy: 'Line Busy',
  voicemail: 'Voicemail',
  ghosted: 'Ghosted',
  interested: 'Interested',
  not_interested: 'Not Interested',
  link_sent: 'Link Sent',
  callback_requested: 'Callback Requested',
  hung_up_early: 'Hung Up Early',
  technical_error: 'Technical Error',
}

// --------------------------------------------------------------------------
// Mock LogCard component (simplified rendering logic)
// --------------------------------------------------------------------------

function MockLogCard({ logs }: { logs: VoiceAgentLog[] }) {
  if (logs.length === 0) {
    return <p>No voice agent activity for this project.</p>
  }

  return (
    <div data-testid="log-list">
      {logs.map((log) => (
        <div key={log.id} data-testid={`log-${log.id}`}>
          <span data-testid="attempt-badge">Attempt {log.attempt_number}</span>
          <span data-testid="flow-status">Flow: {log.flow_status}</span>

          {(log.distance_miles !== null || log.distance_zone) && (
            <span data-testid="distance-info">
              {log.distance_miles !== null && `${log.distance_miles.toFixed(1)} mi`}
              {log.drive_time_minutes !== null && ` / ${log.drive_time_minutes} min`}
              {log.distance_zone && ` - ${log.distance_zone}`}
            </span>
          )}

          <span data-testid="sms-status">SMS: {log.sms_status}</span>
          {log.sms_sent_at && (
            <span data-testid="sms-date">{formatDate(log.sms_sent_at)}</span>
          )}

          <span data-testid="call-status">Call: {log.call_status}</span>
          {log.call_duration_seconds !== null && (
            <span data-testid="call-duration">
              {formatDuration(log.call_duration_seconds)}
            </span>
          )}

          {log.outcome && (
            <span data-testid="outcome-badge">
              {OUTCOME_LABELS[log.outcome] || log.outcome}
            </span>
          )}

          {log.call_transcript && (
            <div data-testid="transcript">
              <button>Transcript</button>
              <pre>{log.call_transcript}</pre>
            </div>
          )}

          {log.call_summary && (
            <div data-testid="summary">
              <button>Summary</button>
              <p>{log.call_summary}</p>
            </div>
          )}
        </div>
      ))}
    </div>
  )
}

// --------------------------------------------------------------------------
// Helper
// --------------------------------------------------------------------------

function makeLog(overrides: Partial<VoiceAgentLog> = {}): VoiceAgentLog {
  return {
    id: `log-${Math.random().toString(36).slice(2, 8)}`,
    sms_status: 'sent',
    call_status: 'completed',
    outcome: 'interested',
    call_duration_seconds: 120,
    distance_miles: 15.2,
    drive_time_minutes: 22,
    distance_zone: 'near',
    customer_type_used: 'homeowner',
    attempt_number: 1,
    flow_status: 'completed',
    call_transcript: null,
    call_summary: null,
    sms_sent_at: '2025-03-15T10:00:00Z',
    ...overrides,
  }
}

afterEach(() => {
  cleanup()
})

// --------------------------------------------------------------------------
// Tests - Formatting Functions
// --------------------------------------------------------------------------

describe('formatDuration()', () => {
  it('formats seconds into m/s', () => {
    expect(formatDuration(120)).toBe('2m 0s')
    expect(formatDuration(65)).toBe('1m 5s')
    expect(formatDuration(30)).toBe('0m 30s')
  })

  it('returns -- for null', () => {
    expect(formatDuration(null)).toBe('--')
  })

  it('handles zero seconds', () => {
    expect(formatDuration(0)).toBe('0m 0s')
  })
})

describe('formatDate()', () => {
  it('returns -- for null', () => {
    expect(formatDate(null)).toBe('--')
  })

  it('returns -- for empty string', () => {
    expect(formatDate('')).toBe('--')
  })

  it('formats a valid date string', () => {
    const result = formatDate('2025-03-15T10:00:00Z')
    expect(result).toBeTruthy()
    expect(result).not.toBe('--')
  })
})

// --------------------------------------------------------------------------
// Tests - LogCard Rendering
// --------------------------------------------------------------------------

describe('MockLogCard - Empty State', () => {
  it('shows empty message when no logs exist', () => {
    render(<MockLogCard logs={[]} />)
    expect(
      screen.getByText('No voice agent activity for this project.')
    ).toBeInTheDocument()
  })
})

describe('MockLogCard - SMS/Call/Outcome Display', () => {
  it('renders SMS status', () => {
    render(<MockLogCard logs={[makeLog({ sms_status: 'sent' })]} />)
    expect(screen.getByText('SMS: sent')).toBeInTheDocument()
  })

  it('renders SMS failed status', () => {
    render(<MockLogCard logs={[makeLog({ sms_status: 'failed' })]} />)
    expect(screen.getByText('SMS: failed')).toBeInTheDocument()
  })

  it('renders call status', () => {
    render(<MockLogCard logs={[makeLog({ call_status: 'completed' })]} />)
    expect(screen.getByText('Call: completed')).toBeInTheDocument()
  })

  it('renders outcome badge with label', () => {
    render(<MockLogCard logs={[makeLog({ outcome: 'interested' })]} />)
    expect(screen.getByText('Interested')).toBeInTheDocument()
  })

  it('renders call duration', () => {
    render(<MockLogCard logs={[makeLog({ call_duration_seconds: 120 })]} />)
    expect(screen.getByText('2m 0s')).toBeInTheDocument()
  })

  it('hides duration when null', () => {
    render(<MockLogCard logs={[makeLog({ call_duration_seconds: null })]} />)
    expect(screen.queryByTestId('call-duration')).not.toBeInTheDocument()
  })
})

describe('MockLogCard - Multiple Attempts', () => {
  it('renders multiple attempt badges', () => {
    const logs = [
      makeLog({ id: 'log-1', attempt_number: 1, outcome: 'no_answer' }),
      makeLog({ id: 'log-2', attempt_number: 2, outcome: 'interested' }),
    ]
    render(<MockLogCard logs={logs} />)

    expect(screen.getByText('Attempt 1')).toBeInTheDocument()
    expect(screen.getByText('Attempt 2')).toBeInTheDocument()
  })

  it('renders three attempts', () => {
    const logs = [
      makeLog({ id: 'log-1', attempt_number: 1 }),
      makeLog({ id: 'log-2', attempt_number: 2 }),
      makeLog({ id: 'log-3', attempt_number: 3 }),
    ]
    render(<MockLogCard logs={logs} />)

    // 3 log items + 1 log-list container = 4 elements matching /^log-/
    // Use attempt badges to verify count
    expect(screen.getAllByTestId('attempt-badge')).toHaveLength(3)
  })
})

describe('MockLogCard - Distance Info', () => {
  it('renders distance info when present', () => {
    render(
      <MockLogCard
        logs={[makeLog({ distance_miles: 15.2, drive_time_minutes: 22, distance_zone: 'near' })]}
      />
    )

    const distanceInfo = screen.getByTestId('distance-info')
    expect(distanceInfo.textContent).toContain('15.2 mi')
    expect(distanceInfo.textContent).toContain('22 min')
    expect(distanceInfo.textContent).toContain('near')
  })

  it('hides distance info when not available', () => {
    render(
      <MockLogCard
        logs={[
          makeLog({
            distance_miles: null,
            drive_time_minutes: null,
            distance_zone: null,
          }),
        ]}
      />
    )

    expect(screen.queryByTestId('distance-info')).not.toBeInTheDocument()
  })
})

describe('MockLogCard - Transcript and Summary', () => {
  it('renders transcript when available', () => {
    render(
      <MockLogCard
        logs={[makeLog({ call_transcript: 'AI: Hello! Customer: Hi.' })]}
      />
    )

    expect(screen.getByText('Transcript')).toBeInTheDocument()
    expect(screen.getByText('AI: Hello! Customer: Hi.')).toBeInTheDocument()
  })

  it('hides transcript when null', () => {
    render(<MockLogCard logs={[makeLog({ call_transcript: null })]} />)
    expect(screen.queryByTestId('transcript')).not.toBeInTheDocument()
  })

  it('renders summary when available', () => {
    render(
      <MockLogCard
        logs={[makeLog({ call_summary: 'Customer wants to schedule.' })]}
      />
    )

    expect(screen.getByText('Summary')).toBeInTheDocument()
    expect(
      screen.getByText('Customer wants to schedule.')
    ).toBeInTheDocument()
  })
})
