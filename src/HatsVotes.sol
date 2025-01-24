// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotes } from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import { IHats } from "../lib/hats-protocol/src/Interfaces/IHats.sol";

/// @title HatsVotes
/// @notice A Hats Protocol-enabled implementation of IVotes that uses hat ownership to determine voting power
contract HatsVotes is IVotes {
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/
    error HatsVotes_ZeroAddress();
    error HatsVotes_ZeroVotingPower();
    error HatsVotes_NotAdmin();

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/
    event VotingPowerSet(uint256 hatId, uint256 votingPower);
    event VotingHatAdded(uint256 hatId, uint256 votingPower);
    event VotingHatRemoved(uint256 hatId);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice The Hats Protocol contract
    IHats public immutable HATS;

    /// @notice The admin hat that can configure voting power
    uint256 public immutable ADMIN_HAT;

    /// @notice Mapping of hat ID to voting power
    mapping(uint256 => uint256) public hatVotingPower;

    /// @notice Array of hat IDs that have voting power
    uint256[] public votingHats;

    /// @notice Mapping to track index of hat in votingHats array (+1)
    mapping(uint256 => uint256) private votingHatIndex;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address hats, uint256 adminHat) {
        if (hats == address(0)) revert HatsVotes_ZeroAddress();
        HATS = IHats(hats);
        ADMIN_HAT = adminHat;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the current votes balance for `account`
    /// @dev Only checks hats that have been explicitly given voting power
    function getVotes(address account) external view returns (uint256) {
        uint256 votes;
        uint256 length = votingHats.length;
        for (uint256 i; i < length;) {
            uint256 hatId = votingHats[i];
            if (HATS.isWearerOfHat(account, hatId)) {
                votes += hatVotingPower[hatId];
            }
            unchecked { ++i; }
        }
        return votes;
    }

    /// @notice Set voting power for a hat
    /// @dev Only callable by admin hat wearer
    function setHatVotingPower(uint256 hatId, uint256 power) external {
        // Check caller is admin
        if (!HATS.isWearerOfHat(msg.sender, ADMIN_HAT)) revert HatsVotes_NotAdmin();
      

        // If setting to 0, remove from voting hats
        if (power == 0) {
            _removeVotingHat(hatId);
            emit VotingHatRemoved(hatId);
        } else {
            // If hat not already in voting hats, add it
            if (votingHatIndex[hatId] == 0) {
                votingHats.push(hatId);
                votingHatIndex[hatId] = votingHats.length;
                emit VotingHatAdded(hatId, power);
            }
            hatVotingPower[hatId] = power;
            emit VotingPowerSet(hatId, power);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the primary timepoint used by the contract
    /// @dev Always returns current block number since we don't support historical votes
    function clock() public view returns (uint48) {
        return uint48(block.number);
    }

    /// @notice Returns how many clock values can fit in a timestamp
    /// @dev Always returns 1 since we use block numbers directly
    function CLOCK_MODE() public pure returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    /// @notice Returns array of all hats with voting power
    function getVotingHats() external view returns (uint256[] memory) {
        return votingHats;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @dev Removes a hat from the votingHats array
    function _removeVotingHat(uint256 hatId) internal {
        uint256 index = votingHatIndex[hatId];
        if (index > 0) {
            // Convert from 1-based to 0-based index
            index--;
            
            // Get index of last element
            uint256 lastIndex = votingHats.length - 1;
            
            // If not last element, swap with last
            if (index != lastIndex) {
                uint256 lastHat = votingHats[lastIndex];
                votingHats[index] = lastHat;
                votingHatIndex[lastHat] = index + 1;
            }
            
            // Remove last element
            votingHats.pop();
            delete votingHatIndex[hatId];
            delete hatVotingPower[hatId];
        }
    }

    /*//////////////////////////////////////////////////////////////
                        EMPTY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Not implemented - no historical votes support
    function getPastVotes(address, uint256) external pure returns (uint256) {
        return 0;
    }

    /// @notice Not implemented - no delegation support  
    function delegates(address) external pure returns (address) {
        return address(0);
    }

    /// @notice Not implemented - no delegation support
    function delegate(address) external pure {
        return;
    }

    /// @notice Not implemented - no delegation support
    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        return;
    }

    /// @notice Not implemented - no checkpoints
    function numCheckpoints(address) external pure returns (uint32) {
        return 0;
    }

    /// @notice Not implemented - no historical supply support
    function getPastTotalSupply(uint256) external pure returns (uint256) {
        return 0;
    }
} 