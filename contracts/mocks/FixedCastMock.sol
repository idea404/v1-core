// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../libraries/FixedCast.sol";

contract FixedCastMock {
    using FixedCast for uint16;
    using FixedCast for uint256;

    function toUint256Fixed(uint16 value) external pure returns (uint256) {
        return value.toUint256Fixed();
    }

    function toUint16Fixed(uint256 value) external pure returns (uint16) {
        return value.toUint16Fixed();
    }
}
