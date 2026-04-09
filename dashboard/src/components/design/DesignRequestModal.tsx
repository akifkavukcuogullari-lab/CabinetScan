'use client'

import { useState, useEffect } from 'react'
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
import { AlertTriangle, Loader2 } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'

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
  const [priorityPricing, setPriorityPricing] = useState<Record<string, number>>({})
  const [balanceCents, setBalanceCents] = useState<number | null>(null)

  const PRIORITY_OPTIONS = [
    { value: 'low', label: 'Low', desc: '2-3 business days' },
    { value: 'normal', label: 'Normal', desc: '1 business day' },
    { value: 'high', label: 'High', desc: '3 hours' },
    { value: 'urgent', label: 'Urgent', desc: '1 hour' },
  ]

  useEffect(() => {
    if (!open) return
    const supabase = createClient()

    async function fetchCreditInfo() {
      const [{ data: configs }, { data: balance }] = await Promise.all([
        supabase
          .from('credit_service_config')
          .select('service_type, cost_per_unit_cents, multiplier, minimum_charge_cents')
          .like('service_type', 'design_%'),
        supabase
          .from('showroom_credit_balances')
          .select('balance_cents')
          .eq('showroom_id', showroomId)
          .single(),
      ])

      if (configs) {
        const pricing: Record<string, number> = {}
        for (const c of configs) {
          const p = c.service_type.replace('design_', '')
          pricing[p] = Math.max(
            Math.ceil(c.cost_per_unit_cents * c.multiplier),
            c.minimum_charge_cents
          )
        }
        setPriorityPricing(pricing)
      }
      setBalanceCents(balance?.balance_cents ?? 0)
    }

    fetchCreditInfo()
  }, [open, showroomId])

  const designCostCents = priorityPricing[priority] ?? null
  const insufficientBalance = designCostCents !== null && balanceCents !== null && balanceCents < designCostCents

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
            <Label>Priority</Label>
            <div className="grid grid-cols-2 gap-2">
              {PRIORITY_OPTIONS.map((opt) => {
                const price = priorityPricing[opt.value]
                const isSelected = priority === opt.value
                return (
                  <button
                    key={opt.value}
                    type="button"
                    onClick={() => setPriority(opt.value)}
                    disabled={isSubmitting}
                    className={`p-3 rounded-lg border-2 text-left transition-colors ${
                      isSelected
                        ? 'border-blue-500 bg-blue-50'
                        : 'border-gray-200 hover:border-gray-300'
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <p className="font-medium text-sm">{opt.label}</p>
                      {price != null && (
                        <span className={`text-sm font-semibold ${isSelected ? 'text-blue-600' : 'text-gray-900'}`}>
                          ${(price / 100).toFixed(0)}
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-gray-500 mt-0.5">{opt.desc}</p>
                  </button>
                )
              })}
            </div>
          </div>
        </div>

        {/* Credit cost info */}
        {designCostCents !== null && (
          <div className="text-sm text-gray-500 border-t pt-3">
            This will use <span className="font-medium text-gray-900">${(designCostCents / 100).toFixed(2)}</span> from your credits
            {balanceCents !== null && (
              <span> (balance: ${(balanceCents / 100).toFixed(2)})</span>
            )}
          </div>
        )}

        {insufficientBalance && (
          <Alert variant="destructive" className="border-amber-200 bg-amber-50">
            <AlertTriangle className="h-4 w-4 text-amber-600" />
            <AlertDescription className="text-amber-700">
              Insufficient credits.{' '}
              <a href="/showroom/billing" className="underline font-medium">Top up your balance</a> to request a design.
            </AlertDescription>
          </Alert>
        )}

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={isSubmitting}
          >
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={isSubmitting || insufficientBalance}>
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
