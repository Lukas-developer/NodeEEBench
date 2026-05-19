library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master_tb is
end;

architecture sim of i2c_master_tb is

-- Clock / Control
signal clk_tb     : std_logic := '0';
signal reset_n_tb : std_logic := '0';
signal ena_tb     : std_logic := '0';

-- I2C Interface
signal addr_tb    : std_logic_vector(6 downto 0) := "1010101";
signal rw_tb      : std_logic := '0';
signal data_wr_tb : std_logic_vector(7 downto 0) := "10011001";

signal busy_tb    : std_logic;
signal data_rd_tb : std_logic_vector(7 downto 0);
signal ack_error_tb : std_logic;

signal sda_tb : std_logic := 'Z';
signal scl_tb : std_logic := 'Z';

-- Slave Daten
constant slave_data : std_logic_vector(7 downto 0) := "11001100";

-- SDA Treiber (open drain)
signal sda_slave_drive : std_logic := 'Z';

-- FSM
type state_type is (
    IDLE,
    ADDR,
    ACK_ADDR,
    WRITE_DATA,
    READ_DATA,
    ACK_DATA
);

signal state    : state_type := IDLE;
signal bit_cnt  : integer range 0 to 7 := 7;
signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');

begin

------------------------------------------------
-- Clock 100 MHz
------------------------------------------------
clk_tb <= not clk_tb after 5 ns;

------------------------------------------------
-- Wired AND SDA
------------------------------------------------
sda_tb <= '0' when sda_slave_drive = '0' else 'Z';

------------------------------------------------
-- DUT
------------------------------------------------
dut : entity work.i2c_master
generic map(
    input_clk => 100_000_000,
    bus_clk   => 400_000
)
port map(
    clk       => clk_tb,
    reset_n   => reset_n_tb,
    ena       => ena_tb,
    addr      => addr_tb,
    rw        => rw_tb,
    data_wr   => data_wr_tb,
    busy      => busy_tb,
    data_rd   => data_rd_tb,
    ack_error => ack_error_tb,
    sda       => sda_tb,
    scl       => scl_tb
);

------------------------------------------------
-- I2C SLAVE FSM
------------------------------------------------
process(scl_tb)
begin

    --------------------------------------------
    -- Rising Edge: Sampling
    --------------------------------------------
    if rising_edge(scl_tb) then

        case state is

            when IDLE =>
                if busy_tb = '1' then
                    state   <= ADDR;
                    bit_cnt <= 7;
                end if;

            when ADDR =>
                shift_reg(bit_cnt) <= sda_tb;

                if bit_cnt = 0 then
                    state <= ACK_ADDR;
                else
                    bit_cnt <= bit_cnt - 1;
                end if;

            when WRITE_DATA =>
                shift_reg(bit_cnt) <= sda_tb;

                if bit_cnt = 0 then
                    state <= ACK_DATA;
                else
                    bit_cnt <= bit_cnt - 1;
                end if;

            when READ_DATA =>
                if bit_cnt = 0 then
                    state <= ACK_DATA;
                else
                    bit_cnt <= bit_cnt - 1;
                end if;

            when ACK_ADDR =>
                null;

            when ACK_DATA =>
                state <= IDLE;

        end case;

    --------------------------------------------
    -- Falling Edge: Driving SDA
    --------------------------------------------
    elsif falling_edge(scl_tb) then

        case state is

            when IDLE =>
                sda_slave_drive <= 'Z';

            when ADDR =>
                sda_slave_drive <= 'Z';

            when ACK_ADDR =>
                sda_slave_drive <= '0';  -- ACK

                if rw_tb = '1' then
                    state   <= READ_DATA;
                else
                    state   <= WRITE_DATA;
                end if;

                bit_cnt <= 7;

            when WRITE_DATA =>
                sda_slave_drive <= 'Z';

            when READ_DATA =>
                sda_slave_drive <= slave_data(bit_cnt);

            when ACK_DATA =>
                sda_slave_drive <= '0';  -- ACK

        end case;

    end if;

end process;

------------------------------------------------
-- Stimulus
------------------------------------------------
process
begin

    -- Reset
    reset_n_tb <= '0';
    wait for 100 ns;
    reset_n_tb <= '1';
    wait for 100 ns;

    --------------------------------
    -- WRITE
    --------------------------------
    rw_tb  <= '0';
    ena_tb <= '1';
    wait for 2 us;
    ena_tb <= '0';

    wait until busy_tb = '0';
    wait for 2 us;

    --------------------------------
    -- READ
    --------------------------------
    rw_tb  <= '1';
    ena_tb <= '1';
    wait for 2 us;
    ena_tb <= '0';

    wait until busy_tb = '0';
    wait for 10 us;

    wait;

end process;

end sim;