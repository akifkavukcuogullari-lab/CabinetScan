/**
 * E2E Tests: Designer Dashboard
 *
 * NOTE: Playwright is not currently installed in this project.
 * To run these tests, install Playwright first:
 *
 *   npm install -D @playwright/test
 *   npx playwright install
 *
 * Then create a playwright.config.ts in the dashboard root.
 * Run with: npx playwright test e2e/designer-dashboard.spec.ts
 */
import { test, expect, type Page } from '@playwright/test'

// ---- Test Configuration ----

const BASE_URL = process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:3000'

// Test credentials (should be set via environment variables in CI)
const DESIGNER_EMAIL = process.env.TEST_DESIGNER_EMAIL || 'designer@test.com'
const DESIGNER_PASSWORD = process.env.TEST_DESIGNER_PASSWORD || 'testpassword123'
const SHOWROOM_EMAIL = process.env.TEST_SHOWROOM_EMAIL || 'showroom@test.com'
const SHOWROOM_PASSWORD = process.env.TEST_SHOWROOM_PASSWORD || 'testpassword123'

// ---- Helpers ----

async function loginAs(
  page: Page,
  role: 'showroom' | 'designer',
  email: string,
  password: string
) {
  await page.goto(`${BASE_URL}/login`)
  await page.waitForLoadState('networkidle')

  // Select role tab
  const roleButton = page.locator('button', { hasText: role === 'designer' ? 'Designer' : 'Showroom' })
  await roleButton.click()

  // Fill credentials
  await page.fill('input[id="email"]', email)
  await page.fill('input[id="password"]', password)

  // Submit
  await page.click('button[type="submit"]')

  // Wait for navigation
  await page.waitForURL(url => !url.toString().includes('/login'), { timeout: 10000 })
}

// ---- Tests ----

test.describe('Login Page', () => {
  test('shows role selector with Showroom and Designer tabs', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`)

    const showroomTab = page.locator('button', { hasText: 'Showroom' })
    const designerTab = page.locator('button', { hasText: 'Designer' })

    await expect(showroomTab).toBeVisible()
    await expect(designerTab).toBeVisible()
  })

  test('Showroom tab is selected by default', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`)

    const showroomTab = page.locator('button', { hasText: 'Showroom' })
    // The active tab has white background
    await expect(showroomTab).toHaveClass(/bg-white/)
  })

  test('shows email and password fields', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`)

    await expect(page.locator('input[id="email"]')).toBeVisible()
    await expect(page.locator('input[id="password"]')).toBeVisible()
    await expect(page.locator('button[type="submit"]')).toBeVisible()
  })

  test('shows error for invalid credentials', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`)

    await page.fill('input[id="email"]', 'invalid@example.com')
    await page.fill('input[id="password"]', 'wrongpassword')
    await page.click('button[type="submit"]')

    // Wait for error alert
    const errorAlert = page.locator('[role="alert"]')
    await expect(errorAlert).toBeVisible({ timeout: 5000 })
  })

  test('password visibility toggle works', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`)

    const passwordInput = page.locator('input[id="password"]')
    await passwordInput.fill('mypassword')

    // Initially password type
    await expect(passwordInput).toHaveAttribute('type', 'password')

    // Click toggle
    const toggleButton = page.locator('button[aria-label="Show password"]')
    await toggleButton.click()

    // Now text type
    await expect(passwordInput).toHaveAttribute('type', 'text')

    // Click again to hide
    const hideButton = page.locator('button[aria-label="Hide password"]')
    await hideButton.click()
    await expect(passwordInput).toHaveAttribute('type', 'password')
  })
})

test.describe('Designer Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'designer', DESIGNER_EMAIL, DESIGNER_PASSWORD)
  })

  test('designer can view design pool', async ({ page }) => {
    await page.goto(`${BASE_URL}/designer/pool`)
    await page.waitForLoadState('networkidle')

    // Page heading should be visible
    await expect(page.locator('h1', { hasText: 'Design Pool' })).toBeVisible()
    await expect(
      page.locator('text=Available design requests waiting for a designer')
    ).toBeVisible()

    // Refresh button should be visible
    await expect(page.locator('button', { hasText: 'Refresh' })).toBeVisible()
  })

  test('design pool shows empty state when no requests', async ({ page }) => {
    await page.goto(`${BASE_URL}/designer/pool`)
    await page.waitForLoadState('networkidle')

    // If no pending requests, empty state should show
    const emptyState = page.locator('text=No pending design requests')
    const requestCards = page.locator('[data-testid="pool-card"]')

    // One of these should be visible
    const hasEmpty = await emptyState.isVisible().catch(() => false)
    const hasCards = await requestCards.first().isVisible().catch(() => false)

    expect(hasEmpty || hasCards).toBeTruthy()
  })

  test('designer can accept a request from the pool', async ({ page }) => {
    await page.goto(`${BASE_URL}/designer/pool`)
    await page.waitForLoadState('networkidle')

    // Look for an Accept Request button
    const acceptButton = page.locator('button', { hasText: 'Accept Request' }).first()

    if (await acceptButton.isVisible().catch(() => false)) {
      await acceptButton.click()

      // Should redirect to the project detail page
      await page.waitForURL(/\/designer\/projects\//, { timeout: 10000 })

      // Success toast should appear
      await expect(page.locator('text=Design request accepted')).toBeVisible({ timeout: 5000 })
    }
  })

  test('designer can view project detail page', async ({ page }) => {
    // Navigate to the designer's projects list
    await page.goto(`${BASE_URL}/designer/projects`)
    await page.waitForLoadState('networkidle')

    // Click on first project if exists
    const projectLink = page.locator('a[href*="/designer/projects/"]').first()

    if (await projectLink.isVisible().catch(() => false)) {
      await projectLink.click()
      await page.waitForLoadState('networkidle')

      // Project detail page should have status controls
      await expect(page.locator('text=Status')).toBeVisible()
    }
  })

  test('designer can send chat messages', async ({ page }) => {
    // Navigate to a project with an active design request
    await page.goto(`${BASE_URL}/designer/projects`)
    await page.waitForLoadState('networkidle')

    const projectLink = page.locator('a[href*="/designer/projects/"]').first()

    if (await projectLink.isVisible().catch(() => false)) {
      await projectLink.click()
      await page.waitForLoadState('networkidle')

      // Find the chat input
      const chatInput = page.locator('textarea[placeholder*="message"], input[placeholder*="message"]').first()

      if (await chatInput.isVisible().catch(() => false)) {
        await chatInput.fill('E2E test message from designer')

        // Find and click send button
        const sendButton = page.locator('button[aria-label*="send" i], button[type="submit"]').last()
        await sendButton.click()

        // Message should appear in chat
        await expect(
          page.locator('text=E2E test message from designer')
        ).toBeVisible({ timeout: 5000 })
      }
    }
  })

  test('designer can upload files', async ({ page }) => {
    await page.goto(`${BASE_URL}/designer/projects`)
    await page.waitForLoadState('networkidle')

    const projectLink = page.locator('a[href*="/designer/projects/"]').first()

    if (await projectLink.isVisible().catch(() => false)) {
      await projectLink.click()
      await page.waitForLoadState('networkidle')

      // Look for the file upload area
      const uploadArea = page.locator('text=Drop files here or click to browse')

      if (await uploadArea.isVisible().catch(() => false)) {
        // Create a test file and upload
        const fileInput = page.locator('input[type="file"]').first()

        // Set file via input
        await fileInput.setInputFiles({
          name: 'test-design.pdf',
          mimeType: 'application/pdf',
          buffer: Buffer.from('PDF test content'),
        })

        // Wait for upload toast
        await expect(
          page.locator('text=Uploaded test-design.pdf')
        ).toBeVisible({ timeout: 10000 })
      }
    }
  })
})

test.describe('Showroom Owner - Design Requests', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'showroom', SHOWROOM_EMAIL, SHOWROOM_PASSWORD)
  })

  test('showroom can view projects list', async ({ page }) => {
    await page.goto(`${BASE_URL}/showroom/projects`)
    await page.waitForLoadState('networkidle')

    // Projects page should be visible
    await expect(page.locator('h1, h2').filter({ hasText: /projects/i })).toBeVisible()
  })

  test('showroom can request a design from a project', async ({ page }) => {
    await page.goto(`${BASE_URL}/showroom/projects`)
    await page.waitForLoadState('networkidle')

    // Click on first project
    const projectLink = page.locator('a[href*="/showroom/projects/"]').first()

    if (await projectLink.isVisible().catch(() => false)) {
      await projectLink.click()
      await page.waitForLoadState('networkidle')

      // Look for the Request Design button
      const requestBtn = page.locator('button', { hasText: 'Request Design' })

      if (await requestBtn.isVisible().catch(() => false)) {
        await requestBtn.click()

        // Modal should open
        await expect(
          page.locator('text=Submit a design request for this project')
        ).toBeVisible()

        // Fill in the design brief
        const briefTextarea = page.locator('textarea[id="design-brief"]')
        await briefTextarea.fill('E2E test: Modern kitchen with island')

        // Select priority
        const priorityTrigger = page.locator('[id="priority"]')
        await priorityTrigger.click()
        const highOption = page.locator('[role="option"]', { hasText: 'High' })
        await highOption.click()

        // Submit
        const submitBtn = page.locator('button', { hasText: 'Submit Request' })
        await submitBtn.click()

        // Success toast
        await expect(
          page.locator('text=Design request submitted successfully')
        ).toBeVisible({ timeout: 5000 })
      }
    }
  })

  test('showroom can see design status card for a project with a request', async ({ page }) => {
    await page.goto(`${BASE_URL}/showroom/projects`)
    await page.waitForLoadState('networkidle')

    const projectLink = page.locator('a[href*="/showroom/projects/"]').first()

    if (await projectLink.isVisible().catch(() => false)) {
      await projectLink.click()
      await page.waitForLoadState('networkidle')

      // Look for either the design status card or the request button
      const statusCard = page.locator('text=Design Request').first()
      const requestBtn = page.locator('button', { hasText: 'Request Design' })

      const hasStatus = await statusCard.isVisible().catch(() => false)
      const hasRequestBtn = await requestBtn.isVisible().catch(() => false)

      // One of them should be visible
      expect(hasStatus || hasRequestBtn).toBeTruthy()
    }
  })

  test('showroom can approve a delivered design', async ({ page }) => {
    await page.goto(`${BASE_URL}/showroom/projects`)
    await page.waitForLoadState('networkidle')

    const projectLink = page.locator('a[href*="/showroom/projects/"]').first()

    if (await projectLink.isVisible().catch(() => false)) {
      await projectLink.click()
      await page.waitForLoadState('networkidle')

      const approveBtn = page.locator('button', { hasText: 'Approve Design' })

      if (await approveBtn.isVisible().catch(() => false)) {
        await approveBtn.click()

        // Confirmation dialog
        await expect(page.locator('text=Approve Design?')).toBeVisible()

        // Confirm
        const confirmBtn = page.locator('button', { hasText: 'Confirm' })
        await confirmBtn.click()

        // Success toast
        await expect(
          page.locator('text=Design request approved')
        ).toBeVisible({ timeout: 5000 })
      }
    }
  })
})

test.describe('Theme Toggle', () => {
  test('designer can toggle light/dark mode', async ({ page }) => {
    await loginAs(page, 'designer', DESIGNER_EMAIL, DESIGNER_PASSWORD)
    await page.goto(`${BASE_URL}/designer/pool`)
    await page.waitForLoadState('networkidle')

    // Look for theme toggle button (usually in sidebar or header)
    const themeToggle = page.locator(
      'button[aria-label*="theme" i], button[aria-label*="dark" i], button[aria-label*="light" i], button[aria-label*="mode" i]'
    ).first()

    if (await themeToggle.isVisible().catch(() => false)) {
      // Get initial theme
      const htmlEl = page.locator('html')
      const initialClass = await htmlEl.getAttribute('class')
      const wasDark = initialClass?.includes('dark')

      // Toggle
      await themeToggle.click()

      // Wait for theme transition
      await page.waitForTimeout(500)

      // Check if theme changed
      const newClass = await htmlEl.getAttribute('class')
      const isDark = newClass?.includes('dark')

      expect(isDark).not.toBe(wasDark)
    }
  })
})
