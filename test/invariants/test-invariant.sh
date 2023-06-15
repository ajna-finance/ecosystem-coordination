#!/bin/bash
set -ex

# retrieve scenario variables from user input
SCENARIO=$1
NUM_ACTORS=$2
NUM_PROPOSALS=$3
IS_HAPPY_PATH=$4

echo "Exporting environment variables"

# export environment variables
export SCENARIO=$SCENARIO
export NUM_ACTORS=$NUM_ACTORS
export NUM_PROPOSALS=$NUM_PROPOSALS
export IS_HAPPY_PATH=$IS_HAPPY_PATH

echo "Running invariant test"

# run invariant test
# TODO: add support for better specifying the invariant test to run
forge t --mc $SCENARIO
