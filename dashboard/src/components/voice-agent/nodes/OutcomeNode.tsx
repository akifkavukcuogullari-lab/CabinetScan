'use client'

import { memo } from 'react'
import { Handle, Position, type NodeProps } from 'reactflow'
import { CheckCircle, XCircle, PhoneOff, HelpCircle } from 'lucide-react'

const outcomeIcons: Record<string, React.ElementType> = {
  appointment_booked: CheckCircle,
  not_interested: XCircle,
  no_answer: PhoneOff,
  voicemail: PhoneOff,
  callback_requested: HelpCircle,
}

interface OutcomeNodeData {
  outcome: string
  label: string
}

function OutcomeNodeComponent({ data }: NodeProps<OutcomeNodeData>) {
  const Icon = outcomeIcons[data.outcome] || HelpCircle

  return (
    <div className="min-w-[180px] rounded-lg border-2 border-blue-300 bg-blue-50 px-4 py-3 shadow-sm">
      <div className="flex items-center gap-2">
        <Icon className="size-4 shrink-0 text-blue-600" />
        <span className="text-sm font-semibold text-blue-900">
          {data.label}
        </span>
      </div>
      <Handle
        type="source"
        position={Position.Right}
        className="!h-3 !w-3 !border-2 !border-blue-400 !bg-blue-200"
      />
    </div>
  )
}

export const OutcomeNode = memo(OutcomeNodeComponent)
