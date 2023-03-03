// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Governor }    from "@oz/governance/Governor.sol";
import { IGovernor }   from "@oz/governance/IGovernor.sol";
import { IVotes }      from "@oz/governance/utils/IVotes.sol";

import { Maths } from "./libraries/Maths.sol";

import { ExtraordinaryFunding } from "./base/ExtraordinaryFunding.sol";
import { StandardFunding }      from "./base/StandardFunding.sol";

import { IGrantFund } from "./interfaces/IGrantFund.sol";

contract GrantFund is IGrantFund, ExtraordinaryFunding, StandardFunding {

    IVotes public immutable token;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(IVotes token_, uint256 treasury_)
        Governor("AjnaEcosystemGrantFund")
    {
        ajnaTokenAddress = address(token_);
        token = token_;
        treasury = treasury_;
    }

    /**************************/
    /*** Proposal Functions ***/
    /**************************/

    /**
     * @notice Overide the default proposal function to ensure all proposal submission travel through expected mechanisms.
     */
    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) public pure override(Governor) returns (uint256) {
        revert InvalidProposal();
    }

    /**
     * @notice Overriding the default execute function to ensure all proposals travel through expected mechanisms.
     */
    function execute(address[] memory, uint256[] memory, bytes[] memory, bytes32) public payable override(Governor) returns (uint256) {
        revert MethodNotImplemented();
    }

    /**
     * @notice Given a proposalId, find if it is a standard or extraordinary proposal.
     * @param proposalId_ The id of the proposal to query the mechanism of.
     * @return FundingMechanism to which the proposal was submitted.
     */
    function findMechanismOfProposal(
        uint256 proposalId_
    ) public view returns (FundingMechanism) {
        if (standardFundingProposals[proposalId_].proposalId != 0)           return FundingMechanism.Standard;
        else if (extraordinaryFundingProposals[proposalId_].proposalId != 0) return FundingMechanism.Extraordinary;
        else revert ProposalNotFound();
    }

    /**
     * @notice Find the status of a given proposal.
     * @dev Overrides Governor.state() to check proposal status based upon Grant Fund specific logic.
     * @param proposalId_ The id of the proposal to query the status of.
     * @return ProposalState of the given proposal.
     */
    function state(
        uint256 proposalId_
    ) public view override(Governor) returns (IGovernor.ProposalState) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // standard proposal state checks
        if (mechanism == FundingMechanism.Standard) {
            Proposal memory proposal = standardFundingProposals[proposalId_];
            if (proposal.executed)                                                    return IGovernor.ProposalState.Executed;
            else if (distributions[proposal.distributionId].endBlock >= block.number) return IGovernor.ProposalState.Active;
            else if (_standardFundingVoteSucceeded(proposalId_))                      return IGovernor.ProposalState.Succeeded;
            else                                                                      return IGovernor.ProposalState.Defeated;
        }
        // extraordinary funding proposal state
        else {
            bool voteSucceeded = _extraordinaryFundingVoteSucceeded(proposalId_);

            if (extraordinaryFundingProposals[proposalId_].executed)                                         return IGovernor.ProposalState.Executed;
            else if (extraordinaryFundingProposals[proposalId_].endBlock >= block.number && !voteSucceeded)  return IGovernor.ProposalState.Active;
            else if (voteSucceeded)                                                                          return IGovernor.ProposalState.Succeeded;
            else                                                                                             return IGovernor.ProposalState.Defeated;
        }
    }

    /************************/
    /*** Voting Functions ***/
    /************************/

    /**
     * @notice Cast an array of funding votes in one transaction.
     * @dev    Calls out to StandardFunding._fundingVote().
     * @dev    Only iterates through a maximum of 10 proposals that made it through the screening round.
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param voteParams_ The array of votes on proposals to cast.
     * @return votesCast_ The total number of votes cast across all of the proposals.
     */
    function fundingVotesMulti(
        FundingVoteParams[] memory voteParams_
    ) external returns (uint256 votesCast_) {
        QuarterlyDistribution storage currentDistribution = distributions[currentDistributionId];
        QuadraticVoter        storage voter               = quadraticVoters[currentDistribution.id][msg.sender];

        uint256 endBlock = currentDistribution.endBlock;

        uint256 screeningStageEndBlock = _getScreeningStageEndBlock(endBlock);

        // check that the funding stage is active
        if (block.number > screeningStageEndBlock && block.number <= endBlock) {

            // this is the first time a voter has attempted to vote this period,
            // set initial voting power and remaining voting power
            if (voter.votingPower == 0) {

                uint128 newVotingPower = uint128(_getFundingStageVotingPower(msg.sender, screeningStageEndBlock));

                voter.votingPower          = newVotingPower;
                voter.remainingVotingPower = newVotingPower;
            }

            uint256 numVotesCast = voteParams_.length;

            for (uint256 i = 0; i < numVotesCast; ) {
                Proposal storage proposal = standardFundingProposals[voteParams_[i].proposalId];

                // check that the proposal is part of the current distribution period
                if (proposal.distributionId != currentDistribution.id) revert InvalidVote();

                // cast each successive vote
                votesCast_ += _fundingVote(
                    currentDistribution,
                    proposal,
                    msg.sender,
                    voter,
                    voteParams_[i]
                );

                unchecked { ++i; }
            }
        }
    }

    /**
     * @notice Cast an array of screening votes in one transaction.
     * @dev    Calls out to StandardFunding._screeningVote().
     * @dev    Counters incremented in an unchecked block due to being bounded by array length.
     * @param voteParams_ The array of votes on proposals to cast.
     * @return votesCast_ The total number of votes cast across all of the proposals.
     */
    function screeningVoteMulti(
        ScreeningVoteParams[] memory voteParams_
    ) external returns (uint256 votesCast_) {
        QuarterlyDistribution memory currentDistribution = distributions[currentDistributionId];

        // check screening stage is active
        if (block.number >= currentDistribution.startBlock && block.number <= _getScreeningStageEndBlock(currentDistribution.endBlock)) {

            uint256 numVotesCast = voteParams_.length;

            for (uint256 i = 0; i < numVotesCast; ) {
                Proposal storage proposal = standardFundingProposals[voteParams_[i].proposalId];

                // check that the proposal is part of the current distribution period
                if (proposal.distributionId != currentDistribution.id) revert InvalidVote();

                uint256 votes = voteParams_[i].votes;

                // cast each successive vote
                votesCast_ += votes;
                _screeningVote(msg.sender, proposal, votes);

                unchecked { ++i; }
            }
        }
    }

    /**
     * @notice Vote on a proposal in the screening or funding stage of the Distribution Period.
     * @dev Override channels all other castVote methods through here.
     * @param proposalId_ The current proposal being voted upon.
     * @param account_    The voting account.
     * @param params_     The amount of votes being allocated in the funding stage.
     * @return votesCast_ The amount of votes cast.
     */
     function _castVote(
        uint256 proposalId_,
        address account_,
        uint8,
        string memory,
        bytes memory params_
    ) internal override(Governor) returns (uint256 votesCast_) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // standard funding mechanism
        if (mechanism == FundingMechanism.Standard) {
            Proposal storage proposal = standardFundingProposals[proposalId_];

            uint24 distributionId = proposal.distributionId;

            // check that the proposal is part of the current distribution period
            if (distributionId != currentDistributionId) revert InvalidVote();

            QuarterlyDistribution storage currentDistribution = distributions[distributionId];

            uint256 endBlock = currentDistribution.endBlock;
            uint256 screeningStageEndBlock = _getScreeningStageEndBlock(endBlock);

            // screening stage
            if (block.number >= currentDistribution.startBlock && block.number <= screeningStageEndBlock) {

                // decode the amount of votes to allocated to the proposal
                votesCast_ = abi.decode(params_, (uint256));

                // allocate the votes to the proposal
                _screeningVote(account_, proposal, votesCast_);
            }

            // funding stage
            else if (block.number > screeningStageEndBlock && block.number <= endBlock) {
                QuadraticVoter storage voter = quadraticVoters[currentDistribution.id][account_];

                // this is the first time a voter has attempted to vote this period,
                // set initial voting power and remaining voting power
                if (voter.votingPower == 0) {

                    uint128 newVotingPower = uint128(_getFundingStageVotingPower(msg.sender, screeningStageEndBlock));

                    voter.votingPower          = newVotingPower;
                    voter.remainingVotingPower = newVotingPower;
                }

                // decode the amount of votes to allocated to the proposal
                FundingVoteParams memory newVote = FundingVoteParams(proposalId_, abi.decode(params_, (int256)));

                // allocate the votes to the proposal
                votesCast_ = _fundingVote(currentDistribution, proposal, account_, voter, newVote);
            }
        }

        // extraordinary funding mechanism
        else {
            votesCast_ = _extraordinaryFundingVote(proposalId_, account_);
        }
    }

    /**
     * @notice Calculates the number of votes available to an account depending on the current stage of the Distribution Period.
     * @dev    Overrides OpenZeppelin _getVotes implementation to ensure appropriate voting weight is always returned.
     * @dev    Snapshot checks are built into this function to ensure accurate power is returned regardless of the caller.
     * @dev    Number of votes available is equivalent to the usage of voting weight in the super class.
     * @param  account_        The voting account.
     * @param  params_         Params used to pass stage for Standard, and proposalId for extraordinary.
     * @return availableVotes_ The number of votes available to an account in a given stage.
     */
    function _getVotes(
        address account_,
        uint256,
        bytes memory params_
    ) internal view override(Governor) returns (uint256 availableVotes_) {
        QuarterlyDistribution memory currentDistribution = distributions[currentDistributionId];

        // within screening period 1 token 1 vote
        if (keccak256(params_) == keccak256(bytes("Screening"))) {
            // calculate voting weight based on the number of tokens held at the snapshot blocks of the screening stage
            availableVotes_ = _getVotesSinceSnapshot(
                account_,
                currentDistribution.startBlock - VOTING_POWER_SNAPSHOT_DELAY,
                currentDistribution.startBlock
            );
        }
        // else if in funding period quadratic formula squares the number of votes
        else if (keccak256(params_) == keccak256(bytes("Funding"))) {
            QuadraticVoter memory voter = quadraticVoters[currentDistribution.id][account_];

            // voter has already allocated some of their budget this period
            if (voter.votingPower != 0) {
                availableVotes_ = voter.remainingVotingPower;
            }
            // voter hasn't yet called _castVote in this period
            else {
                availableVotes_ = _getFundingStageVotingPower(account_, _getScreeningStageEndBlock(currentDistribution.endBlock));
            }
        }
        else {
            if (params_.length != 0) {
                // attempt to decode a proposalId from the params
                uint256 proposalId = abi.decode(params_, (uint256));

                // one token one vote for extraordinary funding
                if (proposalId != 0) {
                    // get the number of votes available to voters at the start of the proposal, and 33 blocks before the start of the proposal
                    uint256 startBlock = extraordinaryFundingProposals[proposalId].startBlock;

                    availableVotes_ = _getVotesSinceSnapshot(
                        account_,
                        startBlock - VOTING_POWER_SNAPSHOT_DELAY,
                        startBlock
                    );
                }
            }
            // voting is not possible for non-specified pathways
            else {
                availableVotes_ = 0;
            }
        }
    }
     /**
     * @notice Retrieve the funding stage voting power of an account.
     * @dev    Returns the square of the voter's voting power at the snapshot blocks.
     * @param account_                The voting account.
     * @param screeningStageEndBlock_ The block number at which the screening stage end and the funding stage beings.
     * @return votingPower_           The voting power of the account.
     */
    function _getFundingStageVotingPower(address account_, uint256 screeningStageEndBlock_) internal view returns (uint256 votingPower_) {
        votingPower_ = Maths.wpow(
            _getVotesSinceSnapshot(
                account_,
                screeningStageEndBlock_ - VOTING_POWER_SNAPSHOT_DELAY,
                screeningStageEndBlock_
            ), 2
        );
    }

     /**
     * @notice Retrieve the voting power of an account.
     * @dev    Voting power is the minimum of the amount of votes available at a snapshot block 33 blocks prior to voting start, and at the vote starting block.
     * @param account_        The voting account.
     * @param snapshot_       One of the block numbers to retrieve the voting power at. 33 blocks prior to the block at which a proposal is available for voting.
     * @param voteStartBlock_ The block number the proposal became available for voting.
     * @return                The voting power of the account.
     */
    function _getVotesSinceSnapshot(
        address account_,
        uint256 snapshot_,
        uint256 voteStartBlock_
    ) internal view returns (uint256) {
        // calculate the number of votes available at the snapshot block
        uint256 votes1 = token.getPastVotes(account_, snapshot_);

        // enable voting weight to be calculated during the voting period's start block
        voteStartBlock_ = voteStartBlock_ != block.number ? voteStartBlock_ : block.number - 1;

        // calculate the number of votes available at the stage's start block
        uint256 votes2 = token.getPastVotes(account_, voteStartBlock_);

        return Maths.min(votes2, votes1);
    }

    /**************************/
    /*** Required Overrides ***/
    /**************************/

     /**
     * @notice Check whether an account has voted on a proposal.
     * @dev    Votes can only votes once during the screening stage, and only once on proposals in the extraordinary funding round.
               In the funding stage they can vote as long as they have budget.
     * @dev    See {IGovernor-hasVoted}.
     * @return hasVoted_ Boolean for whether the account has already voted in the current proposal, and mechanism.
     */
    function hasVoted(
        uint256 proposalId_,
        address account_
    ) public view override(IGovernor) returns (bool hasVoted_) {
        FundingMechanism mechanism = findMechanismOfProposal(proposalId_);

        // Checks if Proposal is Standard
        if (mechanism == FundingMechanism.Standard) {
            Proposal              memory proposal            = standardFundingProposals[proposalId_]; 
            QuarterlyDistribution memory currentDistribution = distributions[proposal.distributionId];

            uint256 screeningStageEndBlock = _getScreeningStageEndBlock(currentDistribution.endBlock);

            // screening stage
            if (block.number >= currentDistribution.startBlock && block.number <= screeningStageEndBlock) {
                hasVoted_ = screeningVotesCast[proposal.distributionId][account_] != 0;
            }

            // funding stage
            else if (block.number > screeningStageEndBlock && block.number <= currentDistribution.endBlock) {
                hasVoted_ = quadraticVoters[currentDistribution.id][account_].votesCast.length != 0;
            }
        }
        else {
            hasVoted_ = hasVotedExtraordinary[proposalId_][account_];
        }
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // slither-disable-next-line naming-convention
    function COUNTING_MODE() public pure override(IGovernor) returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @notice Required override; not currently used due to divergence in voting logic.
     * @dev    See {IGovernor-_countVote}.
     */
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory) internal override(Governor) {}

    /**
     * @notice Required override used in Governor.state()
     * @dev Since no quorum is used, but this is called as part of state(), this is hardcoded to true.
     * @dev See {IGovernor-quorumReached}.
     */
    // slither-disable-next-line dead-code
    function _quorumReached(uint256) internal pure override(Governor) returns (bool) {
        return true;
    }

   /**
     * @notice Required override; not currently used due to divergence in voting logic.
     * @dev    See {IGovernor-quorum}.
     */
    function quorum(uint256) public pure override(IGovernor) returns (uint256) {}

   /**
     * @notice Required override; not currently used due to divergence in voting logic.
     * @dev    Replaced by mechanism specific voteSucceeded functions.
     * @dev    See {IGovernor-quorum}.
     */
    // slither-disable-next-line dead-code
    function _voteSucceeded(uint256 proposalId) internal view override(Governor) returns (bool) {}

    /**
     * @notice Required override.
     * @dev    Since no voting delay is implemented, this is hardcoded to 0.
     */
    function votingDelay() public pure override(IGovernor) returns (uint256) {
        return 0;
    }

    /**
     * @notice Required override; see {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view override(IGovernor) returns (uint256) {}

}
