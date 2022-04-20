//
//  RESTAccountsProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    class AccountsProxy {
        typealias CompletionHandler<Success> = (OperationCompletion<Success, REST.Error>) -> Void

        private let requestFactory = REST.RequestFactory(
            hostname: ApplicationConfiguration.defaultAPIHostname,
            pathPrefix: "/accounts/v1-beta1",
            networkTimeout: ApplicationConfiguration.defaultAPINetworkTimeout
        )

        private let operationQueue = OperationQueue()
        private let dispatchQueue = DispatchQueue(label: "REST.AccountsProxy.Queue")
        private let configuration: AuthProxyConfiguration

        init(configuration: AuthProxyConfiguration) {
            self.configuration = configuration
        }

        func getMyAccount(accountNumber: String, completion: @escaping CompletionHandler<BetaAccountResponse>) -> Cancellable {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    let request = self.requestFactory.createURLRequest(
                        endpoint: endpoint,
                        method: .post,
                        path: "/accounts/me"
                    )
                    return .success(request)
                },
                handleURLResponse: { response, data -> Result<BetaAccountResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return ResponseHandling.decodeSuccessResponse(BetaAccountResponse.self, from: data)
                    } else {
                        return ResponseHandling.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return scheduleOperation(
                name: "get-my-account",
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

    struct BetaAccountResponse: Decodable {
        let id: String
        let number: String
        let prettyNumber: String
        let isActive: Bool
        let expiry: Date
        let maxPorts: Int
        let canAdPorts: Bool
        let maxDevices: Int
        let canAddDevices: Bool
    }
}
