// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/Structs.sol";

library DefaultCurve {
    // Default Curve Params
    uint256 public constant ALPHA = 5e17;
    uint256 public constant BETA = 35e16;
    uint256 public constant MAX = 15e16;
    uint256 public constant EPSILON = 4e14;
    uint256 public constant LAMBDA = 1e18;

    // // Weights
    uint256 public constant BASE_WEIGHT = 6e17;
    uint256 public constant QUOTE_WEIGHT = 4e17;
    
    // v2 deployed params
    // uint256 public constant ALPHA = 800000000000000000;
    // uint256 public constant BETA = 420000000000000000;
    // uint256 public constant MAX = 302631578947368421;
    // uint256 public constant EPSILON = 5000000000000000;
    // uint256 public constant LAMBDA = 300000000000000000;
    // uint256 public constant BASE_WEIGHT = 5e17;
    // uint256 public constant QUOTE_WEIGHT = 5e17;
}
