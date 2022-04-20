//
//  NetworkOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 08/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging

extension REST {
    class NetworkOperation<Success>: ResultOperation<Success, REST.Error> {
        private let requestHandler: AnyRequestHandler<Success>
        private let dispatchQueue: DispatchQueue
        private let urlSession: URLSession
        private let addressCacheStore: AddressCache.Store

        private var task: URLSessionTask?
        private var authorizationTask: Cancellable?

        private let retryStrategy: RetryStrategy
        private var retryTimer: DispatchSourceTimer?
        private var retryCount = 0

        private let logger = Logger(label: "REST.NetworkOperation")
        private let loggerMetadata: Logger.Metadata

        init(
            name: String,
            dispatchQueue: DispatchQueue,
            configuration: ProxyConfiguration,
            retryStrategy: RetryStrategy,
            requestHandler: AnyRequestHandler<Success>,
            completionHandler: @escaping CompletionHandler
        )
        {
            self.dispatchQueue = dispatchQueue
            self.urlSession = configuration.session
            self.addressCacheStore = configuration.addressCacheStore
            self.retryStrategy = retryStrategy
            self.requestHandler = requestHandler

            loggerMetadata = ["name": .string(name)]

            super.init(completionQueue: .main, completionHandler: completionHandler)
        }

        override func cancel() {
            super.cancel()

            dispatchQueue.async {
                self.retryTimer?.cancel()
                self.task?.cancel()

                self.authorizationTask?.cancel()
                self.authorizationTask = nil

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

            guard !isCancelled else {
                finish(completion: .cancelled)
                return
            }

            let result = requestHandler.createURLRequest(endpoint: endpoint)
            let request: URLRequest
            switch result {
            case .success(let anURLRequest):
                request = anURLRequest

            case .failure(let error):
                didFailToCreateURLRequest(error)
                return
            }

            guard let authorizationProvider = requestHandler.getAuthorizationProvider() else {
                didReceiveURLRequest(request, endpoint: endpoint)
                return
            }

            authorizationTask = authorizationProvider.getAuthorization { [weak self] result in
                guard let self = self else { return }

                self.dispatchQueue.async {
                    guard !self.isCancelled else {
                        self.finish(completion: .cancelled)
                        return
                    }

                    switch result {
                    case .success(let authorization):
                        self.didReceiveAuthorization(
                            authorization,
                            request: request,
                            endpoint: endpoint
                        )

                    case .failure(let error):
                        self.didFailToObtainAuthorization(error)

                    case .cancelled:
                        self.finish(completion: .cancelled)
                    }
                }
            }
        }

        private func didReceiveAuthorization(_ authorization: REST.Authorization, request: URLRequest, endpoint: AnyIPEndpoint) {
            var requestBuilder = REST.RequestBuilder(request: request)
            requestBuilder.setAuthorization(authorization)

            didReceiveURLRequest(requestBuilder.getURLRequest(), endpoint: endpoint)
        }

        private func didFailToObtainAuthorization(_ error: REST.Error) {
            dispatchPrecondition(condition: .onQueue(dispatchQueue))

            logger.error(chainedError: error, message: "Failed to obtain authorization.", metadata: loggerMetadata)

            finish(completion: .failure(error))
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
