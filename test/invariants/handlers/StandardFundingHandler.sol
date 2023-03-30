// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Test }     from "forge-std/Test.sol";
import { IVotes }   from "@oz/governance/utils/IVotes.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { GrantFund }        from "../../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../../src/grants/interfaces/IStandardFunding.sol";
import { Maths }            from "../../../src/grants/libraries/Maths.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { FundingHandler }      from "./FundingHandler.sol";

import { console } from "@std/console.sol";

contract StandardFundingHandler is FundingHandler {

    // record standard funding proposals over time
    // proposal count
    uint256 public standardFundingProposalCount;
    // list of submitted standard funding proposals
    uint256[] public standardFundingProposals;

    uint256 public screeningVotesCast;

    // time counter
    uint256 private systemTime = 0;

    struct VotingActor {
        IStandardFunding.FundingVoteParams[] fundingVotes;
        IStandardFunding.ScreeningVoteParams[] screeningVotes;
    }

    struct DistributionState {
        uint24 distributionId;
        bytes32 currentTopSlate;
    }

    mapping(uint24 => DistributionState) public distributionStates;
    mapping(bytes32 => uint256[]) public proposalsInTopSlate;
    mapping(address => VotingActor) internal votingActors; // record the votes of actors over time

    constructor(
        address payable grantFund_,
        address token_,
        address tokenDeployer_,
        uint256 numOfActors_,
        uint256 tokensToDistribute_
    ) FundingHandler(grantFund_, token_, tokenDeployer_, numOfActors_, tokensToDistribute_) {}

    /*********************/
    /*** SFM Functions ***/
    /*********************/

    function startNewDistributionPeriod(uint256 actorIndex_) external useRandomActor(actorIndex_) returns (uint24 newDistributionId_) {
        numberOfCalls['SFH.startNewDistributionPeriod']++;
        systemTime++;

        // vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);

        try _grantFund.startNewDistributionPeriod() returns (uint24 newDistributionId) {
            newDistributionId_ = newDistributionId;
            // FIXME: remove this
            vm.roll(block.number + 100);
            vm.rollFork(block.number + 100);
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("DistributionPeriodStillActive()"))
            );
        }
    }

    function proposeStandard(uint256 actorIndex_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.proposeStandard']++;
        systemTime++;

        // get a random number between 1 and 5
        uint256 numProposalParams = constrictToRange(randomSeed(), 1, 5);

        // generate list of recipients and tokens requested
        TestProposalParams[] memory testProposalParams = generateTestProposalParams(numProposalParams);

        // generate proposal params
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = generateProposalParams(testProposalParams);

        console.log("description", description);
        try _grantFund.proposeStandard(targets, values, calldatas, description) returns (uint256 proposalId) {
            standardFundingProposals.push(proposalId);
            standardFundingProposalCount++;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("ProposalAlreadyExists()")) ||
                err == keccak256(abi.encodeWithSignature("ScreeningPeriodEnded()")) ||
                err == keccak256(abi.encodeWithSignature("InvalidProposal()"))
            );
        }

    }

    function screeningVote(uint256 actorIndex_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.screeningVote']++;

        systemTime++;

        // bind proposalsToVoteOn_ to the number of proposals
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);
        // vm.rollFork(block.number + 100);

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), _actor);

        // construct vote params
        IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams = new IStandardFunding.ScreeningVoteParams[](proposalsToVoteOn_);
        for (uint256 i = 0; i < proposalsToVoteOn_; i++) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // generate screening vote params
            screeningVoteParams[i] = IStandardFunding.ScreeningVoteParams({
                proposalId: proposalId,
                votes: constrictToRange(randomSeed(), 0, votingPower) // FIXME: account for previously used voting power
            });
        }

        try _grantFund.screeningVote(screeningVoteParams) {
            // update actor screeningVotes count if vote was successful
            VotingActor storage actor = votingActors[_actor];

            for (uint256 i = 0; i < proposalsToVoteOn_; ) {
                IStandardFunding.ScreeningVoteParams[] storage existingScreeningVoteParams = actor.screeningVotes;
                // existingScreeningVoteParams.push(screeningVoteParams);
                actor.screeningVotes.push(screeningVoteParams[i]);
                screeningVotesCast++;

                ++i;
            }
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()"))
            );
        }
    }

    function fundingVote(uint256 actorIndex_, uint256 proposalsToVoteOn_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.fundingVote']++;
        systemTime++;

        // bind proposalsToVoteOn_ to the number of proposals
        proposalsToVoteOn_ = bound(proposalsToVoteOn_, 0, standardFundingProposals.length);

        vm.roll(block.number + 100);

        // TODO: implement time counter incremeneted monotonically per call depth
        // check where block is in the distribution period
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        if (block.number < endBlock - 72000) {

        //     // check if we should activate the funding stage
        //     if (systemTime >= 1500) {
        //         // skip time into the funding stage
        //         uint256 fundingStageStartBlock = endBlock - 72000;
        //         vm.roll(fundingStageStartBlock + 100);
        //         numberOfCalls['SFH.FundingStage']++;
        //     }
        //     else {
                return;
        //     }
        }

        // get actor voting power
        uint256 votingPower = _grantFund.getVotesFunding(_grantFund.getDistributionId(), _actor);

        // Take the square root of the voting power to determine how many votes are actually available for casting
        uint256 availableVotes = _grantFund.getFundingPowerVotes(votingPower);

        // construct vote params
        IStandardFunding.FundingVoteParams[] memory fundingVoteParams = new IStandardFunding.FundingVoteParams[](proposalsToVoteOn_);
        for (uint256 i = 0; i < proposalsToVoteOn_; ) {
            // TODO: replace proposalId with retrieval from top ten list?
            uint256 proposalId = randomProposal();

            // TODO: account for past votes cast in determining votes to use
            int256 votesToCast = int256(constrictToRange(randomSeed(), 0, availableVotes));

            // flip a coin to see if should instead use a negative vote
            if (randomSeed() % 2 == 0) {
                numberOfCalls['SFH.negativeFundingVote']++;
                // generate negative vote
                fundingVoteParams[i] = IStandardFunding.FundingVoteParams({
                    proposalId: proposalId,
                    votesUsed: -1 * votesToCast
                });
                ++i;
                continue;
            }

            fundingVoteParams[i] = IStandardFunding.FundingVoteParams({
                proposalId: proposalId,
                votesUsed: votesToCast
            });

            ++i;
        }

        try _grantFund.fundingVote(fundingVoteParams) returns (uint256 votesCast) {
            numberOfCalls['SFH.fundingVote.success']++;

            // assertGt(votesCast, 0);

            // TODO: account for possibly being negative
            // check votesCast is equal to the sum of votes cast
            assertEq(votesCast, SafeCast.toUint256(sumVoterFundingVotes(_actor, fundingVoteParams)));

            // update actor funding votes counts
            // TODO: find and replace previous vote record for that proposlId, in that distributonId
            VotingActor storage actor = votingActors[_actor];
            for (uint256 i = 0; i < proposalsToVoteOn_; ) {

                // update existing proposal voting record as opposed to a new entry in the list
                int256 voteCastIndex = _findProposalIndexOfVotesCast(fundingVoteParams[i].proposalId, actor.fundingVotes);
                // voter had already cast a funding vote on this proposal
                if (voteCastIndex != -1) {
                    actor.fundingVotes[uint256(voteCastIndex)].votesUsed += fundingVoteParams[i].votesUsed;
                }
                else {
                    actor.fundingVotes.push(fundingVoteParams[i]);
                }

                ++i;
            }
        }
        catch (bytes memory _err){
            // TODO: replace with _recordError()
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidVote()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()")) ||
                err == keccak256(abi.encodeWithSignature("FundingVoteWrongDirection()"))
            );
        }
    }

    function updateSlate(uint256 actorIndex_, uint256 proposalSeed) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.updateSlate']++;
        systemTime++;

        // check that the distribution period ended
        if (keccak256(getStage()) != keccak256(bytes("Challenge"))) {
            return;
        }

        if (systemTime > 2800) {
            return;
        }

        uint256 potentialSlateLength = constrictToRange(proposalSeed, 0, 10);
        uint24 distributionId = _grantFund.getDistributionId();

        // get top ten proposals
        uint256[] memory topTen = _grantFund.getTopTenProposals(distributionId);
        // construct potential slate of proposals
        uint256[] memory potentialSlate = new uint256[](potentialSlateLength);

        // get random potentialSlate of proposals
        for (uint i = 0; i < potentialSlateLength; ++i) {
            potentialSlate[i] = topTen[randomSeed() % 10];
        }

        try _grantFund.updateSlate(potentialSlate, distributionId) returns (bool newTopSlate) {
            numberOfCalls['SFH.updateSlate.called']++;
            if (newTopSlate) {
                numberOfCalls['SFH.updateSlate.success']++;

                // update distribution state
                DistributionState storage distribution = distributionStates[distributionId];
                distribution.distributionId = distributionId;
                distribution.currentTopSlate = keccak256(abi.encode(potentialSlate));

                // update list of proposals in top slate
                for (uint i = 0; i < potentialSlateLength; ++i) {
                    proposalsInTopSlate[distribution.currentTopSlate].push(potentialSlate[i]);
                }
            }
        }
        catch (bytes memory _err){
            // TODO: replace with _recordError()
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidProposalSlate()"))
            );
        }
    }

    function executeStandard(uint256 actorIndex_) external useRandomActor(actorIndex_) {
        numberOfCalls['SFH.executeStandard']++;
        systemTime++;

    }

    /*****************************/
    /*** SFM Utility Functions ***/
    /*****************************/

    function generateProposalParams(TestProposalParams[] memory testProposalParams_) internal view
        returns(
            address[] memory targets_,
            uint256[] memory values_,
            bytes[] memory calldatas_,
            string memory description_
        ) {

        uint256 numParams = testProposalParams_.length;
        targets_ = new address[](numParams);
        values_ = new uint256[](numParams);
        calldatas_ = new bytes[](numParams);

        // generate description string
        string memory descriptionPartOne = "Proposal to transfer ";
        string memory descriptionPartTwo;

        for (uint256 i = 0; i < numParams; ++i) {
            targets_[i] = address(_token);
            values_[i] = 0;
            calldatas_[i] = abi.encodeWithSignature(
                "transfer(address,uint256)",
                testProposalParams_[i].recipient,
                testProposalParams_[i].tokensRequested
            );
            descriptionPartTwo = string.concat(descriptionPartTwo, Strings.toString(testProposalParams_[i].tokensRequested));
            descriptionPartTwo = string.concat(descriptionPartTwo, " tokens to recipient: ");
            descriptionPartTwo = string.concat(descriptionPartTwo, Strings.toHexString(uint160(testProposalParams_[i].recipient), 20));
            descriptionPartTwo = string.concat(descriptionPartTwo, ", ");

            // FIXME: random actor and amount in generateTestProposalParams are returning same value due to not being able to advance time
            descriptionPartTwo = string.concat(descriptionPartTwo, Strings.toString(standardFundingProposals.length));
        }
        description_ = string(abi.encodePacked(descriptionPartOne, descriptionPartTwo));
    }

    function generateTestProposalParams(uint256 numParams_) internal returns (TestProposalParams[] memory testProposalParams_) {
        testProposalParams_ = new TestProposalParams[](numParams_);

        // FIXME: these values aren't random
        uint256 totalTokensRequested = 0;
        for (uint256 i = 0; i < numParams_; ++i) {
            // get distribution info
            uint24 distributionId = _grantFund.getDistributionId();
            (, , , uint128 fundsAvailable, , ) = _grantFund.getDistributionPeriodInfo(distributionId);

            // account for amount that was previously requested
            uint256 additionalTokensRequested = randomAmount((fundsAvailable * 9 /10) - totalTokensRequested);
            totalTokensRequested += additionalTokensRequested;

            testProposalParams_[i] = TestProposalParams({
                recipient: randomActor(),
                tokensRequested: additionalTokensRequested
            });
        }
    }

    function randomProposal() internal returns (uint256) {
        return standardFundingProposals[constrictToRange(randomSeed(), 0, standardFundingProposals.length - 1)];
    }

    function getStage() internal view returns (bytes memory stage_) {
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        if (block.number < endBlock - 72000) {
            stage_ = bytes("Screening");
        }
        else if (block.number > endBlock - 72000 && block.number < endBlock) {
            stage_ = bytes("Funding");
        }
        else if (block.number > endBlock) {
            stage_ = bytes("Challenge");
        }
    }

    function _createProposals(uint256 numProposals_) internal returns (uint256[] memory proposalIds_) {
        proposalIds_ = new uint256[](numProposals_);
        for (uint256 i = 0; i < numProposals_; ++i) {
            proposalIds_[i] = _createProposal();
        }
    }

    function _createProposal() internal returns (uint256 proposalId_) {
        // get a random number between 1 and 5
        uint256 numProposalParams = constrictToRange(randomSeed(), 1, 5);
        // uint256 numProposalParams = 3;

        // TODO: increase randomness of number of params
        // generate list of recipients and tokens requested
        TestProposalParams[] memory testProposalParams = generateTestProposalParams(numProposalParams);

        // generate proposal params
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = generateProposalParams(testProposalParams);

        // create proposal
        proposalId_ = _grantFund.proposeStandard(targets, values, calldatas, description);

        // record new proposal
        standardFundingProposals.push(proposalId_);
        standardFundingProposalCount++;
    }

    function createProposals(uint256 numProposals) external returns (uint256[] memory proposalIds_) {
        proposalIds_ = _createProposals(numProposals);
    }

    function _findProposalIndexOfVotesCast(
        uint256 proposalId_,
        IStandardFunding.FundingVoteParams[] memory voteParams_
    ) internal pure returns (int256 index_) {
        index_ = -1; // default value indicating proposalId not in the array

        // since we are converting from uint256 to int256, we can safely assume that the value will not overflow
        int256 numVotesCast = int256(voteParams_.length);
        for (int256 i = 0; i < numVotesCast; ) {
            //slither-disable-next-line incorrect-equality
            if (voteParams_[uint256(i)].proposalId == proposalId_) {
                index_ = i;
                break;
            }

            unchecked { ++i; }
        }
    }

    function screeningVoteProposals() external {
        for (uint256 i = 0; i < actors.length; ++i) {
            // get an actor who hasn't already voted
            address actor = actors[i];

            // actor votes on random number of proposals
            _screeningVoteProposal(actor);
        }
    }

    function _screeningVoteProposal(address actor_) internal {
        uint256 votingPower = _grantFund.getVotesScreening(_grantFund.getDistributionId(), actor_);

        // get random number of proposals to vote on
        uint256 numProposalsToVoteOn = constrictToRange(randomSeed(), 1, 10);

        uint256 totalVotesUsed = 0;

        // calculate which proposals should be voted upon
        IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams = new IStandardFunding.ScreeningVoteParams[](numProposalsToVoteOn);
        for (uint256 i = 0; i < numProposalsToVoteOn; ++i) {
            // get a random proposal
            uint256 proposalId = randomProposal();

            // account for already used voting power
            uint256 additionalVotesUsed = randomAmount(votingPower - totalVotesUsed);
            totalVotesUsed += additionalVotesUsed;

            // generate screening vote params
            screeningVoteParams[i] = IStandardFunding.ScreeningVoteParams({
                proposalId: proposalId,
                votes: additionalVotesUsed
            });
        }

        // cast votes
        changePrank(actor_);
        _grantFund.screeningVote(screeningVoteParams);

        // record cast votes
        VotingActor storage actor = votingActors[actor_];
        for (uint256 i = 0; i < numProposalsToVoteOn; ) {
            actor.screeningVotes.push(screeningVoteParams[i]);
            // actor.screeningProposalIds.push(proposalsVotedOn[i]);
            screeningVotesCast++;

            ++i;
        }
    }

    // TODO: add support for handling input strings and number of calls
    function _recordError(bytes memory err_) internal {
        bytes32 err = keccak256(err_);
        if (err == keccak256(abi.encodeWithSignature("InvalidVote()"))) {
            numberOfCalls['SFH.fv.e.InvalidVote']++;
        }
        else if (err == keccak256(abi.encodeWithSignature("InsufficientVotingPower()"))) {
            numberOfCalls['SFH.fv.e.InsufficientVotingPower']++;
        }
        else if (err == keccak256(abi.encodeWithSignature("FundingVoteWrongDirection()"))) {
            numberOfCalls['SFH.fv.e.FVWD']++;
        }
        else {
            numberOfCalls['SFH.fv.e.unknown']++;
            revert("unknown error");
        }
    }

    function hasDuplicates(
        uint256[] calldata proposalIds_
    ) public pure returns (bool) {
        uint256 numProposals = proposalIds_.length;

        for (uint i = 0; i < numProposals; ) {
            for (uint j = i + 1; j < numProposals; ) {
                if (proposalIds_[i] == proposalIds_[j]) return true;

                unchecked { ++j; }
            }

            unchecked { ++i; }

        }
        return false;
    }

    function sumSquareOfVotesCast(
        IStandardFunding.FundingVoteParams[] memory votesCast_
    ) public pure returns (uint256 votesCastSumSquared_) {
        uint256 numVotesCast = votesCast_.length;

        for (uint256 i = 0; i < numVotesCast; ) {
            votesCastSumSquared_ += Maths.wpow(SafeCast.toUint256(Maths.abs(votesCast_[i].votesUsed)), 2);

            unchecked { ++i; }
        }
    }

    function _votingActorsInfo(address actor_) internal view returns (IStandardFunding.FundingVoteParams[] memory, IStandardFunding.ScreeningVoteParams[] memory) {
        return (
            votingActors[actor_].fundingVotes,
            votingActors[actor_].screeningVotes
        );
    }

    /*****************************/
    /*** SFM Getter Functions ****/
    /*****************************/

    function getStandardFundingProposals() external view returns (uint256[] memory) {
        return standardFundingProposals;
    }

    // TODO: will need to handle this per distribution period
    function getVotingActorsInfo(address actor_) external view returns (IStandardFunding.FundingVoteParams[] memory, IStandardFunding.ScreeningVoteParams[] memory) {
        return _votingActorsInfo(actor_);
    }

    function sumVoterScreeningVotes(address actor_) public view returns (uint256 sum_) {
        for (uint256 i = 0; i < votingActors[actor_].screeningVotes.length; ++i) {
            sum_ += votingActors[actor_].screeningVotes[i].votes;
        }
    }

    function sumVoterFundingVotes(address actor_, IStandardFunding.FundingVoteParams[] memory fundingVotes_) public pure returns (int256 sum_) {
        for (uint256 i = 0; i < fundingVotes_.length; ++i) {
            sum_ += Maths.abs(fundingVotes_[i].votesUsed);
        }
    }

    function countNegativeFundingVotes(address actor_, IStandardFunding.FundingVoteParams[] memory fundingVotes_) public pure returns (uint256 count_) {
        for (uint256 i = 0; i < fundingVotes_.length; ++i) {
            if (fundingVotes_[i].votesUsed < 0) {
                count_++;
            }
        }
    }

}
