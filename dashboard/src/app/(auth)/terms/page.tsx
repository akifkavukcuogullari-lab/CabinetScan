import Link from "next/link";
import { ArrowLeft } from "lucide-react";

export const metadata = {
  title: "Terms of Service - CabinetScan",
  description: "Terms of Service for CabinetScan 3D room scanning platform",
};

export default function TermsPage() {
  const lastUpdated = "January 4, 2025";

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
          <h1 className="text-3xl font-bold text-gray-900">Terms of Service</h1>
          <p className="text-gray-500 mt-2">Last updated: {lastUpdated}</p>
        </div>
      </header>

      {/* Content */}
      <main className="max-w-4xl mx-auto px-4 py-12">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8 md:p-12 prose prose-gray max-w-none">

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">1. Agreement to Terms</h2>
            <p className="text-gray-600 leading-relaxed">
              These Terms of Service (&quot;Terms&quot;) constitute a legally binding agreement between you and
              NEXTLYN LLC (&quot;Company,&quot; &quot;we,&quot; &quot;our,&quot; or &quot;us&quot;) governing your use of the CabinetScan
              mobile application and web dashboard (collectively, the &quot;Service&quot;).
            </p>
            <p className="text-gray-600 leading-relaxed mt-4">
              By accessing or using the Service, you agree to be bound by these Terms. If you do not agree
              to these Terms, you may not access or use the Service.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">2. Description of Service</h2>
            <p className="text-gray-600 leading-relaxed">
              CabinetScan is a 3D room scanning platform that enables:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li><strong>End Users:</strong> To scan rooms using LiDAR technology, capture measurements, select products, and submit projects to cabinet showrooms</li>
              <li><strong>Showroom Owners:</strong> To receive and manage room scan submissions, view measurements, generate quotes, and communicate with customers</li>
            </ul>
            <p className="text-gray-600 leading-relaxed mt-4">
              The Service uses Apple&apos;s RoomPlan framework to capture 3D room data. Accuracy of measurements
              depends on device capabilities, room conditions, and proper scanning technique.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">3. User Accounts</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">3.1 End Users (Mobile App)</h3>
            <p className="text-gray-600 leading-relaxed">
              End users do not need to create an account to use the mobile app. By submitting a project,
              you provide your contact information which will be shared with the selected showroom.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">3.2 Showroom Owners (Dashboard)</h3>
            <p className="text-gray-600 leading-relaxed">
              Showroom owners must create an account and subscribe to a plan to access the dashboard.
              You are responsible for:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Maintaining the confidentiality of your account credentials</li>
              <li>All activities that occur under your account</li>
              <li>Notifying us immediately of any unauthorized access</li>
              <li>Ensuring your account information is accurate and up-to-date</li>
            </ul>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">4. Acceptable Use</h2>
            <p className="text-gray-600 leading-relaxed">
              You agree not to use the Service to:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Violate any applicable laws or regulations</li>
              <li>Infringe on the intellectual property rights of others</li>
              <li>Upload malicious code, viruses, or harmful content</li>
              <li>Attempt to gain unauthorized access to our systems or other users&apos; accounts</li>
              <li>Harass, abuse, or harm other users</li>
              <li>Submit false or misleading information</li>
              <li>Use the Service for any illegal or unauthorized purpose</li>
              <li>Scan rooms or properties without proper authorization from the property owner</li>
              <li>Reverse engineer, decompile, or disassemble the Service</li>
              <li>Resell or redistribute the Service without our written consent</li>
            </ul>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">5. User Content</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">5.1 Your Content</h3>
            <p className="text-gray-600 leading-relaxed">
              You retain ownership of all content you submit through the Service, including room scans,
              photos, videos, and personal information (&quot;User Content&quot;). By submitting User Content, you grant us
              a non-exclusive, worldwide, royalty-free license to use, store, process, and transmit your
              User Content solely for the purpose of providing the Service.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">5.2 Content Sharing</h3>
            <p className="text-gray-600 leading-relaxed">
              When you submit a project, your User Content is shared with the selected showroom. You
              acknowledge and consent to this sharing as an essential part of the Service.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">5.3 Property Authorization</h3>
            <p className="text-gray-600 leading-relaxed">
              You represent and warrant that you have the legal right and authorization to scan any
              property you submit through the Service. This includes obtaining consent from property
              owners if you are not the owner yourself.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">6. Subscription and Payments</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">6.1 Subscription Plans</h3>
            <p className="text-gray-600 leading-relaxed">
              Showroom owners must subscribe to a paid plan to access the dashboard. Plans are billed
              monthly or annually as selected at checkout. Current pricing is available on our pricing page.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">6.2 Free Trial</h3>
            <p className="text-gray-600 leading-relaxed">
              We may offer a free trial period. After the trial ends, you must subscribe to a paid plan
              to continue using the Service. We will not charge you until you select a plan.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">6.3 Billing</h3>
            <p className="text-gray-600 leading-relaxed">
              Subscriptions automatically renew unless canceled before the renewal date. You authorize
              us to charge your payment method for all fees incurred. All payments are processed securely
              through Stripe.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">6.4 Refunds</h3>
            <p className="text-gray-600 leading-relaxed">
              Subscription fees are non-refundable except where required by law. If you cancel your
              subscription, you will retain access until the end of your current billing period.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">6.5 Plan Limits</h3>
            <p className="text-gray-600 leading-relaxed">
              Each subscription plan has limits on projects, products, storage, and team members.
              Exceeding these limits may result in service restrictions until you upgrade your plan.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">7. Intellectual Property</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">7.1 Our Property</h3>
            <p className="text-gray-600 leading-relaxed">
              The Service, including its design, features, code, and content (excluding User Content),
              is owned by NEXTLYN LLC and protected by copyright, trademark, and other intellectual
              property laws. You may not copy, modify, distribute, or create derivative works based
              on the Service without our written consent.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">7.2 Feedback</h3>
            <p className="text-gray-600 leading-relaxed">
              If you provide us with feedback, suggestions, or ideas about the Service, you grant us
              an unrestricted, perpetual, royalty-free license to use such feedback for any purpose.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">8. Disclaimer of Warranties</h2>
            <p className="text-gray-600 leading-relaxed uppercase font-medium">
              THE SERVICE IS PROVIDED &quot;AS IS&quot; AND &quot;AS AVAILABLE&quot; WITHOUT WARRANTIES OF ANY KIND,
              EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF
              MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.
            </p>
            <p className="text-gray-600 leading-relaxed mt-4">
              We do not warrant that:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>The Service will be uninterrupted, secure, or error-free</li>
              <li>Room measurements will be 100% accurate</li>
              <li>The Service will meet your specific requirements</li>
              <li>Any defects or errors will be corrected</li>
            </ul>
            <p className="text-gray-600 leading-relaxed mt-4">
              <strong>Measurement Accuracy:</strong> Room scans and measurements are estimates based on
              LiDAR technology. Actual dimensions may vary. Professional verification is recommended
              before making purchasing or construction decisions based on measurements from the Service.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">9. Limitation of Liability</h2>
            <p className="text-gray-600 leading-relaxed uppercase font-medium">
              TO THE MAXIMUM EXTENT PERMITTED BY LAW, NEXTLYN LLC SHALL NOT BE LIABLE FOR ANY INDIRECT,
              INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS
              OF PROFITS, DATA, OR BUSINESS OPPORTUNITIES, ARISING OUT OF OR RELATED TO YOUR USE OF THE SERVICE.
            </p>
            <p className="text-gray-600 leading-relaxed mt-4">
              Our total liability for any claims arising from or related to the Service shall not exceed
              the greater of: (a) the amount you paid us in the 12 months preceding the claim, or (b) $100.
            </p>
            <p className="text-gray-600 leading-relaxed mt-4">
              We are not liable for any damages arising from:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Inaccurate measurements or room scan data</li>
              <li>Decisions made based on information from the Service</li>
              <li>Third-party products or services recommended through the Service</li>
              <li>Actions or omissions of showrooms using the platform</li>
              <li>Unauthorized access to your account or data</li>
            </ul>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">10. Indemnification</h2>
            <p className="text-gray-600 leading-relaxed">
              You agree to indemnify, defend, and hold harmless NEXTLYN LLC and its officers, directors,
              employees, and agents from any claims, damages, losses, liabilities, costs, and expenses
              (including reasonable attorneys&apos; fees) arising from:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Your use of the Service</li>
              <li>Your violation of these Terms</li>
              <li>Your violation of any third-party rights</li>
              <li>Your User Content</li>
              <li>Scanning properties without proper authorization</li>
            </ul>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">11. Termination</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">11.1 By You</h3>
            <p className="text-gray-600 leading-relaxed">
              You may stop using the Service at any time. Showroom owners may cancel their subscription
              through the billing settings in the dashboard.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">11.2 By Us</h3>
            <p className="text-gray-600 leading-relaxed">
              We may suspend or terminate your access to the Service at any time, with or without cause,
              and with or without notice. Reasons for termination may include:
            </p>
            <ul className="list-disc list-inside text-gray-600 space-y-2 mt-3">
              <li>Violation of these Terms</li>
              <li>Non-payment of subscription fees</li>
              <li>Fraudulent or illegal activity</li>
              <li>Extended inactivity</li>
              <li>At our sole discretion</li>
            </ul>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">11.3 Effect of Termination</h3>
            <p className="text-gray-600 leading-relaxed">
              Upon termination, your right to use the Service will cease immediately. We may retain
              your data as required by law or for legitimate business purposes. Sections 5, 7, 8, 9,
              10, and 13 shall survive termination.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">12. Changes to Terms</h2>
            <p className="text-gray-600 leading-relaxed">
              We may modify these Terms at any time by posting the revised Terms on our website.
              Material changes will be communicated via email or through the Service. Your continued
              use of the Service after changes become effective constitutes acceptance of the revised Terms.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">13. General Provisions</h2>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">13.1 Governing Law</h3>
            <p className="text-gray-600 leading-relaxed">
              These Terms shall be governed by and construed in accordance with the laws of the State
              of Delaware, United States, without regard to its conflict of law provisions.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">13.2 Dispute Resolution</h3>
            <p className="text-gray-600 leading-relaxed">
              Any disputes arising from these Terms or the Service shall first be attempted to be
              resolved through good-faith negotiation. If negotiation fails, disputes shall be resolved
              through binding arbitration in accordance with the rules of the American Arbitration Association.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">13.3 Entire Agreement</h3>
            <p className="text-gray-600 leading-relaxed">
              These Terms, together with our Privacy Policy, constitute the entire agreement between
              you and NEXTLYN LLC regarding the Service and supersede all prior agreements.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">13.4 Severability</h3>
            <p className="text-gray-600 leading-relaxed">
              If any provision of these Terms is found to be unenforceable, the remaining provisions
              shall continue in full force and effect.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">13.5 Waiver</h3>
            <p className="text-gray-600 leading-relaxed">
              Our failure to enforce any right or provision of these Terms shall not constitute a
              waiver of such right or provision.
            </p>

            <h3 className="text-lg font-medium text-gray-800 mt-6 mb-3">13.6 Assignment</h3>
            <p className="text-gray-600 leading-relaxed">
              You may not assign or transfer these Terms without our written consent. We may assign
              these Terms without restriction.
            </p>
          </section>

          <section className="mb-10">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">14. Contact Us</h2>
            <p className="text-gray-600 leading-relaxed">
              If you have any questions about these Terms, please contact us:
            </p>
            <div className="mt-4 p-4 bg-gray-50 rounded-lg">
              <p className="text-gray-700"><strong>NEXTLYN LLC</strong></p>
              <p className="text-gray-600">Email: <a href="mailto:contact@nextlyn.ai" className="text-blue-600 hover:underline">contact@nextlyn.ai</a></p>
              <p className="text-gray-600">Website: <a href="https://nextlyn.ai" className="text-blue-600 hover:underline">https://nextlyn.ai</a></p>
            </div>
          </section>

        </div>

        {/* Footer */}
        <div className="mt-8 text-center">
          <Link href="/privacy" className="text-blue-600 hover:underline">
            View Privacy Policy
          </Link>
        </div>
      </main>
    </div>
  );
}
