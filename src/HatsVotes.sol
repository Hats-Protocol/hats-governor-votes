// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

interface IHatMintHook {
  function onHatMinted(uint256 hatId, address wearer, bytes memory hookData) external returns (bool success);
}

/// @title HatsVotes
/// @notice A Hats Protocol-enabled implementation of IVotes that assigns voting weight based on wearing a hat.
///   Wearers of a hat can register to receive voting weight on proposals created after their registration.
///   They must wear the hat to have voting weight at any point in time.
contract HatsVotes is IVotes, IHatMintHook {
  /*//////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/
  error HatsVotes_NotAdmin();
  error HatsVotes_InvalidHat();
  error HatsVotes_NotHatWearer();
  error HatsVotes_AlreadyRegistered();
  error HatsVotes_NotRegisterableFor();
  error HatsVotes_ReregistrationNotAllowed();
  error HatsVotes_Locked();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/
  event VoterRegistered(uint256 hatId, address voter, uint256 registrationTime);
  event RegisterableForSet(bool registerableFor);
  event OwnerHatSet(uint256 ownerHat);
  event Locked();
  event HatsVotingWeightSet(uint256[] hatIds, uint256[] votingWeights);

  /*//////////////////////////////////////////////////////////////
                              DATA MODELS
  //////////////////////////////////////////////////////////////*/
  /// @notice Struct to store a voter's registration data
  /// @param hatId The hat with which the voter is registered
  /// @param time The unix timestamp of when the voter registered
  struct VoterRegistration {
    uint256 hatId;
    uint256 time;
  }

  /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
  //////////////////////////////////////////////////////////////*/
  /// @notice The Hats Protocol contract
  IHats public immutable HATS;

  /// @notice Whether the contract is locked from further owner changes
  bool public locked;

  /// @notice Whether it is possible to register (ie claim voting weight) on behalf of a voter
  bool public registerableFor;

  /// @notice The owner hat that can configure voting weight
  uint256 public ownerHat;

  /// @notice Mapping of hat ID to voting weight
  mapping(uint256 hatId => uint256 votingWeight) public hatVotingWeight;

  /// @notice Mapping of account to voter registration data
  mapping(address voter => VoterRegistration registration) public voterRegistry;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/
  constructor(
    address hats,
    uint256 _ownerHat,
    bool _registerableFor,
    uint256[] memory _hatIds,
    uint256[] memory _weights
  ) {
    HATS = IHats(hats);
    _setOwnerHat(_ownerHat);
    _setRegisterableFor(_registerableFor);
    _setHatsVotingWeight(_hatIds, _weights);
  }

  // TODO determine how instances of this contract should be deployed
  // - via HatsModuleFactory (and then initialized with a setUp function)?
  // - via some other create2 factory and then intialized with a setUp function?
  // - with a standard constructor?

  /*//////////////////////////////////////////////////////////////
                    IMPLEMENTED IVOTES FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IVotes
  function getVotes(address account) public view returns (uint256) {
    return _getVotes(voterRegistry[account].hatId);
  }

  /// @inheritdoc IVotes
  function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
    VoterRegistration memory registration = voterRegistry[account];
    // Voters must have registered before the timepoint to have voting weight
    if (registration.time > timepoint) return 0;
    return _getVotes(registration.hatId);
  }

  /// @inheritdoc IVotes
  /// @notice A voter's delegate is always themselves, since hats already represent delegated authority
  function delegates(address account) external pure returns (address) {
    return account;
  }

  /*//////////////////////////////////////////////////////////////
                    VOTER REGISTRATION FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Register yourself as a voter with a valid hat
  function registerVoter(uint256 hatId) external {
    _registerVoter(hatId, msg.sender);
  }

  /// @notice Register someone else as a voter with a valid hat
  function registerVoterFor(uint256 hatId, address account) public {
    require(registerableFor, HatsVotes_NotRegisterableFor());
    _registerVoter(hatId, account);
  }

  /// @inheritdoc IHatMintHook
  /// @notice This hook is called when a hat is minted from a hook-enabled contract, such as MultiClaimsHatter
  function onHatMinted(uint256 hatId, address wearer, bytes memory /*hookData*/ ) external returns (bool success) {
    registerVoterFor(hatId, wearer);
    return true;
  }

  /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Set voting weight for multiple hats
  /// @dev Only callable by owner hat wearer and when contract is not locked
  /// @param hatIds The hat IDs to set voting weight for
  /// @param weights The voting weights to set for the hats
  function setHatsVotingWeight(uint256[] memory hatIds, uint256[] memory weights) external {
    _checkUnlocked();
    _checkOwner();
    _setHatsVotingWeight(hatIds, weights);
  }

  /// @notice Set whether it is possible to register (ie claim voting weight) on behalf of a voter
  /// @dev Only callable by owner hat wearer and when contract is not locked
  function setRegisterableFor(bool _registerableFor) external {
    _checkUnlocked();
    _checkOwner();
    _setRegisterableFor(_registerableFor);
  }

  /// @notice Set the owner hat
  /// @dev Only callable by owner hat wearer and when contract is not locked
  function setOwnerHat(uint256 _ownerHat) external {
    _checkUnlocked();
    _checkOwner();
    _setOwnerHat(_ownerHat);
  }

  /// @notice Lock the contract from further owner changes
  /// @dev Only callable by owner hat wearer and when contract is not locked
  function lock() external {
    _checkUnlocked();
    _checkOwner();
    locked = true;
    emit Locked();
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Internal function to calculate a voter's voting weight from their registered hat. The voter must be
  /// wearing the hat to have voting weight.
  function _getVotes(uint256 hatId) internal view returns (uint256) {
    if (HATS.isWearerOfHat(msg.sender, hatId)) return hatVotingWeight[hatId];
    else return 0;
  }

  function _registerVoter(uint256 hatId, address account) internal {
    // Check hat has voting weight
    require(hatVotingWeight[hatId] > 0, HatsVotes_InvalidHat());

    // Check that the voter is not already registered for this hat
    require(voterRegistry[account].hatId != hatId, HatsVotes_AlreadyRegistered());

    // Check account wears hat
    require(HATS.isWearerOfHat(account, hatId), HatsVotes_NotHatWearer());

    // Register the hat and timestamp
    voterRegistry[account] = VoterRegistration({ hatId: hatId, time: block.timestamp });
    emit VoterRegistered(hatId, account, block.timestamp);
  }

  function _checkOwner() internal view {
    require(HATS.isWearerOfHat(msg.sender, ownerHat), HatsVotes_NotAdmin());
  }

  function _checkUnlocked() internal view {
    require(!locked, HatsVotes_Locked());
  }

  function _setOwnerHat(uint256 _ownerHat) internal {
    ownerHat = _ownerHat;
    emit OwnerHatSet(_ownerHat);
  }

  function _setRegisterableFor(bool _registerableFor) internal {
    registerableFor = _registerableFor;
    emit RegisterableForSet(_registerableFor);
  }

  function _setHatsVotingWeight(uint256[] memory hatIds, uint256[] memory weights) internal {
    for (uint256 i = 0; i < hatIds.length; i++) {
      hatVotingWeight[hatIds[i]] = weights[i];
    }
    emit HatsVotingWeightSet(hatIds, weights);
  }

  /*//////////////////////////////////////////////////////////////
                        EMPTY IVOTES IMPLEMENTATIONS
  //////////////////////////////////////////////////////////////*/

  /// @dev Not implemented since hats already represent delegated authority
  function delegate(address) external pure {
    return;
  }

  /// @dev Not implemented since hats already represent delegated authority
  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
    return;
  }

  /* 
  TODO should we implement this?

  Option A: track registrations (* voting weight per hat)
  - would require adding functionality to deregister voters, but any latency between the revocation of a hat and the
  corresponding deregistration could distort quorum calculations
  
  Option B: sum up supply of all voting hats (* voting weight per hat)
  - would require an iterable data structure for voting hats
  - hat.supply is not always up to date, eg if there are dynamic hat revocations that don't update Hats.sol storage

  Option C: don't implement
  - incompatible with proportional quorum calculations
  */
  function getPastTotalSupply(uint256) external pure returns (uint256) {
    return 0;
  }
}
