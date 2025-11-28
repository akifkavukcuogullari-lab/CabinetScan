import SwiftUI

struct CustomerInfoView: View {
    @EnvironmentObject var appState: AppState
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case firstName, lastName, email, phone
    }

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let config = appState.showroomConfig {
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundStyle(.blue)
                            Text(config.name)
                                .fontWeight(.medium)
                        }
                    }
                } header: {
                    Text("Showroom")
                }

                Section {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                        .focused($focusedField, equals: .firstName)
                        .submitLabel(.next)

                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                        .focused($focusedField, equals: .lastName)
                        .submitLabel(.next)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)

                    TextField("Phone (Optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                } header: {
                    Text("Your Information")
                } footer: {
                    Text("We'll use this to send you the project details")
                }

                Section {
                    Button {
                        saveAndContinue()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Start Scanning")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!isFormValid)
                }
            }
            .navigationTitle("Your Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        appState.currentScreen = .onboarding
                    }
                }
            }
            .onSubmit {
                switch focusedField {
                case .firstName:
                    focusedField = .lastName
                case .lastName:
                    focusedField = .email
                case .email:
                    focusedField = .phone
                case .phone:
                    if isFormValid {
                        saveAndContinue()
                    }
                case .none:
                    break
                }
            }
        }
    }

    private func saveAndContinue() {
        let info = CustomerInfo(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            phone: phone.isEmpty ? nil : phone
        )
        appState.setCustomerInfo(info)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
}

#Preview {
    CustomerInfoView()
        .environmentObject(AppState.shared)
}
