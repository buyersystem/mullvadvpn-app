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

    func createURLRequest(
        endpoint: AnyIPEndpoint,
        completion: @escaping (OperationCompletion<URLRequest, REST.Error>) -> Void
    ) -> Cancellable

    func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error>
}

extension REST {
    class AnyRequestHandler<Success>: RESTRequestHandler {
        typealias CreateURLRequestBlock = (
            AnyIPEndpoint, @escaping (OperationCompletion<URLRequest, REST.Error>) -> Void
        ) -> Cancellable

        typealias HandleURLResponseBlock = (HTTPURLResponse, Data) -> Result<Success, REST.Error>

        private let _createURLRequest: CreateURLRequestBlock
        private let _handleURLResponse: HandleURLResponseBlock

        init<T>(_ handler: T) where T: RESTRequestHandler, T.Success == Success {
            _createURLRequest = handler.createURLRequest
            _handleURLResponse = handler.handleURLResponse
        }

        init(
            createURLRequest: @escaping CreateURLRequestBlock,
            handleURLResponse: @escaping HandleURLResponseBlock
        ) {
            _createURLRequest = createURLRequest
            _handleURLResponse = handleURLResponse
        }

        func createURLRequest(
            endpoint: AnyIPEndpoint,
            completion: @escaping (OperationCompletion<URLRequest, REST.Error>) -> Void
        ) -> Cancellable {
            return _createURLRequest(endpoint, completion)
        }

        func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error> {
            return _handleURLResponse(response, data)
        }
    }

}
