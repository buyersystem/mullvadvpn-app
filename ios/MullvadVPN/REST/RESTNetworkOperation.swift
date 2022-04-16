//
//  NetworkOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 08/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging

protocol RESTRequestHandler {
    associatedtype Success

    func createURLRequest(endpoint: AnyIPEndpoint, completionHandler: @escaping (Result<URLRequest, REST.Error>) -> Void)
    func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error>
}

extension REST {
    class AnyRequestHandler<Success>: RESTRequestHandler {
        typealias CreateURLRequestBlock = (AnyIPEndpoint, @escaping (Result<URLRequest, REST.Error>) -> Void) -> Void
        typealias CreateURLRequestNonFallibleBlock = (AnyIPEndpoint) -> URLRequest
        typealias HandleURLResponseBlock = (HTTPURLResponse, Data) -> Result<Success, REST.Error>

        private let _createURLRequest: CreateURLRequestBlock
        private let _handleURLResponse: HandleURLResponseBlock

        init<T>(_ handler: T) where T: RESTRequestHandler, T.Success == Success {
            _createURLRequest = handler.createURLRequest
            _handleURLResponse = handler.handleURLResponse
        }

        init(createURLRequest: @escaping CreateURLRequestBlock, handleURLResponse: @escaping HandleURLResponseBlock) {
            _createURLRequest = createURLRequest
            _handleURLResponse = handleURLResponse
        }

        init(createURLRequest: @escaping CreateURLRequestNonFallibleBlock, handleURLResponse: @escaping HandleURLResponseBlock) {
            _createURLRequest = { endpoint, completion in
                completion(.success(createURLRequest(endpoint)))
            }
            _handleURLResponse = handleURLResponse
        }

        func createURLRequest(endpoint: AnyIPEndpoint, completionHandler: @escaping (Result<URLRequest, REST.Error>) -> Void) {
            _createURLRequest(endpoint, completionHandler)
        }

        func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error> {
            return _handleURLResponse(response, data)
        }
    }

    class NetworkOperation<Success>: ResultOperation<Success, REST.Error> {
        private let requestHandler: AnyRequestHandler<Success>
        private let dispatchQueue: DispatchQueue
        private let urlSession: URLSession
        private let addressCacheStore: AddressCache.Store

        private var task: URLSessionTask?

        private let retryStrategy: RetryStrategy
        private var retryTimer: DispatchSourceTimer?
        private var retryCount = 0

        private let logger = Logger(label: "REST.NetworkOperation")
        private let loggerMetadata: Logger.Metadata


        init<T>(
            taskIdentifier: UInt32,
            name: String,
            dispatchQueue: DispatchQueue,
            urlSession: URLSession,
            addressCacheStore: AddressCache.Store,
            retryStrategy: RetryStrategy,
            requestHandler: T,
            completionHandler: @escaping CompletionHandler
        ) where T: RESTRequestHandler, T.Success == Success
        {
            self.dispatchQueue = dispatchQueue
            self.urlSession = urlSession
            self.addressCacheStore = addressCacheStore
            self.retryStrategy = retryStrategy
            self.requestHandler = AnyRequestHandler(requestHandler)

            loggerMetadata = ["taskIdentifier": .stringConvertible(taskIdentifier), "name": .string(name)]

            super.init(completionQueue: .main, completionHandler: completionHandler)
        }

        override func cancel() {
            super.cancel()

            dispatchQueue.async {
                self.retryTimer?.cancel()
                self.task?.cancel()

                self.retryTimer = nil
                self.task = nil
            }
        }

        override func main() {
            dispatchQueue.async {
                let endpoint = self.addressCacheStore.getCurrentEndpoint()

                self.sendRequest(endpoint: endpoint)
            }
        }

        private func sendRequest(endpoint: AnyIPEndpoint) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            requestHandler.createURLRequest(endpoint: endpoint) { [weak self] result in
                guard let self = self else { return }

                self.dispatchQueue.async {
                    guard !self.isCancelled else {
                        self.finish(completion: .cancelled)
                        return
                    }

                    switch result {
                    case .success(let urlRequest):
                        self.didReceiveURLRequest(urlRequest, endpoint: endpoint)

                    case .failure(let error):
                        self.didFailToCreateURLRequest(error)
                    }
                }
            }
        }

        private func didReceiveURLRequest(_ urlRequest: URLRequest, endpoint: AnyIPEndpoint) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            logger.debug("Executing request using \(endpoint).", metadata: loggerMetadata)

            task = self.urlSession.dataTask(with: urlRequest) { [weak self] data, response, error in
                if let error = error {
                    let urlError = error as! URLError

                    self?.didReceiveURLError(urlError, endpoint: endpoint)
                } else {
                    let httpResponse = response as! HTTPURLResponse
                    let data = data ?? Data()

                    self?.didReceiveURLResponse(httpResponse, data: data, endpoint: endpoint)
                }
            }

            task?.resume()
        }

        private func didFailToCreateURLRequest(_ error: REST.Error) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            logger.error(chainedError: error, message: "Failed to create URLRequest.", metadata: loggerMetadata)

            finish(completion: .failure(error))
        }

        private func didReceiveURLError(_ urlError: URLError, endpoint: AnyIPEndpoint) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            let retryEndpoint: AnyIPEndpoint

            switch urlError.code {
            case .cancelled:
                finish(completion: .cancelled)
                return

            case .notConnectedToInternet, .internationalRoamingOff, .callIsActive:
                retryEndpoint = addressCacheStore.getCurrentEndpoint()

            default:
                retryEndpoint = addressCacheStore.selectNextEndpoint(endpoint)
            }

            logger.error(
                chainedError: AnyChainedError(urlError),
                message: "Failed to perform request to \(endpoint).",
                metadata: loggerMetadata
            )

            // Check if retry count is not exceeded.
            guard retryCount < retryStrategy.maxRetryCount else {
                logger.debug("Ran out of retry attempts (\(retryStrategy.maxRetryCount))", metadata: loggerMetadata)

                finish(completion: OperationCompletion(result: .failure(.network(urlError))))
                return
            }

            // Increment retry count.
            retryCount += 1

            // Retry immediatly if retry delay is set to never.
            guard retryStrategy.retryDelay != .never else {
                sendRequest(endpoint: retryEndpoint)
                return
            }

            // Create timer to delay retry.
            let timer = DispatchSource.makeTimerSource(queue: dispatchQueue)

            timer.setEventHandler { [weak self] in
                self?.sendRequest(endpoint: retryEndpoint)
            }

            timer.setCancelHandler { [weak self] in
                self?.finish(completion: .cancelled)
            }

            timer.schedule(wallDeadline: .now() + retryStrategy.retryDelay)
            timer.activate()

            retryTimer = timer
        }

        private func didReceiveURLResponse(_ response: HTTPURLResponse, data: Data, endpoint: AnyIPEndpoint) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            let result = requestHandler.handleURLResponse(response, data: data)

            finish(completion: OperationCompletion(result: result))
        }
    }

}
