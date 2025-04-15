library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity UART_TX is
generic (
    CLK_FREQ: integer := 100_000_000; -- System clock frequency in Hz
    BAUD    : integer := 115_200;     -- Baud rate for UART communication
    DBIT    : integer := 8;           -- Number of data bits
    SB_TICK : integer := 2            -- Number of stop bit ticks
);
port (
    CLK             : in  std_logic;                    -- System clock input
    TX_START        : in  std_logic;                    -- Start transmission signal
    DIN             : in  std_logic_vector (7 downto 0); -- Data input to be transmitted
    TX_DONE_TICK    : out std_logic;                    -- Signal indicating transmission completion
    TX              : out std_logic                     -- UART transmit output
);
end UART_TX;

architecture Behavioral of UART_TX is

    constant s_reg_lim    : integer := CLK_FREQ / BAUD;    -- Number of clock cycles per bit period
    constant SB_TICK_lim : integer := s_reg_lim * SB_TICK; -- Number of clock cycles for stop bit(s)

    type states is (idle, start, data, stop); -- Define state machine states
    signal state            : states := idle;           -- State machine signal
    signal s_reg            : integer range 0 to SB_TICK_lim := 0; -- Counter for bit timing
    signal n_reg            : integer range 0 to 7 := 0;          -- Counter for data bits
    signal b_reg            : std_logic_vector (7 downto 0) := (others => '0'); -- Data register for transmission
    signal tx_reg           : std_logic := '1';                  -- Transmit data register
    signal tx_done_tick_reg : std_logic := '0';                  -- Transmission done tick register

begin

    process (clk)
    begin
        if (clk'event and clk = '1') then -- Execute on rising edge of clock

            case state is

                when idle =>
                    tx_done_tick_reg <= '0';    -- Reset transmission done tick
                    tx_reg <= '1';              -- Idle state: TX line is high
                    if (tx_start = '1') then    -- Start transmission signal received
                        state <= start;         -- Go to start bit state
                        s_reg <= 0;             -- Reset bit timing counter
                        b_reg <= din;           -- Load data into transmit register
                    end if;

                when start =>
                    tx_reg <= '0';              -- Start bit: TX line is low
                    if (s_reg = s_reg_lim - 1) then -- Check if bit period is complete
                        state <= data;          -- Go to data bit state
                        s_reg <= 0;             -- Reset bit timing counter
                        n_reg <= 0;             -- Reset data bit counter
                    else
                        s_reg <= s_reg + 1;     -- Increment bit timing counter
                    end if;

                when data =>
                    tx_reg <= b_reg(0);         -- Transmit current data bit
                    if (s_reg = s_reg_lim - 1) then -- Check if bit period is complete
                        s_reg <= 0;             -- Reset bit timing counter
                        b_reg <= ('0' & b_reg(7 downto 1)); -- Shift data register
                        if (n_reg = (DBIT - 1)) then -- Check if all data bits are transmitted
                            state <= stop;      -- Go to stop bit state
                        else
                            n_reg <= n_reg + 1; -- Increment data bit counter
                        end if;
                    else
                        s_reg <= s_reg + 1;     -- Increment bit timing counter
                    end if;

                when stop =>
                    tx_reg <= '1';              -- Stop bit(s): TX line is high
                    if (s_reg = (SB_TICK_lim - 1)) then -- Check if stop bit period is complete
                        state <= idle;          -- Go back to idle state
                        tx_done_tick_reg <= '1'; -- Signal transmission completion
                    else
                        s_reg <= s_reg + 1;     -- Increment bit timing counter
                    end if;

            end case;

        end if;
    end process;

    tx <= tx_reg;               -- Assign transmit data register to TX output
    tx_done_tick <= tx_done_tick_reg; -- Assign transmission done tick to output

end Behavioral;