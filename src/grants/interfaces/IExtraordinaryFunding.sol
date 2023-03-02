// SPDX-License-Identifier: MIT

//slither-disable-next-line solc-version
pragma solidity 0.8.16;

/**
 * @title Ajna Grant Coordination Fund Extraordinary Proposal flow.
 */
interface IExtraordinaryFunding {

    /*********************/
    /*** Custom Errors ***/
    /*********************/

    /**
     * @notice User attempted to submit a proposal with invalid parameters.
     */
    error ExtraordinaryFundingProposalInvalid();

    /**
     * @notice The current block isn't in the specified range of active blocks.
     */
    error ExtraordinaryFundingProposalInactive();

    /**
     * @notice Proposal wasn't approved or has already been executed and isn't available for execution.
     */
    error ExecuteExtraordinaryProposalInvalid();

    /***************/
    /*** Structs ***/
    /***************/

    /**
     * @notice Contains information about proposals made to the ExtraordinaryFunding mechanism.
     */
    struct ExtraordinaryFundingProposal {
        uint256  proposalId;      // Unique ID of the proposal. Hashed from proposeExtraordinary inputs.
        uint128  startBlock;      // Block number of the start of the extraordinary funding proposal voting period.
        uint128  endBlock;        // Block number of the end of the extraordinary funding proposal voting period.
        uint248  tokensRequested; // Number of AJNA tokens requested.
        bool     succeeded;       // Whether the proposal succeeded or not.
        uint248  votesReceived;   // Total votes received for this proposal.
        bool     executed;        // Whether the proposal has been executed or not.
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Execute an extraordinary funding proposal if it has passed its' requisite vote threshold.
     * @param targets_         The addresses of the contracts to call.
     * @param values_          The amounts of ETH to send to each target.
     * @param calldatas_       The calldata to send to each target.
     * @param descriptionHash_ The hash of the proposal's description.
     * @return proposalId_     The ID of the executed proposal.
     */
    function executeExtraordinary(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external returns (uint256 proposalId_);

    /**
     * @notice Submit a proposal to the extraordinary funding flow.
     * @param endBlock_            Block number of the end of the extraordinary funding proposal voting period.
     * @param targets_             Array of addresses to send transactions to.
     * @param values_              Array of values to send with transactions.
     * @param calldatas_           Array of calldata to execute in transactions.
     * @param description_         Description of the proposal.
     * @return proposalId_         ID of the newly submitted proposal.
     */
    function proposeExtraordinary(
        uint256 endBlock_,
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        string memory description_
    ) external returns (uint256 proposalId_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param  percentage_ The percentage of the Non treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getSliceOfNonTreasury(
        uint256 percentage_
    ) external view returns (uint256);

    /**
     * @notice Get the number of ajna tokens equivalent to a given percentage.
     * @param percentage_ The percentage of the treasury to retrieve, in WAD.
     * @return The number of tokens, in WAD.
     */
    function getSliceOfTreasury(
        uint256 percentage_
    ) external view returns (uint256);

    /**
     *  @notice Mapping of proposalIds to {ExtraordinaryFundingProposal} structs.
     *  @param  proposalId_     The proposalId to retrieve information about.
     *  @return proposalId      The retrieved struct's proposalId.
     *  @return tokensRequested Amount of Ajna tokens requested by the proposal.
     *  @return startBlock      The block at which the proposal was submitted.
     *  @return endBlock        The block by which the proposal must pass.
     *  @return votesReceived   Number of votes the proposal has received. One Ajna token is one vote.
     *  @return succeeded       Whether the proposal received enough votes to pass required thresholds.
     *  @return executed        Whether a succesful proposal has been executed.
     */
    function getExtraordinaryProposalInfo(
        uint256 proposalId_
    ) external view returns (uint256, uint256, uint256, uint256, uint256, bool, bool);

    /**
     * @notice Get the current minimum threshold percentage of Ajna tokens required for a proposal to exceed.
     * @return The minimum threshold percentage, in WAD.
     */
    function getMinimumThresholdPercentage() external view returns (uint256);

}
