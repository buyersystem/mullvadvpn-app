//
//  RESTRequestHandler.swift
//  MullvadVPN
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol RESTRequestHandler {
    associatedtype Success

    func createURLRequest(endpoint: AnyIPEndpoint) -> Result<URLRequest, REST.Error>
    func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error>
    func getAuthorizationProvider() -> RESTAuthorizationProvider?
}

extension REST {
    class AnyRequestHandler<Success>: RESTRequestHandler {
        typealias CreateURLRequestBlock = (AnyIPEndpoint) -> Result<URLRequest, REST.Error>
        typealias HandleURLResponseBlock = (HTTPURLResponse, Data) -> Result<Success, REST.Error>
        typealias GetAuthorizationProviderBlock = () -> RESTAuthorizationProvider?

        private let _createURLRequest: CreateURLRequestBlock
        private let _handleURLResponse: HandleURLResponseBlock
        private let _getAuthorizationProvider: GetAuthorizationProviderBlock?

        init<T>(_ handler: T) where T: RESTRequestHandler, T.Success == Success {
            _createURLRequest = handler.createURLRequest
            _handleURLResponse = handler.handleURLResponse
            _getAuthorizationProvider = handler.getAuthorizationProvider
        }

        init(
            createURLRequest: @escaping CreateURLRequestBlock,
            handleURLResponse: @escaping HandleURLResponseBlock,
            getAuthorizationProvider: GetAuthorizationProviderBlock? = nil
        ) {
            _createURLRequest = createURLRequest
            _handleURLResponse = handleURLResponse
            _getAuthorizationProvider = getAuthorizationProvider
        }

        func createURLRequest(endpoint: AnyIPEndpoint) -> Result<URLRequest, REST.Error> {
            return _createURLRequest(endpoint)
        }

        func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error> {
            return _handleURLResponse(response, data)
        }

        func getAuthorizationProvider() -> RESTAuthorizationProvider? {
            return _getAuthorizationProvider?()
        }
    }

}
