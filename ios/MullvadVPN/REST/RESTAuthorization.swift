//
//  RESTAuthorization.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol RESTAuthorizationProvider {
    typealias Completion = (OperationCompletion<REST.Authorization, REST.Error>) -> Void

    func getAuthorization(_ completion: @escaping Completion) -> Cancellable
}

extension REST {
    enum Authorization {
        case accountNumber(String)
        case accessToken(String)
    }

    struct AccessTokenAuthorizationProvider: RESTAuthorizationProvider {
        private let accountNumber: String
        private let accessTokenManager: REST.AccessTokenManager

        init(accountNumber: String, accessTokenManager: REST.AccessTokenManager) {
            self.accountNumber = accountNumber
            self.accessTokenManager = accessTokenManager
        }

        func getAuthorization(_ completionHandler: @escaping Completion) -> Cancellable {
            return accessTokenManager.getAccessToken(accountNumber: accountNumber) { completion in
                let mappedCompletion = completion.map { tokenData -> REST.Authorization in
                    return .accessToken(tokenData.accessToken)
                }

                completionHandler(mappedCompletion)
            }
        }
    }
}
