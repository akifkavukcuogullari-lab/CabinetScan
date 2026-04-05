'use client'

import { memo } from 'react'
import { Handle, Position, type NodeProps } from 'reactflow'
import { MessageSquare } from 'lucide-react'

interface SmsNodeData {
  template: string
}

function SmsNodeComponent({ data }: NodeProps<SmsNodeData>) {
  const preview =
    data.template.length > 60
      ? data.template.slice(0, 60) + '...'
      : data.template

  return (
    <div className="min-w-[180px] max-w-[220px] rounded-lg border-2 border-green-300 bg-green-50 px-4 py-3 shadow-sm">
      <Handle
        type="target"
        position={Position.Left}
        className="!h-3 !w-3 !border-2 !border-green-400 !bg-green-200"
      />
      <div className="flex items-center gap-2">
        <MessageSquare className="size-4 shrink-0 text-green-600" />
        <span className="text-sm font-semibold text-green-900">SMS</span>
      </div>
      <p className="mt-1 text-xs leading-relaxed text-green-700">{preview}</p>
      <Handle
        type="source"
        position={Position.Right}
        className="!h-3 !w-3 !border-2 !border-green-400 !bg-green-200"
      />
    </div>
  )
}

export const SmsNode = memo(SmsNodeComponent)
