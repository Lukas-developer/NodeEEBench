library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master_tb is
end entity;

architecture sim of i2c_master_tb is
    -- Clock / Control
    signal clk_tb       : std_logic := '0';
    signal reset_n_tb   : std_logic := '0';
    signal ena_tb       : std_logic := '0';
    
    -- I2C Interface
    signal addr_tb      : std_logic_vector(6 downto 0) := "1100000";
    signal rw_tb        : std_logic := '0';
    signal data_wr_tb   : std_logic_vector(7 downto 0) := x"99";
    signal busy_tb      : std_logic;
    signal data_rd_tb   : std_logic_vector(7 downto 0);
    signal ack_error_tb : std_logic;
    
    -- Offene Kollektorleitungen (mit Pull-Up 'H')
    signal sda_tb       : std_logic := 'H';
    signal scl_tb       : std_logic := 'H';
    
    signal sda_slave    : std_logic := 'H';
    signal sda_master   : std_logic := 'H';
    signal scl_master   : std_logic := 'H'; -- Falls dein Master SCL aktiv treibt
    
    constant SLAVE_DATA : std_logic_vector(7 downto 0) := x"CC";
    
    type state_t is (IDLE, ADDR_BITS, ACK_ADDR, WRITE_BITS, READ_BITS, ACK_WRITE, WAIT_ACK_READ);
    signal state     : state_t := IDLE;
    signal bit_cnt   : integer range 0 to 7 := 7;
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal rw_bit    : std_logic := '0';
    
    signal start_detected  : std_logic ;
    signal stop_detected   : std_logic ;
    
begin

    -- Taktgenerator (100 MHz)
    clk_tb <= not clk_tb after 5 ns;

    ----------------------------------------------------
    -- WIRED-AND / OPEN-DRAIN EMULATION
    ----------------------------------------------------
    sda_tb <= '0' when sda_master = '0' else
              '0' when sda_slave = '0' else
              'H';

    -- WICHTIG: Falls dein Master SCL als Open-Drain ausgibt, hier verknüpfen!
    scl_tb <= '0' when scl_master = '0' else 'H';

    ----------------------------------------------------
    -- DUT Instanziierung
    ----------------------------------------------------
    dut : entity work.i2c_master
        generic map (
            input_clk => 100_000_000,
            bus_clk   => 400_000
        )
        port map (
            clk       => clk_tb,
            reset_n   => reset_n_tb,
            ena       => ena_tb,
            addr      => addr_tb,
            rw        => rw_tb,
            data_wr   => data_wr_tb,
            busy      => busy_tb,
            data_rd   => data_rd_tb,
            ack_error => ack_error_tb,
            sda       => sda_master,
            scl       => scl_master
        );

    ----------------------------------------------------
    -- SDA Monitor
    ----------------------------------------------------
    process(sda_tb)
    begin
        report "[MONITOR] SDA changed to " & std_logic'image(sda_tb) & " at " & time'image(now);
    end process;

    ----------------------------------------------------
    -- SCL Monitor (Hilft zu sehen, ob der Master stoppt!)
    ----------------------------------------------------
    process(scl_tb)
    begin
        report "[MONITOR] SCL changed to " & std_logic'image(scl_tb) & " at " & time'image(now);
    end process;

    
    ----------------------------------------------------
    -- 1. Separater, robuster START/STOP Detektor
    ----------------------------------------------------
    process(sda_tb, reset_n_tb)
    begin
        if reset_n_tb = '0' then
            start_detected <= '0';
            stop_detected  <= '0';
        else
            -- START: SDA fällt, während SCL HIGH ist
            -- Wichtig: Nur im IDLE erlauben, um Fehltrigger während ACKs zu verhindern
            if falling_edge(sda_tb) and (scl_tb = '1' or scl_tb = 'H') then
                if state = IDLE then
                    start_detected <= '1';
                end if;
            else
                start_detected <= '0';
            end if;

            -- STOP: SDA steigt, während SCL HIGH ist
            if rising_edge(sda_tb) and (scl_tb = '1' or scl_tb = 'H') then
                stop_detected <= '1';
            else
                stop_detected <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------
    -- 2. Rein synchrone, flankengesteuerte Slave FSM
    ----------------------------------------------------
    process(scl_tb, reset_n_tb, start_detected, stop_detected)
    begin
        if reset_n_tb = '0' then
            state     <= IDLE;
            sda_slave <= 'H';
            bit_cnt   <= 7;
            shift_reg <= (others => '0');
            rw_bit    <= '0';
        else
            -- Asynchrone Strukturänderungen durch START / STOP
            if start_detected = '1' then
                report "[SLAVE-FSM] >>> VALID START DETECTED <<<";
                state     <= ADDR_BITS;
                bit_cnt   <= 7;
                sda_slave <= 'H';
            elsif stop_detected = '1' then
                report "[SLAVE-FSM] >>> STOP DETECTED <<<";
                state     <= IDLE;
                sda_slave <= 'H';
            
            -- Synchrone Verarbeitung bei SCL-Flanken
            elsif rising_edge(scl_tb) then
                case state is
                    when ADDR_BITS =>
                        shift_reg(bit_cnt) <= to_x01(sda_tb);
                        report "[SLAVE-FSM] Bit " & integer'image(bit_cnt) & " received: " & std_logic'image(sda_tb);
                        if bit_cnt = 0 then
                            rw_bit <= to_x01(sda_tb);
                            state  <= ACK_ADDR;
                        else
                            bit_cnt <= bit_cnt - 1;
                        end if;

                    when READ_BITS =>
                        if bit_cnt = 0 then
                            state <= WAIT_ACK_READ;
                        else
                            bit_cnt <= bit_cnt - 1;
                        end if;

                    when WAIT_ACK_READ =>
                        -- Master sendet ACK ('0') oder NACK ('1'/'H')
                        if sda_tb = '0' then
                            state   <= READ_BITS;
                            bit_cnt <= 7;
                        else
                            state   <= IDLE;
                        end if;

                    when others => null;
                end case;

            elsif falling_edge(scl_tb) then
                case state is
                    when ACK_ADDR =>
                        report "[SLAVE-FSM] Sending ACK for Address. RW-Bit is: " & std_logic'image(rw_bit);
                        sda_slave <= '0'; -- ACK stabil ausgeben
                        bit_cnt   <= 7;
                        if rw_bit = '1' then
                            state <= READ_BITS;
                        else
                            state <= IDLE; -- Falls Write (hier ungenutzt)
                        end if;

                    when READ_BITS =>
                        -- Hier treibt der Slave die Datenleitung bitweise mit x"CC"
                        if SLAVE_DATA(bit_cnt) = '0' then
                            sda_slave <= '0';
                        else
                            sda_slave <= 'H';
                        end if;

                    when WAIT_ACK_READ =>
                        sda_slave <= 'H'; -- Leitung freigeben, damit der Master ACK senden kann

                    when others =>
                        sda_slave <= 'H';
                end case;
            end if;
        end if;
    end process;
    ----------------------------------------------------
    -- Stimulus
    ----------------------------------------------------
    stimulus : process
    begin
        -- Initialer Reset
        reset_n_tb <= '0';
        ena_tb     <= '0';
        wait for 200 ns;
        reset_n_tb <= '1';
        wait for 1000 ns; -- Dem Master etwas Zeit nach dem Reset geben
        
        ------------------------------------------------
        -- READ Test
        ------------------------------------------------
        report "=== READ TEST START ===";
        addr_tb    <= "1010101"; -- 0x55
        rw_tb      <= '1';       -- Read Mode
        ena_tb     <= '1';       -- Master aktivieren
        
        -- ROBUSTES WARTEN 1: Warte, bis der Master die Arbeit aufnimmt (busy -> '1')
        loop
            wait until rising_edge(clk_tb);
            if busy_tb = '1' then
                exit; -- Master hat gestartet!
            end if;
        end loop;
        
        -- Enable wieder wegnehmen (damit er nach dem Byte stoppt)
        ena_tb <= '0';
        report "[TESTBENCH] Master ist jetzt BUSY. Warte auf Uebertragung...";
        
        -- ROBUSTES WARTEN 2: Warte, bis der Master komplett fertig ist (busy -> '0')
        loop
            wait until rising_edge(clk_tb);
            if busy_tb = '0' then
                exit; -- Master ist fertig!
            end if;
        end loop;
        
        report "[TESTBENCH] Master fertig (BUSY ist '0'). Prüfe Daten...";
        
        -- Prüfungen am Ende der Übertragung
        assert ack_error_tb = '0' 
            report "READ: Unexpected ACK error! Der Slave hat nicht geantwortet." 
            severity error;
            
        assert data_rd_tb = x"CC" 
            report "READ: Data mismatch! Erwartet 0xCC." 
            severity error;
            
        report "=== READ TEST DONE ===";
        
        wait for 5 us;
        report "=== SIMULATION SUCCESSFUL ===";
        std.env.stop;
        wait;
    end process;

end architecture;