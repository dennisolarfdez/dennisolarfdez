// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

interface IV_cTokenMinimalUnderlyingResolver {
    function underlying() external view returns (address);
}

// Soporte para cTokens que exponen underlyingAddress() en vez de underlying()
interface IV_cTokenUnderlyingAddress {
    function underlyingAddress() external view returns (address);
}

contract VibeOracleHybridV3 {
    enum PriceSource { NONE, FEED_ONLY, MANUAL_ONLY, BLEND, DEVIATION_FEED, DEVIATION_MANUAL, DEVIATION_MIN }

    address public admin;

    // Defaults globales
    uint256 public maxStalenessDefault;    // segundos
    uint256 public maxDeviationBpsDefault; // base 10_000

    // Overrides por activo
    mapping(address => uint256) public maxStalenessAsset;    // 0 => usa default
    mapping(address => uint256) public maxDeviationBpsAsset; // 0 => usa default
    mapping(address => bool)    public preferManualOnDeviation;

    // Feeds y manuales (clave = underlying)
    mapping(address => address) public feeds;        // underlying -> chainlink feed
    mapping(address => uint256) public manualPrices; // precio 1e18

    // Eventos
    event FeedSet(address indexed token, address indexed feed);
    event ManualPriceSet(address indexed token, uint256 price);
    event ManualPriceCleared(address indexed token);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event ParamsUpdated(uint256 maxStalenessDefault, uint256 maxDeviationBpsDefault);
    event AssetParamsUpdated(address indexed token, uint256 staleness, uint256 deviationBps, bool preferManual);

    modifier onlyAdmin() { require(msg.sender == admin, "oracle: !admin"); _; }

    constructor(uint256 _staleness, uint256 _devBps) {
        admin = msg.sender;
        maxStalenessDefault = _staleness;
        maxDeviationBpsDefault = _devBps;
        emit ParamsUpdated(_staleness, _devBps);
    }

    // Admin

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "oracle: zero");
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    // Mantiene compatibilidad (permite address(0)); para limpieza explícita existe clearFeed()
    function setFeed(address token, address feed) external onlyAdmin {
        feeds[token] = feed;
        emit FeedSet(token, feed);
    }

    function clearFeed(address token) external onlyAdmin {
        address old = feeds[token];
        require(old != address(0), "oracle: no feed set");
        feeds[token] = address(0);
        emit FeedSet(token, address(0));
    }

    function setManualPrice(address token, uint256 price) external onlyAdmin {
        manualPrices[token] = price;
        emit ManualPriceSet(token, price);
    }

    function clearManualPrice(address token) external onlyAdmin {
        manualPrices[token] = 0;
        emit ManualPriceCleared(token);
    }

    function setParams(uint256 _staleness, uint256 _devBps) external onlyAdmin {
        maxStalenessDefault = _staleness;
        maxDeviationBpsDefault = _devBps;
        emit ParamsUpdated(_staleness, _devBps);
    }

    function setAssetParams(address token, uint256 staleness, uint256 deviationBps, bool preferManual) external onlyAdmin {
        maxStalenessAsset[token] = staleness;
        maxDeviationBpsAsset[token] = deviationBps;
        preferManualOnDeviation[token] = preferManual;
        emit AssetParamsUpdated(token, staleness, deviationBps, preferManual);
    }

    function clearAssetParams(address token) external onlyAdmin {
        maxStalenessAsset[token] = 0;
        maxDeviationBpsAsset[token] = 0;
        emit AssetParamsUpdated(token, 0, 0, preferManualOnDeviation[token]);
    }

    // Lecturas

    function getRawFeedPrice(address asset) public view returns (uint256 feedPrice) {
        address token = _resolveUnderlying(asset);
        address feed = feeds[token];
        if (feed == address(0)) return 0;

        try AggregatorV3Interface(feed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (
                answer > 0 &&
                answeredInRound >= roundId &&
                updatedAt >= startedAt &&
                _notStale(token, updatedAt)
            ) {
                uint8 dec = AggregatorV3Interface(feed).decimals();
                feedPrice = _scale(uint256(answer), dec);
            }
        } catch {
            return 0;
        }
    }

    function getManualPrice(address asset) public view returns (uint256) {
        address token = _resolveUnderlying(asset);
        return manualPrices[token];
    }

    // Principal: retorna precio 1e18 (0 si no hay fuente válida)
    function getUnderlyingPrice(address asset) public view returns (uint256) {
        address token = _resolveUnderlying(asset);

        uint256 feedPrice = getRawFeedPrice(asset);
        uint256 manual = manualPrices[token];

        if (feedPrice == 0 && manual == 0) return 0;
        if (feedPrice != 0 && manual == 0) return feedPrice;
        if (feedPrice == 0 && manual != 0) return manual;

        uint256 deviationBps = _computeDeviation(feedPrice, manual);
        uint256 maxDev = _maxDeviation(token);

        if (deviationBps > maxDev) {
            if (preferManualOnDeviation[token]) {
                return manual;
            } else {
                return feedPrice < manual ? feedPrice : manual;
            }
        }

        return (feedPrice + manual) / 2; // blend simple
    }

    function diagnosePrice(address asset) external view returns (
        uint256 effectivePrice,
        PriceSource source,
        uint256 feedPrice,
        uint256 manualPrice
    ) {
        address token = _resolveUnderlying(asset);
        feedPrice = getRawFeedPrice(asset);
        manualPrice = manualPrices[token];

        if (feedPrice == 0 && manualPrice == 0) {
            return (0, PriceSource.NONE, 0, 0);
        }
        if (feedPrice != 0 && manualPrice == 0) {
            return (feedPrice, PriceSource.FEED_ONLY, feedPrice, 0);
        }
        if (feedPrice == 0 && manualPrice != 0) {
            return (manualPrice, PriceSource.MANUAL_ONLY, 0, manualPrice);
        }

        uint256 deviationBps = _computeDeviation(feedPrice, manualPrice);
        uint256 maxDev = _maxDeviation(token);
        if (deviationBps > maxDev) {
            if (preferManualOnDeviation[token]) {
                return (manualPrice, PriceSource.DEVIATION_MANUAL, feedPrice, manualPrice);
            } else {
                uint256 chosen = feedPrice < manualPrice ? feedPrice : manualPrice;
                return (chosen, PriceSource.DEVIATION_MIN, feedPrice, manualPrice);
            }
        }
        uint256 blended = (feedPrice + manualPrice) / 2;
        return (blended, PriceSource.BLEND, feedPrice, manualPrice);
    }

    // Internos

    function _notStale(address token, uint256 updatedAt) internal view returns (bool) {
        uint256 limit = maxStalenessAsset[token];
        if (limit == 0) limit = maxStalenessDefault;
        if (limit == 0) return true;
        // Blindaje: si el feed devuelve un updatedAt en el futuro, considéralo inválido (stale)
        if (updatedAt > block.timestamp) return false;
        return block.timestamp - updatedAt <= limit;
    }

    function _maxDeviation(address token) internal view returns (uint256) {
        uint256 dev = maxDeviationBpsAsset[token];
        if (dev == 0) dev = maxDeviationBpsDefault;
        return dev;
    }

    function _computeDeviation(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 diff = a > b ? a - b : b - a;
        if (b == 0) return type(uint256).max;
        return diff * 10_000 / b;
    }

    function _scale(uint256 price, uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ == 18) return price;
        if (decimals_ < 18) return price * (10 ** (18 - decimals_));
        return price / (10 ** (decimals_ - 18));
    }

    function _resolveUnderlying(address asset) internal view returns (address) {
        // 1) Intentar cToken.underlying()
        (bool ok1, bytes memory data1) = asset.staticcall(
            abi.encodeWithSelector(IV_cTokenMinimalUnderlyingResolver.underlying.selector)
        );
        if (ok1 && data1.length >= 32) return abi.decode(data1, (address));

        // 2) Intentar cToken.underlyingAddress() (tu cToken actual)
        (bool ok2, bytes memory data2) = asset.staticcall(
            abi.encodeWithSelector(IV_cTokenUnderlyingAddress.underlyingAddress.selector)
        );
        if (ok2 && data2.length >= 32) return abi.decode(data2, (address));

        // 3) Fallback: asumir que `asset` ya es el underlying
        return asset;
    }
}