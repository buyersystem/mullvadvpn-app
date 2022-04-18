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
        private let session: URLSession
        private let addressCacheStore: AddressCache.Store

        init(session: URLSession, addressCacheStore: AddressCache.Store) {
            self.session = session
            self.addressCacheStore = addressCacheStore
        }

        func getMyAccount(completion: @escaping CompletionHandler<BetaAccountResponse>) -> Cancellable {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    let requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "/accounts/me"
                    )

                    // TODO: Add account token into header!

                    completion(.success(requestBuilder.getURLRequest()))
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
                urlSession: session,
                addressCacheStore: addressCacheStore,
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }
    }

    struct BetaAccountResponse: Decodable {
        let number: String
        let isActive: Bool
        let expiry: Date
        let maxPorts: Int
        let canAdPorts: Bool
        let maxDevices: Int
        let canAddDevices: Bool
    }
}
