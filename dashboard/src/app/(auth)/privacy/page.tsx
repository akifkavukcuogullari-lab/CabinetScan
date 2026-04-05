import Link from "next/link";
import { ArrowLeft } from "lucide-react";

export const metadata = {
  title: "Privacy Policy - CabinetScan by Nextlyn",
  description: "Privacy Policy for CabinetScan 3D room scanning platform by NEXTLYN LLC",
};

export default function PrivacyPage() {
  const lastUpdated = "April 5, 2026";

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white border-b border-gray-200">
        <div className="max-w-4xl mx-auto px-4 py-6">
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-gray-600 hover:text-gray-900 mb-4"
          >
            <ArrowLeft className="h-4 w-4" />
            Back to Home
          </Link>
          <h1 className="text-3xl font-bold text-gray-900">Privacy Policy</h1>
          <p className="text-gray-500 mt-2">Last updated: {lastUpdated}</p>
        </div>
      </header>

      {/* Content */}
      <main className="max-w-4xl mx-auto px-4 py-12">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8 md:p-12 prose prose-gray max-w-none">

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">1. Introduction</h2>
            <p className="text-gray-600 leading-relaxed">
              CabinetScan (&quot;we,&quot; &quot;our,&quot; or &quot;us&quot;) is a 3D room scanning platform operated by NEXTLYN LLC.
              This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you
              use our mobile application and web dashboard (collectively, the &quot;Service&quot;).
            </p>
            <p className="text-gray-600 leading-relaxed mt-4">
              By using CabinetScan, you consent to the data practices described in this policy. If you do not
              agree with the terms of this Privacy Policy, please do not access or use the Service.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">2. Information We Collect</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">2.1 Personal Information</h3>
            <p className="text-gray-600 leading-relaxed">
              When you use our mobile app to submit a room scan project, we collect:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li><strong>Contact Information:</strong> First name, last name, email address, phone number</li>
              <li><strong>Address Information:</strong> Street address, city, state, and zip code</li>
              <li><strong>Customer Type:</strong> Whether you are a homeowner or contractor</li>
              <li><strong>End-Client Information:</strong> If you are a contractor, optional information about the homeowner you are working for</li>
            </ul>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">2.2 Room Scan Data</h3>
            <p className="text-gray-600 leading-relaxed">
              Our app uses Apple&apos;s RoomPlan technology to capture 3D room data. We collect:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li><strong>3D Room Scans:</strong> USDZ files containing 3D models of scanned rooms</li>
              <li><strong>Room Measurements:</strong> Dimensions of walls, cabinets, appliances, windows, doors, and countertops</li>
              <li><strong>Floor Plans:</strong> 2D representations generated from the 3D scan</li>
              <li><strong>Photos:</strong> Visualization photos taken during the scanning process</li>
              <li><strong>Videos:</strong> Optional video recordings of the room scan session</li>
            </ul>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">2.3 Product Selections</h3>
            <p className="text-gray-600 leading-relaxed">
              When you select products during the scanning process, we collect:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Selected product categories and specific products</li>
              <li>Color/variant preferences</li>
              <li>Quantity selections</li>
              <li>Special requests or notes you provide</li>
            </ul>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">2.4 Device Information</h3>
            <p className="text-gray-600 leading-relaxed">
              We automatically collect certain device information:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Device model (e.g., iPhone 15 Pro)</li>
              <li>iOS version</li>
              <li>App version</li>
            </ul>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">2.5 Consent Records</h3>
            <p className="text-gray-600 leading-relaxed">
              We record when you agree to our Terms of Service and Privacy Policy, including the timestamp
              of your consent and which version of the policies you agreed to.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">3. How We Use Your Information</h2>
            <p className="text-gray-600 leading-relaxed">
              We use the information we collect for the following purposes:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li><strong>Service Delivery:</strong> To provide room scanning and measurement services to showrooms</li>
              <li><strong>Communication:</strong> To send you project confirmations and updates via email</li>
              <li><strong>Quote Generation:</strong> To share your room data with the showroom so they can provide you with quotes</li>
              <li><strong>Service Improvement:</strong> To analyze usage patterns and improve our scanning technology</li>
              <li><strong>Legal Compliance:</strong> To comply with legal obligations and protect our rights</li>
              <li><strong>SMS Communications:</strong> We may use your phone number to send you appointment reminders, pre-call notifications, post-call follow-ups, and promotional messages via SMS on behalf of cabinet showrooms. Message and data rates may apply. You can opt out at any time by replying STOP.</li>
            </ul>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">4. How We Share Your Information</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">4.1 With Showrooms</h3>
            <p className="text-gray-600 leading-relaxed">
              When you submit a project through our app, your information is shared with the cabinet showroom
              you selected. This includes your contact information, room scan data, measurements, and product
              selections. The showroom uses this information to prepare quotes and communicate with you about
              your project.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">4.2 Service Providers</h3>
            <p className="text-gray-600 leading-relaxed">
              We use third-party service providers to help operate our Service:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li><strong>Supabase:</strong> Cloud database and file storage</li>
              <li><strong>Amazon Web Services (AWS):</strong> Cloud infrastructure and file archival</li>
              <li><strong>Resend:</strong> Email delivery services</li>
              <li><strong>Vercel:</strong> Web hosting</li>
            </ul>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">4.3 Legal Requirements</h3>
            <p className="text-gray-600 leading-relaxed">
              We may disclose your information if required by law, court order, or government regulation,
              or if we believe disclosure is necessary to protect our rights, your safety, or the safety of others.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">5. Data Retention</h2>
            <p className="text-gray-600 leading-relaxed">
              Your project data is retained according to the showroom&apos;s subscription plan:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li><strong>Active Storage:</strong> 30-90 days depending on the showroom&apos;s plan</li>
              <li><strong>Archived Storage:</strong> After the active period, files are moved to cold storage but remain accessible</li>
              <li><strong>Deletion:</strong> You may request deletion of your data at any time by contacting the showroom or us directly</li>
            </ul>
            <p className="text-gray-600 leading-relaxed mt-4">
              Contact information and project metadata may be retained longer for business records and legal compliance purposes.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">6. Data Security</h2>
            <p className="text-gray-600 leading-relaxed">
              We implement appropriate technical and organizational security measures to protect your personal
              information, including:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Encryption of data in transit (TLS/SSL)</li>
              <li>Encryption of data at rest</li>
              <li>Access controls and authentication</li>
              <li>Regular security assessments</li>
              <li>Row-level security policies in our database</li>
            </ul>
            <p className="text-gray-600 leading-relaxed mt-4">
              However, no method of transmission over the Internet or electronic storage is 100% secure.
              While we strive to use commercially acceptable means to protect your information, we cannot
              guarantee its absolute security.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">7. Your Rights</h2>
            <p className="text-gray-600 leading-relaxed">
              Depending on your location, you may have certain rights regarding your personal information:
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">7.1 Access and Portability</h3>
            <p className="text-gray-600 leading-relaxed">
              You have the right to request a copy of the personal information we hold about you.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">7.2 Correction</h3>
            <p className="text-gray-600 leading-relaxed">
              You have the right to request that we correct inaccurate personal information.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">7.3 Deletion</h3>
            <p className="text-gray-600 leading-relaxed">
              You have the right to request that we delete your personal information, subject to certain exceptions.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">7.4 Opt-Out</h3>
            <p className="text-gray-600 leading-relaxed">
              You may opt out of receiving promotional communications from us by following the unsubscribe
              instructions in those messages.
            </p>

            <p className="text-gray-600 leading-relaxed mt-4">
              To exercise any of these rights, please contact us at <a href="mailto:contact@nextlyn.ai" className="text-blue-600 hover:underline">contact@nextlyn.ai</a>.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">8. California Privacy Rights (CCPA)</h2>
            <p className="text-gray-600 leading-relaxed">
              If you are a California resident, you have additional rights under the California Consumer Privacy Act (CCPA):
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>The right to know what personal information we collect, use, and disclose</li>
              <li>The right to request deletion of your personal information</li>
              <li>The right to opt-out of the sale of your personal information (we do not sell personal information)</li>
              <li>The right to non-discrimination for exercising your privacy rights</li>
            </ul>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">9. Children&apos;s Privacy</h2>
            <p className="text-gray-600 leading-relaxed">
              Our Service is not intended for children under 18 years of age. We do not knowingly collect
              personal information from children under 18. If you are a parent or guardian and believe your
              child has provided us with personal information, please contact us so we can delete it.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">10. Changes to This Privacy Policy</h2>
            <p className="text-gray-600 leading-relaxed">
              We may update this Privacy Policy from time to time. We will notify you of any changes by
              posting the new Privacy Policy on this page and updating the &quot;Last updated&quot; date. You are
              advised to review this Privacy Policy periodically for any changes.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">11. Contact Us</h2>
            <p className="text-gray-600 leading-relaxed">
              If you have any questions about this Privacy Policy or our data practices, please contact us:
            </p>
            <div className="mt-4 p-4 bg-gray-50 rounded-lg space-y-1">
              <p className="text-gray-700"><strong>NEXTLYN LLC</strong></p>
              <p className="text-gray-600">Email: <a href="mailto:contact@nextlyn.ai" className="text-blue-600 hover:underline">contact@nextlyn.ai</a></p>
              <p className="text-gray-600">Phone: <a href="tel:+18569795500" className="text-blue-600 hover:underline">(856) 979-5500</a></p>
              <p className="text-gray-600">Website: <a href="https://nextlyn.ai" className="text-blue-600 hover:underline">https://nextlyn.ai</a></p>
            </div>
          </section>

        </div>

        {/* Footer */}
        <div className="mt-8 text-center">
          <Link href="/terms" className="text-blue-600 hover:underline">
            View Terms of Service
          </Link>
        </div>
      </main>
    </div>
  );
}
