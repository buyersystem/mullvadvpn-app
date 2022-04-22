//
//  RESTAuthenticationProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    class AuthenticationProxy: Proxy<ProxyConfiguration> {
        init(configuration: ProxyConfiguration) {
            super.init(
                name: "AuthenticationProxy",
                configuration: configuration,
                requestFactory: RequestFactory.withDefaultAPICredentials(
                    pathPrefix: "/auth/v1-beta1",
                    bodyEncoder: Coding.makeJSONEncoder(type: .beta)
                ),
                responseDecoder: ResponseDecoder(
                    decoder: Coding.makeJSONDecoder(type: .beta)
                )
            )
        }

        func getAccessToken(
            accountNumber: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<AccessTokenData>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "/token"
                    )

                    do {
                        let request = AccessTokenRequest(accountNumber: accountNumber)
                        try requestBuilder.setHTTPBody(value: request)

                        completion(.success(requestBuilder.getURLRequest()))
                    } catch {
                        completion(.failure(.encodePayload(error)))
                    }

                    return EmptyCancellable()
                },
                handleURLResponse: { response, data -> Result<AccessTokenData, REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return self.responseDecoder.decodeSuccessResponse(AccessTokenData.self, from: data)
                    } else {
                        return self.responseDecoder.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return addOperation(
                name: "get-access-token",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completion
            )
        }
    }

    struct AccessTokenData: Decodable {
        let accessToken: String
        let expiry: Date
    }

    fileprivate struct AccessTokenRequest: Encodable {
        let accountNumber: String
    }
}
