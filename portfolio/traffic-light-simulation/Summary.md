# Dynamic Traffic Light Simulation

Project for Fermanagh Community Transport: would queue-responsive traffic lights reduce delays at a junction in Enniskillen?

## Model
- Discrete-event simulation of one junction with time-varying Poisson arrivals, based on 2015 traffic counter data.
- Fixed-time light versus a dynamic light whose green time grows with the queue.
- Waiting time is measured per vehicle, including time spent waiting during red.

## Results (calibrated scenario, 30 replications of 5 simulated days)
| Light | Mean wait per vehicle |
|---|---|
| Fixed-time | 25.5 s |
| Dynamic | 12.3 s (52% lower) |

Emergency vehicles (0.5% of arrivals) with an override that lengthens the green phase while one is queued: mean wait 12.2 s (dynamic) to 6.1 s (dynamic with override). Ordinary vehicles' waits were unchanged at 12.3 s.

## Files
- `traffic_wait_replications.py`: the simulation and the fixed versus dynamic comparison.
- `traffic_emergency.py`: adds emergency vehicles and the override. Needs the first file in the same folder.
