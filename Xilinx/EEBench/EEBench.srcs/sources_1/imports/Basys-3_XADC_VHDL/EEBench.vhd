----------------------------------------------------------------------------
--	EEBench.vhd -- Basys3 Dataconverter Project
----------------------------------------------------------------------------
-- Author:  Joerg Vollrath
----------------------------------------------------------------------------
-- Documentation
-- V00: switches control JB,JC pins, shows 7 segment and LED 
-- V01: BTNL switches between sw, XADC1,2,3,4 dp shows what is displayed
-- Serial communication RX, AWG: Receive signals: X: Reset,
--  S Sine: MACC.vhdl  FCLK, StepRe, StepIm, StepRe1, StepIm1, sample  (32bit, 8hex each)
--  T Triangle, tri_counter.vhd start, stop, step, repeat (16bit, 4hex each)
--  U Data, nData 32 bit
----------------------------------------------------------------------------
-- Revision History:
--  2022/10/05(JV): started
----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--The IEEE.std_logic_unsigned contains definitions that allow 
--std_logic_vector types to be used with the + operator to instantiate a 
--counter.
use IEEE.std_logic_unsigned.all;

entity EEBench is
    Port ( SW 			: in  STD_LOGIC_VECTOR (15 downto 0);  -- 16 switches
           BTN 			: in  STD_LOGIC_VECTOR (4 downto 0);   -- 5 Buttons
           CLK			: in  STD_LOGIC;
           vn_in		: in  STD_LOGIC;
           vp_in		: in  STD_LOGIC;
           RX		    : in  STD_LOGIC;                       -- UART RX
           TX    		: out  STD_LOGIC;                      -- UART TX
           LED 			: out  STD_LOGIC_VECTOR (15 downto 0); -- 16 LEDs next to switches 
           JXA 			: in   STD_LOGIC_VECTOR (7 downto 0);  -- Analog Diff Inputs
           JA 			: out  STD_LOGIC_VECTOR (7 downto 2);  -- PMOD lower 8bit DAC
           JB 			: out  STD_LOGIC_VECTOR (7 downto 2);  -- PMOD lower 8bit DAC
           JC 			: out  STD_LOGIC_VECTOR (7 downto 0);  -- PMOD upper 8bit DAC
           SSEG_CA 		: out  STD_LOGIC_VECTOR (7 downto 0);  -- 7 segment + dp
           SSEG_AN 		: out  STD_LOGIC_VECTOR (3 downto 0);   -- 4 digits 
           SCL          : inout STD_LOGIC;
           SDA          : inout STD_LOGIC
			  );
end EEBench;

architecture Behavioral of EEBench is

-- Debounced Button signal
component ButtonD
Port(
		BTN 			: in  STD_LOGIC_VECTOR (4 downto 0);
		CLK : in std_logic;          
		btnDeBnc     : out STD_LOGIC_VECTOR (4 downto 0);
		btnDetect    : out STD_LOGIC
     );
end component;

-- Seven Segment display
component SevenSegDH
    Port ( CLK			       : in  STD_LOGIC;
           RES			       : in  STD_LOGIC;                       -- reset
           D3                  : in STD_LOGIC_VECTOR (3 downto 0);
           D2                  : in STD_LOGIC_VECTOR (3 downto 0);
           D1                  : in STD_LOGIC_VECTOR (3 downto 0);
           D0                  : in STD_LOGIC_VECTOR (3 downto 0);
           DP                  : in STD_LOGIC_VECTOR (3 downto 0);    -- hex values digits and dp
           SSEG_CA 		       : out  STD_LOGIC_VECTOR (7 downto 0);  -- 7 segment + dp
           SSEG_AN 		       : out  STD_LOGIC_VECTOR (3 downto 0)   -- 4 digits 
	     );
end component;

-- XADC channels
COMPONENT XADC_EE
  PORT (
    di_in : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    daddr_in : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
    den_in : IN STD_LOGIC;
    dwe_in : IN STD_LOGIC;
    drdy_out : OUT STD_LOGIC;
    do_out : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    dclk_in : IN STD_LOGIC;
    reset_in : IN STD_LOGIC;
    vp_in : IN STD_LOGIC;
    vn_in : IN STD_LOGIC;
    vauxp6 : IN STD_LOGIC;
    vauxn6 : IN STD_LOGIC;
    vauxp7 : IN STD_LOGIC;
    vauxn7 : IN STD_LOGIC;
    vauxp14 : IN STD_LOGIC;
    vauxn14 : IN STD_LOGIC;
    vauxp15 : IN STD_LOGIC;
    vauxn15 : IN STD_LOGIC;
    channel_out : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
    eoc_out : OUT STD_LOGIC;
    alarm_out : OUT STD_LOGIC;
    eos_out : OUT STD_LOGIC;
    busy_out : OUT STD_LOGIC
  );
END COMPONENT;

-- Memory
COMPONENT One_port_ram
  generic(
    ADDR_WIDTH: integer := 16;   -- 5 channels(3) * 512 values(9)
    DATA_WIDTH: integer := 16
   );
  port (
      clk: in std_logic;
      we: in std_logic;
      addr: in std_logic_vector(ADDR_WIDTH-1 downto 0);
      din: in std_logic_vector(DATA_WIDTH-1 downto 0);
      dout: out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end COMPONENT;

-- UART
COMPONENT uart_mem
   generic(
      -- 100MHz, 19200 = 326,  115200 = 54, 230400 = 27, 460800 = 14, 921600 = 7
	  DVSR: integer:= 27;  -- baud rate divisor
                            -- DVSR = 100M/(16*baud rate)
      DVSR_BIT: integer:=10; -- # bits of DVSR
      DBIT: integer:=8;     -- # data bits
      SB_TICK: integer:=16;  -- # ticks for stop bits
      TX_SIZE: integer:= 512 * 128;     -- # data bits X increase buffer
      RX_SIZE: integer:= 512     -- # data bits
   );
   port(
      clk, reset: in std_logic;
      rx: in std_logic;
      dtx: in std_logic_vector(15 downto 0);             -- data from block memory to send
      dataMax: in std_logic_vector(15 downto 0);         -- block size
      aBuf: out std_logic_vector(15 downto 0);           -- address for block memory
      rx_mem: out std_logic_vector(RX_SIZE-1 downto 0);  -- receive memory
      addr01: out std_logic_vector(11 downto 0);         -- Lookup interface
      we01: out std_logic;
      din01: out std_logic_vector(15 downto 0);
      addr02: out std_logic_vector(11 downto 0);
      we02: out std_logic;
      din02: out std_logic_vector(15 downto 0);
      tx: out std_logic;
      tx_busy: out std_logic             -- '1' during send
   );
end COMPONENT;

-- I2C 
COMPONENT i2c_master
generic(
    input_clk : integer := 100_000_000;
    bus_clk   : integer := 400_000
);
port(
    clk       : in std_logic;
    reset_n   : in std_logic;
    ena       : in std_logic;
    addr      : in std_logic_vector(6 downto 0);
    rw        : in std_logic;
    data_wr   : in std_logic_vector(7 downto 0);
    busy      : out std_logic;
    data_rd   : out std_logic_vector(7 downto 0);
    ack_error : buffer std_logic;
    sda       : inout std_logic;
    scl       : inout std_logic
);
end COMPONENT;

COMPONENT tri_counter
   generic(
      N: integer := 16     -- number of bits
  );
   port(
      clk, reset: in std_logic;
      start, stop, step: in std_logic_vector(N-1 downto 0);
      repeat: in std_logic_vector(2*N-1 downto 0);
      q: out std_logic_vector(N-1 downto 0)
   );
end COMPONENT;

COMPONENT sineX
   Port (
       CLK : in STD_LOGIC;
       RST: in STD_LOGIC;
       step: in STD_LOGIC_Vector(31 downto 0);   -- increment
       amplitude: in STD_LOGIC_Vector(31 downto 0);   -- signal amplitude
       offset: in STD_LOGIC_Vector(31 downto 0);   -- signal offset
       mySine: out STD_LOGIC_Vector(31 downto 0) 
   );
end COMPONENT;

COMPONENT CLK_DIV 
Port (
    CLK : in  STD_LOGIC;
    RST : in STD_LOGIC;
    EN_2 : out  STD_LOGIC;
    EN_4 : out  STD_LOGIC;
    EN_8 : out  STD_LOGIC;
    EN_16 : out  STD_LOGIC;
    EN_32 : out  STD_LOGIC;
    EN_64 : out  STD_LOGIC;
    EN_128 : out  STD_LOGIC;
    EN_256 : out  STD_LOGIC
);     
end COMPONENT;

-- Button signals and registers
--Used to determine when a button press has occured
signal btnDetect : std_logic;                                  -- one clock cycle for rising edge button
--Debounced btn signals used to prevent single button presses
--from being interpreted as multiple button presses.
signal btnDeBnc : std_logic_vector(4 downto 0);               -- button state

-- XADC signals
signal daddr_in: STD_LOGIC_VECTOR(6 DOWNTO 0);
signal enable: STD_LOGIC;
signal ready: STD_LOGIC;
signal readyX: STD_LOGIC;       -- generate ready for simulation
signal data: STD_LOGIC_VECTOR(15 DOWNTO 0);
signal channel_out: STD_LOGIC_VECTOR(4 DOWNTO 0); -- not used
signal alarm_out: STD_LOGIC;                      -- not used
signal eos_out: STD_LOGIC;                      -- not used
signal busy_out: STD_LOGIC;                      -- not used
signal debugbus: STD_LOGIC_VECTOR(5 DOWNTO 0);

-- Multiplexing of inputs to 4 digit 7 segment display
signal source: STD_LOGIC_VECTOR(2 DOWNTO 0);
signal xDisp: STD_LOGIC_VECTOR(15 DOWNTO 0);
signal dpX: STD_LOGIC_VECTOR(3 DOWNTO 0);

-- UART signals
   signal tx_full, rx_empty, tx_busy: std_logic;
   signal rec_data,tx_data: std_logic_vector(7 downto 0);
   signal btn_tick: std_logic;
   signal tx_l: std_logic;
   signal tx_en: std_logic;
   signal xtick: std_logic_vector( 9 downto 0);
   
-- I2C signals
signal ena_sig      : std_logic;
signal addr_sig     : std_logic_vector(6 downto 0) := "1100000";
signal rw_sig       : std_logic := '0';
signal data_wr_sig  : std_logic_vector(7 downto 0) := x"58";
signal data_rd_sig  : std_logic_vector(7 downto 0);
signal busy_sig     : std_logic;
signal ack_err_sig  : std_logic;
signal reset_n_sig  : std_logic;
type i2c_state_type is (
    IDLE,
    WAIT_CMD,
    SEND_HIGH,
    WAIT_HIGH,
    SEND_LOW,
    WAIT_LOW
);
signal i2c_state : i2c_state_type := idle;
signal i2c_tick      : std_logic := '0';
signal i2c_cnt       : integer range 0 to 99999 := 0;
signal dac_value : unsigned(11 downto 0) := to_unsigned(2048,12);

signal mcp_byte1 : std_logic_vector(7 downto 0) := x"08";
signal mcp_byte2 : std_logic_vector(7 downto 0) := x"00";

signal mcp_cmd       : std_logic_vector(7 downto 0);
signal mcp_data_high : std_logic_vector(7 downto 0);
signal mcp_data_low  : std_logic_vector(7 downto 0);


-- Register Memory for UART
signal rMem: std_logic_vector(511 downto 0) := (others=>'0');
--signal tMem: std_logic_vector(512 * 128 - 1 downto 0);

signal we: std_logic;  
signal addr: std_logic_vector(15 downto 0);       -- 11: 4096 -> 512samples
signal we01: std_logic;  
signal addr01: std_logic_vector(11 downto 0);       -- 11: 4096 -> 512samples
signal addr01a: std_logic_vector(11 downto 0);       -- 11: 4096 -> 512samples
signal addr01b: std_logic_vector(11 downto 0);       -- 11: 4096 -> 512samples
signal we02: std_logic;  
signal addr02: std_logic_vector(11 downto 0);       -- 11: 4096 -> 512samples
signal addr02a: std_logic_vector(11 downto 0);       -- 11: 4096 -> 512samples
signal addr02b: std_logic_vector(11 downto 0);       -- 11: 4096 -> 512samples
signal addrUart: std_logic_vector(15 downto 0);   -- 15: 64k -> 8k samples
signal addrGen: std_logic_vector(15 downto 0);  
signal din: std_logic_vector(15 downto 0);  
signal dout: std_logic_vector(15 downto 0);  
signal din01: std_logic_vector(15 downto 0);  
signal dout01: std_logic_vector(15 downto 0);  
signal din02: std_logic_vector(15 downto 0);  
signal dout02: std_logic_vector(15 downto 0);  
signal doutX: std_logic_vector(15 downto 0);  
  
-- Triangle
signal tstart, tstop, tstep: std_logic_vector(15 downto 0);
signal trepeat: std_logic_vector(31 downto 0);  
signal tout: std_logic_vector(15 downto 0);  

-- Sine
signal enSIN: std_logic;                                         -- Enable CLK signal
signal step: STD_LOGIC_VECTOR(31 downto 0);     -- sin(dphi) complex step
signal amplitude: STD_LOGIC_VECTOR(31 downto 0);  -- cos(phi)
signal offset: STD_LOGIC_VECTOR(31 downto 0); -- sin(phi*256) complex coarse step
signal mysine: STD_LOGIC_VECTOR(31 downto 0);              -- output waveform (25 downto 0) 26bits

signal ENX, EN_2, EN_4, EN_8, EN_16, EN_32, EN_64, EN_128, EN_256: STD_LOGIC;
signal mywave: STD_LOGIC_VECTOR(15 downto 0);
signal mywaveX: STD_LOGIC_VECTOR(15 downto 0);
signal wavesel: STD_LOGIC_VECTOR(2 downto 0);
signal xrst: STD_LOGIC;

-- Oscilloscope
signal dataMax: STD_LOGIC_VECTOR(15 downto 0);    -- Data block size
signal timeBase: STD_LOGIC_VECTOR(15 downto 0);   -- sampling frequency 1 maximum
signal upSample: STD_LOGIC := '1';                       -- if valid save data at address

begin

----------------------------------------------------------
------      acquisition  memory                    -------
----------------------------------------------------------
myBuf: One_port_ram
   port map (
      clk => CLK,
      we => we,
      addr => addr,
      din => din,
      dout => dout
    );

-- address multiplexer write read
with tx_busy select
	addr <= addrUart   when '1',      -- uart addr for tx
		    addrGen  when '0',        -- generator address
		    addrGen when others;      -- switches

----------------------------------------------------------
------      LUT  memory                    -------
----------------------------------------------------------
myLut1: One_port_ram
   generic map ( ADDR_WIDTH => 12 )
   port map (
      clk => CLK,
      we => we01,
      addr => addr01,
      din => din01,
      dout => dout01
    );

-- address multiplexer write read

addr01b <= mywave(15 downto 4);         -- from AWG

with rMem(13) select
	addr01 <= addr01a  when '0',        -- uart writing
		      addr01b  when '1',        -- lut reading
		      addrGen when others;      -- switches

myLut2: One_port_ram
   generic map ( ADDR_WIDTH => 12 )
   port map (
      clk => CLK,
      we => we02,
      addr => addr02,
      din => din02,
      dout => dout02
    );

-- missing address multiplex

----------------------------------------------------------
------        Switches to LED                      -------
----------------------------------------------------------

with BTN(3) select -- BTND
	LED(15 DOWNTO 2) <= SW(15 DOWNTO 2)   when '0',
		   data(15 DOWNTO 2) when others;
--		   "00000000000000" when others;
			 			 
----------------------------------------------------------
------    Switches to PMOD JB,JC                   -------
------    Multiplexer                              -------
----------------------------------------------------------

wavesel <= rMem(15)&rMem(9 downto 8);
with wavesel select
	mywave(7 downto 0) <= mysine(22 downto 15)   when "101",  -- sine
		                  tout(7 downto 0)   when "110",      -- triangel
		                  SW(7 downto 0) when "111",          -- switches
		                  "00000000" when others; -- switches

with wavesel select
	mywave(15 downto 8) <= mysine(30 downto 23)   when "101", -- sine
		                   tout(15 downto 8) when "110",      -- triangel
		                   SW(15 downto 8)   when "111",      -- switches   
		                   "00000000" when others; 

doutX <= dout01;   -- lower bits add count of mywave?? 
with rMem(13) select -- lookup table data or not
    mywaveX <= mywave when '0',
               dout01 when '1',
               "0000000000000000" when others;

JB <= mywaveX(7 downto 2);  			 			 
JC <= mywaveX(15 downto 8);		

				 			 
----------------------------------------------------------
------           7-Seg Display Control             -------
----------------------------------------------------------
-- xDisp is mapped to 7 segment display

with source select
	xDisp <= SW   when "000",  -- switches
		     data when others; -- ADC output

Inst_sevensegDH: SevenSegDH
    port map(
		CLK => CLK,
		RES => BTN(4),
		D3 => xDisp(15 downto 12),
		D2 => xDisp(11 downto 8), 
		D1 => xDisp(7 downto 4), 
		D0 => xDisp(3 downto 0), 
		DP => dpX,
		SSEG_CA => SSEG_CA,
		SSEG_AN => SSEG_AN 
	);

----------------------------------------------------------
------              Button Control                 -------
----------------------------------------------------------

--Debounces btn signals
Inst_btn_debounce: ButtonD 
    port map(
		BTN => BTN,
		CLK => CLK,
		btnDeBnc => btnDeBnc,
		btnDetect => btnDetect
	);

----------------------------------------------------------
------              XADC                 -------
----------------------------------------------------------
--select ADC channel with SW1 and sw0

dataMax <= rMem(275 downto 272)&rMem(279 downto 276)
           &rMem(283 downto 280)&rMem(287 downto 284);
timeBase <= rMem(291 downto 288)&rMem(295 downto 292)
           &rMem(299 downto 296)&rMem(303 downto 300);

dpX <= "1"&source;

with source select
	daddr_in <= "0010110"	when "001",  -- Hex16
	            "0010111"	when "010",  -- Hex17
	            "0011110"	when "011",  -- Hex1e
	            "0011111"	when "100",  -- Hex1f
			    "0010110" when others;

debugbus <=	din(15 downto 12) & tx_busy & we; 
--& daddr_in(3) & daddr_in(0); 			 

readyX <= ready;    -- Simulation create ADC ready with EN_16:  or EN_16;

-- sample rate reduction process
--- time Base 000  upSample always 1
--  timebase 001   upSample 1-16-times-0-16-times
--  timebase 010   upSample 1-16-times-0-32-times
  sampleRed: process(CLK, BTN(4), readyX)
     variable jCnt: integer;  -- counter for reduction
     variable kCnt: integer;  -- 16 samples
  begin
       if ( BTN(4) = '1') then  -- asynchron reset with button 0
         jCnt := 0;  kCnt := 0;
       elsif  (rising_edge(CLK) and (readyX = '1')) then
         kCnt := kCnt + 1;
         if (kCnt >= 8) then  -- Clk divider 8 by kCnt
             kCnt := 0; jCnt := jCnt + 1;
             if (jCnt >= timeBase) then -- upSample short '1' long '0' 
               upSample <= '1';  jCnt := 0;
             else  upSample <= '0';
             end if;  
         end if; 
       end if; 
  end process;
  
  -- XADC data into tMem
  storeMem: process(CLK, BTN(4), readyX, upSample)
     variable iCnt: integer;  -- counter for memory address to store addrGen
     variable bCnt: integer;
     variable sCnt: integer;  -- how many samples since last transfer saved at first block address
     begin
       if ( BTN(4) = '1') then  -- asynchron reset with button 0
          iCnt := 5;            -- start at memory position 5
          bCnt := 0;
          we <= '0';
          din <= x"0000";
          addrGen <= (others => '0');
          source <= (others => '0');
          --                         XADC ready        not transmitting
       elsif  (rising_edge(CLK) and (readyX = '1') 
                -- slow clock ??
                -- and (upSample = '1')
                ) then  -- continous cycling through ADC if no transmit
         if (tx_busy = '1') then  -- transfer started
            sCnt := 0;
            we <='0';
         else                    -- data sampling
          if (upSample = '1') then                -- only if upSample valid write
            case source is                        -- write to BlockRAM operation
		      --  when  "000" => source <= "001";
		       when  "001" => addrGen <= std_logic_vector(to_signed(iCnt,16)); din <= data; we <= '1';
		       when  "010" => addrGen <= std_logic_vector(to_signed(iCnt + 1,16)); din <= data; we <= '1';
		       when  "011" => addrGen <= std_logic_vector(to_signed(iCnt + 2,16)); din <= data; we <= '1';
		       when  "100" => addrGen <= std_logic_vector(to_signed(iCnt + 3,16)); din <= data; we <= '1';
		                                            -- awg code including lookup 
		       when  "101" => addrGen <= std_logic_vector(to_signed(iCnt + 4,16)); din <= mywaveX(15 downto 0); we <= '1';
		                      iCnt := iCnt + 5; bCnt := bCnt + 1;  
		       when  "110" => addrGen <= std_logic_vector(to_signed(1,16));            -- save sampled data since last transfer 
		                      din <= std_logic_vector(to_signed(sCnt,16)); we <= '1';
		       when  "111" => addrGen <= std_logic_vector(to_signed(2,16));            -- save current position bCount 
		                     din <= std_logic_vector(to_signed(bCnt,16)); we <= '1';
		       when others => addrGen <= std_logic_vector(to_signed(iCnt,16)); din <= (others => '0'); we <= '0';
            end case;
          end if;  
          source <= source + 1;
          if (bCnt >= (dataMax -1))  then -- Needs memory power of 2 2^N-1 samples 1 sample bCnt, sCnt
             iCnt := 5;
             bCnt := 0;
          end if;
          if ((sCnt < 64*1024 - 1) and (source = "000")) then -- maximum 64k samples
            sCnt := sCnt + 1;
          end if;
        end if;  
       end if;
     end process;

-- tMem(95 downto 80) <= sw(15 downto 0);
-- tMem(251 downto 96) <= rMem(251 downto 160);  -- just send whats in rMem


my_adc : XADC_EE
  PORT MAP (
    di_in => "0000000000000000",          -- input wire [15 : 0] di_in
    daddr_in => daddr_in,    -- input wire [6 : 0] daddr_in hex 16,17,1e,1f
    den_in => enable,        -- input wire den_in
    dwe_in => '0',        -- input wire dwe_in
    drdy_out => ready,     -- output wire drdy_out
    do_out => data,        -- output wire [15 : 0] do_out
    dclk_in => CLK,      -- input wire dclk_in
    reset_in => BTN(4),    -- input wire reset_in
    vp_in => vp_in,          -- input wire vp_in
    vn_in => vn_in,          -- input wire vn_in
    vauxp6 => JXA(0),        -- input wire vauxp6
    vauxn6 => JXA(4),        -- input wire vauxn6
    vauxp7 => JXA(2),        -- input wire vauxp7
    vauxn7 => JXA(6),        -- input wire vauxn7
    vauxp14 => JXA(1),      -- input wire vauxp14
    vauxn14 => JXA(5),      -- input wire vauxn14
    vauxp15 => JXA(3),      -- input wire vauxp15
    vauxn15 => JXA(7),      -- input wire vauxn15
    channel_out => channel_out, -- output wire [4 : 0] channel_out
    eoc_out => enable,         -- output wire eoc_out
    alarm_out => alarm_out,     -- output wire alarm_out
    eos_out => eos_out,         -- output wire eos_out
    busy_out => busy_out        -- output wire busy_out
  );

----------------------------------------------------------
------              UART                 -------
------  Sine Step_Re Step_Im Step_Re1Step_Im1Sample 
------      S7DA87F73185F5B402BDC4E6F87BFCCD800400000
------      S7FFFFF4D000D5A0D7F4DE4500D53DB9200400000
-- Triangle  Sta Sto StepRepeat	
-- 			T0000FFFF00010000
----------------------------------------------------------
   -- instantiate uart
   uart_unit: uart_mem
   port map(
      clk=>CLK,
      reset=>BTN(4),
      RX => RX,
      dtx => dout,
      dataMax => dataMax,         -- block size
      aBuf => addrUart,
      rx_mem => rMem,   -- receive memory
      addr01 => addr01a,         -- Lookup interface DAC
      we01 => we01,
      din01 => din01,
      addr02 => addr02a,        -- Lookup interface ADC
      we02 => we02,
      din02 => din02,
      TX => TX,
      tx_busy => tx_busy -- sending data?
   );


----------------------------------------------------------
------                 I2C                   -------
----------------------------------------------------------
-- reset_n_sig <= not xrst;
reset_n_sig <= '1';
-- Instance of I2C master
i2c_unit: i2c_master
   generic map(
      input_clk => 100_000_000,
      bus_clk   => 400_000
      )
   port map(
      clk => CLK,
      reset_n => reset_n_sig,
      ena => ena_sig,
      addr => addr_sig,
      rw => rw_sig,
      data_wr => data_wr_sig,
      busy => busy_sig,
      data_rd => data_rd_sig,
      ack_error => ack_err_sig,
      sda => SDA,
      scl => SCL
   );
   -- 1. Kontinuierliche Zuweisung des Sinus-Signals an die DAC-Datenbytes
    -- Wir nehmen die relevanten 12 Bit aus mysine (analog zu deinem JB/JC Multiplexer)
   process(mysine)
      variable dac_12bit : std_logic_vector(11 downto 0);
   begin
       -- Wir greifen die oberen 12 Bit des Sinus ab (analog zu deinem JB/JC Konstrukt)
       dac_12bit := mysine(30 downto 19); 
    
       -- 1. Das Command-Byte für Fast Write auf Kanal A
       mcp_cmd       <= "01011000"; -- Festgelegt vom Datenblatt (0x58)
    
       -- 2. Das High-Datenbyte: Die oberen 4 Bits des Sinus (Vorangestellt mit 4 Nullen)
       mcp_data_high <= "0000" & dac_12bit(11 downto 8);
    
       -- 3. Das Low-Datenbyte: Die unteren 8 Bits des Sinus
       mcp_data_low  <= dac_12bit(7 downto 0);
    end process;

    -- 2. Takt-Teiler für die Sende-Frequenz (i2c_tick)
    process(CLK)
    begin
       if rising_edge(CLK) then
          if i2c_cnt = 99999 then  -- Bestimmt, wie oft der I2C-Wert aktualisiert wird
              i2c_cnt  <= 0;
              i2c_tick <= '1';
          else
              i2c_cnt  <= i2c_cnt + 1;
              i2c_tick <= '0';
           end if;
       end if;
    end process;
   
    -- 3. Die korrigierte State Machine (Handshake mit busy_sig)
    process(CLK)
    begin
        if rising_edge(CLK) then
            if reset_n_sig = '0' then
                i2c_state <= IDLE;
                ena_sig <= '0';
            else
                case i2c_state is

                    when IDLE =>
                        ena_sig <= '0';
                        -- Hier einen Timer einbauen oder direkt starten, wenn Master frei ist und der Ticker 1 ist
                        if busy_sig = '0' and i2c_tick = '1' then
                            -- Adresse laden (0x60)
                            addr_sig <= "1100000"; 
                            rw_sig   <= '0'; -- Schreiben
                        
                            -- Ersten Befehl anlegen & Master starten
                            data_wr_sig   <= mcp_cmd; 
                            ena_sig       <= '1';
                            i2c_state <= WAIT_CMD;
                        end if;

                    when WAIT_CMD =>
                        -- Warten, bis der Master die Übertragung registriert hat und busy wird
                        if busy_sig = '1' then
                            i2c_state <= SEND_HIGH;
                        end if;

                    when SEND_HIGH =>
                        -- Nächstes Byte anlegen. Wichtig: ena_sig bleibt '1', 
                        -- damit der Master nach dem ACK ohne STOP-Bit weiterzieht!
                        data_wr_sig   <= mcp_data_high;
                        i2c_state <= WAIT_HIGH;

                    when WAIT_HIGH =>
                        -- Der Digi-Key-Master zieht busy kurz auf '0', wenn er ein Byte fertig hat
                        if busy_sig = '0' then 
                            i2c_state <= SEND_LOW;
                        end if;

                    when SEND_LOW =>
                        -- Letztes Byte anlegen
                        data_wr_sig   <= mcp_data_low;
                        -- WICHTIG: Jetzt ena weglatschen, damit der Master danach ein STOP-Signal erzeugt!
                        ena_sig       <= '0'; 
                        i2c_state <= WAIT_LOW;

                    when WAIT_LOW =>
                        -- Warten, bis das gesamte I2C-Paket auf der Hardware übertragen wurde
                        if busy_sig = '0' then
                            i2c_state <= IDLE; -- Zurück zum Anfang für den nächsten Sinus-Punkt
                        end if;

                    when others =>
                        i2c_state <= IDLE;
                end case;
            end if;
        end if;
    end process;
   

    -- Debug LEDs
    LED(0) <= busy_sig;
    LED(1) <= ack_err_sig;


----------------------------------------------------------
------              Triangle                 -------
----------------------------------------------------------
tri_unit: tri_counter
   port map(
      clk => CLK,
      reset => xrst,
      start => tstart, 
      stop => tstop,
      step => tstep ,
      repeat=> trepeat,
      q => tout
   );
   -- 16 Bit each
tstart <= rMem(179 downto 176)&rMem(183 downto 180)
               &rMem(187 downto 184)&rMem(191 downto 188);
tstop <= rMem(195 downto 192)&rMem(199 downto 196)
              &rMem(203 downto 200)&rMem(207 downto 204);
tstep <= rMem(211 downto 208)&rMem(215 downto 212)
              &rMem(219 downto 216)&rMem(223 downto 220);
trepeat <= rMem(227 downto 224)&rMem(231 downto 228)
              &rMem(235 downto 232)&rMem(239 downto 236)
              &rMem(243 downto 240)&rMem(247 downto 244)
              &rMem(251 downto 248)&rMem(255 downto 252);

----------------------------------------------------------
------              Sine                 -------
----------------------------------------------------------
--     step <=  x"00220000";
-- amplitude <= x"40000000";
--   offset <= x"20000000";
-- 512 FFT values in range of 400000000..000000000 with 17 periods
-- 

xrst <= BTN(4) or rMem(14); -- sine needs initialization of step

 
sine_unit: sineX                 -- Sine generator
   Port map (
       CLK => CLK,
       RST => xrst,
       step => step,             -- increment
       amplitude=> amplitude,    -- signal amplitude
       offset => offset,         -- signal offset
       mysine => mysine          -- output waveform (31 downto 0) 32 bits
   );

step     <=   rMem(19 downto 16)&rMem(23 downto 20)
             &rMem(27 downto 24)&rMem(31 downto 28)
             &rMem(35 downto 32)&rMem(39 downto 36)
             &rMem(43 downto 40)&rMem(47 downto 44);
amplitude <=  rMem(51 downto 48)&rMem(55 downto 52)
             &rMem(59 downto 56)&rMem(63 downto 60)
             &rMem(67 downto 64)&rMem(71 downto 68)
             &rMem(75 downto 72)&rMem(79 downto 76);
offset <=     rMem(83 downto 80)&rMem(87 downto 84)
             &rMem(91 downto 88)&rMem(95 downto 92)
             &rMem(99 downto 96)&rMem(103 downto 100)
             &rMem(107 downto 104)&rMem(111 downto 108);


 CLKDIV0: CLK_DIV port map (
    CLK =>CLK,
    RST =>BTN(4),
    EN_2 =>EN_2,
    EN_4 =>EN_4,
    EN_8 =>EN_8,
    EN_16 =>EN_16,
    EN_32 =>EN_32,
    EN_64 =>EN_64,
    EN_128 =>EN_128,
    EN_256 =>EN_256
);
              
-- enSIN <= EN_256;
             
end Behavioral;

