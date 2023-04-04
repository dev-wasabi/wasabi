// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {WasabiStructs} from "./WasabiStructs.sol";

library WasabiValidation {
    function validate(WasabiStructs.PoolConfiguration calldata _poolConfiguration) external pure {
        require(_poolConfiguration.minStrikePrice > 0, "Min strike price needs to be present");
        require(_poolConfiguration.minDuration > 0, "Min duration needs to be present");
        require(_poolConfiguration.minStrikePrice < _poolConfiguration.maxStrikePrice, "Min strike price cannnot greater than max");
        require(_poolConfiguration.minDuration < _poolConfiguration.maxDuration, "Min duration cannnot greater than max");
    }
}