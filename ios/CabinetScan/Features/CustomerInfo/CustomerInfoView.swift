import SwiftUI

struct CustomerInfoView: View {
    @EnvironmentObject var appState: AppState
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zipcode = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case firstName, lastName, email, phone, address, city, state, zipcode
    }

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email) &&
        !phone.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty &&
        !city.trimmingCharacters(in: .whitespaces).isEmpty &&
        !state.trimmingCharacters(in: .whitespaces).isEmpty &&
        !zipcode.trimmingCharacters(in: .whitespaces).isEmpty
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

                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                } header: {
                    Text("Contact Information")
                }

                // Address section
                Section {
                    TextField("Street Address", text: $address)
                        .textContentType(.streetAddressLine1)
                        .focused($focusedField, equals: .address)
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

                        TextField("Zip Code", text: $zipcode)
                            .textContentType(.postalCode)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .zipcode)
                    }
                } header: {
                    Text("Address")
                } footer: {
                    Text("We'll use this information to contact you about your project")
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
                    focusedField = .address
                case .address:
                    focusedField = .city
                case .city:
                    focusedField = .state
                case .state:
                    focusedField = .zipcode
                case .zipcode:
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
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let trimmedCity = city.trimmingCharacters(in: .whitespaces)
        let trimmedState = state.trimmingCharacters(in: .whitespaces)
        let trimmedZipcode = zipcode.trimmingCharacters(in: .whitespaces)

        let info = CustomerInfo(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
            address: trimmedAddress.isEmpty ? nil : trimmedAddress,
            city: trimmedCity.isEmpty ? nil : trimmedCity,
            state: trimmedState.isEmpty ? nil : trimmedState,
            zipcode: trimmedZipcode.isEmpty ? nil : trimmedZipcode
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
