// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

interface IHatMintHook {
  function onHatMinted(uint256 hatId, address wearer, bytes memory hookData) external returns (bool success);
}

/// @title HatsVotes
/// @notice A Hats Protocol-enabled implementation of IVotes that uses hat ownership to determine voting weight
contract HatsVotes is IVotes, IHatMintHook {
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
  event VoterRegistered(uint256 hatId, address account, uint256 timestamp);
  event ClaimableForSet(bool claimableFor);
  event OwnerHatSet(uint256 ownerHat);
  event HatsVotesLocked();
  event HatsVotingWeightSet(uint256[] hatIds, uint256[] votingWeights);

  /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
  //////////////////////////////////////////////////////////////*/
  /// @notice The Hats Protocol contract
  IHats public immutable HATS;

  /// @notice Whether the contract is locked from further admin changes
  bool public locked;

  /// @notice Whether voting weight can be claimed on behalf of hat wearers
  bool public claimableFor;

  /// @notice The owner hat that can configure voting weight
  uint256 public ownerHat;

  /// @notice Mapping of hat ID to voting weight
  mapping(uint256 hatId => uint256 votingWeight) public hatVotingWeight;
  /// @notice Struct to store voter registration data

  struct VoterData {
    uint256 hatId; // Full hat ID
    uint256 registrationTime; // Keep exact timestamp for compatibility
  }

  /// @notice Mapping of account to voter data
  mapping(address => VoterData) public voterData;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/
  constructor(
    address hats,
    uint256 _ownerHat,
    bool _claimableFor,
    uint256[] memory _hatIds,
    uint256[] memory _weights
  ) {
    HATS = IHats(hats);
    _setOwnerHat(_ownerHat);
    _setClaimableFor(_claimableFor);
    _setHatsVotingWeight(_hatIds, _weights);
  }

  /*//////////////////////////////////////////////////////////////
                    IMPLEMENTED IVOTES FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Returns the current votes balance for `account`
  function getVotes(address account) public view returns (uint256) {
    return _getVotes(voterData[account].hatId);
  }

  /// @notice Returns voting weight at a past timestamp
  function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
    VoterData memory data = voterData[account];
    if (data.registrationTime > timepoint) return 0;
    return _getVotes(data.hatId);
  }

  /// @notice Internal function to calculate votes from voter data
  function _getVotes(uint256 hatId) internal view returns (uint256) {
    if (!HATS.isWearerOfHat(msg.sender, hatId)) return 0;
    return hatVotingWeight[hatId];
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
  function registerVoterFor(uint256 hatId, address account) public {
    if (!claimableFor) revert HatsVotes_NotClaimableFor();
    if (HATS.isWearerOfHat(account, voterData[account].hatId)) {
      revert HatsVotes_ReregistrationNotAllowed();
    }
    _registerVoter(hatId, account);
  }

  /// @inheritdoc IHatMintHook
  /// @notice This hook is called when a hat is minted from a hook-enabled contract, such as MultiClaimsHatter
  function onHatMinted(uint256 hatId, address wearer, bytes memory /*hookData*/ ) external returns (bool success) {
    registerVoterFor(hatId, wearer);
    return true;
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Set voting weight for a hat
  /// @dev Only callable by admin hat wearer
  function setHatVotingWeight(uint256[] memory hatIds, uint256[] memory weights) external {
    _checkUnlocked();
    _checkOwner();
    _setHatsVotingWeight(hatIds, weights);
  }

  /// @notice Set voting weight for multiple hats
  /// @dev Only callable by admin hat wearer
  function setHatsVotingWeight(uint256[] memory hatIds, uint256[] memory weights) external {
    _checkUnlocked();
    _checkOwner();
    _setHatsVotingWeight(hatIds, weights);
  }

  /// @notice Set whether voting weight can be claimed on behalf of hat wearers
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
    // Check hat has voting weight
    if (hatVotingWeight[hatId] == 0) revert HatsVotes_InvalidHat();

    // Check account wears hat
    if (!HATS.isWearerOfHat(account, hatId)) revert HatsVotes_NotHatWearer();

    // Register the hat and timestamp
    voterData[account] = VoterData({ hatId: hatId, registrationTime: block.timestamp });
    emit VoterRegistered(hatId, account, block.timestamp);
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

  function _setHatsVotingWeight(uint256[] memory hatIds, uint256[] memory weights) internal {
    for (uint256 i = 0; i < hatIds.length; i++) {
      hatVotingWeight[hatIds[i]] = weights[i];
    }
    emit HatsVotingWeightSet(hatIds, weights);
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
