'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { toast } from 'sonner'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Loader2 } from 'lucide-react'

interface DesignRequestModalProps {
  projectId: string
  showroomId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function DesignRequestModal({
  projectId,
  showroomId,
  open,
  onOpenChange,
}: DesignRequestModalProps) {
  const router = useRouter()
  const [notes, setNotes] = useState('')
  const [priority, setPriority] = useState('normal')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleSubmit = async () => {
    setIsSubmitting(true)
    try {
      const supabase = createClient()

      // Get current user
      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) {
        toast.error('You must be logged in to submit a design request.')
        return
      }

      // Get the showroom_user id for created_by
      const { data: showroomUser, error: suError } = await supabase
        .from('showroom_users')
        .select('id')
        .eq('user_id', user.id)
        .eq('showroom_id', showroomId)
        .single()

      if (suError || !showroomUser) {
        toast.error('Could not find your showroom user record.')
        return
      }

      // Insert design request
      const { error: insertError } = await supabase
        .from('design_requests')
        .insert({
          project_id: projectId,
          showroom_id: showroomId,
          notes: notes.trim() || null,
          priority,
          created_by: showroomUser.id,
          status: 'pending',
        })

      if (insertError) {
        if (insertError.code === '23505') {
          toast.error('A design request already exists for this project.')
        } else {
          toast.error('Failed to submit design request. Please try again.')
          console.error('Design request insert error:', insertError)
        }
        return
      }

      toast.success('Design request submitted successfully!')
      setNotes('')
      setPriority('normal')
      onOpenChange(false)
      router.refresh()
    } catch (err) {
      console.error('Error submitting design request:', err)
      toast.error('An unexpected error occurred.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[480px]">
        <DialogHeader>
          <DialogTitle>Request Design</DialogTitle>
          <DialogDescription>
            Submit a design request for this project. A designer will be assigned
            to create professional kitchen designs based on the scan data.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="design-brief">Design Brief</Label>
            <Textarea
              id="design-brief"
              placeholder="Describe the design style, preferences, material choices, or any special requirements..."
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={4}
              disabled={isSubmitting}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="priority">Priority</Label>
            <Select value={priority} onValueChange={setPriority} disabled={isSubmitting}>
              <SelectTrigger id="priority">
                <SelectValue placeholder="Select priority" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="low">Low</SelectItem>
                <SelectItem value="normal">Normal</SelectItem>
                <SelectItem value="high">High</SelectItem>
                <SelectItem value="urgent">Urgent</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={isSubmitting}
          >
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={isSubmitting}>
            {isSubmitting ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Submitting...
              </>
            ) : (
              'Submit Request'
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
