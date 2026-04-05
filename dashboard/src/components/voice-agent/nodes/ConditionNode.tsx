'use client'

import { memo } from 'react'
import { Handle, Position, type NodeProps } from 'reactflow'
import { GitBranch } from 'lucide-react'

interface ConditionNodeData {
  condition: string
}

function ConditionNodeComponent({ data }: NodeProps<ConditionNodeData>) {
  return (
    <div className="relative min-w-[180px] rounded-lg border-2 border-yellow-300 bg-yellow-50 px-4 py-3 shadow-sm">
      <Handle
        type="target"
        position={Position.Left}
        className="!h-3 !w-3 !border-2 !border-yellow-400 !bg-yellow-200"
      />
      <div className="flex items-center gap-2">
        <GitBranch className="size-4 shrink-0 text-yellow-600" />
        <span className="text-sm font-semibold text-yellow-900">Condition</span>
      </div>
      <p className="mt-1 text-xs text-yellow-700 font-mono">{data.condition}</p>
      {/* True output */}
      <Handle
        type="source"
        position={Position.Bottom}
        id="true"
        className="!h-3 !w-3 !border-2 !border-green-400 !bg-green-200"
      />
      <span className="absolute -bottom-1 left-1/2 translate-y-full -translate-x-1/2 text-[10px] font-medium text-green-600 pt-1">
        True
      </span>
      {/* False output */}
      <Handle
        type="source"
        position={Position.Right}
        id="false"
        className="!h-3 !w-3 !border-2 !border-red-400 !bg-red-200"
      />
      <span className="absolute -right-1 top-1/2 translate-x-full -translate-y-1/2 text-[10px] font-medium text-red-600 pl-2">
        False
      </span>
    </div>
  )
}

export const ConditionNode = memo(ConditionNodeComponent)
