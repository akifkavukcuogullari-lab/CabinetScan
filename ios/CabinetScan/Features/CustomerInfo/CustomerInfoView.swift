import SwiftUI

struct CustomerInfoView: View {
    @EnvironmentObject var appState: AppState
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var customerType: CustomerType = .homeowner
    @State private var addressLine1 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""

    // End-client fields for contractors
    @State private var endClientFirstName = ""
    @State private var endClientLastName = ""
    @State private var endClientPhone = ""
    @State private var endClientEmail = ""
    @State private var endClientAddress = ""

    @FocusState private var focusedField: Field?

    enum Field {
        case firstName, lastName, email, phone, addressLine1, city, state, zipCode
        case endClientFirstName, endClientLastName, endClientPhone, endClientEmail, endClientAddress
    }

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email) &&
        !phone.trimmingCharacters(in: .whitespaces).isEmpty &&
        !addressLine1.trimmingCharacters(in: .whitespaces).isEmpty &&
        !city.trimmingCharacters(in: .whitespaces).isEmpty &&
        !state.trimmingCharacters(in: .whitespaces).isEmpty &&
        !zipCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Large showroom logo at top - full width
                if let config = appState.showroomConfig {
                    Section {
                        VStack(spacing: 12) {
                            GeometryReader { geometry in
                                ShowroomLogo(
                                    logoUrl: config.branding.logoUrl,
                                    logoDarkUrl: config.branding.logoDarkUrl,
                                    maxHeight: 120,
                                    maxWidth: geometry.size.width
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .frame(height: 120)

                            Text(config.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 16, trailing: 0))
                    }
                }

                // Customer type section
                Section {
                    Picker("I am a", selection: $customerType) {
                        ForEach(CustomerType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Customer Type")
                }

                // Contact information section
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

                    TextField("Phone *", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                } header: {
                    Text("Your Information")
                }

                // Address section
                Section {
                    TextField("Street Address", text: $addressLine1)
                        .textContentType(.streetAddressLine1)
                        .focused($focusedField, equals: .addressLine1)
                        .submitLabel(.next)

                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                        .focused($focusedField, equals: .city)
                        .submitLabel(.next)

                    HStack(spacing: 12) {
                        TextField("State", text: $state)
                            .textContentType(.addressState)
                            .focused($focusedField, equals: .state)
                            .submitLabel(.next)

                        TextField("Zip Code", text: $zipCode)
                            .textContentType(.postalCode)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .zipCode)
                    }
                } header: {
                    Text("Your Address")
                }

                // End-client section (only for contractors)
                if customerType == .contractor {
                    Section {
                        TextField("Client First Name", text: $endClientFirstName)
                            .textContentType(.givenName)
                            .focused($focusedField, equals: .endClientFirstName)
                            .submitLabel(.next)

                        TextField("Client Last Name", text: $endClientLastName)
                            .textContentType(.familyName)
                            .focused($focusedField, equals: .endClientLastName)
                            .submitLabel(.next)

                        TextField("Client Phone", text: $endClientPhone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .focused($focusedField, equals: .endClientPhone)

                        TextField("Client Email", text: $endClientEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .endClientEmail)
                            .submitLabel(.next)

                        TextField("Project Address", text: $endClientAddress)
                            .textContentType(.fullStreetAddress)
                            .focused($focusedField, equals: .endClientAddress)
                            .submitLabel(.done)
                    } header: {
                        Text("End Client Information")
                    } footer: {
                        Text("Optional information about the homeowner you're working for")
                    }
                }

                // Footer text
                Section {
                    Text("We'll use this information to contact you about your project")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                // Start Scanning button
                Section {
                    Button {
                        saveAndContinue()
                    } label: {
                        Text("Start Scanning")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        appState.currentScreen = .onboarding
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
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
                    focusedField = .addressLine1
                case .addressLine1:
                    focusedField = .city
                case .city:
                    focusedField = .state
                case .state:
                    focusedField = .zipCode
                case .zipCode:
                    if customerType == .contractor {
                        focusedField = .endClientFirstName
                    } else if isFormValid {
                        saveAndContinue()
                    }
                case .endClientFirstName:
                    focusedField = .endClientLastName
                case .endClientLastName:
                    focusedField = .endClientPhone
                case .endClientPhone:
                    focusedField = .endClientEmail
                case .endClientEmail:
                    focusedField = .endClientAddress
                case .endClientAddress:
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
            phone: phone.trimmingCharacters(in: .whitespaces),
            customerType: customerType,
            addressLine1: addressLine1.trimmingCharacters(in: .whitespaces).isEmpty ? nil : addressLine1.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces).isEmpty ? nil : city.trimmingCharacters(in: .whitespaces),
            state: state.trimmingCharacters(in: .whitespaces).isEmpty ? nil : state.trimmingCharacters(in: .whitespaces),
            zipCode: zipCode.trimmingCharacters(in: .whitespaces).isEmpty ? nil : zipCode.trimmingCharacters(in: .whitespaces)
        )

        // Create end-client info for contractors
        var endClient: EndClientInfo? = nil
        if customerType == .contractor {
            let hasEndClientData = !endClientFirstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                   !endClientLastName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                   !endClientPhone.trimmingCharacters(in: .whitespaces).isEmpty ||
                                   !endClientEmail.trimmingCharacters(in: .whitespaces).isEmpty ||
                                   !endClientAddress.trimmingCharacters(in: .whitespaces).isEmpty

            if hasEndClientData {
                endClient = EndClientInfo(
                    firstName: endClientFirstName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : endClientFirstName.trimmingCharacters(in: .whitespaces),
                    lastName: endClientLastName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : endClientLastName.trimmingCharacters(in: .whitespaces),
                    phone: endClientPhone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : endClientPhone.trimmingCharacters(in: .whitespaces),
                    email: endClientEmail.trimmingCharacters(in: .whitespaces).isEmpty ? nil : endClientEmail.trimmingCharacters(in: .whitespaces).lowercased(),
                    address: endClientAddress.trimmingCharacters(in: .whitespaces).isEmpty ? nil : endClientAddress.trimmingCharacters(in: .whitespaces)
                )
            }
        }

        appState.setCustomerInfo(info, endClient: endClient)
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
