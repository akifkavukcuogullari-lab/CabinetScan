# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CabinetScan is a white-label multi-tenant SaaS platform for cabinet showrooms. It consists of three main components:

1. **iOS App** - Customer-facing SwiftUI app with RoomPlan for 3D room scanning
2. **Web Dashboard** - Next.js admin portal for showroom owners and super admins
3. **Supabase Backend** - PostgreSQL database, Edge Functions, and file storage

## Architecture

### Multi-Tenancy Model
- **Super Admin**: Platform owner who manages all showrooms and master categories
- **Showroom Owner**: Tenant who manages their products, branding, and customer projects
- **End Customer**: Uses iOS app to scan rooms and select products (no auth required)

### Data Flow
1. Customer enters showroom code in iOS app
2. App fetches showroom config (branding, categories, products) via Edge Function
3. Customer provides contact info, scans room with RoomPlan, selects products
4. Submission sent to Edge Function, stored in database
5. Showroom owner views/manages submissions in web dashboard

## Project Structure

```
/CabinetScan
├── /supabase              # Backend
│   ├── /migrations        # SQL migrations (run in order)
│   ├── /functions         # Deno Edge Functions
│   └── config.toml        # Local dev config
├── /dashboard             # Next.js 15 web app
│   └── /src
│       ├── /app           # App Router pages
│       ├── /components    # UI components (shadcn/ui)
│       ├── /lib           # Supabase clients, utilities
│       └── /types         # TypeScript types
└── /ios                   # iOS app
    └── /CabinetScan
        ├── /App           # Entry point
        ├── /Features      # Feature modules
        ├── /Models        # Data models
        └── /Services      # API, state management
```

## Development Commands

### Dashboard (Next.js)
```bash
cd dashboard
npm install
npm run dev          # Start dev server on :3000
npm run build        # Production build
npm run lint         # ESLint
```

### Supabase
```bash
# Install Supabase CLI: brew install supabase/tap/supabase
supabase start       # Start local Supabase
supabase db reset    # Reset and run all migrations
supabase functions serve  # Run Edge Functions locally
```

### iOS
Open `/ios/CabinetScan.xcodeproj` in Xcode. Requires:
- iOS 17+
- Device with LiDAR (for RoomPlan)

## Key Technical Decisions

### Database
- Row Level Security (RLS) enforces multi-tenant isolation
- `is_super_admin()`, `has_showroom_access(uuid)` helper functions for RLS
- Pricing units stored in `categories`, inherited by products
- Product selections snapshot price at submission time

### Authentication
- Super Admin/Showroom Owner: Supabase Auth (email/password)
- End Customer: No auth required (anonymous Supabase access)
- iOS app uses anon key for all API calls

### Storage Buckets
- `logos`: Public, showroom branding images
- `products`: Public, product images
- `scans`: Private, RoomPlan USDZ files and previews

### Edge Functions
- `get-showroom-config`: Returns full showroom config by code
- `submit-project`: Creates project with measurements and selections

## Environment Variables

### Dashboard (.env.local)
```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
```

### iOS (via Xcode scheme or Config.plist)
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
```

## Specialized Agents

Use these agents for specific tasks:
- **nextlean-architect**: Database schema, API design, system architecture
- **nextlean-scan-builder**: Feature implementation (iOS/Web/Backend)
- **nextlean-polisher**: Animations, UX polish, accessibility, edge cases
- **nextlean-integrator**: Deployment, CI/CD, external integrations (Stripe, Resend)
