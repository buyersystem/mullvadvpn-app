//
//  RESTAccessTokenManager.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging
import UIKit

extension REST {

    final class AccessTokenManager: RESTAccessTokenStore {
        private let operationQueue = OperationQueue()
        private let dispatchQueue = DispatchQueue(label: "REST.AccessTokenManager.dispatchQueue")
        private let proxy: AuthenticationProxy
        private var tokens = [AccessToken]()

        init(authenticationProxy: AuthenticationProxy) {
            proxy = authenticationProxy
            operationQueue.maxConcurrentOperationCount = 1
        }

        func getAuthorization(
            accessToken: REST.AccessToken,
            completionHandler: @escaping (OperationCompletion<REST.Authorization, REST.AccessTokenManager.Error>) -> Void
        ) -> Cancellable
        {
            let operation = GetAuthorizationOperation(
                dispatchQueue: dispatchQueue,
                proxy: proxy,
                accessToken: accessToken,
                completionQueue: .main,
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }

        func getAccessToken(
            accountNumber: String,
            completionHandler: @escaping (OperationCompletion<REST.AccessToken, REST.AccessTokenManager.Error>) -> Void
        ) -> Cancellable
        {
            let operation = GetAccessTokenOperation(
                dispatchQueue: dispatchQueue,
                proxy: proxy,
                store: self,
                accountNumber: accountNumber,
                completionQueue: .main,
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }

        fileprivate func getAccessToken(accountNumber: String) -> REST.AccessToken? {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            return tokens.first { token in
                return token.accountNumber == accountNumber
            }
        }

        fileprivate func addAccessToken(accessToken: REST.AccessToken) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            let index = tokens.firstIndex { token in
                return token.accountNumber == accessToken.accountNumber
            }

            if let index = index {
                tokens[index] = accessToken
            } else {
                tokens.append(accessToken)
            }
        }
    }

    final class AccessToken {
        fileprivate let accountNumber: String
        fileprivate var value: String
        fileprivate var expiry: Date

        fileprivate init(accountNumber: String, data: AccessTokenData) {
            self.accountNumber = accountNumber
            self.value = data.accessToken
            self.expiry = data.expiry
        }

        fileprivate func update(_ data: AccessTokenData) {
            value = data.accessToken
            expiry = data.expiry
        }
    }

}

fileprivate protocol RESTAccessTokenStore {
    func getAccessToken(accountNumber: String) -> REST.AccessToken?
    func addAccessToken(accessToken: REST.AccessToken)
}

extension REST {
    fileprivate class GetAuthorizationOperation: ResultOperation<REST.Authorization, REST.AccessTokenManager.Error> {
        private let dispatchQueue: DispatchQueue
        private let proxy: AuthenticationProxy
        private let accessToken: AccessToken
        private let logger = Logger(label: "REST.GetAuthorizationOperation")
        private var proxyTask: Cancellable?

        init(
            dispatchQueue: DispatchQueue,
            proxy: AuthenticationProxy,
            accessToken: AccessToken,
            completionQueue: DispatchQueue?,
            completionHandler: CompletionHandler?
        )
        {
            self.dispatchQueue = dispatchQueue
            self.proxy = proxy
            self.accessToken = accessToken

            super.init(
                completionQueue: completionQueue,
                completionHandler: completionHandler
            )
        }

        override func main() {
            dispatchQueue.async {
                guard !self.isCancelled else {
                    self.finish(completion: .cancelled)
                    return
                }

                guard self.accessToken.expiry > Date() else {
                    self.refreshAccessToken()
                    return
                }

                self.finish(completion: .success(.accessToken(self.accessToken.value)))
            }
        }

        override func cancel() {
            super.cancel()

            dispatchQueue.async {
                self.proxyTask?.cancel()
                self.proxyTask = nil
            }
        }

        private func refreshAccessToken() {
            proxyTask = proxy.refreshAccessToken(accessToken: accessToken.value) { completion in
                self.dispatchQueue.async {
                    switch completion {
                    case .success(let tokenData):
                        self.accessToken.update(tokenData)

                    case .failure(let error):
                        self.logger.error(
                            chainedError: error,
                            message: "Failed to refresh access token."
                        )

                    case .cancelled:
                        break
                    }

                    let mappedCompletion = completion.map { tokenData -> REST.Authorization in
                        return .accessToken(tokenData.accessToken)
                    }.mapError { error -> AccessTokenManager.Error in
                        return .refreshToken(error)
                    }

                    self.finish(completion: mappedCompletion)
                }
            }
        }
    }

    fileprivate class GetAccessTokenOperation: ResultOperation<AccessToken, REST.AccessTokenManager.Error> {
        private let dispatchQueue: DispatchQueue
        private let proxy: AuthenticationProxy
        private let store: RESTAccessTokenStore
        private let accountNumber: String
        private let logger = Logger(label: "REST.GetAccessTokenOperation")
        private var proxyTask: Cancellable?

        init(
            dispatchQueue: DispatchQueue,
            proxy: AuthenticationProxy,
            store: RESTAccessTokenStore,
            accountNumber: String,
            completionQueue: DispatchQueue?,
            completionHandler: CompletionHandler?
        )
        {
            self.dispatchQueue = dispatchQueue
            self.proxy = proxy
            self.store = store
            self.accountNumber = accountNumber

            super.init(
                completionQueue: completionQueue,
                completionHandler: completionHandler
            )
        }

        override func main() {
            dispatchQueue.async {
                guard !self.isCancelled else {
                    self.finish(completion: .cancelled)
                    return
                }

                guard let accessToken = self.store.getAccessToken(accountNumber: self.accountNumber) else {
                    self.obtainAccessToken()
                    return
                }

                guard accessToken.expiry > Date() else {
                    self.refreshAccessToken(accessToken)
                    return
                }

                self.finish(completion: .success(accessToken))
            }
        }

        override func cancel() {
            super.cancel()

            dispatchQueue.async {
                self.proxyTask?.cancel()
                self.proxyTask = nil
            }
        }

        private func obtainAccessToken() {
            proxyTask = proxy.getAccessToken(accountNumber: accountNumber) { completion in
                self.dispatchQueue.async {
                    let mappedCompletion = completion
                        .map{ tokenData -> AccessToken in
                            let newToken = AccessToken(
                                accountNumber: self.accountNumber,
                                data: tokenData
                            )

                            self.store.addAccessToken(accessToken: newToken)

                            return newToken
                        }
                        .mapError { error -> REST.AccessTokenManager.Error in
                            self.logger.error(
                                chainedError: error,
                                message: "Failed to obtain access token."
                            )

                            return .obtainToken(error)
                        }

                    self.finish(completion: mappedCompletion)
                }
            }
        }

        private func refreshAccessToken(_ accessToken: AccessToken) {
            proxyTask = proxy.refreshAccessToken(accessToken: accessToken.value) { completion in
                self.dispatchQueue.async {
                    let mappedCompletion = completion
                        .map { tokenData -> AccessToken in
                            accessToken.update(tokenData)

                            return accessToken
                        }
                        .mapError { error -> REST.AccessTokenManager.Error in
                            self.logger.error(
                                chainedError: error,
                                message: "Failed to refresh access token."
                            )

                            return .refreshToken(error)
                        }

                    self.finish(completion: mappedCompletion)
                }
            }
        }
    }
}


extension REST.AccessTokenManager {
    enum Error: ChainedError {
        case obtainToken(REST.Error)
        case refreshToken(REST.Error)

        var errorDescription: String? {
            switch self {
            case .obtainToken:
                return "Failure to obtain access token."
            case .refreshToken:
                return "Failure to refresh access token."
            }
        }
    }
}
