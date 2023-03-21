// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IFunding } from "../interfaces/IFunding.sol";
import { IExtraordinaryFunding } from "../interfaces/IExtraordinaryFunding.sol";
import { IStandardFunding }      from "../interfaces/IStandardFunding.sol";

interface IGrantFund is
    IFunding,
    IExtraordinaryFunding,
    IStandardFunding
{

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when Ajna tokens are transferred to the GrantFund contract.
     *  @param  amount          Amount of Ajna tokens transferred.
     *  @param  treasuryBalance GrantFund's total treasury balance after the transfer.
     */
    event FundTreasury(uint256 amount, uint256 treasuryBalance);

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Create a proposalId from a hash of proposal's targets, values, and calldatas arrays, and a description hash.
     * @dev    Consistent with proposalId generation methods used in OpenZeppelin Governor.
     * @param targets_         The addresses of the contracts to call.
     * @param values_          The amounts of ETH to send to each target.
     * @param calldatas_       The calldata to send to each target.
     * @param descriptionHash_ The hash of the proposal's description string. Generated by keccak256(bytes(description))).
     * @return proposalId_     The hashed proposalId created from the provided params.
     */
    function hashProposal(
        address[] memory targets_,
        uint256[] memory values_,
        bytes[] memory calldatas_,
        bytes32 descriptionHash_
    ) external pure returns (uint256 proposalId_);

    /**
     * @notice Find the status of a given proposal.
     * @dev Check proposal status based upon Grant Fund specific logic.
     * @param proposalId_ The id of the proposal to query the status of.
     * @return ProposalState of the given proposal.
     */
    function state(
        uint256 proposalId_
    ) external view returns (ProposalState);

    /**************************/
    /*** Treasury Functions ***/
    /**************************/

    /**
     * @notice Transfers Ajna tokens to the GrantFund contract.
     * @param fundingAmount_ The amount of Ajna tokens to transfer.
     * @return ProposalState of the given proposal.
     */
    function fundTreasury(uint256 fundingAmount_) external returns (uint256);

}
