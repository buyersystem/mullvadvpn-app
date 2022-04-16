//
//  RESTClient.swift
//  MullvadVPN
//
//  Created by pronebird on 10/07/2020.
//  Copyright © 2020 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Network
import class WireGuardKitTypes.PublicKey
import struct WireGuardKitTypes.IPAddressRange

extension REST {

    class Client {
        typealias CompletionHandler<Success> = (OperationCompletion<Success, REST.Error>) -> Void

        static let shared: Client = {
            return Client(addressCacheStore: AddressCache.Store.shared)
        }()

        /// URL session.
        private let session: URLSession

        /// URL session delegate.
        private let sessionDelegate: SSLPinningURLSessionDelegate

        /// Address cache store.
        private let addressCacheStore: AddressCache.Store

        /// REST request factory.
        private let requestFactory = REST.RequestFactory(
            hostname: ApplicationConfiguration.defaultAPIHostname,
            pathPrefix: "/app/v1",
            networkTimeout: 10
        )

        /// Operation queue used for running network requests.
        private let operationQueue = OperationQueue()

        /// Serial dispatch queue used by operations.
        private let dispatchQueue = DispatchQueue(label: "REST.Client.Queue")

        /// Network task counter.
        private var networkTaskCounter: UInt32 = 0

        /// Returns array of trusted root certificates
        private static var trustedRootCertificates: [SecCertificate] {
            let rootCertificate = Bundle.main.path(forResource: "le_root_cert", ofType: "cer")!

            return [rootCertificate].map { (path) -> SecCertificate in
                let data = FileManager.default.contents(atPath: path)!
                return SecCertificateCreateWithData(nil, data as CFData)!
            }
        }

        init(addressCacheStore: AddressCache.Store) {
            sessionDelegate = SSLPinningURLSessionDelegate(
                sslHostname: ApplicationConfiguration.defaultAPIHostname,
                trustedRootCertificates: Self.trustedRootCertificates
            )
            session = URLSession(
                configuration: .ephemeral,
                delegate: sessionDelegate,
                delegateQueue: nil
            )
            self.addressCacheStore = addressCacheStore
        }

        // MARK: - Public

        func createAccount(
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<AccountResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    let request = self.requestFactory.createURLRequest(
                        endpoint: endpoint,
                        method: .post,
                        path: "accounts"
                    )

                    completion(.success(request))
                },
                handleURLResponse: { response, data -> Result<AccountResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return Self.decodeSuccessResponse(AccountResponse.self, from: data)
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "create-account",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func getAddressList(
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<[AnyIPEndpoint]>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    return self.requestFactory.createURLRequest(
                        endpoint: endpoint,
                        method: .get,
                        path: "api-addrs"
                    )
                },
                handleURLResponse: { response, data -> Result<[AnyIPEndpoint], REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return Self.decodeSuccessResponse([AnyIPEndpoint].self, from: data)
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "get-api-addrs",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func getRelays(
            etag: String?,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<ServerRelaysCacheResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: "relays"
                    )

                    if let etag = etag {
                        requestBuilder.setETagHeader(etag: etag)
                    }

                    return requestBuilder.getURLRequest()
                },
                handleURLResponse: { response, data -> Result<ServerRelaysCacheResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return Self.decodeSuccessResponse(ServerRelaysResponse.self, from: data)
                            .map { serverRelays in
                                let newEtag = response.value(forCaseInsensitiveHTTPHeaderField: HTTPHeader.etag)
                                return .newContent(newEtag, serverRelays)
                            }
                    } else if response.statusCode == HTTPStatus.notModified && etag != nil {
                        return .success(.notModified)
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "get-relays",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func getAccountExpiry(
            token: String,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<AccountResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .get,
                            path: "me"
                        )
                    requestBuilder.setAuthorization(.accountNumber(token))

                    return requestBuilder.getURLRequest()
                },
                handleURLResponse: { response, data -> Result<AccountResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return Self.decodeSuccessResponse(AccountResponse.self, from: data)
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "get-account-expiry",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func getWireguardKey(
            token: String,
            publicKey: PublicKey,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<WireguardAddressesResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    let urlEncodedPublicKey = publicKey.base64Key
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                    let path = "wireguard-keys/".appending(urlEncodedPublicKey)

                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .get,
                            path: path
                        )
                    requestBuilder.setAuthorization(.accountNumber(token))

                    return requestBuilder.getURLRequest()
                },
                handleURLResponse: { response, data -> Result<WireguardAddressesResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return Self.decodeSuccessResponse(WireguardAddressesResponse.self, from: data)
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "get-wireguard-key",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func pushWireguardKey(
            token: String,
            publicKey: PublicKey,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<WireguardAddressesResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "wireguard-keys"
                    )
                    requestBuilder.setAuthorization(.accountNumber(token))

                    do {
                        let body = PushWireguardKeyRequest(
                            pubkey: publicKey.rawValue
                        )
                        try requestBuilder.setHTTPBody(value: body)
                        completion(.success(requestBuilder.getURLRequest()))
                    } catch {
                        completion(.failure(.encodePayload(error)))
                    }
                },
                handleURLResponse: { response, data -> Result<WireguardAddressesResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return Self.decodeSuccessResponse(WireguardAddressesResponse.self, from: data)
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "push-wireguard-key",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func replaceWireguardKey(
            token: String,
            oldPublicKey: PublicKey,
            newPublicKey: PublicKey,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<WireguardAddressesResponse>
        ) -> Cancellable {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "replace-wireguard-key"
                    )
                    requestBuilder.setAuthorization(.accountNumber(token))

                    do {
                        let body = ReplaceWireguardKeyRequest(
                            old: oldPublicKey.rawValue,
                            new: newPublicKey.rawValue
                        )
                        try requestBuilder.setHTTPBody(value: body)

                        completion(.success(requestBuilder.getURLRequest()))
                    } catch {
                        completion(.failure(.encodePayload(error)))
                    }
                },
                handleURLResponse: { response, data -> Result<WireguardAddressesResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return Self.decodeSuccessResponse(WireguardAddressesResponse.self, from: data)
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "replace-wireguard-key",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func deleteWireguardKey(
            token: String,
            publicKey: PublicKey,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<Void>
        ) -> Cancellable {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    let urlEncodedPublicKey = publicKey.base64Key
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

                    let path = "wireguard-keys/".appending(urlEncodedPublicKey)
                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .delete,
                            path: path
                        )
                    requestBuilder.setAuthorization(.accountNumber(token))

                    return requestBuilder.getURLRequest()
                },
                handleURLResponse: { response, data -> Result<Void, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return .success(())
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )
            return scheduleOperation(
                name: "delete-wireguard-key",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func createApplePayment(
            token: String,
            receiptString: Data,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<CreateApplePaymentResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .post,
                            path: "create-apple-payment"
                        )
                    requestBuilder.setAuthorization(.accountNumber(token))

                    do {
                        let body = CreateApplePaymentRequest(receiptString: receiptString)
                        try requestBuilder.setHTTPBody(value: body)

                        completion(.success(requestBuilder.getURLRequest()))
                    } catch {
                        completion(.failure(.encodePayload(error)))
                    }
                },
                handleURLResponse: { response, data -> Result<CreateApplePaymentResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return REST.Client.decodeSuccessResponse(CreateApplePaymentRawResponse.self, from: data)
                            .map { (response) in
                                if response.timeAdded > 0 {
                                    return .timeAdded(response.timeAdded, response.newExpiry)
                                } else {
                                    return .noTimeAdded(response.newExpiry)
                                }
                            }
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )
            return scheduleOperation(
                name: "create-apple-payment",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        func sendProblemReport(
            _ body: ProblemReportRequest,
            retryStrategy: REST.RetryStrategy,
            completionHandler: @escaping CompletionHandler<Void>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "problem-report"
                    )

                    do {
                        try requestBuilder.setHTTPBody(value: body)

                        completion(.success(requestBuilder.getURLRequest()))
                    } catch {
                        completion(.failure(.encodePayload(error)))
                    }
                },
                handleURLResponse: { response, data -> Result<Void, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return .success(())
                    } else {
                        return Self.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "send-problem-report",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )
        }

        // MARK: - Private

        private func nextTaskIdentifier() -> UInt32 {
            return dispatchQueue.sync {
                let (partialValue, isOverflow) = networkTaskCounter.addingReportingOverflow(1)
                let nextValue = isOverflow ? 1 : partialValue
                networkTaskCounter = nextValue

                return nextValue
            }
        }

        private func scheduleOperation<RequestHandler>(
            name: String,
            retryStrategy: REST.RetryStrategy,
            requestHandler: RequestHandler,
            completionHandler: @escaping NetworkOperation<RequestHandler.Success>.CompletionHandler
        ) -> Cancellable where RequestHandler: RESTRequestHandler
        {
            let operation = NetworkOperation(
                taskIdentifier: nextTaskIdentifier(),
                name: name,
                dispatchQueue: dispatchQueue,
                urlSession: session,
                addressCacheStore: addressCacheStore,
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }

        private func dataTask(request: URLRequest, completion: @escaping (Result<(HTTPURLResponse, Data), URLError>) -> Void) -> URLSessionDataTask {
            return self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    let urlError = error as? URLError ?? URLError(.unknown)

                    completion(.failure(urlError))
                } else {
                    if let httpResponse = response as? HTTPURLResponse {
                        let data = data ?? Data()
                        let value = (httpResponse, data)

                        completion(.success(value))
                    } else {
                        completion(.failure(URLError(.unknown)))
                    }
                }
            }
        }

        /// Parse JSON response into the given `Decodable` type.
        private static func decodeSuccessResponse<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, REST.Error> {
            return Result { try REST.Coding.makeJSONDecoder().decode(type, from: data) }
            .mapError { error in
                return .decodeSuccessResponse(error)
            }
        }

        /// Parse JSON response in case of error (Any HTTP code except 2xx).
        private static func decodeErrorResponse(from data: Data) -> Result<ServerErrorResponse, REST.Error> {
            return Result { () -> ServerErrorResponse in
                return try REST.Coding.makeJSONDecoder().decode(ServerErrorResponse.self, from: data)
            }.mapError { error in
                return .decodeErrorResponse(error)
            }
        }

        private static func decodeErrorResponseAndMapToServerError<T>(from data: Data) -> Result<T, REST.Error> {
            return Self.decodeErrorResponse(from: data)
                .flatMap { serverError in
                    return .failure(.server(serverError))
                }
        }

        private static func mapNetworkError(_ error: URLError) -> REST.Error {
            return .network(error)
        }
    }

    // MARK: - Response types

    struct AccountResponse: Decodable {
        let token: String
        let expires: Date
    }

    enum ServerRelaysCacheResponse {
        case notModified
        case newContent(_ etag: String?, _ value: ServerRelaysResponse)
    }

    struct WireguardAddressesResponse: Decodable {
        let id: String
        let pubkey: Data
        let ipv4Address: IPAddressRange
        let ipv6Address: IPAddressRange
    }

    fileprivate struct PushWireguardKeyRequest: Encodable {
        let pubkey: Data
    }

    fileprivate struct ReplaceWireguardKeyRequest: Encodable {
        let old: Data
        let new: Data
    }

    fileprivate struct CreateApplePaymentRequest: Encodable {
        let receiptString: Data
    }

    enum CreateApplePaymentResponse {
        case noTimeAdded(_ expiry: Date)
        case timeAdded(_ timeAdded: Int, _ newExpiry: Date)

        var newExpiry: Date {
            switch self {
            case .noTimeAdded(let expiry), .timeAdded(_, let expiry):
                return expiry
            }
        }

        var timeAdded: TimeInterval {
            switch self {
            case .noTimeAdded:
                return 0
            case .timeAdded(let timeAdded, _):
                return TimeInterval(timeAdded)
            }
        }

        /// Returns a formatted string for the `timeAdded` interval, i.e "30 days"
        var formattedTimeAdded: String? {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day, .hour]
            formatter.unitsStyle = .full

            return formatter.string(from: self.timeAdded)
        }
    }

    fileprivate struct CreateApplePaymentRawResponse: Decodable {
        let timeAdded: Int
        let newExpiry: Date
    }

    struct ProblemReportRequest: Encodable {
        let address: String
        let message: String
        let log: String
        let metadata: [String: String]
    }

}
