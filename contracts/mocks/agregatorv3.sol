// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Mock compatible con la interfaz que usa tu oracle.
// Permite probar:
// - actualizaciones normales (setAnswer / setAnswerWithTimestamps)
// - staleness (setStale)
// - answeredInRound < roundId (setAnsweredInRound) para simular rounds inválidos
// - revert manual de latestRoundData (setRevertLatest) para probar try/catch

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 public immutable override decimals;
    string public override description;
    uint256 public override version;

    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    bool public revertLatest;

    event AnswerUpdated(int256 answer, uint80 roundId, uint256 updatedAt);
    event RevertLatestSet(bool enabled);

    constructor(
        uint8 _decimals,
        string memory _description,
        uint256 _version,
        int256 initialAnswer
    ) {
        decimals = _decimals;                 // típicamente 8 en Chainlink
        description = _description;           // ej: "USDC / USD"
        version = _version;                   // ej: 1
        roundId = 1;
        answer = initialAnswer;               // ej: 100000000 (1.0 con 8 dec)
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = roundId;
        emit AnswerUpdated(answer, roundId, updatedAt);
    }

    // Actualización simple: avanza round y refresca timestamps
    function setAnswer(int256 newAnswer) external {
        roundId += 1;
        answer = newAnswer;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = roundId;
        emit AnswerUpdated(answer, roundId, updatedAt);
    }

    // Actualización con timestamps custom (para tests específicos)
    function setAnswerWithTimestamps(
        int256 newAnswer,
        uint256 startedAt_,
        uint256 updatedAt_
    ) external {
        require(updatedAt_ >= startedAt_, "bad timestamps");
        roundId += 1;
        answer = newAnswer;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
        answeredInRound = roundId;
        emit AnswerUpdated(answer, roundId, updatedAt);
    }

    // Fuerza staleness: mueve updatedAt hacia el pasado (secondsAgo)
    function setStale(uint256 secondsAgo) external {
        require(secondsAgo > 0, "secondsAgo=0");
        // No cambia round, solo simula que el último update fue hace mucho
        updatedAt = block.timestamp - secondsAgo;
        emit AnswerUpdated(answer, roundId, updatedAt);
    }

    // Simula un round "incompleto" (answeredInRound < roundId)
    function setAnsweredInRound(uint80 _answeredInRound) external {
        require(_answeredInRound <= roundId, "answeredInRound too new");
        answeredInRound = _answeredInRound;
        // No emite evento para no confundir, no cambia timestamps.
    }

    // Haz que latestRoundData reviente (para probar try/catch del oracle)
    function setRevertLatest(bool enabled) external {
        revertLatest = enabled;
        emit RevertLatestSet(enabled);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (revertLatest) {
            // Nota: revertir en una view es válido para testear el catch del oracle
            revert("Mock: latestRoundData revert");
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}