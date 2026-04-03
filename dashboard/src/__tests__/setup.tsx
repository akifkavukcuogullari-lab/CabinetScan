import '@testing-library/jest-dom/vitest'

// Mock next/navigation
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: vi.fn(),
    refresh: vi.fn(),
    replace: vi.fn(),
    back: vi.fn(),
    forward: vi.fn(),
    prefetch: vi.fn(),
  }),
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
}))

// Mock next/image
vi.mock('next/image', () => ({
  default: (props: Record<string, unknown>) => {
    // eslint-disable-next-line @next/next/no-img-element, jsx-a11y/alt-text
    const { fill, priority, ...rest } = props
    return <img {...rest} />
  },
}))

// Mock sonner toast
vi.mock('sonner', () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
    info: vi.fn(),
    warning: vi.fn(),
  },
}))

// Mock @/lib/supabase/client
const mockSupabaseClient = createMockSupabaseClient()

vi.mock('@/lib/supabase/client', () => ({
  createClient: () => mockSupabaseClient,
}))

// Helper to create a chainable mock Supabase client
function createMockSupabaseClient() {
  const chainable = () => {
    const chain: Record<string, unknown> = {}
    const methods = [
      'select', 'insert', 'update', 'delete', 'upsert',
      'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike',
      'is', 'in', 'contains', 'containedBy', 'filter',
      'order', 'limit', 'range', 'single', 'maybeSingle',
      'csv', 'not', 'or', 'match', 'textSearch',
    ]
    for (const method of methods) {
      chain[method] = vi.fn().mockReturnValue(chain)
    }
    // Terminal methods return promises
    chain.then = undefined
    // Make it thenable by default (resolves with empty data)
    Object.defineProperty(chain, 'then', {
      value: (resolve: (val: { data: null; error: null }) => void) =>
        resolve({ data: null, error: null }),
      writable: true,
      configurable: true,
    })
    return chain
  }

  return {
    auth: {
      signInWithPassword: vi.fn().mockResolvedValue({ data: {}, error: null }),
      signOut: vi.fn().mockResolvedValue({ error: null }),
      getUser: vi.fn().mockResolvedValue({ data: { user: { id: 'test-user-id' } }, error: null }),
      onAuthStateChange: vi.fn().mockReturnValue({ data: { subscription: { unsubscribe: vi.fn() } } }),
    },
    from: vi.fn().mockImplementation(() => chainable()),
    storage: {
      from: vi.fn().mockReturnValue({
        upload: vi.fn().mockResolvedValue({ data: { path: 'test-path' }, error: null }),
        getPublicUrl: vi.fn().mockReturnValue({ data: { publicUrl: 'https://example.com/test.png' } }),
        createSignedUrl: vi.fn().mockResolvedValue({ data: { signedUrl: 'https://example.com/signed' }, error: null }),
        remove: vi.fn().mockResolvedValue({ data: [], error: null }),
      }),
    },
    channel: vi.fn().mockReturnValue({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn().mockReturnThis(),
    }),
    removeChannel: vi.fn(),
  }
}

// Re-export so tests can access and configure the mock
export { mockSupabaseClient }
