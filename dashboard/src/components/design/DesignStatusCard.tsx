'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import {
  Paintbrush,
  CheckCircle2,
  Clock,
  User,
  Loader2,
  XCircle,
  RotateCcw,
} from 'lucide-react'
import { sendDesignNotification } from '@/lib/design-notifications'

export interface DesignRequestData {
  id: string
  status: string
  designer_id: string | null
  priority: string | null
  notes: string | null
  accepted_at: string | null
  delivered_at: string | null
  approved_at: string | null
  completed_at: string | null
  estimated_completion_at: string | null
  rejection_reason: string | null
  showroom_id?: string
  project_id?: string
  created_at: string
}

interface DesignStatusCardProps {
  designRequest: DesignRequestData
  designerName?: string | null
}

const statusConfig: Record<string, { label: string; color: string }> = {
  pending: { label: 'Pending', color: 'bg-orange-100 text-orange-800' },
  accepted: { label: 'Accepted', color: 'bg-blue-100 text-blue-800' },
  in_progress: { label: 'In Progress', color: 'bg-blue-100 text-blue-800' },
  delivered: { label: 'Delivered', color: 'bg-purple-100 text-purple-800' },
  approved: { label: 'Approved', color: 'bg-green-100 text-green-800' },
  revision_requested: { label: 'Revision Requested', color: 'bg-yellow-100 text-yellow-800' },
  completed: { label: 'Completed', color: 'bg-green-100 text-green-800' },
  canceled: { label: 'Canceled', color: 'bg-gray-100 text-gray-800' },
}

const priorityConfig: Record<string, { label: string; color: string }> = {
  low: { label: 'Low', color: 'bg-gray-100 text-gray-700' },
  normal: { label: 'Normal', color: 'bg-blue-50 text-blue-700' },
  high: { label: 'High', color: 'bg-orange-100 text-orange-700' },
  urgent: { label: 'Urgent', color: 'bg-red-100 text-red-700' },
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '-'
  return new Date(dateStr).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZone: 'America/New_York',
  })
}

export function DesignStatusCard({ designRequest, designerName }: DesignStatusCardProps) {
  const router = useRouter()
  const [isUpdating, setIsUpdating] = useState(false)
  const [confirmAction, setConfirmAction] = useState<string | null>(null)
  const [rating, setRating] = useState(0)
  const [reviewText, setReviewText] = useState('')
  const [rejectionReason, setRejectionReason] = useState('')

  const status = statusConfig[designRequest.status] || statusConfig.pending
  const priority = priorityConfig[designRequest.priority || 'normal'] || priorityConfig.normal

  const updateStatus = async (newStatus: string, extraFields: Record<string, string | null> = {}) => {
    setIsUpdating(true)
    try {
      const supabase = createClient()
      const { error } = await supabase
        .from('design_requests')
        .update({
          status: newStatus,
          ...extraFields,
        })
        .eq('id', designRequest.id)

      if (error) {
        toast.error('Failed to update design request status.')
        console.error('Design request update error:', error)
        return
      }

      toast.success(`Design request ${newStatus.replace('_', ' ')}.`)

      // Fire-and-forget notification to designer
      const eventMap: Record<string, string> = {
        approved: 'design_approved',
        revision_requested: 'design_revision',
        completed: 'design_completed',
        canceled: 'design_canceled',
      }
      const eventType = eventMap[newStatus]
      if (eventType) {
        supabase.auth.getUser().then(({ data: { user } }: { data: { user: { id: string } | null } }) => {
          if (user) {
            sendDesignNotification({
              eventType,
              designRequestId: designRequest.id,
              senderType: 'showroom',
              senderId: user.id,
            })
          }
        })
      }

      router.refresh()
    } catch (err) {
      console.error('Error updating design request:', err)
      toast.error('An unexpected error occurred.')
    } finally {
      setIsUpdating(false)
      setConfirmAction(null)
    }
  }

  const handleAction = (action: string) => {
    setConfirmAction(action)
  }

  const executeAction = async () => {
    if (!confirmAction) return
    switch (confirmAction) {
      case 'accept':
        if (rating === 0) {
          toast.error('Please provide a rating (1-5 stars).')
          return
        }
        // Save review first
        {
          const supabase = createClient()
          const { data: { user } } = await supabase.auth.getUser() as { data: { user: { id: string } | null } }
          const { error: reviewError } = await supabase.from('design_reviews').insert({
            design_request_id: designRequest.id,
            designer_id: designRequest.designer_id,
            showroom_id: designRequest.showroom_id || '',
            rating,
            review_text: reviewText.trim() || null,
            reviewed_by: user?.id,
          })
          if (reviewError) {
            console.error('Review insert error:', reviewError)
            toast.error('Failed to save review.')
            return
          }
        }
        updateStatus('approved', { approved_at: new Date().toISOString() })
        break
      case 'reject':
        if (!rejectionReason.trim() || rejectionReason.trim().length < 20) {
          toast.error('Please provide a detailed rejection reason (at least 20 characters).')
          return
        }
        // Reject keeps it with the same designer — goes back to in_progress
        updateStatus('revision_requested', { rejection_reason: rejectionReason.trim() })
        break
      case 'complete':
        updateStatus('completed', { completed_at: new Date().toISOString() })
        break
      case 'cancel': {
        // Delete the pending request so a new one can be created
        const supabase = createClient()
        const { error } = await supabase
          .from('design_requests')
          .delete()
          .eq('id', designRequest.id)

        if (error) {
          toast.error('Failed to cancel design request.')
          console.error('Design request delete error:', error)
        } else {
          // Revert project status to submitted
          await supabase
            .from('projects')
            .update({ status: 'submitted' })
            .eq('id', designRequest.project_id)
          toast.success('Design request canceled.')
          router.refresh()
        }
        setIsUpdating(false)
        setConfirmAction(null)
        return
      }
    }
  }

  const confirmMessages: Record<string, { title: string; description: string }> = {
    accept: {
      title: 'Accept Design',
      description: 'Rate the designer and accept the delivered design.',
    },
    reject: {
      title: 'Reject Design',
      description: 'The design will be sent back to the same designer for revision. Please explain what needs to be fixed.',
    },
    complete: {
      title: 'Mark as Complete?',
      description: 'This will mark the design request as completed.',
    },
    cancel: {
      title: 'Cancel Design Request?',
      description: 'This will cancel the design request. You can submit a new request later if needed.',
    },
  }

  return (
    <>
      <AlertDialog open={!!confirmAction} onOpenChange={() => setConfirmAction(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmAction ? confirmMessages[confirmAction]?.title : ''}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirmAction ? confirmMessages[confirmAction]?.description : ''}
            </AlertDialogDescription>
          </AlertDialogHeader>

          {/* Accept: Star rating + optional review */}
          {confirmAction === 'accept' && (
            <div className="space-y-4 py-2">
              <div className="space-y-2">
                <label className="text-sm font-medium">Rate the designer</label>
                <div className="flex gap-1">
                  {[1, 2, 3, 4, 5].map((star) => (
                    <button
                      key={star}
                      type="button"
                      onClick={() => setRating(star)}
                      className="focus:outline-none"
                    >
                      <svg
                        className={`h-8 w-8 transition-colors ${star <= rating ? 'text-yellow-400 fill-yellow-400' : 'text-gray-300'}`}
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        strokeWidth={1.5}
                        fill={star <= rating ? 'currentColor' : 'none'}
                      >
                        <path strokeLinecap="round" strokeLinejoin="round" d="M11.48 3.499a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.563.563 0 00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.563.563 0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z" />
                      </svg>
                    </button>
                  ))}
                </div>
                {rating > 0 && (
                  <p className="text-xs text-muted-foreground">
                    {['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'][rating]}
                  </p>
                )}
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium">Review (optional)</label>
                <textarea
                  value={reviewText}
                  onChange={(e) => setReviewText(e.target.value)}
                  placeholder="Share your feedback about the designer's work..."
                  className="w-full rounded-md border px-3 py-2 text-sm bg-background min-h-[80px] resize-none"
                />
              </div>
            </div>
          )}

          {/* Reject: Mandatory reason */}
          {confirmAction === 'reject' && (
            <div className="space-y-2 py-2">
              <label className="text-sm font-medium">Rejection reason (required)</label>
              <textarea
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                placeholder="Please explain in detail what needs to be fixed or changed..."
                className="w-full rounded-md border px-3 py-2 text-sm bg-background min-h-[100px] resize-none"
                minLength={20}
              />
              <p className="text-xs text-muted-foreground">
                {rejectionReason.trim().length}/20 characters minimum
              </p>
            </div>
          )}

          <AlertDialogFooter>
            <AlertDialogCancel disabled={isUpdating} onClick={() => { setRating(0); setReviewText(''); setRejectionReason('') }}>
              Cancel
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={executeAction}
              disabled={
                isUpdating
                || (confirmAction === 'accept' && rating === 0)
                || (confirmAction === 'reject' && rejectionReason.trim().length < 20)
              }
              className={confirmAction === 'reject' || confirmAction === 'cancel' ? 'bg-red-600 hover:bg-red-700' : ''}
            >
              {isUpdating ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                confirmAction === 'accept' ? 'Accept & Submit Review'
                : confirmAction === 'reject' ? 'Reject Design'
                : 'Confirm'
              )}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <Card>
        <CardContent className="p-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Paintbrush className="h-4 w-4 text-gray-500" />
              <h3 className="font-semibold text-sm">Design Request</h3>
            </div>
            <Badge className={status.color}>{status.label}</Badge>
          </div>

          {/* Priority */}
          <div className="flex items-center justify-between text-sm">
            <span className="text-gray-500">Priority</span>
            <Badge variant="outline" className={priority.color}>
              {priority.label}
            </Badge>
          </div>

          {/* Assigned Designer */}
          {designerName && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-gray-500">Designer</span>
              <div className="flex items-center gap-1.5">
                <User className="h-3.5 w-3.5 text-gray-400" />
                <span className="font-medium">{designerName}</span>
              </div>
            </div>
          )}

          {/* Key Dates */}
          <div className="space-y-1.5 text-sm">
            <div className="flex items-center justify-between">
              <span className="text-gray-500 flex items-center gap-1.5">
                <Clock className="h-3.5 w-3.5" />
                Requested
              </span>
              <span>{formatDate(designRequest.created_at)}</span>
            </div>
            {designRequest.accepted_at && (
              <div className="flex items-center justify-between">
                <span className="text-gray-500 flex items-center gap-1.5">
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  Accepted
                </span>
                <span>{formatDate(designRequest.accepted_at)}</span>
              </div>
            )}
            {designRequest.accepted_at && designRequest.status !== 'completed' && designRequest.status !== 'canceled' && (
              <div className="mt-2 p-3 rounded-lg bg-blue-50 border border-blue-100">
                <div className="flex items-center gap-1.5 mb-1">
                  <Clock className="h-3.5 w-3.5 text-blue-600" />
                  <span className="text-xs font-semibold text-blue-700">Expected Delivery</span>
                </div>
                {designRequest.estimated_completion_at ? (
                  <p className="text-sm font-bold text-blue-800">
                    {formatDate(designRequest.estimated_completion_at)}
                  </p>
                ) : (
                  <p className="text-xs text-blue-500 italic">
                    Designer has not set an estimate yet
                  </p>
                )}
              </div>
            )}
            {designRequest.delivered_at && (
              <div className="flex items-center justify-between">
                <span className="text-gray-500 flex items-center gap-1.5">
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  Delivered
                </span>
                <span>{formatDate(designRequest.delivered_at)}</span>
              </div>
            )}
          </div>

          {/* Design Brief (notes) */}
          {designRequest.notes && (
            <div className="pt-2 border-t">
              <p className="text-xs text-gray-500 mb-1">Design Brief</p>
              <p className="text-sm text-gray-700 line-clamp-3">{designRequest.notes}</p>
            </div>
          )}

          {/* Action Buttons */}
          <div className="pt-2 border-t space-y-2">
            {designRequest.status === 'delivered' && (
              <>
                <Button
                  size="sm"
                  className="w-full gap-2 bg-green-600 hover:bg-green-700"
                  onClick={() => handleAction('accept')}
                  disabled={isUpdating}
                >
                  <CheckCircle2 className="h-4 w-4" />
                  Accept Design
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  className="w-full gap-2 text-red-600 hover:text-red-700 hover:bg-red-50"
                  onClick={() => handleAction('reject')}
                  disabled={isUpdating}
                >
                  <XCircle className="h-4 w-4" />
                  Reject Design
                </Button>
              </>
            )}
            {designRequest.status === 'revision_requested' && designRequest.rejection_reason && (
              <div className="p-3 rounded-lg bg-red-50 border border-red-100">
                <p className="text-xs font-semibold text-red-700 mb-1">Rejection Reason</p>
                <p className="text-sm text-red-600">{designRequest.rejection_reason}</p>
              </div>
            )}
            {designRequest.status === 'approved' && (
              <Button
                size="sm"
                className="w-full gap-2"
                onClick={() => handleAction('complete')}
                disabled={isUpdating}
              >
                <CheckCircle2 className="h-4 w-4" />
                Mark Complete
              </Button>
            )}
            {designRequest.status === 'pending' && (
              <Button
                size="sm"
                variant="outline"
                className="w-full gap-2"
                onClick={() => handleAction('cancel')}
                disabled={isUpdating}
              >
                <XCircle className="h-4 w-4" />
                Cancel Request
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    </>
  )
}
