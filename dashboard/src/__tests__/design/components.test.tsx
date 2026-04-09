/**
 * Component Tests: Designer Dashboard UI Components
 *
 * Tests the rendering and behavior of design-related React components
 * using React Testing Library with mocked Supabase.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

// ---- Component imports ----
import { DesignRequestButton } from '@/components/design/DesignRequestButton'
import { DesignStatusCard, type DesignRequestData } from '@/components/design/DesignStatusCard'
import { ChatMessageBubble } from '@/components/design/ChatMessageBubble'
import { DesignerStatusControls } from '@/components/design/DesignerStatusControls'

// ---- Helpers ----

function createDesignRequest(
  overrides: Partial<DesignRequestData> = {}
): DesignRequestData {
  return {
    id: 'dr-001',
    status: 'pending',
    designer_id: null,
    priority: 'normal',
    notes: null,
    accepted_at: null,
    delivered_at: null,
    approved_at: null,
    completed_at: null,
    created_at: '2026-01-15T10:00:00.000Z',
    ...overrides,
  }
}

function createChatMessage(
  overrides: Partial<{
    id: string
    sender_type: 'designer' | 'showroom'
    sender_name: string
    message_type: 'text' | 'image' | 'audio' | 'file'
    content: string | null
    file_url: string | null
    file_name: string | null
    file_size_bytes: number | null
    created_at: string
  }> = {}
) {
  return {
    id: 'msg-001',
    sender_type: 'designer' as const,
    sender_name: 'John Designer',
    message_type: 'text' as const,
    content: 'Hello from the designer!',
    file_url: null,
    file_name: null,
    file_size_bytes: null,
    created_at: new Date().toISOString(),
    ...overrides,
  }
}

// ---- Tests ----

describe('DesignRequestButton', () => {
  it('renders the button when there is no existing request', () => {
    render(
      <DesignRequestButton
        projectId="proj-001"
        showroomId="sr-001"
        hasExistingRequest={false}
      />
    )
    const button = screen.getByRole('button', { name: /request design/i })
    expect(button).toBeInTheDocument()
  })

  it('does not render when hasExistingRequest is true', () => {
    const { container } = render(
      <DesignRequestButton
        projectId="proj-001"
        showroomId="sr-001"
        hasExistingRequest={true}
      />
    )
    expect(container.innerHTML).toBe('')
  })

  it('opens the modal on click', async () => {
    render(
      <DesignRequestButton
        projectId="proj-001"
        showroomId="sr-001"
        hasExistingRequest={false}
      />
    )

    const button = screen.getByRole('button', { name: /request design/i })
    await userEvent.click(button)

    // The modal should now be visible (button + modal title both say "Request Design")
    await waitFor(() => {
      expect(screen.getAllByText(/request design/i).length).toBeGreaterThanOrEqual(2)
    })
  })

  it('renders with the Paintbrush icon and correct text', () => {
    render(
      <DesignRequestButton
        projectId="proj-001"
        showroomId="sr-001"
        hasExistingRequest={false}
      />
    )
    expect(screen.getByText('Request Design')).toBeInTheDocument()
  })
})

describe('DesignStatusCard', () => {
  it('shows the correct status badge for pending', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'pending' })}
      />
    )
    expect(screen.getByText('Pending')).toBeInTheDocument()
  })

  it('shows the correct status badge for accepted', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'accepted' })}
      />
    )
    expect(screen.getByText('Accepted')).toBeInTheDocument()
  })

  it('shows the correct status badge for in_progress', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'in_progress' })}
      />
    )
    expect(screen.getByText('In Progress')).toBeInTheDocument()
  })

  it('shows the correct status badge for delivered', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'delivered' })}
      />
    )
    expect(screen.getByText('Delivered')).toBeInTheDocument()
  })

  it('shows the correct status badge for completed', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'completed' })}
      />
    )
    expect(screen.getByText('Completed')).toBeInTheDocument()
  })

  it('shows the correct status badge for canceled', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'canceled' })}
      />
    )
    expect(screen.getByText('Canceled')).toBeInTheDocument()
  })

  it('shows the correct status badge for revision_requested', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'revision_requested' })}
      />
    )
    expect(screen.getByText('Revision Requested')).toBeInTheDocument()
  })

  it('shows approve and revision buttons when status is delivered', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'delivered' })}
      />
    )
    expect(
      screen.getByRole('button', { name: /approve design/i })
    ).toBeInTheDocument()
    expect(
      screen.getByRole('button', { name: /request revision/i })
    ).toBeInTheDocument()
  })

  it('shows cancel button when status is pending', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'pending' })}
      />
    )
    expect(
      screen.getByRole('button', { name: /cancel request/i })
    ).toBeInTheDocument()
  })

  it('shows mark complete button when status is approved', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'approved' })}
      />
    )
    expect(
      screen.getByRole('button', { name: /mark complete/i })
    ).toBeInTheDocument()
  })

  it('shows no action buttons when status is completed', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'completed' })}
      />
    )
    // Should not have approve, revision, cancel, or complete buttons
    expect(
      screen.queryByRole('button', { name: /approve design/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /request revision/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /cancel request/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /mark complete/i })
    ).not.toBeInTheDocument()
  })

  it('shows no action buttons when status is canceled', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'canceled' })}
      />
    )
    expect(
      screen.queryByRole('button', { name: /approve design/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /cancel request/i })
    ).not.toBeInTheDocument()
  })

  it('shows no action buttons when status is in_progress', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'in_progress' })}
      />
    )
    expect(
      screen.queryByRole('button', { name: /approve design/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /cancel request/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /mark complete/i })
    ).not.toBeInTheDocument()
  })

  it('displays designer name when provided', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({
          status: 'in_progress',
          designer_id: 'designer-1',
        })}
        designerName="Jane Smith"
      />
    )
    expect(screen.getByText('Jane Smith')).toBeInTheDocument()
  })

  it('does not display designer section when designerName is not provided', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'pending' })}
      />
    )
    expect(screen.queryByText('Designer')).not.toBeInTheDocument()
  })

  it('displays priority badge', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ priority: 'urgent' })}
      />
    )
    expect(screen.getByText('Urgent')).toBeInTheDocument()
  })

  it('displays priority badge for high priority', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ priority: 'high' })}
      />
    )
    expect(screen.getByText('High')).toBeInTheDocument()
  })

  it('displays design brief when notes are provided', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({
          notes: 'Modern kitchen with white marble countertops',
        })}
      />
    )
    expect(
      screen.getByText('Modern kitchen with white marble countertops')
    ).toBeInTheDocument()
    expect(screen.getByText('Design Brief')).toBeInTheDocument()
  })

  it('does not display design brief when notes are null', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ notes: null })}
      />
    )
    expect(screen.queryByText('Design Brief')).not.toBeInTheDocument()
  })

  it('shows the requested date', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({
          created_at: '2026-01-15T10:00:00.000Z',
        })}
      />
    )
    expect(screen.getByText('Requested')).toBeInTheDocument()
    expect(screen.getByText('Jan 15, 2026')).toBeInTheDocument()
  })

  it('shows accepted date when present', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({
          status: 'in_progress',
          accepted_at: '2026-01-16T10:00:00.000Z',
        })}
      />
    )
    expect(screen.getByText('Accepted')).toBeInTheDocument()
    expect(screen.getByText('Jan 16, 2026')).toBeInTheDocument()
  })

  it('shows delivered date when present', () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({
          status: 'delivered',
          delivered_at: '2026-01-20T10:00:00.000Z',
        })}
      />
    )
    expect(screen.getAllByText('Delivered').length).toBeGreaterThanOrEqual(1)
    // The badge also says "Delivered", so check dates area
    expect(screen.getByText('Jan 20, 2026')).toBeInTheDocument()
  })

  it('opens confirmation dialog when approve is clicked', async () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'delivered' })}
      />
    )
    const approveBtn = screen.getByRole('button', { name: /approve design/i })
    await userEvent.click(approveBtn)

    await waitFor(() => {
      expect(screen.getByText('Approve Design?')).toBeInTheDocument()
    })
  })

  it('opens confirmation dialog when cancel is clicked', async () => {
    render(
      <DesignStatusCard
        designRequest={createDesignRequest({ status: 'pending' })}
      />
    )
    const cancelBtn = screen.getByRole('button', { name: /cancel request/i })
    await userEvent.click(cancelBtn)

    await waitFor(() => {
      expect(screen.getByText('Cancel Design Request?')).toBeInTheDocument()
    })
  })
})

describe('ChatMessageBubble', () => {
  it('renders a text message', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          message_type: 'text',
          content: 'Here is the updated design.',
        })}
        isOwnMessage={false}
      />
    )
    expect(screen.getByText('Here is the updated design.')).toBeInTheDocument()
  })

  it('renders the sender name for non-own messages', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          sender_name: 'Alice Designer',
        })}
        isOwnMessage={false}
      />
    )
    expect(screen.getByText('Alice Designer')).toBeInTheDocument()
  })

  it('does not render sender name for own messages', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          sender_name: 'My Name',
        })}
        isOwnMessage={true}
      />
    )
    expect(screen.queryByText('My Name')).not.toBeInTheDocument()
  })

  it('renders an image message with thumbnail', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          message_type: 'image',
          file_url: 'https://example.com/kitchen-render.png',
          file_name: 'kitchen-render.png',
          content: null,
        })}
        isOwnMessage={false}
      />
    )
    const img = screen.getByRole('img', { name: /kitchen-render/i })
    expect(img).toBeInTheDocument()
    expect(img).toHaveAttribute('src', 'https://example.com/kitchen-render.png')
  })

  it('renders an audio message with a play button', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          message_type: 'audio',
          file_url: 'https://example.com/recording.webm',
          file_name: 'recording.webm',
          content: null,
        })}
        isOwnMessage={false}
      />
    )
    // The AudioPlayer component should have a play button
    const playButton = screen.getByRole('button')
    expect(playButton).toBeInTheDocument()
  })

  it('renders a file message with download link', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          message_type: 'file',
          file_url: 'https://example.com/blueprint.pdf',
          file_name: 'blueprint.pdf',
          file_size_bytes: 2048576,
          content: null,
        })}
        isOwnMessage={false}
      />
    )
    expect(screen.getByText('blueprint.pdf')).toBeInTheDocument()
    expect(screen.getByText('2.0 MB')).toBeInTheDocument()
    const link = screen.getByRole('link')
    expect(link).toHaveAttribute('href', 'https://example.com/blueprint.pdf')
  })

  it('aligns own messages to the right (self-end)', () => {
    const { container } = render(
      <ChatMessageBubble
        message={createChatMessage({ content: 'My message' })}
        isOwnMessage={true}
      />
    )
    const wrapper = container.firstElementChild as HTMLElement
    expect(wrapper.className).toContain('self-end')
  })

  it('aligns other messages to the left (self-start)', () => {
    const { container } = render(
      <ChatMessageBubble
        message={createChatMessage({ content: 'Their message' })}
        isOwnMessage={false}
      />
    )
    const wrapper = container.firstElementChild as HTMLElement
    expect(wrapper.className).toContain('self-start')
  })

  it('applies primary-colored background for own messages', () => {
    const { container } = render(
      <ChatMessageBubble
        message={createChatMessage({ content: 'My message' })}
        isOwnMessage={true}
      />
    )
    const bubble = container.querySelector('.bg-primary')
    expect(bubble).not.toBeNull()
  })

  it('applies muted background for other messages', () => {
    const { container } = render(
      <ChatMessageBubble
        message={createChatMessage({ content: 'Their message' })}
        isOwnMessage={false}
      />
    )
    const bubble = container.querySelector('.bg-muted')
    expect(bubble).not.toBeNull()
  })

  it('formats file size correctly for small files', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          message_type: 'file',
          file_url: 'https://example.com/small.txt',
          file_name: 'small.txt',
          file_size_bytes: 512,
          content: null,
        })}
        isOwnMessage={false}
      />
    )
    expect(screen.getByText('512 B')).toBeInTheDocument()
  })

  it('formats file size correctly for KB-range files', () => {
    render(
      <ChatMessageBubble
        message={createChatMessage({
          message_type: 'file',
          file_url: 'https://example.com/medium.zip',
          file_name: 'medium.zip',
          file_size_bytes: 153600,
          content: null,
        })}
        isOwnMessage={false}
      />
    )
    expect(screen.getByText('150.0 KB')).toBeInTheDocument()
  })
})

describe('DesignerStatusControls', () => {
  it('shows Start Working button when status is accepted', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="accepted"
        hasUploadedFiles={false}
      />
    )
    expect(
      screen.getByRole('button', { name: /start working/i })
    ).toBeInTheDocument()
  })

  it('shows Mark as Delivered button when status is in_progress and has files', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="in_progress"
        hasUploadedFiles={true}
      />
    )
    const deliverBtn = screen.getByRole('button', { name: /mark as delivered/i })
    expect(deliverBtn).toBeInTheDocument()
    expect(deliverBtn).not.toBeDisabled()
  })

  it('disables Mark as Delivered button when no files are uploaded', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="in_progress"
        hasUploadedFiles={false}
      />
    )
    const deliverBtn = screen.getByRole('button', { name: /mark as delivered/i })
    expect(deliverBtn).toBeDisabled()
    expect(
      screen.getByText(/upload at least one design file/i)
    ).toBeInTheDocument()
  })

  it('shows Resume Work button when status is revision_requested', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="revision_requested"
        hasUploadedFiles={true}
      />
    )
    expect(
      screen.getByRole('button', { name: /resume work/i })
    ).toBeInTheDocument()
  })

  it('shows Waiting for review message when status is delivered', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="delivered"
        hasUploadedFiles={true}
      />
    )
    expect(screen.getByText(/waiting for review/i)).toBeInTheDocument()
  })

  it('shows Completed message when status is approved', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="approved"
        hasUploadedFiles={true}
      />
    )
    expect(screen.getByText('Completed')).toBeInTheDocument()
  })

  it('shows Completed message when status is completed', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="completed"
        hasUploadedFiles={true}
      />
    )
    expect(screen.getAllByText('Completed').length).toBeGreaterThanOrEqual(1)
  })

  it('shows the correct status badge', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="in_progress"
        hasUploadedFiles={true}
      />
    )
    expect(screen.getByText('In Progress')).toBeInTheDocument()
  })

  it('does not show any action buttons for pending (designer has not accepted yet)', () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="pending"
        hasUploadedFiles={false}
      />
    )
    expect(
      screen.queryByRole('button', { name: /start working/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /mark as delivered/i })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /resume work/i })
    ).not.toBeInTheDocument()
  })

  it('opens confirmation dialog when Start Working is clicked', async () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="accepted"
        hasUploadedFiles={false}
      />
    )
    const startBtn = screen.getByRole('button', { name: /start working/i })
    await userEvent.click(startBtn)

    await waitFor(() => {
      expect(screen.getByText('Start Working?')).toBeInTheDocument()
    })
  })

  it('opens confirmation dialog when Mark as Delivered is clicked', async () => {
    render(
      <DesignerStatusControls
        designRequestId="dr-001"
        currentStatus="in_progress"
        hasUploadedFiles={true}
      />
    )
    const deliverBtn = screen.getByRole('button', { name: /mark as delivered/i })
    await userEvent.click(deliverBtn)

    await waitFor(() => {
      expect(screen.getByText('Mark as Delivered?')).toBeInTheDocument()
    })
  })
})
