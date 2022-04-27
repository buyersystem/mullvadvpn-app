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

        func createAccount(
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<AccountData>
        ) -> Cancellable {
            let requestHandler = AnyRequestHandler { endpoint in
                let request = self.requestFactory.createURLRequest(
                    endpoint: endpoint,
                    method: .post,
                    path: "accounts"
                )
                return .success(request)
            }

            let responseHandler = AnyResponseHandler { response, data -> Result<AccountData, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(AccountData.self, from: data)
                } else {
                    let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                        from: data,
                        errorLogger: self.logger
                    )

                    return .failure(.unhandledResponse(response.statusCode, serverResponse))
                }
            }

            return addOperation(
                name: "create-account",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        func getAccountData(
            accountNumber: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<AccountData>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: "accounts/me"
                    )

                    requestBuilder.setAuthorization(authorization)

                    return .success(requestBuilder.getURLRequest())
                },
                requestAuthorization: { completion in
                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { operationCompletion in
                            completion(operationCompletion.map { tokenData in
                                return .accessToken(tokenData.accessToken)
                            })
                        }
                }
            )

            let responseHandler = AnyResponseHandler { response, data -> Result<AccountData, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(AccountData.self, from: data)
                } else {
                    let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                        from: data,
                        errorLogger: self.logger
                    )

                    return .failure(.unhandledResponse(response.statusCode, serverResponse))
                }
            }

            return addOperation(
                name: "get-my-account",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }
    }

    struct AccountData: Decodable {
        let id: String
        let number: String
        let expiry: Date
        let maxPorts: Int
        let canAddPorts: Bool
        let maxDevices: Int
        let canAddDevices: Bool
    }
}
