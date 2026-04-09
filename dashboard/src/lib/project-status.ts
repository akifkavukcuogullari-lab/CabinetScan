// Centralized project status definitions
// Used across: projects list, project detail, project sidebar, admin pages

export interface ProjectStatus {
  value: string
  label: string
  color: string
}

export const PROJECT_STATUSES: ProjectStatus[] = [
  { value: 'draft', label: 'Draft', color: 'bg-gray-100 text-gray-800' },
  { value: 'submitted', label: 'Submitted', color: 'bg-blue-100 text-blue-800' },
  { value: 'design_requested', label: 'Design Requested', color: 'bg-orange-100 text-orange-800' },
  { value: 'in_design', label: 'In Design', color: 'bg-indigo-100 text-indigo-800' },
  { value: 'design_delivered', label: 'Design Delivered', color: 'bg-purple-100 text-purple-800' },
  { value: 'design_completed', label: 'Design Completed', color: 'bg-teal-100 text-teal-800' },
  { value: 'in_review', label: 'In Review', color: 'bg-yellow-100 text-yellow-800' },
  { value: 'quoted', label: 'Quoted', color: 'bg-purple-100 text-purple-800' },
  { value: 'accepted', label: 'Accepted', color: 'bg-green-100 text-green-800' },
  { value: 'rejected', label: 'Rejected', color: 'bg-red-100 text-red-800' },
  { value: 'completed', label: 'Completed', color: 'bg-green-100 text-green-800' },
]

// Quick lookup by status value
export const STATUS_COLOR_MAP: Record<string, string> = Object.fromEntries(
  PROJECT_STATUSES.map(s => [s.value, s.color])
)

export const STATUS_LABEL_MAP: Record<string, string> = Object.fromEntries(
  PROJECT_STATUSES.map(s => [s.value, s.label])
)

// Get color for a status value (with fallback)
export function getStatusColor(status: string): string {
  return STATUS_COLOR_MAP[status] || 'bg-gray-100 text-gray-800'
}

// Get label for a status value (with fallback)
export function getStatusLabel(status: string): string {
  return STATUS_LABEL_MAP[status] || status.replace(/_/g, ' ')
}

// Map design_requests.status to project-level status
export function mapDesignStatus(designStatus: string): string | null {
  const map: Record<string, string> = {
    pending: 'design_requested',
    accepted: 'in_design',
    in_progress: 'in_design',
    delivered: 'design_delivered',
    revision_requested: 'in_design',
    approved: 'design_completed',
    completed: 'design_completed',
  }
  return map[designStatus] || null
}
