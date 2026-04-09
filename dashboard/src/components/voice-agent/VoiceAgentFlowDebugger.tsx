'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import ReactFlow, {
  Controls,
  Background,
  BackgroundVariant,
  type Edge,
  type Node,
  ReactFlowProvider,
} from 'reactflow'
import 'reactflow/dist/style.css'

import { OutcomeNode } from './nodes/OutcomeNode'
import { WaitNode } from './nodes/WaitNode'
import { SmsNode } from './nodes/SmsNode'
import { RetryCallNode } from './nodes/RetryCallNode'
import { SendLinkNode } from './nodes/SendLinkNode'
import { ConditionNode } from './nodes/ConditionNode'
import { StopNode } from './nodes/StopNode'
import { NodeDetailPanel } from './NodeDetailPanel'

import { createClient } from '@/lib/supabase/client'
import type {
  VoiceAgentLog,
  PostCallFlow,
  SimplifiedOutcome,
} from '@/types/voice-agent'
import {
  CheckCircle2,
  XCircle,
  Clock,
  Circle,
  AlertTriangle,
} from 'lucide-react'

// ---------------------------------------------------------------------------
// Execution status types
// ---------------------------------------------------------------------------

export type ExecutionStatus = 'success' | 'failed' | 'waiting' | 'pending'

interface ExecutionData {
  status: ExecutionStatus
  log?: VoiceAgentLog
  attemptNumber?: number
}

// ---------------------------------------------------------------------------
// Default post-call flow (matches FlowBuilder default if none configured)
// ---------------------------------------------------------------------------

const DEFAULT_POST_CALL_FLOW: PostCallFlow = {
  nodes: [
    {
      id: 'outcome_no_answer',
      type: 'outcome',
      data: { outcome: 'no_answer', label: 'No Answer' },
      position: { x: 0, y: 0 },
    },
    {
      id: 'outcome_voicemail',
      type: 'outcome',
      data: { outcome: 'voicemail', label: 'Voicemail' },
      position: { x: 0, y: 150 },
    },
    {
      id: 'outcome_interested',
      type: 'outcome',
      data: { outcome: 'interested', label: 'Interested' },
      position: { x: 0, y: 300 },
    },
    {
      id: 'outcome_not_interested',
      type: 'outcome',
      data: { outcome: 'not_interested', label: 'Not Interested' },
      position: { x: 0, y: 450 },
    },
    {
      id: 'stop_1',
      type: 'stop',
      data: {},
      position: { x: 400, y: 450 },
    },
  ],
  edges: [
    {
      id: 'e_not_interested_stop',
      source: 'outcome_not_interested',
      target: 'stop_1',
    },
  ],
}

// ---------------------------------------------------------------------------
// Status icon overlay component
// ---------------------------------------------------------------------------

function StatusIcon({ status }: { status: ExecutionStatus }) {
  switch (status) {
    case 'success':
      return (
        <div className="absolute -top-2 -right-2 z-10 rounded-full bg-white p-0.5 shadow">
          <CheckCircle2 className="size-4 text-green-600" />
        </div>
      )
    case 'failed':
      return (
        <div className="absolute -top-2 -right-2 z-10 rounded-full bg-white p-0.5 shadow">
          <XCircle className="size-4 text-red-600" />
        </div>
      )
    case 'waiting':
      return (
        <div className="absolute -top-2 -right-2 z-10 rounded-full bg-white p-0.5 shadow">
          <Clock className="size-4 text-amber-600" />
        </div>
      )
    case 'pending':
      return null
    default:
      return null
  }
}

// ---------------------------------------------------------------------------
// Debug wrapper HOC — wraps any node component with execution status ring
// ---------------------------------------------------------------------------

function withDebugWrapper(
  WrappedComponent: React.ComponentType<any>,
  nodeType: string
) {
  const DebugNode = (props: any) => {
    const executionStatus: ExecutionStatus | undefined =
      props.data?.executionStatus
    const statusClass = getStatusClasses(executionStatus)

    return (
      <div className={`relative rounded-lg ${statusClass}`}>
        {executionStatus && executionStatus !== 'pending' && (
          <StatusIcon status={executionStatus} />
        )}
        <WrappedComponent {...props} />
      </div>
    )
  }

  DebugNode.displayName = `Debug${nodeType}`
  return DebugNode
}

function getStatusClasses(status?: ExecutionStatus): string {
  switch (status) {
    case 'success':
      return 'ring-2 ring-green-500 ring-offset-1 bg-green-50/50'
    case 'failed':
      return 'ring-2 ring-red-500 ring-offset-1 bg-red-50/50'
    case 'waiting':
      return 'ring-2 ring-amber-500 ring-offset-1 bg-amber-50/50 animate-pulse'
    case 'pending':
      return 'opacity-40'
    default:
      return ''
  }
}

// ---------------------------------------------------------------------------
// Execution status computation
// ---------------------------------------------------------------------------

function computeExecutionStatuses(
  flowNodes: Node[],
  flowEdges: Edge[],
  logs: VoiceAgentLog[]
): Map<string, ExecutionData> {
  const statusMap = new Map<string, ExecutionData>()

  if (logs.length === 0) {
    // Mark all nodes as pending
    for (const node of flowNodes) {
      statusMap.set(node.id, { status: 'pending' })
    }
    return statusMap
  }

  // Sort logs by attempt_number ascending
  const sortedLogs = [...logs].sort(
    (a, b) => a.attempt_number - b.attempt_number
  )

  // The first log gives us the initial outcome
  const firstLog = sortedLogs[0]
  const latestLog = sortedLogs[sortedLogs.length - 1]

  // Find the outcome node that matches the first call's outcome
  const outcomeNodeId = flowNodes.find(
    (n) =>
      n.type === 'outcome' &&
      n.data?.outcome === firstLog.outcome
  )?.id

  // Build an adjacency map for walking edges
  const adjacency = new Map<string, string[]>()
  for (const edge of flowEdges) {
    const existing = adjacency.get(edge.source) || []
    existing.push(edge.target)
    adjacency.set(edge.source, existing)
  }

  // Start by marking all as pending
  for (const node of flowNodes) {
    statusMap.set(node.id, { status: 'pending' })
  }

  if (!outcomeNodeId) {
    // Outcome not found in flow — just mark first log's outcome as success
    return statusMap
  }

  // Mark the outcome node as success (the call happened and produced this outcome)
  statusMap.set(outcomeNodeId, {
    status: 'success',
    log: firstLog,
    attemptNumber: 1,
  })

  // Determine what the current flow node is from the latest log
  const currentFlowNode = latestLog.flow_current_node
  const flowStatus = latestLog.flow_status

  // Walk the flow from the outcome node, following edges
  // We do a BFS/DFS to find the path to the current node
  const visited = new Set<string>([outcomeNodeId])
  const queue: string[] = [outcomeNodeId]
  const pathNodes: string[] = [] // nodes in execution order after outcome

  // Simple BFS to find all reachable nodes from outcome
  while (queue.length > 0) {
    const current = queue.shift()!
    const neighbors = adjacency.get(current) || []
    for (const neighbor of neighbors) {
      if (!visited.has(neighbor)) {
        visited.add(neighbor)
        pathNodes.push(neighbor)
        queue.push(neighbor)
      }
    }
  }

  // Now assign statuses based on flow_current_node and flow_status
  // Nodes that come before the current node in the path are "success"
  // The current node depends on flow_status
  // Nodes after the current node are "pending"

  if (currentFlowNode) {
    // Find which path nodes are before/at/after the current node
    const currentIdx = pathNodes.indexOf(currentFlowNode)

    if (currentIdx >= 0) {
      // All nodes before current in the path are success
      for (let i = 0; i < currentIdx; i++) {
        const nodeId = pathNodes[i]
        const relevantLog = findRelevantLog(
          flowNodes,
          nodeId,
          sortedLogs
        )
        statusMap.set(nodeId, {
          status: 'success',
          log: relevantLog,
        })
      }

      // Current node status depends on flow_status
      const currentNodeObj = flowNodes.find((n) => n.id === currentFlowNode)
      const relevantLog = findRelevantLog(
        flowNodes,
        currentFlowNode,
        sortedLogs
      )

      if (flowStatus === 'waiting') {
        statusMap.set(currentFlowNode, {
          status: 'waiting',
          log: relevantLog || latestLog,
        })
      } else if (flowStatus === 'completed' || flowStatus === 'stopped') {
        // Everything up to and including current is done
        statusMap.set(currentFlowNode, {
          status: currentNodeObj?.type === 'stop' ? 'success' : 'success',
          log: relevantLog || latestLog,
        })
        // Mark remaining path nodes after current as pending (they were skipped or not reached)
      } else if (flowStatus === 'active') {
        // Flow is actively processing this node
        statusMap.set(currentFlowNode, {
          status: 'success',
          log: relevantLog || latestLog,
        })
      }

      // Nodes after current remain pending (already set)
    } else {
      // currentFlowNode not in our computed path — mark all visited as success
      // This handles cases where the flow took a different branch
      for (const nodeId of pathNodes) {
        if (nodeId === currentFlowNode) {
          statusMap.set(nodeId, {
            status:
              flowStatus === 'waiting'
                ? 'waiting'
                : flowStatus === 'stopped'
                ? 'failed'
                : 'success',
            log: latestLog,
          })
        }
      }

      // Also mark the current flow node wherever it is
      if (!statusMap.has(currentFlowNode) || statusMap.get(currentFlowNode)?.status === 'pending') {
        statusMap.set(currentFlowNode, {
          status:
            flowStatus === 'waiting'
              ? 'waiting'
              : flowStatus === 'stopped'
              ? 'failed'
              : 'success',
          log: latestLog,
        })
      }
    }
  } else {
    // No current flow node — flow may have completed or just started
    if (flowStatus === 'completed') {
      // Mark all path nodes as success
      for (const nodeId of pathNodes) {
        statusMap.set(nodeId, {
          status: 'success',
          log: latestLog,
        })
      }
    }
  }

  // Check for any logs with errors and mark related nodes as failed
  for (const log of sortedLogs) {
    if (log.call_error && log.attempt_number > 1) {
      // Find a retryCall node and mark it failed for this attempt
      const retryNodes = flowNodes.filter((n) => n.type === 'retryCall')
      for (const retryNode of retryNodes) {
        const existing = statusMap.get(retryNode.id)
        if (existing && existing.status !== 'pending') {
          statusMap.set(retryNode.id, {
            status: 'failed',
            log,
            attemptNumber: log.attempt_number,
          })
        }
      }
    }

    if (log.sms_error) {
      // Find sms nodes and mark them failed
      const smsNodes = flowNodes.filter((n) => n.type === 'sms')
      for (const smsNode of smsNodes) {
        const existing = statusMap.get(smsNode.id)
        if (existing && existing.status !== 'pending') {
          statusMap.set(smsNode.id, {
            status: 'failed',
            log,
          })
        }
      }
    }
  }

  return statusMap
}

function findRelevantLog(
  flowNodes: Node[],
  nodeId: string,
  logs: VoiceAgentLog[]
): VoiceAgentLog | undefined {
  const node = flowNodes.find((n) => n.id === nodeId)
  if (!node) return undefined

  // For retryCall nodes, find the log with matching attempt
  if (node.type === 'retryCall') {
    // Find logs with attempt > 1 (retry attempts)
    const retryLogs = logs.filter((l) => l.attempt_number > 1)
    return retryLogs[retryLogs.length - 1] || logs[logs.length - 1]
  }

  // For other nodes, find the log that references this node as flow_current_node
  const matchingLog = logs.find((l) => l.flow_current_node === nodeId)
  if (matchingLog) return matchingLog

  // Fallback to latest log
  return logs[logs.length - 1]
}

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

interface VoiceAgentFlowDebuggerProps {
  projectId: string
  showroomId: string
}

// ---------------------------------------------------------------------------
// Inner component (inside ReactFlowProvider)
// ---------------------------------------------------------------------------

function FlowDebuggerInner({
  projectId,
  showroomId,
}: VoiceAgentFlowDebuggerProps) {
  const [flow, setFlow] = useState<PostCallFlow | null>(null)
  const [logs, setLogs] = useState<VoiceAgentLog[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedNode, setSelectedNode] = useState<Node | null>(null)

  // Fetch showroom settings and logs
  useEffect(() => {
    let cancelled = false

    async function fetchData() {
      setLoading(true)
      setError(null)

      const supabase = createClient()

      try {
        // Fetch showroom settings for post_call_flow
        const { data: settings, error: settingsError } = await supabase
          .from('voice_agent_showroom_settings')
          .select('post_call_flow')
          .eq('showroom_id', showroomId)
          .single()

        if (settingsError && settingsError.code !== 'PGRST116') {
          throw new Error(settingsError.message)
        }

        // Fetch logs for this project
        const { data: logData, error: logsError } = await supabase
          .from('voice_agent_logs')
          .select('*')
          .eq('project_id', projectId)
          .order('attempt_number', { ascending: true })

        if (logsError) {
          throw new Error(logsError.message)
        }

        if (!cancelled) {
          const postCallFlow =
            (settings?.post_call_flow as PostCallFlow | null) ||
            DEFAULT_POST_CALL_FLOW
          setFlow(postCallFlow)
          setLogs(logData || [])
        }
      } catch (err: any) {
        if (!cancelled) {
          setError(err.message || 'Failed to load flow data')
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    fetchData()
    return () => {
      cancelled = true
    }
  }, [projectId, showroomId])

  // Build debug-aware node types
  const debugNodeTypes = useMemo(
    () => ({
      outcome: withDebugWrapper(OutcomeNode, 'Outcome'),
      wait: withDebugWrapper(WaitNode, 'Wait'),
      sms: withDebugWrapper(SmsNode, 'Sms'),
      retryCall: withDebugWrapper(RetryCallNode, 'RetryCall'),
      sendLink: withDebugWrapper(SendLinkNode, 'SendLink'),
      condition: withDebugWrapper(ConditionNode, 'Condition'),
      stop: withDebugWrapper(StopNode, 'Stop'),
    }),
    []
  )

  // Compute execution statuses and inject into node data
  const { nodes, edges } = useMemo(() => {
    if (!flow) return { nodes: [], edges: [] }

    const statusMap = computeExecutionStatuses(
      flow.nodes as Node[],
      flow.edges as Edge[],
      logs
    )

    const enhancedNodes: Node[] = flow.nodes.map((n) => {
      const exec = statusMap.get(n.id)
      return {
        ...n,
        data: {
          ...n.data,
          executionStatus: exec?.status || 'pending',
          executionData: exec,
        },
      } as Node
    })

    const enhancedEdges: Edge[] = flow.edges.map((e, i) => ({
      ...e,
      id: e.id || `edge_${i}`,
      animated: true,
    }))

    return { nodes: enhancedNodes, edges: enhancedEdges }
  }, [flow, logs])

  // Handle node click
  const onNodeClick = useCallback(
    (_: React.MouseEvent, node: Node) => {
      setSelectedNode(node)
    },
    []
  )

  const onPaneClick = useCallback(() => {
    setSelectedNode(null)
  }, [])

  // Loading state
  if (loading) {
    return (
      <div className="flex min-h-[500px] items-center justify-center rounded-lg border bg-muted/20">
        <div className="flex flex-col items-center gap-3 text-muted-foreground">
          <div className="size-6 animate-spin rounded-full border-2 border-current border-t-transparent" />
          <span className="text-sm">Loading flow debugger...</span>
        </div>
      </div>
    )
  }

  // Error state
  if (error) {
    return (
      <div className="flex min-h-[500px] items-center justify-center rounded-lg border bg-red-50">
        <div className="flex flex-col items-center gap-2 text-red-600">
          <AlertTriangle className="size-6" />
          <span className="text-sm font-medium">{error}</span>
        </div>
      </div>
    )
  }

  // No logs state
  if (logs.length === 0) {
    return (
      <div className="flex min-h-[500px] items-center justify-center rounded-lg border bg-muted/20">
        <div className="flex flex-col items-center gap-3 text-muted-foreground">
          <Circle className="size-8 opacity-40" />
          <span className="text-sm font-medium">
            No voice agent activity for this project yet.
          </span>
          <span className="text-xs">
            The flow will appear here once a call is made.
          </span>
        </div>
      </div>
    )
  }

  return (
    <div className="relative flex min-h-[500px] w-full flex-col gap-0 overflow-hidden rounded-lg border">
      {/* Legend */}
      <div className="flex items-center gap-4 border-b bg-muted/30 px-4 py-2">
        <span className="text-xs font-medium text-muted-foreground">
          Execution Status:
        </span>
        <div className="flex items-center gap-1.5">
          <div className="size-2.5 rounded-full bg-green-500" />
          <span className="text-xs text-muted-foreground">Success</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="size-2.5 rounded-full bg-red-500" />
          <span className="text-xs text-muted-foreground">Failed</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="size-2.5 animate-pulse rounded-full bg-amber-500" />
          <span className="text-xs text-muted-foreground">Waiting</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="size-2.5 rounded-full bg-gray-300" />
          <span className="text-xs text-muted-foreground">Pending</span>
        </div>
      </div>

      {/* Flow canvas */}
      <div className="relative flex flex-1" style={{ minHeight: 460 }}>
        <div className="flex-1">
          <ReactFlow
            nodes={nodes}
            edges={edges}
            nodeTypes={debugNodeTypes}
            nodesDraggable={false}
            nodesConnectable={false}
            elementsSelectable={true}
            onNodeClick={onNodeClick}
            onPaneClick={onPaneClick}
            fitView
            fitViewOptions={{ padding: 0.3 }}
            deleteKeyCode={null}
            className="bg-background"
          >
            <Controls showInteractive={false} />
            <Background variant={BackgroundVariant.Dots} gap={16} size={1} />
          </ReactFlow>
        </div>

        {/* Detail panel */}
        {selectedNode && (
          <NodeDetailPanel
            node={selectedNode}
            logs={logs}
            onClose={() => setSelectedNode(null)}
          />
        )}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Exported wrapper with ReactFlowProvider
// ---------------------------------------------------------------------------

export function VoiceAgentFlowDebugger(props: VoiceAgentFlowDebuggerProps) {
  return (
    <ReactFlowProvider>
      <FlowDebuggerInner {...props} />
    </ReactFlowProvider>
  )
}
