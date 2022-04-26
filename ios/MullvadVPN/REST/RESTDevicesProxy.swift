//
//  RESTDevicesProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import class WireGuardKitTypes.PublicKey
import struct WireGuardKitTypes.IPAddressRange

extension REST {
    class DevicesProxy: Proxy<AuthProxyConfiguration> {
        init(configuration: AuthProxyConfiguration) {
            super.init(
                name: "DevicesProxy",
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

        /// Fetch device by identifier.
        /// The completion handler receives `nil` if device is not found.
        func getDevice(
            accountNumber: String,
            identifier: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<Device?>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    let urlEncodedIdentifier = identifier
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                    let path = "device/\(urlEncodedIdentifier)"

                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: path
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

            let responseHandler = AnyResponseHandler { response, data -> Result<Device?, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(Device.self, from: data)
                        .map { device in
                            return .some(device)
                        }
                } else if response.statusCode == HTTPStatus.notFound {
                    return .success(nil)
                } else {
                    return .failure(.server(.unhandledResponse(response.statusCode)))
                }
            }

            return addOperation(
                name: "get-device",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Fetch the list of created devices.
        func getDevices(
            accountNumber: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<[Device]>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: "devices"
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

            let responseHandler = REST.defaultResponseHandler(
                decoding: [Device].self,
                with: responseDecoder
            )

            return addOperation(
                name: "get-devices",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Create new device.
        /// The completion handler will receive a `CreateDeviceResponse.created(Device)` on success.
        /// Other `CreateDeviceResponse` variants describe errors.
        func createDevice(
            accountNumber: String,
            request: CreateDeviceRequest,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<CreateDeviceResponse>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "devices"
                    )

                    requestBuilder.setAuthorization(authorization)

                    return Result {
                        try requestBuilder.setHTTPBody(value: request)
                    }
                    .mapError { error in
                        return .encodePayload(error)
                    }
                    .map { _ in
                        return requestBuilder.getURLRequest()
                    }
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

            let responseHandler = AnyResponseHandler { response, data -> Result<CreateDeviceResponse, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(Device.self, from: data)
                        .map { device in
                            return .created(device)
                        }
                } else if response.statusCode == HTTPStatus.badRequest {
                    let serverResponse = try? self.responseDecoder
                        .decodeSuccessResponse(ServerErrorResponseV2.self, from: data)
                        .get()

                    if serverResponse?.code == "PUBKEY_IN_USE" {
                        return .success(.publicKeyInUse)
                    } else if serverResponse?.code == "MAX_DEVICES_REACHED" {
                        return .success(.maxDevicesReached)
                    }
                }

                return .failure(.server(.unhandledResponse(response.statusCode)))
            }

            return addOperation(
                name: "create-device",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Delete device by identifier.
        /// The completion handler will receive `true` if device is successfully removed,
        /// otherwise `false` if device is not found or already removed.
        func deleteDivice(
            accountNumber: String,
            identifier: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<Bool>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    let urlEncodedIdentifier = identifier
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                    let path = "devices/".appending(urlEncodedIdentifier)

                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .delete,
                            path: path
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

            let responseHandler = AnyResponseHandler { response, data -> Result<Bool, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return .success(true)
                } else if response.statusCode == HTTPStatus.notFound {
                    return .success(false)
                } else {
                    return .failure(.server(.unhandledResponse(response.statusCode)))
                }
            }

            return addOperation(
                name: "delete-device",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Rotate device key
        func rotateDeviceKey(
            accountNumber: String,
            identifier: String,
            publicKey: PublicKey,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<RotateDeviceKeyResponse>
        ) -> Cancellable {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    let urlEncodedIdentifier = identifier
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                    let path = "devices/\(urlEncodedIdentifier)/pubkey"

                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .put,
                            path: path
                        )

                    requestBuilder.setAuthorization(authorization)

                    return Result {
                        let request = RotateDeviceKeyRequest(
                            pubkey: publicKey.base64Key
                        )
                        try requestBuilder.setHTTPBody(value: request)
                    }
                    .mapError { error in
                        return .encodePayload(error)
                    }
                    .map { _ in
                        return requestBuilder.getURLRequest()
                    }
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

            let responseHandler = AnyResponseHandler { response, data -> Result<RotateDeviceKeyResponse, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(Device.self, from: data)
                        .map { device in
                            return .succeeded(device)
                        }
                } else if response.statusCode == HTTPStatus.badRequest {
                    let serverResponse = try? self.responseDecoder
                        .decodeSuccessResponse(ServerErrorResponseV2.self, from: data)
                        .get()

                    if serverResponse?.code == "PUBKEY_IN_USE" {
                        return .success(.publicKeyInUse)
                    }
                } else if response.statusCode == HTTPStatus.notFound {
                    return .success(.deviceNotFound)
                }

                return .failure(.server(.unhandledResponse(response.statusCode)))
            }

            return addOperation(
                name: "rotate-device-key",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

    }

    struct CreateDeviceRequest: Encodable {
        let pubkey: String
        let hijackDNS: Bool

        private enum CodingKeys: String, CodingKey {
            case hijackDNS = "hijackDns"
            case pubkey
        }
    }

    enum CreateDeviceResponse {
        case created(Device)
        case publicKeyInUse // PUBKEY_IN_USE
        case maxDevicesReached // MAX_DEVICES_REACHED
    }

    enum RotateDeviceKeyResponse {
        case succeeded(Device)
        case deviceNotFound
        case publicKeyInUse // PUBKEY_IN_USE
    }

    struct ServerErrorResponseV2: Decodable {
        let code: String
        let detail: String?
    }

    fileprivate struct RotateDeviceKeyRequest: Encodable {
        let pubkey: String
    }

    struct Device: Decodable {
        let id: String
        let name: String
        let pubkey: Data
        let hijackDNS: Bool
        let created: Date
        let ipv4Address: IPAddressRange
        let ipv6Address: IPAddressRange
        let ports: [Port]

        private enum CodingKeys: String, CodingKey {
            case hijackDNS = "hijackDns"
            case id, name, pubkey, created, ipv4Address, ipv6Address, ports
        }
    }

    struct Port: Decodable {
        let id: String
    }

}
