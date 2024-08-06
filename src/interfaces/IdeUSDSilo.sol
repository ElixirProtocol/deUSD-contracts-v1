// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

interface IdeUSDSilo {
    /// @notice Error emitted when the staking vault is not the caller
    error OnlyStakingVault();
    /// @notice Error emitted when the address is zero.
    error ZeroAddressException();
}
