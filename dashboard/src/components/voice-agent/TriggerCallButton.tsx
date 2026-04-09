'use client'

import { useState, useEffect, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Loader2, Phone, StopCircle, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'

interface TriggerCallButtonProps {
  projectId: string
  showroomId: string
  customerPhone: string
  disabled?: boolean
}

const FLOW_STATUS_CONFIG: Record<string, { label: string; color: string }> = {
  active: { label: 'Active', color: 'bg-blue-100 text-blue-800' },
  waiting: { label: 'Waiting', color: 'bg-yellow-100 text-yellow-800' },
  completed: { label: 'Completed', color: 'bg-green-100 text-green-800' },
  stopped: { label: 'Stopped', color: 'bg-gray-100 text-gray-800' },
}

interface ActiveFlow {
  id: string
  flow_status: string
  call_status: string
  outcome: string | null
}

export function TriggerCallButton({
  projectId,
  showroomId,
  customerPhone,
  disabled,
}: TriggerCallButtonProps) {
  const [loading, setLoading] = useState(false)
  const [stopping, setStopping] = useState(false)
  const [activeFlow, setActiveFlow] = useState<ActiveFlow | null>(null)
  const [checkingStatus, setCheckingStatus] = useState(true)

  const supabase = createClient()
  const isPhoneValid = customerPhone && customerPhone.trim().length > 0

  const fetchFlowStatus = useCallback(async () => {
    try {
      const { data } = await supabase
        .from('voice_agent_logs')
        .select('id, flow_status, call_status, outcome')
        .eq('project_id', projectId)
        .not('flow_status', 'in', '("completed","stopped")')
        .order('created_at', { ascending: false })
        .limit(1)

      setActiveFlow(data && data.length > 0 ? data[0] : null)
    } catch {
      // ignore
    } finally {
      setCheckingStatus(false)
    }
  }, [projectId, supabase])

  useEffect(() => {
    fetchFlowStatus()
    const interval = setInterval(fetchFlowStatus, 5000)
    return () => clearInterval(interval)
  }, [fetchFlowStatus])

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
          errorMessage = errorData.error || errorData.message || errorMessage
        } catch {
          // ignore
        }
        throw new Error(errorMessage)
      }

      toast.success('Voice agent call triggered')
      await fetchFlowStatus()
    } catch (error) {
      console.error('Error triggering voice agent call:', error)
      toast.error(
        error instanceof Error ? error.message : 'Failed to trigger call'
      )
    } finally {
      setLoading(false)
    }
  }

  const handleStop = async () => {
    if (!activeFlow) return

    setStopping(true)
    try {
      const { error } = await supabase
        .from('voice_agent_logs')
        .update({ flow_status: 'stopped' })
        .eq('id', activeFlow.id)

      if (error) throw error

      toast.success('Voice agent flow stopped')
      setActiveFlow(null)
    } catch (error) {
      console.error('Error stopping flow:', error)
      toast.error('Failed to stop flow')
    } finally {
      setStopping(false)
    }
  }

  if (checkingStatus) {
    return (
      <Button variant="outline" disabled className="w-full justify-start gap-2">
        <Loader2 className="h-4 w-4 animate-spin" />
        Checking status...
      </Button>
    )
  }

  // Active flow — show status + stop/restart + view flow link
  if (activeFlow) {
    const flowStatus = FLOW_STATUS_CONFIG[activeFlow.flow_status] || FLOW_STATUS_CONFIG.active

    return (
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Phone className="h-3.5 w-3.5 text-blue-500" />
            <span className="text-sm font-medium">Flow</span>
          </div>
          <Badge className={`text-[10px] uppercase ${flowStatus.color}`}>{flowStatus.label}</Badge>
        </div>

        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleStop}
            disabled={stopping}
            className="flex-1 gap-1.5"
          >
            {stopping ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              <StopCircle className="h-3.5 w-3.5" />
            )}
            Stop
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={async () => {
              await handleStop()
              // Wait for DB to propagate the stop before re-triggering
              await new Promise(r => setTimeout(r, 1500))
              await handleTrigger()
            }}
            disabled={stopping || loading}
            className="flex-1 gap-1.5"
          >
            <RotateCcw className="h-3.5 w-3.5" />
            Restart
          </Button>
        </div>

      </div>
    )
  }

  // No active flow — show trigger button
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
