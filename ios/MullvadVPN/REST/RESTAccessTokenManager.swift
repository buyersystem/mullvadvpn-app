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
        private var tokens = [String: AccessTokenData]()

        init(authenticationProxy: AuthenticationProxy) {
            proxy = authenticationProxy
            operationQueue.maxConcurrentOperationCount = 1
        }

        func getAccessToken(
            accountNumber: String,
            completionHandler: @escaping (OperationCompletion<REST.AccessTokenData, REST.Error>) -> Void
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

        fileprivate func getTokenData(accountNumber: String) -> REST.AccessTokenData? {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            return tokens[accountNumber]
        }

        fileprivate func setTokenData(accountNumber: String, tokenData: REST.AccessTokenData) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            tokens[accountNumber] = tokenData
        }
    }

}

fileprivate protocol RESTAccessTokenStore {
    func getTokenData(accountNumber: String) -> REST.AccessTokenData?
    func setTokenData(accountNumber: String, tokenData: REST.AccessTokenData)
}

extension REST {
    fileprivate class GetAccessTokenOperation: ResultOperation<REST.AccessTokenData, REST.Error> {
        private let logger = Logger(label: "REST.GetAccessTokenOperation")
        private let dispatchQueue: DispatchQueue
        private let proxy: AuthenticationProxy
        private let store: RESTAccessTokenStore
        private let accountNumber: String
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

                guard let tokenData = self.store.getTokenData(accountNumber: self.accountNumber),
                      tokenData.expiry > Date() else {
                          self.obtainAccessToken()
                          return
                      }

                self.finish(completion: .success(tokenData))
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
                    switch completion {
                    case .success(let tokenData):
                        self.store.setTokenData(accountNumber: self.accountNumber, tokenData: tokenData)

                    case .failure(let error):
                        self.logger.error(
                            chainedError: error,
                            message: "Failed to obtain access token."
                        )

                    case .cancelled:
                        break
                    }

                    self.finish(completion: completion)
                }
            }
        }
    }
}
