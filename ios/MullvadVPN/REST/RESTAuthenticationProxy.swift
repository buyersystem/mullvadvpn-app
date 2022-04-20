//
//  RESTAuthenticationProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    class AuthenticationProxy {
        typealias CompletionHandler<Success> = (OperationCompletion<Success, REST.Error>) -> Void

        private let requestFactory = REST.RequestFactory(
            hostname: ApplicationConfiguration.defaultAPIHostname,
            pathPrefix: "/auth/v1-beta1",
            networkTimeout: ApplicationConfiguration.defaultAPINetworkTimeout
        )

        private let operationQueue = OperationQueue()
        private let dispatchQueue = DispatchQueue(label: "REST.AuthenticationProxy.Queue")
        private let configuration: ProxyConfiguration

        init(configuration: ProxyConfiguration) {
            self.configuration = configuration
        }

        func getAccessToken(accountNumber: String, completion: @escaping CompletionHandler<AccessTokenData>) -> Cancellable {
            let request = NewAccessTokenRequest(accountNumber: accountNumber)

            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "/token"
                    )

                    do {
                        try requestBuilder.setHTTPBody(value: request)

                        return .success(requestBuilder.getURLRequest())
                    } catch {
                        return .failure(.encodePayload(error))
                    }
                },
                handleURLResponse: { response, data -> Result<AccessTokenData, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return ResponseHandling.decodeSuccessResponse(AccessTokenData.self, from: data)
                    } else {
                        return ResponseHandling.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "get-access-token",
                retryStrategy: .default,
                requestHandler: requestHandler,
                completionHandler: completion
            )
        }

        // MARK: - Private

        private func scheduleOperation<RequestHandler>(
            name: String,
            retryStrategy: REST.RetryStrategy,
            requestHandler: RequestHandler,
            completionHandler: @escaping NetworkOperation<RequestHandler.Success>.CompletionHandler
        ) -> Cancellable where RequestHandler: RESTRequestHandler
        {
            let operation = NetworkOperation(
                name: getTaskIdentifier(name: name),
                dispatchQueue: dispatchQueue,
                configuration: configuration,
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }
    }

    struct AccessTokenData: Decodable {
        let accessToken: String
        let expiry: Date
    }

    fileprivate struct NewAccessTokenRequest: Encodable {
        let accountNumber: String
    }
}
