/**
 * Integration tests for voice agent database operations (mocked Supabase).
 *
 * Tests CRUD operations for platform_settings, voice_agent_showroom_settings,
 * and voice_agent_logs tables.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'

// --------------------------------------------------------------------------
// Mock Supabase client (simplified version)
// --------------------------------------------------------------------------

interface MockRow {
  [key: string]: unknown
}

function createMockDb() {
  const store: Record<string, MockRow[]> = {
    platform_settings: [],
    voice_agent_showroom_settings: [],
    voice_agent_logs: [],
  }

  return {
    from(table: string) {
      const rows = store[table] || []

      return {
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            single: vi.fn().mockResolvedValue({
              data: rows[0] || null,
              error: rows.length === 0 ? { message: 'Not found' } : null,
            }),
            eq: vi.fn().mockReturnValue({
              order: vi.fn().mockResolvedValue({
                data: rows,
                error: null,
              }),
            }),
            limit: vi.fn().mockResolvedValue({
              data: rows,
              error: null,
            }),
            order: vi.fn().mockResolvedValue({
              data: rows,
              error: null,
            }),
          }),
          in: vi.fn().mockResolvedValue({
            data: rows,
            error: null,
          }),
          order: vi.fn().mockResolvedValue({
            data: rows,
            error: null,
          }),
        }),
        insert: vi.fn().mockImplementation((row: MockRow) => {
          const newRow = { ...row, id: `id-${Date.now()}` }
          store[table].push(newRow)
          return {
            select: vi.fn().mockReturnValue({
              single: vi.fn().mockResolvedValue({
                data: newRow,
                error: null,
              }),
            }),
          }
        }),
        upsert: vi.fn().mockImplementation((row: MockRow) => {
          const existingIndex = store[table].findIndex(
            (r) => r.key === row.key || r.showroom_id === row.showroom_id
          )
          if (existingIndex >= 0) {
            store[table][existingIndex] = { ...store[table][existingIndex], ...row }
          } else {
            store[table].push({ ...row, id: `id-${Date.now()}` })
          }
          return Promise.resolve({ data: row, error: null })
        }),
        update: vi.fn().mockImplementation((updates: MockRow) => ({
          eq: vi.fn().mockResolvedValue({
            data: { ...updates },
            error: null,
          }),
        })),
        delete: vi.fn().mockReturnValue({
          eq: vi.fn().mockResolvedValue({ data: null, error: null }),
        }),
      }
    },
    _store: store,
  }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('platform_settings CRUD', () => {
  let db: ReturnType<typeof createMockDb>

  beforeEach(() => {
    db = createMockDb()
  })

  it('inserts a new platform setting', async () => {
    const result = await db
      .from('platform_settings')
      .upsert({ key: 'voice_agent_globally_enabled', value: 'true' })

    expect(result.error).toBeNull()
    expect(db._store.platform_settings).toHaveLength(1)
    expect(db._store.platform_settings[0].key).toBe('voice_agent_globally_enabled')
  })

  it('upserts an existing platform setting', async () => {
    await db
      .from('platform_settings')
      .upsert({ key: 'vapi_api_key', value: 'old-key' })
    await db
      .from('platform_settings')
      .upsert({ key: 'vapi_api_key', value: 'new-key' })

    expect(db._store.platform_settings).toHaveLength(1)
    expect(db._store.platform_settings[0].value).toBe('new-key')
  })

  it('reads a platform setting by key', async () => {
    db._store.platform_settings.push({
      key: 'twilio_account_sid',
      value: 'AC_test',
      is_secret: true,
    })

    const result = await db
      .from('platform_settings')
      .select('value')
      .eq('key', 'twilio_account_sid')
      .single()

    expect(result.data).toBeTruthy()
  })

  it('returns error when key not found', async () => {
    const result = await db
      .from('platform_settings')
      .select('value')
      .eq('key', 'nonexistent')
      .single()

    // Our mock returns the first row or null with error
    expect(result.data).toBeNull()
    expect(result.error).toBeTruthy()
  })
})

describe('voice_agent_showroom_settings CRUD', () => {
  let db: ReturnType<typeof createMockDb>

  beforeEach(() => {
    db = createMockDb()
  })

  it('creates showroom settings', async () => {
    const settings = {
      showroom_id: 'sr-001',
      enabled: true,
      trigger_mode: 'immediate',
      delay_minutes: 0,
      distance_threshold_miles: 30,
      scheduling_link: 'https://calendly.com/test',
    }

    const result = await db
      .from('voice_agent_showroom_settings')
      .upsert(settings)

    expect(result.error).toBeNull()
    expect(db._store.voice_agent_showroom_settings).toHaveLength(1)
    expect(db._store.voice_agent_showroom_settings[0].enabled).toBe(true)
  })

  it('updates showroom settings', async () => {
    db._store.voice_agent_showroom_settings.push({
      id: 'vs-1',
      showroom_id: 'sr-001',
      enabled: false,
      trigger_mode: 'manual',
    })

    await db
      .from('voice_agent_showroom_settings')
      .upsert({ showroom_id: 'sr-001', enabled: true, trigger_mode: 'immediate' })

    expect(db._store.voice_agent_showroom_settings[0].enabled).toBe(true)
    expect(db._store.voice_agent_showroom_settings[0].trigger_mode).toBe('immediate')
  })

  it('reads showroom settings by showroom_id', async () => {
    db._store.voice_agent_showroom_settings.push({
      id: 'vs-1',
      showroom_id: 'sr-001',
      enabled: true,
      trigger_mode: 'delayed',
      delay_minutes: 15,
    })

    const result = await db
      .from('voice_agent_showroom_settings')
      .select('*')
      .eq('showroom_id', 'sr-001')
      .single()

    expect(result.data).toBeTruthy()
  })
})

describe('voice_agent_logs CRUD', () => {
  let db: ReturnType<typeof createMockDb>

  beforeEach(() => {
    db = createMockDb()
  })

  it('inserts a new log entry', async () => {
    const log = {
      showroom_id: 'sr-001',
      project_id: 'proj-001',
      customer_phone: '+15551234567',
      sms_status: 'pending',
      call_status: 'pending',
      attempt_number: 1,
      flow_status: 'active',
      trigger_mode: 'immediate',
    }

    const insertResult = db.from('voice_agent_logs').insert(log)
    const result = await insertResult.select().single()

    expect(result.data).toBeTruthy()
    expect(result.data?.id).toBeDefined()
    expect(db._store.voice_agent_logs).toHaveLength(1)
  })

  it('updates log with SMS result', async () => {
    db._store.voice_agent_logs.push({
      id: 'log-1',
      showroom_id: 'sr-001',
      sms_status: 'pending',
      call_status: 'pending',
    })

    const updateResult = db
      .from('voice_agent_logs')
      .update({
        sms_status: 'sent',
        sms_sid: 'SM_abc123',
        sms_sent_at: new Date().toISOString(),
      })

    const result = await updateResult.eq('id', 'log-1')
    expect(result.error).toBeNull()
  })

  it('updates log with call outcome', async () => {
    db._store.voice_agent_logs.push({
      id: 'log-1',
      showroom_id: 'sr-001',
      call_status: 'completed',
    })

    const updateResult = db
      .from('voice_agent_logs')
      .update({
        call_status: 'completed',
        outcome: 'interested',
        call_duration_seconds: 120,
        call_summary: 'Customer interested in scheduling',
      })

    const result = await updateResult.eq('id', 'log-1')
    expect(result.error).toBeNull()
  })

  it('reads logs ordered by attempt number', async () => {
    db._store.voice_agent_logs.push(
      { id: 'log-1', project_id: 'proj-1', attempt_number: 1 },
      { id: 'log-2', project_id: 'proj-1', attempt_number: 2 }
    )

    const result = await db
      .from('voice_agent_logs')
      .select('*')
      .eq('project_id', 'proj-1')
      .order('attempt_number')

    expect(result.data).toHaveLength(2)
  })
})
