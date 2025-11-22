// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./V_MasterEnhanced.sol";

contract V_MasterEnhancedV2 is V_MasterEnhanced {
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    function setOracle(address newOracle) external onlyAdmin {
        require(newOracle != address(0), "oracle=0");
        emit OracleUpdated(oracle, newOracle);
        oracle = newOracle;
    }
}