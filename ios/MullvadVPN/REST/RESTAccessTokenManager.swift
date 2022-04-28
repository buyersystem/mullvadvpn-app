//
//  RESTAccessTokenManager.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging

extension REST {

    final class AccessTokenManager {
        private let logger = Logger(label: "REST.AccessTokenManager")
        private let operationQueue = OperationQueue()
        private let dispatchQueue = DispatchQueue(label: "REST.AccessTokenManager.dispatchQueue")
        private let proxy: AuthenticationProxy
        private var tokens = [String: AccessTokenData]()

        init(authenticationProxy: AuthenticationProxy) {
            operationQueue.name = "REST.AccessTokenManager.operationQueue"
            operationQueue.maxConcurrentOperationCount = 1
            operationQueue.underlyingQueue = dispatchQueue
            proxy = authenticationProxy
        }

        func getAccessToken(
            accountNumber: String,
            completionHandler: @escaping (OperationCompletion<REST.AccessTokenData, REST.Error>) -> Void
        ) -> Cancellable
        {
            let operation = ResultBlockOperation<REST.AccessTokenData, REST.Error> { operation in
                if let tokenData = self.tokens[accountNumber], tokenData.expiry > Date() {
                    operation.finish(completion: .success(tokenData))
                    return
                }

                let task = self.proxy.getAccessToken(accountNumber: accountNumber) { completion in
                    self.dispatchQueue.async {
                        switch completion {
                        case .success(let tokenData):
                            self.tokens[accountNumber] = tokenData

                        case .failure(let error):
                            self.logger.error(chainedError: error, message: "Failed to fetch access token.")

                        case .cancelled:
                            break
                        }

                        operation.finish(completion: completion)
                    }
                }

                operation.addCancellationBlock {
                    task.cancel()
                }
            }

            operation.completionQueue = .main
            operation.completionHandler = { completion in
                completionHandler(completion)
            }

            operationQueue.addOperation(operation)

            return operation
        }
    }

}
