'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Loader2, Phone } from 'lucide-react'
import { toast } from 'sonner'

interface TriggerCallButtonProps {
  projectId: string
  showroomId: string
  customerPhone: string
  disabled?: boolean
}

export function TriggerCallButton({
  projectId,
  showroomId,
  customerPhone,
  disabled,
}: TriggerCallButtonProps) {
  const [loading, setLoading] = useState(false)

  const isPhoneValid = customerPhone && customerPhone.trim().length > 0

  const handleTrigger = async () => {
    if (!isPhoneValid) {
      toast.error('No customer phone number available')
      return
    }

    setLoading(true)
    try {
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
      const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

      if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error('Supabase configuration missing')
      }

      const response = await fetch(
        `${supabaseUrl}/functions/v1/voice-agent-trigger`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${supabaseAnonKey}`,
          },
          body: JSON.stringify({
            project_id: projectId,
            showroom_id: showroomId,
            triggered_by: 'manual',
          }),
        }
      )

      if (!response.ok) {
        let errorMessage = 'Failed to trigger call'
        try {
          const errorData = await response.json()
          errorMessage = errorData.error || errorMessage
        } catch {
          // ignore parse error
        }
        throw new Error(errorMessage)
      }

      toast.success('Voice agent call triggered successfully')
    } catch (error) {
      console.error('Error triggering voice agent call:', error)
      toast.error(
        error instanceof Error ? error.message : 'Failed to trigger call'
      )
    } finally {
      setLoading(false)
    }
  }

  return (
    <Button
      variant="outline"
      onClick={handleTrigger}
      disabled={disabled || loading || !isPhoneValid}
      className="w-full justify-start gap-2"
    >
      {loading ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : (
        <Phone className="h-4 w-4" />
      )}
      {loading ? 'Calling...' : 'Call Customer'}
    </Button>
  )
}
