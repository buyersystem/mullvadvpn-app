//
//  RESTAccountsProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    class AccountsProxy: Proxy<AuthProxyConfiguration> {
        init(configuration: AuthProxyConfiguration) {
            super.init(
                name: "AccountsProxy",
                pathPrefix: "/accounts/v1-beta1",
                configuration: configuration
            )
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
                },
                getAuthorizationProvider: {
                    return REST.AccessTokenAuthorizationProvider(
                        accountNumber: accountNumber,
                        accessTokenManager: self.configuration.accessTokenManager
                    )
                }
            )

            return addOperation(
                name: "get-my-account",
                retryStrategy: .default,
                requestHandler: requestHandler,
                completionHandler: completion
            )
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
