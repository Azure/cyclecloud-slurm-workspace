#!/bin/bash
/usr/local/bin/cyclecloud start_cluster ccw --test
CycleCloudDevel=1 /usr/local/bin/cyclecloud await_target_state ccw -n scheduler