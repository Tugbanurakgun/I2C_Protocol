library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;

ENTITY lm75b_t IS
GENERIC (
    CLKFREQ     : INTEGER := 100_000_000; -- System clock frequency
    I2C_BUS_CLK : INTEGER := 400_000;     -- I2C bus clock frequency
    DEVICE_ADDR : STD_LOGIC_VECTOR(6 DOWNTO 0) := "1001000" -- I2C address of the LM75B device
);
PORT (
    CLK         : IN STD_LOGIC;
    RST_N       : IN STD_LOGIC;
    SCL         : INOUT STD_LOGIC;
    SDA         : INOUT STD_LOGIC;
    INTERRUPT   : OUT STD_LOGIC;          -- Interrupt signal indicating new temperature data is ready
    TEMP        : OUT STD_LOGIC_VECTOR (10 DOWNTO 0) -- Temperature data output
);
END lm75b_t;

architecture Behavioral of lm75b_t is

COMPONENT I2C_MASTER IS
  GENERIC(
    INPUT_CLK : INTEGER := 25_000_000; -- Input clock frequency for I2C master
    BUS_CLK   : INTEGER := 400_000     -- I2C bus clock frequency
  );
  PORT(
    CLK       : IN  STD_LOGIC;
    RESET_N   : IN  STD_LOGIC;
    ENA       : IN  STD_LOGIC;          -- Enable signal to start I2C transaction
    ADDR      : IN  STD_LOGIC_VECTOR(6 DOWNTO 0); -- Slave device address
    RW        : IN  STD_LOGIC;          -- Read/Write flag
    DATA_WR   : IN  STD_LOGIC_VECTOR(7 DOWNTO 0); -- Data to write
    BUSY      : OUT STD_LOGIC;          -- Indicates I2C transaction is in progress
    DATA_RD   : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- Data read from slave
    ACK_ERROR : BUFFER STD_LOGIC;       -- Acknowledge error flag
    SDA       : INOUT STD_LOGIC;
    SCL       : INOUT STD_LOGIC
  );
END COMPONENT;

--------------------------------------------------------------------------------------------------------------------------------
-- SIGNALS AND CONSTANTS --
-- i2c_master signals
signal ena         : std_logic := '0';
signal rw          : std_logic := '0';
signal data_wr     : std_logic_vector (7 downto 0) := (others => '0');
signal busy        : std_logic := '0';
signal busyPrev    : std_logic := '0';
signal busyCntr    : integer range 0 to 255 := 0;
signal data_rd     : std_logic_vector (7 downto 0) := (others => '0');
signal ack_error   : std_logic := '0';

signal enable      : std_logic := '0';
signal waitEn      : std_logic := '0';
signal cntr        : integer range 0 to 255 := 0;

-- State machine for LM75B operation
type states is (IDLE_S, ACQUIRE_S);
signal state : states := IDLE_S;

-- Signals for 250ms timer
constant cntr250msLim : integer := clkFreq/4; -- Timer limit for 250ms (4Hz)
signal cntr250ms : integer range 0 to cntr250msLim-1 := 0;
signal cntr250msEn : std_logic := '0';
signal cntr250msTick : std_logic := '0';

begin
--------------------------------------------------------------------------------------------------------------------------------
-- COMPONENT INSTANTIATIONS --
i2c_master_inst : i2c_master
GENERIC MAP (
    input_clk   => CLKFREQ,
    bus_clk     => I2C_BUS_CLK
)
PORT MAP (
    clk         => clk,
    reset_n     => RST_N,
    ena         => ena,
    addr        => DEVICE_ADDR,
    rw          => rw,
    data_wr     => data_wr,
    busy        => busy,
    data_rd     => data_rd,
    ack_error   => ack_error,
    sda         => SDA,
    scl         => SCL
); -- Instantiate the I2C master component

cntr250msEn <= '1'; -- Enable the 250ms timer

--------------------------------------------------------------------------------------------------------------------------------
-- MAIN STATE MACHINE --
MAIN : process (clk)
begin
    if (rising_edge(clk)) then

        case (state) is

            -- IDLE state: send write command for register address to slave
            -- Wait for 250ms after power-up and reset
            -- This 250ms delay is only applied once after reset
            when IDLE_S =>

                busyPrev    <= busy;

                if (busyPrev = '0' and busy = '1') then -- Count I2C transaction starts
                    busyCntr <= busyCntr + 1;
                end if;

                INTERRUPT   <= '0'; -- Clear interrupt signal

                -- Wait 250ms before starting I2C transaction (as per datasheet)
                if (RST_N = '1') then
                    if (cntr250msTick = '1') then
                        enable  <= '1';
                    end if;
                else
                    enable <= '0';
                end if;

                if (enable = '1') then

                    if (busyCntr = 0) then  -- First byte write (address register)
                        ena     <= '1';
                        rw      <= '0';     -- Write operation
                        data_wr <= x"00";   -- Temperature MSB register address
                    elsif (busyCntr = 1) then -- End of write operation
                        ena     <= '0';
                        if (busy = '0') then
                            waitEn      <= '1';
                            busyCntr    <= 0;
                            enable      <= '0';
                        end if;
                    end if;

                end if;

                -- Wait a little bit before next I2C transaction (min 1.3us as per datasheet)
                if (waitEn = '1') then
                    if (cntr = 255) then
                        state       <= ACQUIRE_S;
                        cntr        <= 0;
                        waitEn      <= '0';
                    else
                        cntr    <= cntr + 1;
                    end if;
                end if;

            when ACQUIRE_S =>

                busyPrev    <= busy;
                if (busyPrev = '0' and busy = '1') then -- Count I2C transaction starts
                    busyCntr <= busyCntr + 1;
                end if;

                if (busyCntr = 0) then
                    ena     <= '1';
                    rw      <= '1';     -- Read operation
                    data_wr <= x"00";
                elsif (busyCntr = 1) then -- Read temperature MSB
                    if (busy = '0') then
                        TEMP(10 downto 3)   <= data_rd;
                    end if;
                    rw      <= '1';
                elsif (busyCntr = 2) then -- Read temperature LSB
                    ena     <= '0';
                    if (busy = '0') then
                        TEMP(2 downto 0)    <= data_rd(7 downto 5);
                        state               <= IDLE_S;
                        busyCntr            <= 0;
                        INTERRUPT           <= '1'; -- Signal new temperature data available
                    end if;
                end if;

        end case;

    end if;
end process;

CNTR250MS_P : process (clk) -- 250ms timer process
begin
    if (rising_edge(CLK)) then

        if (cntr250msEn = '1') then
            if (cntr250ms = cntr250msLim - 1) then
                cntr250msTick   <= '1';
                cntr250ms       <= 0;
            else
                cntr250msTick   <= '0';
                cntr250ms       <= cntr250ms + 1;
            end if;
        else
            cntr250msTick   <= '0';
            cntr250ms       <= 0;
        end if;

    end if;
end process;

end Behavioral;