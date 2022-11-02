// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@oz/governance/Governor.sol";

abstract contract Funding is Governor {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice Voter has already voted on a proposal in the screening stage in a quarter.
     */
    error AlreadyVoted();

    /**
     * @notice Non Ajna token contract address specified in target list.
     */
    error InvalidTarget();

    /**
     * @notice Non-zero amount specified in values array.
     * @dev This parameter is only used for sending ETH which the GrantFund doesn't utilize.
     */
    error InvalidValues();

    /**
     * @notice Calldata for a method other than `transfer(address,uint256) was provided in a proposal.
     * @dev seth sig "transfer(address,uint256)" == 0xa9059cbb.
     */
    error InvalidSignature();

    // TODO: move this to IGrantFund?
    /**
     * @notice User attempted to submit a proposal with too many target, values or calldatas, or to the wrong method.
     */
    error InvalidProposal();

    error ProposalAlreadyExists();

    error ProposalNotFound();

    /***********************/
    /*** State Variables ***/
    /***********************/

    // address of the ajna token used in grant coordination
    address public ajnaTokenAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /**
     * @notice Mapping checking if a voter has voted on a given proposal.
     * @dev proposalId => address => bool.
     */
    mapping(uint256 => mapping(address => bool)) hasScreened;

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     * @notice Restrict voter to only voting once during the screening stage.
     * @dev    See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId_, address account_) public view override(IGovernor) returns (bool) {
        return hasScreened[proposalId_][account_];
    }
}
