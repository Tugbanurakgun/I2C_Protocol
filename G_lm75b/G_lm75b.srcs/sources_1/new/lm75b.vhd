library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;

ENTITY TOP IS
GENERIC (
    CLKFREQ     : INTEGER := 100_000_000;  -- System clock frequency (100 MHz)
    I2C_BUS_CLK : INTEGER := 400_000;      -- I2C bus clock frequency (400 kHz)
    DEVICE_ADDR : STD_LOGIC_VECTOR(6 DOWNTO 0) := "1001000" -- I2C device address of the LM75B temperature sensor
);
PORT (
    CLK     : IN STD_LOGIC;               -- System clock input
    RST_N   : IN STD_LOGIC;               -- Asynchronous reset input (active low)
    SDA     : INOUT STD_LOGIC;            -- I2C serial data line
    SCL     : INOUT STD_LOGIC;            -- I2C serial clock line
    TX      : OUT STD_LOGIC;              -- UART transmit output
    LED     : OUT STD_LOGIC_VECTOR (15 DOWNTO 0) -- LED outputs for debugging/display
);
END TOP;

architecture Behavioral of top is

COMPONENT lm75b_t IS
GENERIC (
    CLKFREQ     : INTEGER := 100_000_000;  -- Clock frequency for the LM75B module
    I2C_BUS_CLK : INTEGER := 400_000;      -- I2C bus clock frequency
    DEVICE_ADDR : STD_LOGIC_VECTOR(6 DOWNTO 0) := "1001000" -- I2C device address
);
PORT (
    CLK         : IN STD_LOGIC;           -- Clock input
    RST_N       : IN STD_LOGIC;           -- Reset input (active low)
    SCL         : INOUT STD_LOGIC;        -- I2C serial clock
    SDA         : INOUT STD_LOGIC;        -- I2C serial data
    INTERRUPT   : OUT STD_LOGIC;          -- Interrupt output from LM75B
    TEMP        : OUT STD_LOGIC_VECTOR (10 DOWNTO 0) -- Temperature data output from LM75B
);
END COMPONENT;

COMPONENT UART_TX IS
GENERIC (
    CLK_FREQ    : INTEGER := 100_000_000;  -- Clock frequency for the UART module
    BAUD        : INTEGER := 115_200;      -- Baud rate for UART communication
    DBIT        : INTEGER := 8;            -- Number of data bits
    SB_TICK     : INTEGER := 2             -- Number of stop bit ticks
);
PORT (
    CLK         : IN STD_LOGIC;           -- Clock input
    TX_START    : IN STD_LOGIC;           -- Start transmit signal
    DIN         : IN STD_LOGIC_VECTOR (7 DOWNTO 0); -- Data input to UART
    TX_DONE_TICK: OUT STD_LOGIC;          -- Indicates completion of transmission
    TX          : OUT STD_LOGIC           -- UART transmit output
);
END COMPONENT;

-- UART_TX signals
signal TX_START   : std_logic := '0';        -- Signal to start UART transmission
signal TX_DONE_TICK : std_logic := '0';     -- Signal indicating UART transmission completion
signal DIN        : std_logic_vector (7 downto 0) := (others => '0'); -- Data to be transmitted by UART

signal INTERRUPT  : std_logic := '0';        -- Interrupt signal from LM75B
signal TEMP       : std_logic_vector (10 downto 0) := (others => '0'); -- Temperature data from LM75B
signal sign       : std_logic_vector (4 downto 0) := (others => '0'); -- Sign extension for temperature data

begin
-----------------------------------------------------------------------------------------------

lm75b_i : lm75b_t
GENERIC MAP(
    CLKFREQ     => CLKFREQ,
    I2C_BUS_CLK => I2C_BUS_CLK,
    DEVICE_ADDR => DEVICE_ADDR
)
PORT MAP(
    CLK         => CLK,
    RST_N       => RST_N,
    SCL         => SCL,
    SDA         => SDA,
    INTERRUPT   => INTERRUPT,
    TEMP        => TEMP
); -- Instantiates the LM75B temperature sensor module

UART_TX_i : UART_TX
GENERIC MAP(
    CLK_FREQ    => CLKFREQ,
    BAUD        => 115_200,
    DBIT        => 8,
    SB_TICK     => 1 --changed from 2 to 1.
)
PORT MAP(
    CLK         => CLK,
    TX_START    => TX_START,
    DIN         => DIN,
    TX_DONE_TICK=> TX_DONE_TICK,
    TX          => TX
); -- Instantiates the UART transmitter module

sign    <= TEMP(10) & TEMP(10) & TEMP(10)& TEMP(10) & TEMP(10); -- Sign extension for the temperature data

process (CLK) begin
    if (rising_edge(CLK)) then -- Executes on the rising edge of the clock

        DIN <= TEMP(7 downto 0); -- Assigns the lower 8 bits of the temperature to DIN for UART transmission.

        if (INTERRUPT = '1') then -- Checks if the LM75B interrupt is active
            DIN        <= sign & TEMP(10 downto 8); -- Constructs the data for UART transmission, including the sign and upper 3 bits
            TX_START    <= '1'; -- Starts UART transmission
        end if;

        if (TX_DONE_TICK = '1') then -- Checks if UART transmission is complete
            TX_START    <= '0'; -- Resets the TX_START signal
        end if;

    end if;
end process;

LED(10 downto 0)   <= TEMP; -- Displays the temperature data on LEDs
LED(11)             <= TEMP(10); -- Displays the sign bit of the temperature on LED[11]

end Behavioral;