# DPD/TDD Controller (tddctl)

## What it does
When enabled monitors the tdd_rx signal to emit a write enable signal and control trigger delegation

## How it works
### Write enable
Emits a write enable signal only when the following expression is true
(tdd_en & ~tdd_rx) | !tdd_en

| tdd_en  | tdd_rx  | we  |
| :---:   | :---:   | :-: |
|    0    |    0    |  1  |
|    0    |    1    |  1  |
|    1    |    0    |  0  |
|    1    |    1    |  1  |

### Trigger delegation
Works based on wether tdd is enabled and transmiting.  
In case a trigger is received and tdd is disabled or already transmitting the trigger is sent out immediatelly.   
Else if tdd is enabled and transmission is not happening the trigger is sent out only when the tdd transmission signal is received.

The truth table is the same as write enable, but only actuates after the controller is triggered
| triggered |  tdd_en  |  tdd_rx | delegated_trigger  |
|   :---:   |  :---:   |  :---:  |        :-:         |
|     0     |    *     |    *    |         0          |
|     1     |    0     |    0    |         1          |
|     1     |    0     |    1    |         1          |
|     1     |    1     |    0    |         0          |
|     1     |    1     |    1    |         1          |