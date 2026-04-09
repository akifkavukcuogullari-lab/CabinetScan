import { createClient } from '@/lib/supabase/client'

const MESSAGE_TEMPLATES: Record<string, (ref: string) => string> = {
  design_accepted: (ref) => `A designer has accepted project ${ref}.`,
  design_delivered: (ref) => `Design files have been delivered for project ${ref}. Please review.`,
  design_approved: (ref) => `Your design for project ${ref} has been approved!`,
  design_revision: (ref) => `Revision requested for project ${ref}. Please check the feedback.`,
  design_dropped: (ref) => `Designer has dropped project ${ref}. It's back in the design pool.`,
  design_completed: (ref) => `Project ${ref} has been marked as completed.`,
  design_canceled: (ref) => `Design request for project ${ref} has been canceled.`,
  design_started: (ref) => `Designer has started working on project ${ref}.`,
  estimate_set: (ref) => `Designer has set an estimated completion time for project ${ref}.`,
  chat_message: (ref) => `New message on project ${ref}.`,
}

export async function sendDesignNotification(params: {
  eventType: string
  designRequestId: string
  senderType: 'designer' | 'showroom'
  senderId: string
  messagePreview?: string
}) {
  const supabase = createClient()

  try {
    // Get design request details for recipient and project reference
    const { data: request, error: reqError } = await supabase
      .from('design_requests')
      .select('id, showroom_id, designer_id, project_id, projects(reference_number)')
      .eq('id', params.designRequestId)
      .single()

    if (reqError) {
      console.error('Notification: failed to fetch design request:', reqError)
      return
    }
    if (!request) return

    const projectRef = (request.projects as { reference_number: string } | null)?.reference_number || 'Unknown'

    // Determine recipient
    let recipientType: 'designer' | 'showroom'
    let recipientId: string

    if (params.senderType === 'designer') {
      // Designer did something → notify showroom owner
      recipientType = 'showroom'
      const { data: owner } = await supabase
        .from('showroom_users')
        .select('user_id')
        .eq('showroom_id', request.showroom_id)
        .eq('is_primary', true)
        .single()
      if (!owner) return
      recipientId = owner.user_id
    } else {
      // Showroom did something → notify designer
      recipientType = 'designer'
      if (!request.designer_id) return
      recipientId = request.designer_id
    }

    // Build message
    const template = MESSAGE_TEMPLATES[params.eventType]
    let message = template ? template(projectRef) : `Update on project ${projectRef}.`
    if (params.eventType === 'chat_message' && params.messagePreview) {
      const preview = params.messagePreview.substring(0, 50)
      message = `New message on project ${projectRef}: "${preview}${params.messagePreview.length > 50 ? '...' : ''}"`
    }

    // Insert notification directly — no Edge Function needed
    const { error: insertError } = await supabase.from('design_notifications').insert({
      recipient_type: recipientType,
      recipient_id: recipientId,
      event_type: params.eventType,
      design_request_id: params.designRequestId,
      project_reference: projectRef,
      message,
    })
    if (insertError) {
      console.error('Notification: failed to insert:', insertError)
    }
  } catch (err) {
    console.error('Failed to send design notification:', err)
  }
}
