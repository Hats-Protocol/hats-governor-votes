// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

/// @title HatsVotes
/// @notice A Hats Protocol-enabled implementation of IVotes that uses hat ownership to determine voting power
contract HatsVotes is IVotes {
  /*//////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/
  error HatsVotes_NotAdmin();
  error HatsVotes_InvalidHat();
  error HatsVotes_NotHatWearer();
  error HatsVotes_AlreadyRegistered();
  error HatsVotes_NotClaimableFor();
  error HatsVotes_ReregistrationNotAllowed();
  error HatsVotes_Locked();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/
  event VoterRegistered(uint256 hatId, address account);
  event ClaimableForSet(bool claimableFor);
  event OwnerHatSet(uint256 ownerHat);
  event HatsVotesLocked();
  event HatsVotingPowerSet(uint256[] hatIds, uint256[] votingPowers);

  /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
  //////////////////////////////////////////////////////////////*/
  /// @notice The Hats Protocol contract
  IHats public immutable HATS;

  /// @notice Whether the contract is locked from further admin changes
  bool public locked;

  /// @notice Whether voting power can be claimed on behalf of hat wearers
  bool public claimableFor;

  /// @notice The owner hat that can configure voting power
  uint256 public ownerHat;

  /// @notice Mapping of hat ID to voting power
  mapping(uint256 hatId => uint256 votingPower) public hatVotingPower;

  /// @notice Mapping of account to registered hat ID
  mapping(address voter => uint256 hatId) public registeredHats;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/
  constructor(address hats, uint256 _ownerHat, bool _claimableFor, uint256[] memory _hatIds, uint256[] memory _powers) {
    HATS = IHats(hats);
    _setOwnerHat(_ownerHat);
    _setClaimableFor(_claimableFor);
    _setHatsVotingPower(_hatIds, _powers);
  }

  /*//////////////////////////////////////////////////////////////
                    IMPLEMENTED IVOTES FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Returns the current votes balance for `account`
  function getVotes(address account) public view returns (uint256) {
    uint256 hat = registeredHats[account];
    if (hat == 0 || !HATS.isWearerOfHat(account, hat)) return 0;
    return hatVotingPower[hat];
  }

  /// @notice Returns voting power at a past timestamp, but since we don't support checkpointing, just returns current
  /// power
  function getPastVotes(address account, uint256) external view returns (uint256) {
    return getVotes(account);
  }

  /// @notice Returns the delegate for an account, which is the account itself
  function delegates(address account) external pure returns (address) {
    return account;
  }

  /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Register yourself as a voter with a valid hat
  function registerVoter(uint256 hatId) external {
    _registerVoter(hatId, msg.sender);
  }

  /// @notice Register someone else as a voter with a valid hat
  function registerVoterFor(uint256 hatId, address account) external {
    if (!claimableFor) revert HatsVotes_NotClaimableFor();
    if (HATS.isWearerOfHat(account, registeredHats[account])) {
      revert HatsVotes_ReregistrationNotAllowed();
    }
    _registerVoter(hatId, account);
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Set voting power for a hat
  /// @dev Only callable by admin hat wearer
  function setHatVotingPower(uint256[] memory hatIds, uint256[] memory powers) external {
    _checkUnlocked();
    _checkOwner();
    _setHatsVotingPower(hatIds, powers);
  }

  /// @notice Set voting power for multiple hats
  /// @dev Only callable by admin hat wearer
  function setHatsVotingPower(uint256[] memory hatIds, uint256[] memory powers) external {
    _checkUnlocked();
    _checkOwner();
    _setHatsVotingPower(hatIds, powers);
  }

  /// @notice Set whether voting power can be claimed on behalf of hat wearers
  function setClaimableFor(bool _claimableFor) external {
    _checkUnlocked();
    _checkOwner();
    _setClaimableFor(_claimableFor);
  }

  /// @notice Set the owner hat
  function setOwnerHat(uint256 _ownerHat) external {
    _checkUnlocked();
    _checkOwner();
    _setOwnerHat(_ownerHat);
  }

  /// @notice Lock the contract from further admin changes
  function lock() external {
    _checkUnlocked();
    _checkOwner();
    locked = true;
    emit HatsVotesLocked();
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
  function _registerVoter(uint256 hatId, address account) internal {
    // Check hat has voting power
    if (hatVotingPower[hatId] == 0) revert HatsVotes_InvalidHat();

    // Check account wears hat
    if (!HATS.isWearerOfHat(account, hatId)) revert HatsVotes_NotHatWearer();

    // Register the hat
    registeredHats[account] = hatId;
    emit VoterRegistered(hatId, account);
  }

  function _checkOwner() internal view {
    if (!HATS.isWearerOfHat(msg.sender, ownerHat)) revert HatsVotes_NotAdmin();
  }

  function _checkUnlocked() internal view {
    if (locked) revert HatsVotes_Locked();
  }

  function _setOwnerHat(uint256 _ownerHat) internal {
    ownerHat = _ownerHat;
    emit OwnerHatSet(_ownerHat);
  }

  function _setClaimableFor(bool _claimableFor) internal {
    claimableFor = _claimableFor;
    emit ClaimableForSet(_claimableFor);
  }

  function _setHatsVotingPower(uint256[] memory hatIds, uint256[] memory powers) internal {
    for (uint256 i = 0; i < hatIds.length; i++) {
      hatVotingPower[hatIds[i]] = powers[i];
    }
    emit HatsVotingPowerSet(hatIds, powers);
  }

  /*//////////////////////////////////////////////////////////////
                        VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
  function clock() public view returns (uint48) {
    return uint48(block.number);
  }

  function CLOCK_MODE() public pure returns (string memory) {
    return "mode=blocknumber&from=default";
  }

  /*//////////////////////////////////////////////////////////////
                        EMPTY IVOTES IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

  function delegate(address) external pure {
    return;
  }

  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
    return;
  }

  function numCheckpoints(address) external pure returns (uint32) {
    return 0;
  }

  function getPastTotalSupply(uint256) external pure returns (uint256) {
    return 0;
  }
}
