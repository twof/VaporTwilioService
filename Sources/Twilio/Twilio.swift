import Vapor

public protocol TwilioProvider {
    func send(_ sms: OutgoingSMS) -> EventLoopFuture<ClientResponse>
}

public struct Twilio: TwilioProvider {
    let application: Application
    
    public init (_ app: Application) {
        application = app
    }
}

// MARK: - Configuration

extension Twilio {
    struct ConfigurationKey: StorageKey {
        typealias Value = TwilioConfiguration
    }

    public var configuration: TwilioConfiguration? {
        get {
            application.storage[ConfigurationKey.self]
        }
        nonmutating set {
            application.storage[ConfigurationKey.self] = newValue
        }
    }
}

// MARK: Send message

extension Twilio {
    /// Send sms
    ///
    /// - Parameters:
    ///   - content: outgoing sms
    ///   - container: Container
    /// - Returns: Future<Response>
    public func send(_ sms: OutgoingSMS) -> EventLoopFuture<ClientResponse> {
        guard let configuration = self.configuration else {
            fatalError("Twilio not configured. Use app.twilio.configuration = ...")
        }
        
        return application.eventLoopGroup.future().flatMapThrowing { _ -> HTTPHeaders in
            let authKeyEncoded = try self.encode(accountId: configuration.accountId, accountSecret: configuration.accountSecret)
            var headers = HTTPHeaders()
            headers.add(name: .authorization, value: "Basic \(authKeyEncoded)")
            return headers
        }.flatMap { headers in
            let twilioURI = URI(string: "https://api.twilio.com/2010-04-01/Accounts/\(configuration.accountId)/Messages.json")
            return self.application.client.post(twilioURI, headers: headers) {
                try $0.content.encode(sms, as: .urlEncodedForm)
            }
        }
    }

    /// Lookup phone number
    ///
    /// - Parameters:
    ///   - number: The number to look up
    /// - Returns: EventLoopFuture<LookupResponse>
    public func lookup(_ number: String) -> EventLoopFuture<LookupResponse> {
        guard let configuration = self.configuration else {
            fatalError("Twilio not configured. Use app.twilio.configuration = ...")
        }

        return application.eventLoopGroup.future().flatMapThrowing { _ -> HTTPHeaders in
            let authKeyEncoded = try self.encode(accountId: configuration.accountId, accountSecret: configuration.accountSecret)
            var headers = HTTPHeaders()
            headers.add(name: .authorization, value: "Basic \(authKeyEncoded)")
            return headers
        }.flatMap { headers in
            let trimmedNumber = number.filter { !$0.isWhitespace }
            let twilioURI = URI(string: "https://lookups.twilio.com/v1/PhoneNumbers/\(trimmedNumber)?Type=carrier")
            return self.application.client.get(twilioURI, headers: headers).flatMapThrowing { response in
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                do {
                    return try response.content.decode(LookupResponse.self, using: decoder)
                } catch {
                    throw Abort(.notFound, reason: "The requested resource \(number) was not found.")
                }

            }
        }
    }

    public func respond(with response: SMSResponse) -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/xml")
        return Response(status: .ok, headers: headers, body: .init(string: response.generateTwiml()))
    }
}

// MARK: Private

fileprivate extension Twilio {

    func encode(accountId: String, accountSecret: String) throws -> String {
        guard let apiKeyData = "\(accountId):\(accountSecret)".data(using: .utf8) else {
            throw TwilioError.encodingProblem
        }
        let authKey = apiKeyData.base64EncodedData()
        guard let authKeyEncoded = String.init(data: authKey, encoding: .utf8) else {
            throw TwilioError.encodingProblem
        }

        return authKeyEncoded
    }
}

extension Application {
    public var twilio: Twilio { .init(self) }
}

extension Request {
    public var twilio: Twilio { .init(application) }
}
