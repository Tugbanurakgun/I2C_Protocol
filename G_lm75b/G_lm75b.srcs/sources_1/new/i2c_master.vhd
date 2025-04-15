LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;

ENTITY i2c_master IS
  GENERIC(
    input_clk : INTEGER := 100_000_000; -- Input clock frequency from user logic in Hz-basys3
    bus_clk   : INTEGER := 400_000      -- I2C bus clock frequency (SCL) in Hz
  );
  PORT(
    clk       : IN  STD_LOGIC;               -- System clock input
    reset_n   : IN  STD_LOGIC;               -- Asynchronous reset input (active low)
    ena       : IN  STD_LOGIC;               -- Enable signal to latch command
    addr      : IN  STD_LOGIC_VECTOR(6 DOWNTO 0); -- Address of the target slave device
    rw        : IN  STD_LOGIC;               -- Read/Write flag: '0' for write, '1' for read
    data_wr   : IN  STD_LOGIC_VECTOR(7 DOWNTO 0); -- Data to be written to the slave
    busy      : OUT STD_LOGIC;               -- Indicates if a transaction is in progress
    data_rd   : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Data read from the slave
    ack_error : BUFFER STD_LOGIC;            -- Flag indicating an acknowledge error from the slave
    sda       : INOUT STD_LOGIC;             -- Serial Data line of the I2C bus
    scl       : INOUT STD_LOGIC              -- Serial Clock line of the I2C bus
  );
END i2c_master;

ARCHITECTURE logic OF i2c_master IS
  CONSTANT divider     : INTEGER := (input_clk / bus_clk) / 4; -- Number of system clock cycles in 1/4 SCL cycle
  TYPE machine IS (ready, start, command, slv_ack1, wr, rd, slv_ack2, mstr_ack, stop); -- Define state machine states
  SIGNAL state         : machine;                             -- State machine signal
  SIGNAL data_clk      : STD_LOGIC;                             -- Data clock for SDA timing
  SIGNAL data_clk_prev : STD_LOGIC;                             -- Previous value of data clock
  SIGNAL scl_clk       : STD_LOGIC;                             -- Internal SCL clock signal
  SIGNAL scl_ena       : STD_LOGIC := '0';                      -- Enable signal for internal SCL output
  SIGNAL sda_int       : STD_LOGIC := '1';                      -- Internal SDA signal
  SIGNAL sda_ena_n     : STD_LOGIC;                             -- Enable signal for internal SDA output (active low)
  SIGNAL addr_rw       : STD_LOGIC_VECTOR(7 DOWNTO 0);          -- Latched address and read/write bit
  SIGNAL data_tx       : STD_LOGIC_VECTOR(7 DOWNTO 0);          -- Latched data to be transmitted
  SIGNAL data_rx       : STD_LOGIC_VECTOR(7 DOWNTO 0);          -- Data received from slave
  SIGNAL bit_cnt       : INTEGER RANGE 0 TO 7 := 7;             -- Bit counter for data transmission/reception
  SIGNAL stretch       : STD_LOGIC := '0';                      -- Flag indicating if slave is stretching SCL
BEGIN

  -- Generate timing for SCL clock (scl_clk) and data clock (data_clk)
  PROCESS (clk, reset_n)
    VARIABLE count : INTEGER RANGE 0 TO divider * 4; -- Counter for clock generation timing
  BEGIN
    IF (reset_n = '0') THEN                  -- Reset asserted
      stretch <= '0';
      count := 0;
    ELSIF (clk'EVENT AND clk = '1') THEN
      data_clk_prev <= data_clk;             -- Store previous data clock value
      IF (count = divider * 4 - 1) THEN      -- End of timing cycle
        count := 0;                         -- Reset counter
      ELSIF (stretch = '0') THEN            -- Slave is not stretching SCL
        count := count + 1;                 -- Increment counter
      END IF;
      CASE count IS
        WHEN 0 TO divider - 1 =>             -- First 1/4 cycle: SCL low, data setup
          scl_clk <= '0';
          data_clk <= '0';
        WHEN divider TO divider * 2 - 1 =>   -- Second 1/4 cycle: SCL low, data change
          scl_clk <= '0';
          data_clk <= '1';
        WHEN divider * 2 TO divider * 3 - 1 => -- Third 1/4 cycle: SCL high, data stable, check stretch
          scl_clk <= '1';
          IF (scl = '0') THEN              -- Slave is stretching SCL
            stretch <= '1';
          ELSE
            stretch <= '0';
          END IF;
          data_clk <= '1';
        WHEN OTHERS =>                      -- Fourth 1/4 cycle: SCL high, data stable
          scl_clk <= '1';
          data_clk <= '0';
      END CASE;
    END IF;
  END PROCESS;

  -- State machine and SDA writing during SCL low (data_clk rising edge)
  PROCESS (clk, reset_n)
  BEGIN
    IF (reset_n = '0') THEN                  -- Reset asserted
      state <= ready;                       -- Go to idle state
      busy <= '0';                          -- Not busy
      scl_ena <= '0';                       -- Disable SCL output
      sda_int <= '1';                       -- Set SDA to high-impedance
      ack_error <= '0';                     -- Clear acknowledge error flag
      bit_cnt <= 7;                         -- Reset bit counter
      data_rd <= "00000000";                 -- Clear read data
    ELSIF (clk'EVENT AND clk = '1') THEN
      IF (data_clk = '1' AND data_clk_prev = '0') THEN -- Data clock rising edge
        CASE state IS
          WHEN ready =>                     -- Idle state
            IF (ena = '1') THEN             -- Enable signal received
              busy <= '1';                    -- Set busy flag
              addr_rw <= addr & rw;          -- Store address and R/W bit
              data_tx <= data_wr;            -- Store data to write
              state <= start;                 -- Go to start condition state
            ELSE
              busy <= '0';                    -- Not busy
              state <= ready;                 -- Stay in idle state
            END IF;
          WHEN start =>                     -- Start condition
            busy <= '1';                    -- Busy
            sda_int <= addr_rw(bit_cnt);     -- Send first address bit
            state <= command;                 -- Go to command state
          WHEN command =>                   -- Address and R/W bit transmission
            IF (bit_cnt = 0) THEN           -- All bits sent
              sda_int <= '1';                 -- Release SDA for acknowledge
              bit_cnt <= 7;                   -- Reset bit counter
              state <= slv_ack1;              -- Go to slave acknowledge state (command)
            ELSE
              bit_cnt <= bit_cnt - 1;         -- Decrement bit counter
              sda_int <= addr_rw(bit_cnt - 1); -- Send next address/command bit
              state <= command;               -- Continue command state
            END IF;
          WHEN slv_ack1 =>                  -- Slave acknowledge after address/command
            IF (addr_rw(0) = '0') THEN       -- Write command
              sda_int <= data_tx(bit_cnt);   -- Send first data bit
              state <= wr;                    -- Go to write state
            ELSE                            -- Read command
              sda_int <= '1';                 -- Release SDA for slave data
              state <= rd;                    -- Go to read state
            END IF;
          WHEN wr =>                        -- Write data to slave
            busy <= '1';                    -- Busy
            IF (bit_cnt = 0) THEN           -- All bits sent
              sda_int <= '1';                 -- Release SDA for acknowledge
              bit_cnt <= 7;                   -- Reset bit counter
              state <= slv_ack2;              -- Go to slave acknowledge state (write)
            ELSE
              bit_cnt <= bit_cnt - 1;         -- Decrement bit counter
              sda_int <= data_tx(bit_cnt - 1); -- Send next data bit
              state <= wr;                    -- Continue write state
            END IF;
          WHEN rd =>                        -- Read data from slave
            busy <= '1';                    -- Busy
            IF (bit_cnt = 0) THEN           -- All bits received
              IF (ena = '1' AND addr_rw = addr & rw) THEN -- Continue read
                sda_int <= '0';               -- Send acknowledge
              ELSE                            -- Stop or next write
                sda_int <= '1';               -- Send no-acknowledge
              END IF;
              bit_cnt <= 7;                   -- Reset bit counter
              data_rd <= data_rx;            -- Store received data
              state <= mstr_ack;              -- Go to master acknowledge state
            ELSE
              bit_cnt <= bit_cnt - 1;         -- Decrement bit counter
              state <= rd;                    -- Continue read state
            END IF;
          WHEN slv_ack2 =>                  -- Slave acknowledge after write
            IF (ena = '1') THEN             -- Continue transaction
              busy <= '0';                    -- Not busy
              addr_rw <= addr & rw;          -- Store address and R/W
              data_tx <= data_wr;            -- Store data to write
              IF (addr_rw = addr & rw) THEN   -- Continue write
                sda_int <= data_wr(bit_cnt); -- Send first data bit
                state <= wr;                  -- Go to write state
              ELSE                            -- New read or new slave
                state <= start;               -- Go to repeated start
              END IF;
            ELSE                            -- Stop transaction
              state <= stop;                  -- Go to stop state
            END IF;
          WHEN mstr_ack =>                  -- Master acknowledge after read
            IF (ena = '1') THEN             -- Continue transaction
              busy <= '0';                    -- Not busy
              addr_rw <= addr & rw;          -- Store address and R/W
              data_tx <= data_wr;            -- Store data to write
              IF (addr_rw = addr & rw) THEN   -- Continue read
                sda_int <= '1';               -- Release SDA for slave data
                state <= rd;                  -- Go to read state
              ELSE                            -- New write or new slave
                state <= start;               -- Go to repeated start
              END IF;
            ELSE                            -- Stop transaction
              state <= stop;                  -- Go to stop state
            END IF;
          WHEN stop =>                      -- Stop condition
            busy <= '0';                    -- Not busy
            state <= ready;                 -- Go to idle state
        END CASE;
      ELSIF (data_clk = '0' AND data_clk_prev = '1') THEN -- Data clock falling edge
        CASE state IS
          WHEN start =>
            IF (scl_ena = '0') THEN           -- Start new transaction
              scl_ena <= '1';                 -- Enable SCL output
              ack_error <= '0';               -- Reset acknowledge error
            END IF;
          WHEN slv_ack1 =>                  -- Slave acknowledge after address/command
            IF (sda /= '0' OR ack_error = '1') THEN -- No-acknowledge or previous error
              ack_error <= '1';               -- Set acknowledge error
            END IF;
          WHEN rd =>                        -- Read data
            data_rx(bit_cnt) <= sda;          -- Receive data bit
          WHEN slv_ack2 =>                  -- Slave acknowledge after write
            IF (sda /= '0' OR ack_error = '1') THEN -- No-acknowledge or previous error
              ack_error <= '1';               -- Set acknowledge error
            END IF;
          WHEN stop =>
            scl_ena <= '0';                 -- Disable SCL output
          WHEN OTHERS =>
            NULL;
        END CASE;
      END IF;
    END IF;
  END PROCESS;

  -- Set SDA output
  WITH state SELECT
    sda_ena_n <= data_clk_prev WHEN start,       -- Generate start condition
                 NOT data_clk_prev WHEN stop,    -- Generate stop condition
                 sda_int WHEN OTHERS;            -- Set to internal SDA signal

  -- Set SCL and SDA outputs
  scl <= '0' WHEN (scl_ena = '1' AND scl_clk = '0') ELSE 'Z';
  sda <= '0' WHEN sda_ena_n = '0' ELSE 'Z';

END logic;