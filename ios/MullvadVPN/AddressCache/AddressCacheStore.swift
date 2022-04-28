//
//  AddressCacheStore.swift
//  MullvadVPN
//
//  Created by pronebird on 08/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging

extension AddressCache {

    struct CachedAddresses: Codable {
        /// Date when the cached addresses were last updated.
        var updatedAt: Date

        /// API endpoints.
        var endpoints: [AnyIPEndpoint]
    }

    enum CacheSource: CustomStringConvertible {
        /// Cache file originates from disk location.
        case disk

        /// Cache file originates from application bundle.
        case bundle

        var description: String {
            switch self {
            case .disk:
                return "disk"
            case .bundle:
                return "bundle"
            }
        }
    }

    struct ReadResult {
        var cachedAddresses: CachedAddresses
        var source: CacheSource
    }

    class Store {

        static let shared: Store = {
            let cacheFilename = "api-ip-address.json"
            let cacheDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let cacheFileURL = cacheDirectoryURL.appendingPathComponent(cacheFilename, isDirectory: false)
            let prebundledCacheFileURL = Bundle.main.url(forResource: cacheFilename, withExtension: nil)!

            return Store(
                cacheFileURL: cacheFileURL,
                prebundledCacheFileURL: prebundledCacheFileURL
            )
        }()

        static var defaultCachedAddresses: CachedAddresses {
            return CachedAddresses(
                updatedAt: Date(timeIntervalSince1970: 0),
                endpoints: [
                    ApplicationConfiguration.defaultAPIEndpoint
                ]
            )
        }

        /// Logger.
        private let logger = Logger(label: "AddressCache.Store")

        /// Memory cache.
        private var cachedAddresses: CachedAddresses

        /// Cache file location.
        private let cacheFileURL: URL

        /// The location of pre-bundled address cache file.
        private let prebundledCacheFileURL: URL

        /// Lock used for synchronizing access to instance members.
        private let nslock = NSLock()

        /// Designated initializer
        init(cacheFileURL: URL, prebundledCacheFileURL: URL) {
            self.cacheFileURL = cacheFileURL
            self.prebundledCacheFileURL = prebundledCacheFileURL
            cachedAddresses = Self.defaultCachedAddresses

            initializeStore()
        }

        func getCurrentEndpoint() -> AnyIPEndpoint {
            nslock.lock()
            defer { nslock.unlock() }
            return cachedAddresses.endpoints.first!
        }

        func selectNextEndpoint(_ failedEndpoint: AnyIPEndpoint) -> AnyIPEndpoint {
            nslock.lock()
            defer { nslock.unlock() }

            var currentEndpoint = cachedAddresses.endpoints.first!

            if failedEndpoint == currentEndpoint {
                cachedAddresses.endpoints.removeFirst()
                cachedAddresses.endpoints.append(failedEndpoint)

                currentEndpoint = cachedAddresses.endpoints.first!

                logger.debug("Failed to communicate using \(failedEndpoint). Next endpoint: \(currentEndpoint)")

                if case .failure(let error) = writeToDisk() {
                    logger.error(chainedError: error, message: "Failed to write address cache after selecting next endpoint.")
                }
            }

            return currentEndpoint
        }

        func setEndpoints(_ endpoints: [AnyIPEndpoint]) -> Result<Void, AddressCache.StoreError> {
            nslock.lock()
            defer { nslock.unlock() }

            guard !endpoints.isEmpty else {
                return .failure(.emptyAddressList)
            }

            if Set(cachedAddresses.endpoints) == Set(endpoints) {
                cachedAddresses.updatedAt = Date()
            } else {
                // Shuffle new endpoints
                var newEndpoints = endpoints.shuffled()

                // Move current endpoint to the top of the list
                let currentEndpoint = cachedAddresses.endpoints.first!
                if let index = newEndpoints.firstIndex(of: currentEndpoint) {
                    newEndpoints.remove(at: index)
                    newEndpoints.insert(currentEndpoint, at: 0)
                }

                cachedAddresses = CachedAddresses(
                    updatedAt: Date(),
                    endpoints: newEndpoints
                )
            }

            return writeToDisk()
        }

        func getLastUpdateDate() -> Date {
            nslock.lock()
            defer { nslock.unlock() }

            return cachedAddresses.updatedAt
        }

        private func initializeStore() {
            switch readFromCacheLocationWithFallback() {
            case .success(let readResult):
                if readResult.cachedAddresses.endpoints.isEmpty {
                    logger.debug("Read empty cache from \(readResult.source). Fallback to default API endpoint.")

                    cachedAddresses = Self.defaultCachedAddresses

                    logger.debug("Initialized cache with default API endpoint.")
                } else {
                    switch readResult.source {
                    case .disk:
                        cachedAddresses = readResult.cachedAddresses

                    case .bundle:
                        var addresses = readResult.cachedAddresses
                        addresses.endpoints.shuffle()
                        cachedAddresses = addresses

                        logger.debug("Persist address list read from bundle.")

                        if case .failure(let error) = writeToDisk() {
                            logger.error(chainedError: error, message: "Failed to persist address cache after reading it from bundle.")
                        }
                    }

                    logger.debug("Initialized cache from \(readResult.source) with \(cachedAddresses.endpoints.count) endpoint(s).")
                }

            case .failure(let error):
                logger.error(chainedError: error, message: "Failed to read address cache. Fallback to default API endpoint.")

                cachedAddresses = Self.defaultCachedAddresses

                logger.debug("Initialized cache with default API endpoint.")
            }
        }

        private func readFromCacheLocationWithFallback() -> Result<ReadResult, AddressCache.StoreError> {
            return readFromCacheLocation()
                .map { addresses in
                    return ReadResult(
                        cachedAddresses: addresses,
                        source: .disk
                    )
                }
                .flatMapError { error in
                    logger.error(chainedError: error, message: "Failed to read address cache from disk. Fallback to pre-bundled cache.")

                    return readFromBundle().map { cachedAddresses in
                        return ReadResult(
                            cachedAddresses: cachedAddresses,
                            source: .bundle
                        )
                    }
                }
        }

        private func readFromCacheLocation() -> Result<CachedAddresses, AddressCache.StoreError> {
            return Result { try Data(contentsOf: cacheFileURL) }
                .mapError { error in
                    return .readCache(error)
                }
                .flatMap { data in
                    return Result { try JSONDecoder().decode(CachedAddresses.self, from: data) }
                        .mapError { error in
                            return .decodeCache(error)
                        }
                }
        }

        private func writeToDisk() -> Result<(), AddressCache.StoreError> {
            let cacheDirectoryURL = cacheFileURL.deletingLastPathComponent()

            try? FileManager.default.createDirectory(
                at: cacheDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )

            return Result { try JSONEncoder().encode(cachedAddresses) }
                .mapError { error in
                    return .encodeCache(error)
                }
                .flatMap { data in
                    return Result { try data.write(to: cacheFileURL, options: .atomic) }
                        .mapError { error in
                            return .writeCache(error)
                        }
                }
        }

        private func readFromBundle() -> Result<CachedAddresses, AddressCache.StoreError> {
            return Result { try Data(contentsOf: prebundledCacheFileURL) }
                .mapError { error in
                    return .readCacheFromBundle(error)
                }
                .flatMap { data in
                    return Result { try JSONDecoder().decode([AnyIPEndpoint].self, from: data) }
                        .mapError { error in
                            return .decodeCacheFromBundle(error)
                        }
                        .map { endpoints in
                            return CachedAddresses(
                                updatedAt: Date(timeIntervalSince1970: 0),
                                endpoints: endpoints
                            )
                        }
                }
        }

    }
}
