// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IChainlinkAggregator {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface ITwapSource {
    function consult(address token, uint32 secondsAgo) external view returns (uint256 amountOutMantissa); // 1e18
}

/**
 * @title V_VibePriceOracleAdapter
 * @notice Provee precio dinámico de VIBE en mantissa 1e18 (USD por VIBE).
 *         Combina Chainlink (si existe) + TWAP Uniswap + fallback manual.
 */
contract V_VibePriceOracleAdapter {
    address public admin;
    address public chainlinkFeed;     // Opcional
    address public twapSource;        // Contrato que implementa consulta TWAP
    address public vibeToken;
    uint32  public twapWindowSeconds = 1800; // 30 min
    uint256 public maxDeviationBps = 3_000;  // 30%
    uint256 public maxChangeBps = 5_000;     // 50% vs lectura anterior
    uint256 public maxStale = 2 hours;

    // Fallback manual
    uint256 public manualOverridePrice; // 1e18
    uint256 public manualOverrideExpiry;

    uint256 public lastValidPrice;
    uint256 public lastUpdatedAt;

    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event ChainlinkFeedSet(address indexed feed);
    event TwapSourceSet(address indexed source);
    event ManualOverrideSet(uint256 price, uint256 expiry);
    event ParametersUpdated(uint32 twapWindow, uint256 maxDevBps, uint256 maxChangeBps, uint256 maxStale);

    modifier onlyAdmin() { require(msg.sender == admin, "not admin"); _; }

    constructor(address _admin, address _vibe) {
        admin = _admin;
        vibeToken = _vibe;
        lastValidPrice = 1e18; // inicial 1 USD
        lastUpdatedAt = block.timestamp;
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "zero");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }

    function setChainlinkFeed(address feed) external onlyAdmin {
        chainlinkFeed = feed;
        emit ChainlinkFeedSet(feed);
    }

    function setTwapSource(address source) external onlyAdmin {
        twapSource = source;
        emit TwapSourceSet(source);
    }

    function setManualOverride(uint256 price, uint256 duration) external onlyAdmin {
        manualOverridePrice = price;
        manualOverrideExpiry = block.timestamp + duration;
        emit ManualOverrideSet(price, manualOverrideExpiry);
    }

    function setParameters(
        uint32 twapWindow,
        uint256 _maxDeviationBps,
        uint256 _maxChangeBps,
        uint256 _maxStaleSeconds
    ) external onlyAdmin {
        require(twapWindow >= 300 && twapWindow <= 7200, "twap invalid");
        twapWindowSeconds = twapWindow;
        maxDeviationBps = _maxDeviationBps;
        maxChangeBps = _maxChangeBps;
        maxStale = _maxStaleSeconds;
        emit ParametersUpdated(twapWindow, _maxDeviationBps, _maxChangeBps, _maxStaleSeconds);
    }

    function _readChainlink() internal view returns (uint256 price, bool ok, uint256 updatedAt) {
        if (chainlinkFeed == address(0)) return (0, false, 0);
        try IChainlinkAggregator(chainlinkFeed).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 feedUpdatedAt,
            uint80
        ) {
            if (answer > 0) {
                // Asumimos answer en 8 dec (como USD feeds comunes)
                price = uint256(answer) * 1e10; // convertir a 1e18
                ok = true;
                updatedAt = feedUpdatedAt;
            }
        } catch {}
    }

    function _readTwap() internal view returns (uint256 price, bool ok) {
        if (twapSource == address(0)) return (0, false);
        try ITwapSource(twapSource).consult(vibeToken, twapWindowSeconds) returns (uint256 twapPrice) {
            if (twapPrice > 0) {
                price = twapPrice;
                ok = true;
            }
        } catch {}
    }

    function getVibePrice() external view returns (uint256 price, bool isStale, bool usedManual) {
        // Manual override vigente
        if (manualOverridePrice > 0 && block.timestamp <= manualOverrideExpiry) {
            return (manualOverridePrice, false, true);
        }

        (uint256 chainlinkPrice, bool cOk, uint256 cUpdated) = _readChainlink();
        (uint256 twapPrice, bool tOk) = _readTwap();

        uint256 chosen;
        uint256 nowTs = block.timestamp;

        if (cOk && tOk) {
            // Verificar desviación
            uint256 diff = chainlinkPrice > twapPrice ? chainlinkPrice - twapPrice : twapPrice - chainlinkPrice;
            uint256 maxPrice = chainlinkPrice > twapPrice ? chainlinkPrice : twapPrice;
            require(diff * 10_000 / maxPrice <= maxDeviationBps, "deviation");
            chosen = (chainlinkPrice + twapPrice) / 2;
            isStale = (nowTs - cUpdated) > maxStale;
        } else if (cOk) {
            chosen = chainlinkPrice;
            isStale = (nowTs - cUpdated) > maxStale;
        } else if (tOk) {
            // Sin chainlink, se acepta twap solo si no se excede cambio brusco
            uint256 prev = lastValidPrice;
            if (prev > 0) {
                uint256 change = twapPrice > prev ? twapPrice - prev : prev - twapPrice;
                require(change * 10_000 / prev <= maxChangeBps, "change too big");
            }
            chosen = twapPrice;
            isStale = false; // twap calculado en ventana actual
        } else {
            // Fallback último válido
            chosen = lastValidPrice;
            isStale = (nowTs - lastUpdatedAt) > maxStale;
        }

        return (chosen, isStale, false);
    }

    // Pull actualizado para snapshots; opcional
    function updatePrice() external {
        (uint256 p, bool stale, bool manualUsed) = this.getVibePrice();
        require(!stale || manualUsed, "stale");
        lastValidPrice = p;
        lastUpdatedAt = block.timestamp;
    }
}