// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";

import { IStandardFunding } from "../../src/grants/interfaces/IStandardFunding.sol";

import { StandardFundingTestBase } from "./base/StandardFundingTestBase.sol";
import { StandardFundingHandler } from "./handlers/StandardFundingHandler.sol";

contract StandardFundingFundingInvariant is StandardFundingTestBase {

    // override setup to start tests in the funding stage with already screened proposals
    function setUp() public override {
        super.setUp();

        // create 15 proposals
        _standardFundingHandler.createProposals(15);

        // vote on proposals
        _standardFundingHandler.screeningVoteProposals();

        // skip time into the funding stage
        uint24 distributionId = _grantFund.getDistributionId();
        (, , uint256 endBlock, , , ) = _grantFund.getDistributionPeriodInfo(distributionId);
        uint256 fundingStageStartBlock = endBlock - 72000;
        vm.roll(fundingStageStartBlock + 100);

        // set the list of function selectors to run
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = _standardFundingHandler.fundingVote.selector;
        selectors[1] = _standardFundingHandler.updateSlate.selector;

        // ensure utility functions are excluded from the invariant runs
        targetSelector(FuzzSelector({
            addr: address(_standardFundingHandler),
            selectors: selectors
        }));
    }

    function invariant_FS1_FS2() external {
        uint256[] memory topTenProposals = _grantFund.getTopTenProposals(_grantFund.getDistributionId());

        // invariant: 10 or less proposals should make it through the screening stage
        assertTrue(topTenProposals.length <= 10);
        assertTrue(topTenProposals.length > 0); // check if something went wrong in setup

        // invariant FS1: only proposals in the top ten list should be able to recieve funding votes
        for (uint256 j = 0; j < _standardFundingHandler.standardFundingProposalCount(); ++j) {
            uint256 proposalId = _standardFundingHandler.standardFundingProposals(j);
            (, uint24 distributionId, , , int128 fundingVotesReceived, ) = _grantFund.getProposalInfo(proposalId);
            if (_findProposalIndex(proposalId, topTenProposals) == -1) {
                assertEq(fundingVotesReceived, 0);
            }
            // invariant FS2: distribution id for a proposal should be the same as the current distribution id
            assertEq(distributionId, _grantFund.getDistributionId());
        }
    }

    function invariant_FS3() external {

        for (uint256 i = 0; i < _standardFundingHandler.getActorsCount(); ++i) {
            address actor = _standardFundingHandler.actors(i);

            // get the funding stage voting power of the actor
            uint256 votingPower = _grantFund.getVotesFunding(_grantFund.getDistributionId(), actor);

            // get the voting info of the actor
            (IStandardFunding.FundingVoteParams[] memory fundingVoteParams, ) = _standardFundingHandler.getVotingActorsInfo(actor);

            uint256 sumOfSquares = _standardFundingHandler.sumSquareOfVotesCast(fundingVoteParams);

            // invariant FS3: sum of square of votes cast <= voting power of actor
            assertLt(sumOfSquares, votingPower);

            // TODO: check each proposal that was voted on's funding votes received

        }

    }

    function invariant_call_summary() external view {
        console.log("\nCall Summary\n");
        console.log("--SFM----------");
        console.log("SFH.startNewDistributionPeriod ",  _standardFundingHandler.numberOfCalls("SFH.startNewDistributionPeriod"));
        console.log("SFH.proposeStandard            ",  _standardFundingHandler.numberOfCalls("SFH.proposeStandard"));
        console.log("SFH.screeningVote              ",  _standardFundingHandler.numberOfCalls("SFH.screeningVote"));
        console.log("SFH.fundingVote                ",  _standardFundingHandler.numberOfCalls("SFH.fundingVote"));
        console.log("SFH.updateSlate                ",  _standardFundingHandler.numberOfCalls("SFH.updateSlate"));
        console.log("------------------");
        console.log(
            "Total Calls:",
            _standardFundingHandler.numberOfCalls("SFH.startNewDistributionPeriod") +
            _standardFundingHandler.numberOfCalls("SFH.proposeStandard") +
            _standardFundingHandler.numberOfCalls("SFH.screeningVote") +
            _standardFundingHandler.numberOfCalls("SFH.fundingVote") +
            _standardFundingHandler.numberOfCalls("SFH.updateSlate")
        );
        console.log(" ");
        console.log("--Proposal Stats--");
        console.log("Number of Proposals", _standardFundingHandler.standardFundingProposalCount());
        console.log("------------------");

        uint24 distributionId = _grantFund.getDistributionId();

        // sum proposal votes of each actor
        for (uint256 i = 0; i < _standardFundingHandler.getActorsCount(); ++i) {
            address actor = _standardFundingHandler.actors(i);
            console.log("Actor: ", actor);

            // get actor info
            (
                IStandardFunding.FundingVoteParams[] memory fundingVoteParams,
                IStandardFunding.ScreeningVoteParams[] memory screeningVoteParams
            ) = _standardFundingHandler.getVotingActorsInfo(actor);

            console.log("Delegate: ", _token.delegates(actor));
            console.log("Screening Voting Power: ", _grantFund.getVotesScreening(distributionId, actor));
            console.log("Screening Votes Cast:   ", _standardFundingHandler.sumVoterScreeningVotes(actor));
            console.log("Screening proposals voted for:   ", screeningVoteParams.length);

            console.log("Funding proposals voted for:     ", fundingVoteParams.length);
            console.log("Sum of squares of fvc:           ", _standardFundingHandler.sumSquareOfVotesCast(fundingVoteParams));
            console.log("Funding Votes Cast:              ", uint256(_standardFundingHandler.sumVoterFundingVotes(actor)));
            console.log("------------------");
        }
        console.log("------------------");
        console.log("Number of Actors", _standardFundingHandler.getActorsCount());
        console.log("number of funding stage starts       ", _standardFundingHandler.numberOfCalls("SFH.FundingStage"));
        console.log("number of funding stage success votes", _standardFundingHandler.numberOfCalls("SFH.fundingVote.success"));
        console.log("distributionId", _grantFund.getDistributionId());
        console.log("SFH.updateSlate.success", _standardFundingHandler.numberOfCalls("SFH.updateSlate.success"));
    }


}
