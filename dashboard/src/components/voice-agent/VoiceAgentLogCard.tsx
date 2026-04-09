'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Badge } from '@/components/ui/badge'
import { DollarSign, Loader2, MessageSquare, Phone, Clock, MapPin } from 'lucide-react'
import type { VoiceAgentLog, SimplifiedOutcome } from '@/types/voice-agent'
import { OUTCOME_COLORS, OUTCOME_LABELS } from '@/types/voice-agent'

interface VoiceAgentLogCardProps {
  projectId: string
  showroomId: string
}

function formatDuration(seconds: number | null): string {
  if (seconds === null || seconds === undefined) return '--'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}m ${s}s`
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '--'
  return new Date(dateStr).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

const CALL_STATUS_COLORS: Record<string, string> = {
  completed: 'bg-green-100 text-green-800',
  'in-progress': 'bg-blue-100 text-blue-800',
  ringing: 'bg-yellow-100 text-yellow-800',
  failed: 'bg-red-100 text-red-800',
  pending: 'bg-gray-100 text-gray-800',
}

const FLOW_STATUS_COLORS: Record<string, string> = {
  active: 'bg-blue-100 text-blue-800',
  waiting: 'bg-yellow-100 text-yellow-800',
  completed: 'bg-green-100 text-green-800',
  stopped: 'bg-gray-100 text-gray-800',
}

export function VoiceAgentLogCard({ projectId, showroomId }: VoiceAgentLogCardProps) {
  const supabase = createClient()
  const [latestLog, setLatestLog] = useState<VoiceAgentLog | null>(null)
  const [costCents, setCostCents] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function loadLatest() {
      setLoading(true)
      try {
        const { data, error } = await supabase
          .from('voice_agent_logs')
          .select('*')
          .eq('project_id', projectId)
          .eq('showroom_id', showroomId)
          .order('created_at', { ascending: false })
          .limit(1)

        if (error) throw error
        const log = data && data.length > 0 ? data[0] : null
        setLatestLog(log)

        // Fetch credit cost for this log
        if (log) {
          const { data: txn } = await supabase
            .from('showroom_credit_transactions')
            .select('billed_cost_cents')
            .eq('reference_id', log.id)
            .eq('reference_type', 'voice_agent_log')
            .single()

          if (txn) setCostCents(txn.billed_cost_cents)
        }
      } catch (error) {
        console.error('Error loading voice agent log:', error)
      } finally {
        setLoading(false)
      }
    }

    loadLatest()
  }, [supabase, projectId, showroomId])

  if (loading) {
    return (
      <div className="flex items-center justify-center py-4">
        <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
      </div>
    )
  }

  if (!latestLog) {
    return (
      <p className="text-sm text-gray-400">No voice agent activity for this project.</p>
    )
  }

  const log = latestLog

  return (
    <div className="space-y-2.5">
      {/* Outcome */}
      {log.outcome && (
        <div className="flex items-center gap-2 flex-wrap">
          <Badge className={`text-[10px] ${OUTCOME_COLORS[log.outcome as SimplifiedOutcome] || 'bg-gray-100 text-gray-800'}`}>
            {OUTCOME_LABELS[log.outcome as SimplifiedOutcome] || log.outcome}
          </Badge>
        </div>
      )}

      {/* SMS */}
      <div className="flex items-center gap-2 text-xs text-gray-600">
        <MessageSquare className="h-3.5 w-3.5 text-gray-400" />
        <span className="capitalize">{log.sms_status}</span>
        {log.sms_sent_at && <span className="text-gray-400">{formatDate(log.sms_sent_at)}</span>}
      </div>

      {/* Call */}
      <div className="flex items-center gap-2 text-xs text-gray-600">
        <Phone className="h-3.5 w-3.5 text-gray-400" />
        <Badge className={`text-[10px] ${CALL_STATUS_COLORS[log.call_status] || 'bg-gray-100 text-gray-800'}`}>
          {log.call_status}
        </Badge>
        {log.call_scheduled_at && (log.call_status === 'scheduled' || log.flow_status === 'active') && (
          <span className="text-gray-400">{formatDate(log.call_scheduled_at)}</span>
        )}
        {log.call_duration_seconds !== null && (
          <span className="flex items-center gap-1 text-gray-400">
            <Clock className="h-3 w-3" />
            {formatDuration(log.call_duration_seconds)}
          </span>
        )}
      </div>

      {/* Distance */}
      {log.distance_miles !== null && (
        <div className="flex items-center gap-2 text-xs text-gray-500">
          <MapPin className="h-3.5 w-3.5 text-gray-400" />
          <span>{log.distance_miles.toFixed(1)} mi</span>
          {log.distance_zone && <span className="capitalize">({log.distance_zone})</span>}
        </div>
      )}

      {/* Cost */}
      {costCents != null && (
        <div className="flex items-center gap-2 text-xs text-gray-500">
          <DollarSign className="h-3.5 w-3.5 text-gray-400" />
          <span>Cost: ${(costCents / 100).toFixed(2)}</span>
        </div>
      )}

      {/* Summary */}
      {log.call_summary && (
        <p className="text-xs text-gray-500 italic leading-relaxed">{log.call_summary}</p>
      )}
    </div>
  )
}
