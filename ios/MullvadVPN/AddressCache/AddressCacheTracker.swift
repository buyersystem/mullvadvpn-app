//
//  AddressCacheTracker.swift
//  MullvadVPN
//
//  Created by pronebird on 08/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import UIKit
import BackgroundTasks
import Logging

extension AddressCache {
    class Tracker {
        /// Update interval (in seconds).
        private static let updateInterval: TimeInterval = 60 * 60 * 24

        /// Retry interval (in seconds).
        private static let retryInterval: TimeInterval = 60 * 15

        /// Logger.
        private let logger = Logger(label: "AddressCache.Tracker")

        /// REST API proxy.
        private let apiProxy: REST.APIProxy

        /// Store.
        private let store: AddressCache.Store

        /// A flag that indicates whether periodic updates are running
        private var isPeriodicUpdatesEnabled = false

        /// The date of last failed attempt.
        private var lastFailureAttemptDate: Date?

        /// Timer used for scheduling periodic updates.
        private var timer: DispatchSourceTimer?

        /// Operation queue.
        private let operationQueue: OperationQueue = {
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = 1
            return operationQueue
        }()

        /// Queue used for synchronizing access to instance members.
        private let stateQueue = DispatchQueue(label: "AddressCache.Tracker.stateQueue")

        /// Designated initializer
        init(apiProxy: REST.APIProxy, store: AddressCache.Store) {
            self.apiProxy = apiProxy
            self.store = store
        }

        func startPeriodicUpdates() {
            stateQueue.async {
                guard !self.isPeriodicUpdatesEnabled else {
                    return
                }

                self.logger.debug("Start periodic address cache updates")

                self.isPeriodicUpdatesEnabled = true

                let scheduleDate = self.nextScheduleDate()

                self.logger.debug("Schedule address cache update on \(scheduleDate.logFormatDate())")

                self.scheduleEndpointsUpdate(startTime: .now() + scheduleDate.timeIntervalSinceNow)
            }
        }

        func stopPeriodicUpdates() {
            stateQueue.async {
                guard self.isPeriodicUpdatesEnabled else { return }

                self.logger.debug("Stop periodic address cache updates")

                self.isPeriodicUpdatesEnabled = false

                self.timer?.cancel()
                self.timer = nil
            }
        }

        func updateEndpoints(completionHandler: ((_ completion: OperationCompletion<CacheUpdateResult, Error>) -> Void)? = nil) -> Cancellable {
            let operation = UpdateAddressCacheOperation(
                queue: stateQueue,
                apiProxy: apiProxy,
                store: store,
                updateInterval: Self.updateInterval,
                completionHandler: { [weak self] completion in
                    self?.handleCacheUpdateCompletion(completion)

                    completionHandler?(completion)
                }
            )

            let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "AddressCache.Tracker.updateEndpoints") {
                operation.cancel()
            }

            operation.completionBlock = {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            }

            operationQueue.addOperation(operation)

            return operation
        }

        private func scheduleEndpointsUpdate(startTime: DispatchWallTime) {
            let newTimer = DispatchSource.makeTimerSource()
            newTimer.setEventHandler { [weak self] in
                self?.handleTimer()
            }

            newTimer.schedule(wallDeadline: startTime)
            newTimer.activate()

            timer?.cancel()
            timer = newTimer
        }

        private func handleTimer() {
            _ = updateEndpoints { result in
                guard self.isPeriodicUpdatesEnabled else { return }

                let scheduleDate = self.nextScheduleDate()

                self.logger.debug("Schedule next address cache update on \(scheduleDate.logFormatDate())")

                self.scheduleEndpointsUpdate(startTime: .now() + scheduleDate.timeIntervalSinceNow)
            }
        }

        private func nextScheduleDate() -> Date {
            if let lastFailureAttemptDate = lastFailureAttemptDate {
                return Date(timeInterval: Self.retryInterval, since: lastFailureAttemptDate)
            } else {
                let updatedAt = store.getLastUpdateDate()

                return Date(timeInterval: Self.updateInterval, since: updatedAt)
            }
        }

        private func handleCacheUpdateCompletion(_ completion: OperationCompletion<AddressCache.CacheUpdateResult, Error>) {
            switch completion {
            case .success(let updateResult):
                switch updateResult {
                case .finished:
                    logger.debug("Finished updating address cache.")
                case .throttled:
                    logger.debug("Address cache update was throttled.")
                }

                lastFailureAttemptDate = nil

            case .failure(let error):
                logger.error(chainedError: AnyChainedError(error), message: "Failed to update address cache.")
                lastFailureAttemptDate = Date()

            case .cancelled:
                logger.debug("Address cache update was cancelled.")
                lastFailureAttemptDate = Date()
            }
        }

    }
}

// MARK: - Background tasks

@available(iOS 13.0, *)
extension AddressCache.Tracker {

    /// Register background task with scheduler.
    func registerBackgroundTask() {
        let taskIdentifier = ApplicationConfiguration.addressCacheUpdateTaskIdentifier

        let isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            self.handleBackgroundTask(task as! BGProcessingTask)
        }

        if isRegistered {
            logger.debug("Registered address cache update task")
        } else {
            logger.error("Failed to register address cache update task")
        }
    }

    /// Create and submit task request to scheduler.
    func scheduleBackgroundTask() throws {
        let beginDate = nextScheduleDate()

        logger.debug("Schedule address cache update task on \(beginDate.logFormatDate())")

        let taskIdentifier = ApplicationConfiguration.addressCacheUpdateTaskIdentifier

        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = beginDate
        request.requiresNetworkConnectivity = true

        return try BGTaskScheduler.shared.submit(request)
    }

    /// Background task handler.
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        logger.debug("Start address cache update task")

        let cancellable = updateEndpoints { completion in
            do {
                // Schedule next background task
                try self.scheduleBackgroundTask()
            } catch {
                self.logger.error(chainedError: AnyChainedError(error), message: "Failed to schedule next address cache update task")
            }

            task.setTaskCompleted(success: completion.isSuccess)
        }

        task.expirationHandler = {
            cancellable.cancel()
        }
    }
}
