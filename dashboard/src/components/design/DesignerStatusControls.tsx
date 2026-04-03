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
  Play,
  CheckCircle2,
  Clock,
  Loader2,
  RotateCcw,
  Truck,
  XCircle,
} from 'lucide-react'
import { sendDesignNotification } from '@/lib/design-notifications'

interface DesignerStatusControlsProps {
  designRequestId: string
  currentStatus: string
  hasUploadedFiles: boolean
  estimatedCompletionAt?: string | null
  designerId?: string
  rejectionReason?: string | null
}

const statusConfig: Record<string, { label: string; color: string }> = {
  pending: { label: 'Pending', color: 'bg-orange-100 text-orange-800' },
  accepted: { label: 'Accepted', color: 'bg-blue-100 text-blue-800' },
  in_progress: { label: 'In Progress', color: 'bg-indigo-100 text-indigo-800' },
  delivered: { label: 'Delivered', color: 'bg-purple-100 text-purple-800' },
  approved: { label: 'Approved', color: 'bg-green-100 text-green-800' },
  revision_requested: { label: 'Revision Requested', color: 'bg-yellow-100 text-yellow-800' },
  completed: { label: 'Completed', color: 'bg-green-100 text-green-800' },
  canceled: { label: 'Canceled', color: 'bg-gray-100 text-gray-800' },
}

export function DesignerStatusControls({
  designRequestId,
  currentStatus,
  hasUploadedFiles: initialHasFiles,
  estimatedCompletionAt,
  designerId,
  rejectionReason,
}: DesignerStatusControlsProps) {
  const router = useRouter()
  const [isUpdating, setIsUpdating] = useState(false)
  const [confirmAction, setConfirmAction] = useState<string | null>(null)
  const [hasFiles] = useState(initialHasFiles)
  const [estimatedDate, setEstimatedDate] = useState(
    estimatedCompletionAt ? estimatedCompletionAt.slice(0, 16) : ''
  )
  const [savingEstimate, setSavingEstimate] = useState(false)
  const [dropReason, setDropReason] = useState('')

  const status = statusConfig[currentStatus] || statusConfig.pending

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
        .eq('id', designRequestId)

      if (error) {
        toast.error('Failed to update status.')
        console.error('Status update error:', error)
        return
      }

      toast.success(`Status updated to ${newStatus.replace(/_/g, ' ')}.`)

      // Fire-and-forget notification
      if (designerId) {
        const eventMap: Record<string, string> = {
          delivered: 'design_delivered',
          in_progress: 'design_started',
        }
        // For 'pending' with null designer_id, it's a drop
        const eventType = newStatus === 'pending' ? 'design_dropped' : eventMap[newStatus]
        if (eventType) {
          sendDesignNotification({
            eventType,
            designRequestId,
            senderType: 'designer',
            senderId: designerId,
          })
        }
      }

      if (newStatus === 'pending') {
        router.push('/designer/pool')
      } else {
        router.refresh()
      }
    } catch (err) {
      console.error('Error updating status:', err)
      toast.error('An unexpected error occurred.')
    } finally {
      setIsUpdating(false)
      setConfirmAction(null)
    }
  }

  const saveEstimate = async () => {
    if (!estimatedDate) return
    setSavingEstimate(true)
    try {
      const supabase = createClient()
      const { error } = await supabase
        .from('design_requests')
        .update({ estimated_completion_at: new Date(estimatedDate).toISOString() })
        .eq('id', designRequestId)
      if (error) {
        toast.error('Failed to save estimated completion time.')
      } else {
        toast.success('Estimated completion time saved.')
        if (designerId) {
          sendDesignNotification({
            eventType: 'estimate_set',
            designRequestId,
            senderType: 'designer',
            senderId: designerId,
          })
        }
        router.refresh()
      }
    } catch {
      toast.error('An unexpected error occurred.')
    } finally {
      setSavingEstimate(false)
    }
  }

  const executeAction = () => {
    if (!confirmAction) return
    switch (confirmAction) {
      case 'start_working':
        updateStatus('in_progress')
        break
      case 'deliver':
        updateStatus('delivered', { delivered_at: new Date().toISOString() })
        break
      case 'resume':
        updateStatus('in_progress')
        break
      case 'drop':
        if (!dropReason.trim() || dropReason.trim().length < 20) {
          toast.error('Please provide a detailed explanation (at least 20 characters).')
          return
        }
        updateStatus('pending', { designer_id: null, accepted_at: null, drop_reason: dropReason.trim() })
        break
    }
  }

  const confirmMessages: Record<string, { title: string; description: string }> = {
    start_working: {
      title: 'Start Working?',
      description: 'This will set the status to "In Progress" and notify the showroom that you have started working on the design.',
    },
    deliver: {
      title: 'Mark as Delivered?',
      description: 'This will notify the showroom that the design files are ready for review. Make sure you have uploaded all necessary files.',
    },
    resume: {
      title: 'Resume Work?',
      description: 'This will set the status back to "In Progress" so you can upload revised design files.',
    },
    drop: {
      title: 'Drop This Project?',
      description: 'This will release the project back to the design pool so another designer can pick it up. You will lose access to this project.',
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
          {confirmAction === 'drop' && (
            <div className="space-y-2">
              <label className="text-sm font-medium">Reason for dropping (required)</label>
              <textarea
                value={dropReason}
                onChange={(e) => setDropReason(e.target.value)}
                placeholder="Please provide a detailed explanation for why you are dropping this project..."
                className="w-full rounded-md border px-3 py-2 text-sm bg-background min-h-[100px] resize-none"
                minLength={20}
              />
              <p className="text-xs text-muted-foreground">
                {dropReason.trim().length}/20 characters minimum
              </p>
            </div>
          )}
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isUpdating} onClick={() => setDropReason('')}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={executeAction}
              disabled={isUpdating || (confirmAction === 'drop' && dropReason.trim().length < 20)}
              className={confirmAction === 'drop' ? 'bg-red-600 hover:bg-red-700' : ''}
            >
              {isUpdating ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                confirmAction === 'drop' ? 'Drop Project' : 'Confirm'
              )}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <Card>
        <CardContent className="p-4 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-sm">Status</h3>
            <Badge className={status.color}>{status.label}</Badge>
          </div>

          <div className="space-y-2">
            {currentStatus === 'accepted' && (
              <Button
                size="sm"
                className="w-full gap-2"
                onClick={() => setConfirmAction('start_working')}
                disabled={isUpdating}
              >
                <Play className="h-4 w-4" />
                Start Working
              </Button>
            )}

            {currentStatus === 'in_progress' && (
              <div className="space-y-2">
                <Button
                  size="sm"
                  className="w-full gap-2"
                  onClick={() => setConfirmAction('deliver')}
                  disabled={isUpdating || !hasFiles}
                >
                  <Truck className="h-4 w-4" />
                  Mark as Delivered
                </Button>
                {!hasFiles && (
                  <p className="text-xs text-amber-600 text-center">
                    Upload at least one design file before delivering.
                  </p>
                )}
              </div>
            )}

            {currentStatus === 'revision_requested' && rejectionReason && (
              <div className="p-3 rounded-lg bg-red-50 border border-red-100 dark:bg-red-900/20 dark:border-red-800">
                <p className="text-xs font-semibold text-red-700 dark:text-red-400 mb-1">Rejection Reason</p>
                <p className="text-sm text-red-600 dark:text-red-300">{rejectionReason}</p>
              </div>
            )}
            {currentStatus === 'revision_requested' && (
              <Button
                size="sm"
                className="w-full gap-2"
                onClick={() => setConfirmAction('resume')}
                disabled={isUpdating}
              >
                <RotateCcw className="h-4 w-4" />
                Resume Work
              </Button>
            )}

            {(currentStatus === 'accepted' || currentStatus === 'in_progress' || currentStatus === 'revision_requested') && (
              <div className="space-y-2 pt-2 border-t">
                <label className="text-xs font-medium text-muted-foreground">Estimated Completion</label>
                <div className="flex gap-2">
                  <input
                    type="datetime-local"
                    value={estimatedDate}
                    onChange={(e) => setEstimatedDate(e.target.value)}
                    className="flex-1 rounded-md border px-3 py-1.5 text-sm bg-background"
                  />
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={saveEstimate}
                    disabled={savingEstimate || !estimatedDate}
                  >
                    {savingEstimate ? <Loader2 className="h-3 w-3 animate-spin" /> : 'Save'}
                  </Button>
                </div>
              </div>
            )}

            {(currentStatus === 'accepted' || currentStatus === 'in_progress') && (
              <Button
                size="sm"
                variant="outline"
                className="w-full gap-2 text-red-600 hover:text-red-700 hover:bg-red-50"
                onClick={() => setConfirmAction('drop')}
                disabled={isUpdating}
              >
                <XCircle className="h-4 w-4" />
                Drop Project
              </Button>
            )}

            {currentStatus === 'delivered' && (
              <div className="flex items-center gap-2 justify-center py-2 text-sm text-gray-500">
                <Clock className="h-4 w-4" />
                <span>Waiting for review</span>
              </div>
            )}

            {(currentStatus === 'approved' || currentStatus === 'completed') && (
              <div className="flex items-center gap-2 justify-center py-2 text-sm text-green-600">
                <CheckCircle2 className="h-4 w-4" />
                <span>Completed</span>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </>
  )
}
