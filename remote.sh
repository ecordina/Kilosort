#!/bin/bash

# Remote server details
USER="ecordina"
HOST="front.migale.inrae.fr"

# Command to run remotely
COMMAND="bash test.sh"

# Connect via SSH and execute the command
ssh "${USER}@${HOST}" "${COMMAND}"