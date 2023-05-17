// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.18;

/**
 * @title Ajna Grant Coordination Fund Extraordinary Proposal flow.
 */
interface IFunding {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice Voter has already voted on a proposal in the screening stage in a quarter.
     */
    error AlreadyVoted();

    /**
     * @notice User submitted a proposal with invalid parameteres.
     * @dev    A proposal is invalid if it has a mismatch in the number of targets, values, or calldatas.
     * @dev    It is also invalid if it's calldata selector doesn't equal transfer().
     */
    error InvalidProposal();

    /**
     * @notice User attempted to cast an invalid vote (outside of the distribution period, ).
     * @dev    This error is thrown when the user attempts to vote outside of the allowed period, vote with 0 votes, or vote with more than their voting power.
     */
    error InvalidVote();

    /**
     * @notice User attempted to submit a duplicate proposal.
     */
    error ProposalAlreadyExists();

    /**
     * @notice Proposal didn't meet requirements for execution.
     */
    error ProposalNotSuccessful();

    /*********************/
    /*** Custom Events ***/
    /*********************/

    /**
     * @dev Emitted when a proposal is executed.
     */
    event ProposalExecuted(uint256 proposalId);

    /**
     * @dev Emitted when a proposal is created.
     */
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    /**
     * @dev Emitted when votes are cast on a proposal.
     */
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Enum listing available proposal types.
     */
    enum FundingMechanism {
        Standard,
        Extraordinary
    }

    /**
     * @dev Enum listing a proposal's lifecycle.
     */
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }
}
