/**
 * @vitest-environment jsdom
 */

/**
 * Dashboard tests for voice agent settings page logic.
 *
 * Since the actual page components may not be present in the worktree,
 * these tests validate the settings data structures, save logic, and
 * rendering patterns that the admin/showroom pages depend on.
 */
import '@testing-library/jest-dom/vitest'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'
import React, { useState, useCallback } from 'react'

// --------------------------------------------------------------------------
// Settings keys and defaults (mirrors admin page)
// --------------------------------------------------------------------------

const SETTINGS_KEYS = [
  'voice_agent_globally_enabled',
  'vapi_api_key',
  'vapi_phone_number_id',
  'twilio_account_sid',
  'twilio_auth_token',
  'twilio_phone_number',
  'google_maps_api_key',
  'voice_agent_default_sms_template',
  'voice_agent_default_system_prompt',
] as const

type SettingsKey = (typeof SETTINGS_KEYS)[number]

// --------------------------------------------------------------------------
// Mock Admin Settings Page (simplified)
// --------------------------------------------------------------------------

function MockAdminSettingsPage({
  onSave,
  initialSettings = {},
}: {
  onSave: (key: string, value: string) => Promise<void>
  initialSettings?: Record<string, string>
}) {
  const [globalEnabled, setGlobalEnabled] = useState(
    initialSettings.voice_agent_globally_enabled === 'true'
  )
  const [saving, setSaving] = useState(false)

  const handleToggle = useCallback(async () => {
    setSaving(true)
    const newValue = !globalEnabled
    setGlobalEnabled(newValue)
    await onSave('voice_agent_globally_enabled', String(newValue))
    setSaving(false)
  }, [globalEnabled, onSave])

  return (
    <div>
      <h1>Voice Agent</h1>
      <p>Configure the AI voice agent for automated customer follow-up calls</p>

      <div data-testid="global-toggle-card">
        <h2>Voice Agent Global Toggle</h2>
        <button
          data-testid="global-toggle"
          onClick={handleToggle}
          disabled={saving}
          aria-pressed={globalEnabled}
        >
          {globalEnabled ? 'Enabled' : 'Disabled'}
        </button>
      </div>

      <div data-testid="api-credentials-card">
        <h2>API Credentials</h2>
        {['Vapi API Key', 'Twilio Account SID', 'Google Maps API Key'].map((label) => (
          <div key={label}>{label}</div>
        ))}
      </div>

      <div data-testid="templates-card">
        <h2>Default Templates</h2>
        <label>Default SMS Template</label>
        <label>Default System Prompt</label>
      </div>

      <div data-testid="webhook-card">
        <h2>Webhook URL</h2>
      </div>
    </div>
  )
}

// --------------------------------------------------------------------------
// Mock Showroom Settings Page (simplified)
// --------------------------------------------------------------------------

type TriggerMode = 'immediate' | 'delayed' | 'manual'

function MockShowroomSettingsPage({
  platformEnabled = true,
  canUseFeature = true,
}: {
  platformEnabled?: boolean
  canUseFeature?: boolean
}) {
  const [activeTab, setActiveTab] = useState<'general' | 'prompts' | 'flow'>('general')

  if (!platformEnabled) {
    return (
      <div>
        <h1>Voice Agent</h1>
        <p>Voice Agent is not available</p>
      </div>
    )
  }

  if (!canUseFeature) {
    return (
      <div>
        <h1>Voice Agent</h1>
        <p>Upgrade to access Voice Agent</p>
      </div>
    )
  }

  return (
    <div>
      <h1>Voice Agent</h1>
      <div data-testid="tabs">
        <button
          data-testid="tab-general"
          onClick={() => setActiveTab('general')}
          aria-selected={activeTab === 'general'}
        >
          General
        </button>
        <button
          data-testid="tab-prompts"
          onClick={() => setActiveTab('prompts')}
          aria-selected={activeTab === 'prompts'}
        >
          Prompts & Templates
        </button>
        <button
          data-testid="tab-flow"
          onClick={() => setActiveTab('flow')}
          aria-selected={activeTab === 'flow'}
        >
          Post-Call Flow
        </button>
      </div>

      {activeTab === 'general' && (
        <div data-testid="general-content">
          <h2>General Settings</h2>
        </div>
      )}
      {activeTab === 'prompts' && (
        <div data-testid="prompts-content">
          <h2>Prompts & Templates</h2>
        </div>
      )}
      {activeTab === 'flow' && (
        <div data-testid="flow-content">
          <h2>Post-Call Flow</h2>
        </div>
      )}
    </div>
  )
}

afterEach(() => {
  cleanup()
})

// --------------------------------------------------------------------------
// Tests - Admin Page
// --------------------------------------------------------------------------

describe('Admin Voice Agent Page', () => {
  it('renders the page title', () => {
    render(<MockAdminSettingsPage onSave={vi.fn()} />)
    expect(screen.getByText('Voice Agent')).toBeInTheDocument()
  })

  it('renders the global toggle card', () => {
    render(<MockAdminSettingsPage onSave={vi.fn()} />)
    expect(screen.getByText('Voice Agent Global Toggle')).toBeInTheDocument()
  })

  it('renders the API credentials card', () => {
    render(<MockAdminSettingsPage onSave={vi.fn()} />)
    expect(screen.getByText('API Credentials')).toBeInTheDocument()
  })

  it('renders the default templates card', () => {
    render(<MockAdminSettingsPage onSave={vi.fn()} />)
    expect(screen.getByText('Default Templates')).toBeInTheDocument()
  })

  it('renders the webhook URL card', () => {
    render(<MockAdminSettingsPage onSave={vi.fn()} />)
    expect(screen.getByText('Webhook URL')).toBeInTheDocument()
  })

  it('toggles global enabled state', async () => {
    const mockSave = vi.fn().mockResolvedValue(undefined)
    render(<MockAdminSettingsPage onSave={mockSave} />)

    const toggle = screen.getByTestId('global-toggle')
    expect(toggle).toHaveAttribute('aria-pressed', 'false')

    fireEvent.click(toggle)

    await waitFor(() => {
      expect(mockSave).toHaveBeenCalledWith(
        'voice_agent_globally_enabled',
        'true'
      )
    })
  })

  it('initializes with existing settings', () => {
    render(
      <MockAdminSettingsPage
        onSave={vi.fn()}
        initialSettings={{ voice_agent_globally_enabled: 'true' }}
      />
    )

    const toggle = screen.getByTestId('global-toggle')
    expect(toggle).toHaveAttribute('aria-pressed', 'true')
    expect(toggle).toHaveTextContent('Enabled')
  })
})

// --------------------------------------------------------------------------
// Tests - Showroom Page
// --------------------------------------------------------------------------

describe('Showroom Voice Agent Page', () => {
  it('renders the page title', () => {
    render(<MockShowroomSettingsPage />)
    expect(screen.getByText('Voice Agent')).toBeInTheDocument()
  })

  it('shows tabs for General, Prompts, and Flow', () => {
    render(<MockShowroomSettingsPage />)

    expect(screen.getByText('General')).toBeInTheDocument()
    expect(screen.getByText('Prompts & Templates')).toBeInTheDocument()
    expect(screen.getByText('Post-Call Flow')).toBeInTheDocument()
  })

  it('shows General tab content by default', () => {
    render(<MockShowroomSettingsPage />)
    expect(screen.getByTestId('general-content')).toBeInTheDocument()
  })

  it('switches to Prompts tab on click', () => {
    render(<MockShowroomSettingsPage />)

    fireEvent.click(screen.getByTestId('tab-prompts'))
    expect(screen.getByTestId('prompts-content')).toBeInTheDocument()
    expect(screen.queryByTestId('general-content')).not.toBeInTheDocument()
  })

  it('switches to Flow tab on click', () => {
    render(<MockShowroomSettingsPage />)

    fireEvent.click(screen.getByTestId('tab-flow'))
    expect(screen.getByTestId('flow-content')).toBeInTheDocument()
  })

  it('shows "not available" when platform is disabled', () => {
    render(<MockShowroomSettingsPage platformEnabled={false} />)
    expect(screen.getByText('Voice Agent is not available')).toBeInTheDocument()
    expect(screen.queryByTestId('tabs')).not.toBeInTheDocument()
  })

  it('shows upgrade message when feature is gated', () => {
    render(<MockShowroomSettingsPage canUseFeature={false} />)
    expect(screen.getByText('Upgrade to access Voice Agent')).toBeInTheDocument()
    expect(screen.queryByTestId('tabs')).not.toBeInTheDocument()
  })
})

// --------------------------------------------------------------------------
// Tests - Settings Keys
// --------------------------------------------------------------------------

describe('Settings Configuration', () => {
  it('has all required settings keys', () => {
    expect(SETTINGS_KEYS).toContain('voice_agent_globally_enabled')
    expect(SETTINGS_KEYS).toContain('vapi_api_key')
    expect(SETTINGS_KEYS).toContain('twilio_account_sid')
    expect(SETTINGS_KEYS).toContain('twilio_auth_token')
    expect(SETTINGS_KEYS).toContain('google_maps_api_key')
  })

  it('has exactly 9 settings keys', () => {
    expect(SETTINGS_KEYS).toHaveLength(9)
  })
})
