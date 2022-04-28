# ISO7816 core
# ============

# Register map
# ------------

# Control & Status `csr` (Read/Write addr `0x00`)

```
,-----------------------------------------------------------------------------------------------,
|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
|-----------------------------------------------------------------------------------------------|
|                                            |ce|fe|ff|fo|fc|ep|     |en|fe|ff|fo|fc|ep|ef|  |en|
|............................................|..|.......................|.......................|
|                                            |wt|          tx           |          rx           |
'-----------------------------------------------------------------------------------------------'

  * [16] - wt_ce : Wait Timer Clear (W) / Expired (R)
  * [15] - tx_fe : TX FIFO Empty
  * [14] - tx_ff : TX FIFO Full
  * [13] - tx_fo : TX FIFO Overflow
  * [12] - tx_fc : TX FIFO Clear
  * [11] - tx_ep : TX Error Parity
  * [ 8] - tx_en : TX Enable
  * [ 7] - rx_fe : RX FIFO Empty
  * [ 6] - rx_ff : RX FIFO Full
  * [ 5] - rx_fo : RX FIFO Overflow
  * [ 4] - rx_fc : RX FIFO Clear
  * [ 3] - rx_ep : RX Error Parity
  * [ 2] - rx_ef : RX Error Frame
  * [ 0] - rx_en : RX Enable
```


# TX FIFO Data `data` (Write only addr `0x02`)

```text
,-----------------------------------------------------------------------------------------------,
|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
|-----------------------------------------------------------------------------------------------|
|                                                                       |        data           |
'-----------------------------------------------------------------------------------------------'

  * [7:0] data : The data byte to push to TX FIFO
```


# RX FIFO Data `data` (Read only addr `0x02`)

```text
,-----------------------------------------------------------------------------------------------,
|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
|-----------------------------------------------------------------------------------------------|
|fe|                                                                    |        data           |
'-----------------------------------------------------------------------------------------------'

  *  [31] -   fe : RX FIFO Empty (If set, no valid data is present)
  * [7:0] - data : The data byte retrieved from RX FIFO
```


# Misc configuration `misc` (Write only addr `0x04`)

```text
,-----------------------------------------------------------------------------------------------,
|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
|-----------------------------------------------------------------------------------------------|
|               GT                  |//|   rt   |              |ei|fi|nk|              |ei|fi|nk|
|.......................................................................|.......................|
|                                 tx                                    |          rx           |
'-----------------------------------------------------------------------------------------------'

  * [31:20] - tx_GT : TX Extra Guard Time
  * [18:16] - tx_rt : TX Number of retries before giving up (N-1)
  *    [10] - tx_ei : TX Exception Interrupt enable (TX Fail, TX FIFO overflow)
  *     [9] - tx_fi : TX FIFO Interrupt enable (TX FIFO empty)
  *     [8] - tx_nk : TX NAK mechanism enable
  *     [2] - rx_ei : RX Exception Interrupt enable (RX parity/frame error, RX FIFO overflow)
  *     [1] - rx_fi : RX FIFO Interrupt enable (RX FIFO not empty)
  *     [0] - rx_nk : RX NAK mechanism enable
```


# Wait Timer `wt` (Write only addr `0x05`)

```text
,-----------------------------------------------------------------------------------------------,
|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
|-----------------------------------------------------------------------------------------------|
|ei|                       |                          WT                                        |
'-----------------------------------------------------------------------------------------------'

  *    [31] - ie : WT interrupt enable
  * [22: 8] - WT : WT expiry in ETU
```


# Baud Rate Generator: Rate control `brg_rate` (Write only addr `0x06`)

```text
,-----------------------------------------------------------------------------------------------,
|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
|-----------------------------------------------------------------------------------------------|
|//|                  Fs                        |     /     |         Ds                        |
'-----------------------------------------------------------------------------------------------'

  * [30:16] - Fs : Accumulator refill value
  * [14: 0] - Ds : Accumulator increment value
```

This register controls the baud rate. The final baudrate will be
approximatively `Baud = f_sys * Ds / Fs`.

Note that the `Fs / Ds` ratio must be greater than 8 for the core to operate properly !


# Baud Rate Generator: Capture phase control `brg_phase` (Write only addr `0x07`)

```text
,-----------------------------------------------------------------------------------------------,
|31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9| 8| 7| 6| 5| 4| 3| 2| 1| 0|
|-----------------------------------------------------------------------------------------------|
|                      /                           |                Init                        |
'-----------------------------------------------------------------------------------------------'

  * [14:0] - Init : Accumulator resync value
```

This register controls the resynchronization value of the accumulator
when starting to receive a character and will influence the sampling phase.

To meet ISO7816 specifications of sampling in the middle of the ETU, it
should be set to `(Fs / 2) - ((k+2) * Ds)` with `k` being the IO latency
added by the IO path external to the core (most often 2 cycles when
using IO registers).
