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
                    bodyEncoder: Coding.makeJSONEncoder()
                ),
                responseDecoder: ResponseDecoder(
                    decoder: Coding.makeJSONDecoder()
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
                createURLRequest: { endpoint, authorization in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: "/accounts/me"
                    )

                    requestBuilder.setAuthorization(authorization!)

                    return .success(requestBuilder.getURLRequest())
                },
                requestAuthorization: { completion in
                    let task = self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { operationCompletion in
                            completion(operationCompletion.map { REST.Authorization.accessToken($0.accessToken) })
                        }

                    return .pending(task)
                },
                handleURLResponse: { response, data -> Result<BetaAccountResponse, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return self.responseDecoder.decodeSuccessResponse(BetaAccountResponse.self, from: data)
                    } else {
                        return self.responseDecoder.decodeErrorResponseAndMapToServerError(from: data, response: response)
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
        let expiry: Date
        let maxPorts: Int
        let canAddPorts: Bool
        let maxDevices: Int
        let canAddDevices: Bool
    }
}
