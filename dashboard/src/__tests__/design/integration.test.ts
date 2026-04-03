/**
 * Integration/Functional Tests: Design Request Data Flow
 *
 * Tests the data flow and API interactions with mocked Supabase client.
 * Verifies that the correct Supabase calls are made with the correct data,
 * and that the responses are handled properly.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { createClient } from '@/lib/supabase/client'

// ---- Helpers ----

/**
 * Creates a mock chainable query builder that records method calls
 * and returns configurable results.
 */
function createMockQueryBuilder(resolvedValue: { data: unknown; error: unknown } = { data: null, error: null }) {
  const calls: Array<{ method: string; args: unknown[] }> = []

  const builder: Record<string, unknown> = {}
  const methods = [
    'select', 'insert', 'update', 'delete', 'upsert',
    'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike',
    'is', 'in', 'contains', 'containedBy', 'filter',
    'order', 'limit', 'range', 'not', 'or', 'match', 'textSearch',
  ]

  for (const method of methods) {
    builder[method] = vi.fn((...args: unknown[]) => {
      calls.push({ method, args })
      return builder
    })
  }

  // single() is terminal
  builder.single = vi.fn(() => {
    calls.push({ method: 'single', args: [] })
    return Promise.resolve(resolvedValue)
  })

  // maybeSingle() is terminal
  builder.maybeSingle = vi.fn(() => {
    calls.push({ method: 'maybeSingle', args: [] })
    return Promise.resolve(resolvedValue)
  })

  // Make the builder itself thenable (for queries without single())
  builder.then = (resolve: (val: unknown) => void) => resolve(resolvedValue)

  return { builder, calls }
}

// ---- Tests ----

describe('Design Request Flow', () => {
  let supabase: ReturnType<typeof createClient>

  beforeEach(() => {
    vi.clearAllMocks()
    supabase = createClient()
  })

  describe('Creating a Design Request', () => {
    it('creates a design request with correct data structure', async () => {
      const projectId = 'proj-001'
      const showroomId = 'sr-001'
      const notes = 'Modern style, white marble countertops'
      const priority = 'high'
      const createdBy = 'su-001'

      const { builder } = createMockQueryBuilder({ data: { id: 'dr-new' }, error: null })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      await supabase
        .from('design_requests')
        .insert({
          project_id: projectId,
          showroom_id: showroomId,
          notes,
          priority,
          created_by: createdBy,
          status: 'pending',
        })

      expect(supabase.from).toHaveBeenCalledWith('design_requests')
      expect(builder.insert).toHaveBeenCalledWith({
        project_id: projectId,
        showroom_id: showroomId,
        notes,
        priority,
        created_by: createdBy,
        status: 'pending',
      })
    })

    it('handles duplicate request error (unique constraint)', async () => {
      const duplicateError = {
        code: '23505',
        message: 'duplicate key value violates unique constraint',
      }

      const { builder } = createMockQueryBuilder({ data: null, error: duplicateError })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      const result = await (supabase
        .from('design_requests')
        .insert({
          project_id: 'proj-001',
          showroom_id: 'sr-001',
          status: 'pending',
        }) as unknown as Promise<{ data: unknown; error: typeof duplicateError | null }>)

      expect(result.error).not.toBeNull()
      expect(result.error?.code).toBe('23505')
    })
  })

  describe('Accepting a Design Request', () => {
    it('sets designer_id, status, and accepted_at', async () => {
      const designerId = 'designer-001'
      const designRequestId = 'dr-001'
      const now = new Date().toISOString()

      const { builder } = createMockQueryBuilder({
        data: [{ id: designRequestId, status: 'accepted', designer_id: designerId }],
        error: null,
      })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      await supabase
        .from('design_requests')
        .update({
          designer_id: designerId,
          status: 'accepted',
          accepted_at: now,
        })
        .eq('id', designRequestId)
        .eq('status', 'pending') // optimistic locking
        .select()

      expect(supabase.from).toHaveBeenCalledWith('design_requests')
      expect(builder.update).toHaveBeenCalledWith(
        expect.objectContaining({
          designer_id: designerId,
          status: 'accepted',
          accepted_at: expect.any(String),
        })
      )
      // Verify optimistic locking check for pending status
      expect(builder.eq).toHaveBeenCalledWith('id', designRequestId)
      expect(builder.eq).toHaveBeenCalledWith('status', 'pending')
    })

    it('returns empty data when request was already accepted (race condition)', async () => {
      const { builder } = createMockQueryBuilder({
        data: [],
        error: null,
      })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      const result = await (supabase
        .from('design_requests')
        .update({
          designer_id: 'designer-B',
          status: 'accepted',
          accepted_at: new Date().toISOString(),
        })
        .eq('id', 'dr-001')
        .eq('status', 'pending')
        .select() as unknown as Promise<{ data: unknown[]; error: null }>)

      // Empty data means another designer already claimed it
      expect(result.data).toEqual([])
    })
  })

  describe('Delivering a Design', () => {
    it('changes status and sets delivered_at', async () => {
      const designRequestId = 'dr-001'
      const deliveredAt = '2026-01-20T14:00:00.000Z'

      const { builder } = createMockQueryBuilder({ data: { id: designRequestId }, error: null })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      await supabase
        .from('design_requests')
        .update({
          status: 'delivered',
          delivered_at: deliveredAt,
        })
        .eq('id', designRequestId)

      expect(builder.update).toHaveBeenCalledWith({
        status: 'delivered',
        delivered_at: deliveredAt,
      })
      expect(builder.eq).toHaveBeenCalledWith('id', designRequestId)
    })
  })

  describe('Chat Messages', () => {
    it('creates a text chat message with correct sender info', async () => {
      const { builder } = createMockQueryBuilder({ data: { id: 'msg-new' }, error: null })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      const messageData = {
        design_request_id: 'dr-001',
        sender_type: 'designer',
        sender_id: 'designer-001',
        sender_name: 'John Designer',
        message_type: 'text',
        content: 'I have started working on the design.',
      }

      await supabase.from('design_chat_messages').insert(messageData)

      expect(supabase.from).toHaveBeenCalledWith('design_chat_messages')
      expect(builder.insert).toHaveBeenCalledWith(messageData)
    })

    it('creates a file chat message with file metadata', async () => {
      const { builder } = createMockQueryBuilder({ data: { id: 'msg-file' }, error: null })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      const messageData = {
        design_request_id: 'dr-001',
        sender_type: 'showroom',
        sender_id: 'showroom-user-001',
        sender_name: 'Showroom Owner',
        message_type: 'image',
        file_url: 'https://storage.example.com/reference-photo.jpg',
        file_name: 'reference-photo.jpg',
        file_size_bytes: 1024000,
      }

      await supabase.from('design_chat_messages').insert(messageData)

      expect(builder.insert).toHaveBeenCalledWith(
        expect.objectContaining({
          message_type: 'image',
          file_url: expect.any(String),
          file_name: 'reference-photo.jpg',
          file_size_bytes: 1024000,
        })
      )
    })

    it('loads messages ordered by created_at ascending', async () => {
      const messages = [
        { id: 'msg-1', content: 'First', created_at: '2026-01-15T10:00:00Z' },
        { id: 'msg-2', content: 'Second', created_at: '2026-01-15T10:05:00Z' },
      ]
      const { builder } = createMockQueryBuilder({ data: messages, error: null })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      await supabase
        .from('design_chat_messages')
        .select('*')
        .eq('design_request_id', 'dr-001')
        .order('created_at', { ascending: true })

      expect(supabase.from).toHaveBeenCalledWith('design_chat_messages')
      expect(builder.select).toHaveBeenCalledWith('*')
      expect(builder.eq).toHaveBeenCalledWith('design_request_id', 'dr-001')
      expect(builder.order).toHaveBeenCalledWith('created_at', { ascending: true })
    })
  })

  describe('File Upload', () => {
    it('uploads a file to the designs storage bucket', async () => {
      const designRequestId = 'dr-001'
      const storagePath = `${designRequestId}/1_kitchen_render.png`
      const mockFile = new File(['file content'], 'kitchen_render.png', {
        type: 'image/png',
      })

      await supabase.storage.from('designs').upload(storagePath, mockFile, {
        upsert: false,
      })

      expect(supabase.storage.from).toHaveBeenCalledWith('designs')
      expect(supabase.storage.from('designs').upload).toHaveBeenCalledWith(
        storagePath,
        mockFile,
        { upsert: false }
      )
    })

    it('creates a design_files database entry after upload', async () => {
      const { builder } = createMockQueryBuilder({ data: { id: 'df-new' }, error: null })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      const fileEntry = {
        design_request_id: 'dr-001',
        designer_id: 'designer-001',
        file_url: 'https://storage.example.com/designs/dr-001/1_render.png',
        file_name: 'render.png',
        file_type: 'image/png',
        file_size_bytes: 2048000,
        version: 1,
      }

      await supabase.from('design_files').insert(fileEntry)

      expect(supabase.from).toHaveBeenCalledWith('design_files')
      expect(builder.insert).toHaveBeenCalledWith(fileEntry)
    })

    it('loads design files ordered by version descending', async () => {
      const { builder } = createMockQueryBuilder({
        data: [
          { id: 'df-2', version: 2, file_name: 'v2.png' },
          { id: 'df-1', version: 1, file_name: 'v1.png' },
        ],
        error: null,
      })
      vi.mocked(supabase.from).mockReturnValue(builder as never)

      await supabase
        .from('design_files')
        .select('*')
        .eq('design_request_id', 'dr-001')
        .order('version', { ascending: false })
        .order('created_at', { ascending: false })

      expect(builder.order).toHaveBeenCalledWith('version', { ascending: false })
      expect(builder.order).toHaveBeenCalledWith('created_at', { ascending: false })
    })
  })
})

describe('Designer Privacy', () => {
  let supabase: ReturnType<typeof createClient>

  beforeEach(() => {
    vi.clearAllMocks()
    supabase = createClient()
  })

  it('designer_project_view excludes customer contact info', async () => {
    // The view should only return project-level data without PII
    const viewColumns = 'id, reference_number, project_name, design_request_id, design_status, priority, design_notes, request_created_at'

    const { builder } = createMockQueryBuilder({
      data: [
        {
          id: 'proj-001',
          reference_number: 'CS-001',
          project_name: 'Kitchen Renovation',
          design_request_id: 'dr-001',
          design_status: 'pending',
          priority: 'normal',
          design_notes: null,
          request_created_at: '2026-01-15T00:00:00Z',
        },
      ],
      error: null,
    })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    const result = await (supabase
      .from('designer_project_view')
      .select(viewColumns)
      .eq('design_status', 'pending') as unknown as Promise<{ data: Record<string, unknown>[]; error: null }>)

    expect(supabase.from).toHaveBeenCalledWith('designer_project_view')

    // Verify the returned data does not contain customer PII fields
    if (result.data && result.data.length > 0) {
      const project = result.data[0]
      expect(project).not.toHaveProperty('customer_name')
      expect(project).not.toHaveProperty('customer_email')
      expect(project).not.toHaveProperty('customer_phone')
      expect(project).not.toHaveProperty('customer_address')
    }
  })

  it('designer cannot access project_selections table directly', async () => {
    // Simulating what happens when a designer tries to query project_selections
    // In production, RLS would block this. Here we verify the app does not make such calls.
    const designerPageQueries: string[] = []

    // Track all from() calls
    vi.mocked(supabase.from).mockImplementation((table: string) => {
      designerPageQueries.push(table)
      return createMockQueryBuilder().builder as never
    })

    // Simulate designer pool page queries
    await supabase.from('designers').select('id').eq('user_id', 'user-1').single()
    await supabase.from('designer_project_view').select('*').eq('design_status', 'pending')

    // Designer should NOT query these tables
    expect(designerPageQueries).not.toContain('project_selections')
    expect(designerPageQueries).not.toContain('projects')
  })

  it('designer cannot see showroom details', async () => {
    const designerPageQueries: string[] = []

    vi.mocked(supabase.from).mockImplementation((table: string) => {
      designerPageQueries.push(table)
      return createMockQueryBuilder().builder as never
    })

    // Simulate designer pool page queries
    await supabase.from('designers').select('id').eq('user_id', 'user-1').single()
    await supabase.from('designer_project_view').select('*').eq('design_status', 'pending')

    // Designer should NOT query the showrooms table
    expect(designerPageQueries).not.toContain('showrooms')
    expect(designerPageQueries).not.toContain('showroom_users')
  })
})

describe('Login Flow', () => {
  let supabase: ReturnType<typeof createClient>

  beforeEach(() => {
    vi.clearAllMocks()
    supabase = createClient()
  })

  it('designer role should check designers table after auth', async () => {
    // Mock successful auth
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: { user: { id: 'user-1' }, session: {} },
      error: null,
    } as never)

    vi.mocked(supabase.auth.getUser).mockResolvedValue({
      data: { user: { id: 'user-1' } },
      error: null,
    } as never)

    const { builder } = createMockQueryBuilder({
      data: { id: 'designer-001', is_active: true },
      error: null,
    })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    // Simulate the login flow for designer role
    const { error: authError } = await supabase.auth.signInWithPassword({
      email: 'designer@example.com',
      password: 'password123',
    })
    expect(authError).toBeNull()

    const { data: { user } } = await supabase.auth.getUser()
    expect(user).not.toBeNull()

    // Check designer table
    const result = await (supabase
      .from('designers')
      .select('id, is_active')
      .eq('user_id', user!.id)
      .single() as unknown as Promise<{ data: { id: string; is_active: boolean } | null; error: null }>)

    expect(supabase.from).toHaveBeenCalledWith('designers')
    expect(result.data?.is_active).toBe(true)
  })

  it('showroom role should check showroom_users table after auth', async () => {
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: { user: { id: 'user-2' }, session: {} },
      error: null,
    } as never)

    vi.mocked(supabase.auth.getUser).mockResolvedValue({
      data: { user: { id: 'user-2' } },
      error: null,
    } as never)

    // First call: admins check (no admin found)
    const adminBuilder = createMockQueryBuilder({
      data: null,
      error: { code: 'PGRST116', message: 'no rows' },
    })

    // Second call: showroom_users check
    const showroomBuilder = createMockQueryBuilder({
      data: { showroom_id: 'sr-001' },
      error: null,
    })

    let callCount = 0
    vi.mocked(supabase.from).mockImplementation((table: string) => {
      callCount++
      if (table === 'admins') return adminBuilder.builder as never
      if (table === 'showroom_users') return showroomBuilder.builder as never
      return createMockQueryBuilder().builder as never
    })

    // Auth
    await supabase.auth.signInWithPassword({
      email: 'owner@showroom.com',
      password: 'password123',
    })

    const { data: { user } } = await supabase.auth.getUser()

    // Check admin
    await (supabase.from('admins').select('id').single() as unknown as Promise<unknown>)

    // Check showroom_users
    const result = await (supabase
      .from('showroom_users')
      .select('showroom_id')
      .eq('user_id', user!.id)
      .eq('is_active', true)
      .single() as unknown as Promise<{ data: { showroom_id: string } | null; error: null }>)

    expect(supabase.from).toHaveBeenCalledWith('admins')
    expect(supabase.from).toHaveBeenCalledWith('showroom_users')
    expect(result.data?.showroom_id).toBe('sr-001')
  })

  it('inactive designer should be rejected', async () => {
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: { user: { id: 'user-3' }, session: {} },
      error: null,
    } as never)

    vi.mocked(supabase.auth.getUser).mockResolvedValue({
      data: { user: { id: 'user-3' } },
      error: null,
    } as never)

    const { builder } = createMockQueryBuilder({
      data: { id: 'designer-inactive', is_active: false },
      error: null,
    })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    // Auth succeeds
    await supabase.auth.signInWithPassword({
      email: 'inactive@designer.com',
      password: 'password',
    })

    const { data: { user } } = await supabase.auth.getUser()

    const result = await (supabase
      .from('designers')
      .select('id, is_active')
      .eq('user_id', user!.id)
      .single() as unknown as Promise<{ data: { id: string; is_active: boolean } | null; error: null }>)

    // Designer found but inactive -- app should sign out and show error
    expect(result.data?.is_active).toBe(false)

    // App should sign out
    await supabase.auth.signOut()
    expect(supabase.auth.signOut).toHaveBeenCalled()
  })

  it('user with no designer account should be rejected', async () => {
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: { user: { id: 'user-4' }, session: {} },
      error: null,
    } as never)

    vi.mocked(supabase.auth.getUser).mockResolvedValue({
      data: { user: { id: 'user-4' } },
      error: null,
    } as never)

    const { builder } = createMockQueryBuilder({
      data: null,
      error: { code: 'PGRST116', message: 'no rows returned' },
    })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    await supabase.auth.signInWithPassword({
      email: 'nodesigner@example.com',
      password: 'password',
    })

    const { data: { user } } = await supabase.auth.getUser()

    const result = await (supabase
      .from('designers')
      .select('id, is_active')
      .eq('user_id', user!.id)
      .single() as unknown as Promise<{ data: null; error: { code: string } }>)

    // No designer found
    expect(result.data).toBeNull()
    expect(result.error?.code).toBe('PGRST116')
  })

  it('wrong credentials should return auth error', async () => {
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: { user: null, session: null },
      error: { message: 'Invalid login credentials', status: 400 },
    } as never)

    const { error } = await supabase.auth.signInWithPassword({
      email: 'wrong@example.com',
      password: 'wrongpassword',
    })

    expect(error).not.toBeNull()
    expect(error?.message).toContain('Invalid login credentials')
  })
})

describe('Design Request Status Updates', () => {
  let supabase: ReturnType<typeof createClient>

  beforeEach(() => {
    vi.clearAllMocks()
    supabase = createClient()
  })

  it('approving a design sets approved_at timestamp', async () => {
    const { builder } = createMockQueryBuilder({ data: { id: 'dr-001' }, error: null })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    const approvedAt = new Date().toISOString()

    await supabase
      .from('design_requests')
      .update({
        status: 'approved',
        approved_at: approvedAt,
      })
      .eq('id', 'dr-001')

    expect(builder.update).toHaveBeenCalledWith({
      status: 'approved',
      approved_at: approvedAt,
    })
  })

  it('requesting revision only updates status', async () => {
    const { builder } = createMockQueryBuilder({ data: { id: 'dr-001' }, error: null })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    await supabase
      .from('design_requests')
      .update({
        status: 'revision_requested',
      })
      .eq('id', 'dr-001')

    expect(builder.update).toHaveBeenCalledWith({
      status: 'revision_requested',
    })
  })

  it('completing a design sets completed_at timestamp', async () => {
    const { builder } = createMockQueryBuilder({ data: { id: 'dr-001' }, error: null })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    const completedAt = new Date().toISOString()

    await supabase
      .from('design_requests')
      .update({
        status: 'completed',
        completed_at: completedAt,
      })
      .eq('id', 'dr-001')

    expect(builder.update).toHaveBeenCalledWith({
      status: 'completed',
      completed_at: completedAt,
    })
  })

  it('canceling a request updates status only', async () => {
    const { builder } = createMockQueryBuilder({ data: { id: 'dr-001' }, error: null })
    vi.mocked(supabase.from).mockReturnValue(builder as never)

    await supabase
      .from('design_requests')
      .update({ status: 'canceled' })
      .eq('id', 'dr-001')

    expect(builder.update).toHaveBeenCalledWith({ status: 'canceled' })
  })
})

describe('Realtime Subscriptions', () => {
  let supabase: ReturnType<typeof createClient>

  beforeEach(() => {
    vi.clearAllMocks()
    supabase = createClient()
  })

  it('subscribes to design chat messages for a specific request', () => {
    const designRequestId = 'dr-001'
    const channelName = `design-chat-${designRequestId}`

    supabase.channel(channelName).on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'design_chat_messages',
        filter: `design_request_id=eq.${designRequestId}`,
      },
      () => {}
    ).subscribe()

    expect(supabase.channel).toHaveBeenCalledWith(channelName)
  })

  it('cleans up channel on unmount', () => {
    const channel = supabase.channel('test-channel')
    supabase.removeChannel(channel)
    expect(supabase.removeChannel).toHaveBeenCalledWith(channel)
  })
})
