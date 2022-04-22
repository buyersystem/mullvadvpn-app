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
                configuration: configuration,
                requestFactory: RequestFactory.withDefaultAPICredentials(
                    pathPrefix: "/accounts/v1-beta1",
                    bodyEncoder: Coding.makeJSONEncoder(type: .beta)
                ),
                responseDecoder: ResponseDecoder(
                    decoder: Coding.makeJSONDecoder(type: .beta)
                )
            )
        }

        func getMyAccount(
            accountNumber: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<BetaAccountResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: "/accounts/me"
                    )
                    
                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { tokenCompletion in
                            let requestCompletion = tokenCompletion.map { tokenData -> URLRequest in
                                requestBuilder.setAuthorization(.accessToken(tokenData.accessToken))
                                return requestBuilder.getURLRequest()
                            }
                            completion(requestCompletion)
                        }
                },
                handleURLResponse: { response, data -> Result<BetaAccountResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return self.responseDecoder.decodeSuccessResponse(BetaAccountResponse.self, from: data)
                    } else {
                        return self.responseDecoder.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return addOperation(
                name: "get-my-account",
                retryStrategy: retryStrategy,
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
