library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.livt_lang_icontext_package.all;

entity receiver_tolerance is
    generic (CLOCK_HZ: positive := 100000000; PEER_PPM: integer := 0;
             PHASE_QUARTERS: natural := 0; SCENARIO: natural := 0);
end;

architecture test of receiver_tolerance is
    constant BAUD_HZ: positive := 1000000;
    constant CLOCK_PERIOD: time := 2 * (1 sec / CLOCK_HZ / 2);
    constant PEER_PERIOD: time := 1 sec / (BAUD_HZ + PEER_PPM);
    type bytes is array(natural range <>) of std_logic_vector(7 downto 0);
    constant DATA: bytes := (x"00", x"FF", x"55", x"AA", x"81", x"7E", x"A3", x"5C");
    signal clk: std_logic := '0';
    signal rst: std_logic := '1';
    signal rx: std_logic := '1';
    signal rx_valid, rx_error: std_logic;
    signal rx_byte: std_logic_vector(7 downto 0);
    signal received, errors: natural := 0;
    signal allow_error: boolean := false;
    signal context_value: t_icontext_in;
begin
    clk <= not clk after CLOCK_PERIOD / 2;
    context_value <= (clk => clk, rst => rst, tickspersecond => to_unsigned(CLOCK_HZ, 32),
        periodns => to_unsigned(CLOCK_PERIOD / 1 ns, 32),
        hightimens => to_unsigned(CLOCK_PERIOD / 2 / 1 ns, 32),
        lowtimens => to_unsigned(CLOCK_PERIOD / 2 / 1 ns, 32));
    dut: entity work.livt_io_timingverification_root1000000
        port map (ctor_lvt_context_in => context_value, ctor_rx => rx,
            ctor_tx => open, ctor_txvalid => '0', ctor_txbyte => x"00",
            ctor_txactive => open, ctor_txdone => open,
            ctor_rxvalid => rx_valid, ctor_rxbyte => rx_byte, ctor_rxerror => rx_error);

    observe: process
    begin
        wait until rising_edge(rx_valid);
        assert received < DATA'length report "duplicated receive" severity failure;
        assert rx_byte = DATA(received) report "wrong byte or unexpected receive" severity failure;
        received <= received + 1;
    end process;

    observe_errors: process
    begin
        wait until rising_edge(rx_error);
        assert allow_error report "unexpected framing error" severity failure;
        errors <= errors + 1;
    end process;

    stimulus: process
        procedure send_byte(value: std_logic_vector(7 downto 0);
                            valid_stop: boolean := true; disturb: boolean := false) is
        begin
            rx <= '0'; wait for PEER_PERIOD;
            for bit_index in 0 to 7 loop
                rx <= value(bit_index);
                if disturb then
                    -- One-clock glitch early in each bit, away from its center.
                    wait for PEER_PERIOD / 8;
                    rx <= not value(bit_index);
                    wait for CLOCK_PERIOD;
                    rx <= value(bit_index);
                    wait for PEER_PERIOD - PEER_PERIOD / 8 - CLOCK_PERIOD;
                elsif SCENARIO = 5 then
                    -- Alternating edge displacement: no accumulating drift.
                    if bit_index mod 2 = 0 then
                        wait for PEER_PERIOD - CLOCK_PERIOD;
                    else
                        wait for PEER_PERIOD + CLOCK_PERIOD;
                    end if;
                else
                    wait for PEER_PERIOD;
                end if;
            end loop;
            if valid_stop then rx <= '1'; else rx <= '0'; end if;
            wait for PEER_PERIOD;
        end procedure;
    begin
        wait for 20 * CLOCK_PERIOD;
        rst <= '0';
        wait for 2 * PEER_PERIOD + PHASE_QUARTERS * CLOCK_PERIOD / 4;
        if SCENARIO = 1 then
            rx <= '0'; wait for PEER_PERIOD / 8; rx <= '1';
            wait for 2 * PEER_PERIOD;
            assert received = 0 report "short start glitch accepted" severity failure;
        elsif SCENARIO = 3 then
            allow_error <= true;
            send_byte(x"C3", false);
            rx <= '1'; wait for 3 * PEER_PERIOD;
            assert received = 0 report "invalid stop accepted" severity failure;
            assert errors > 0 report "missing framing error" severity failure;
            allow_error <= false;
        elsif SCENARIO = 4 then
            allow_error <= true;
            rx <= '0'; wait for 30 * PEER_PERIOD;
            assert received = 0 report "break generated a valid byte" severity failure;
            assert errors > 0 report "break did not report framing error" severity failure;
            rx <= '1'; wait for 12 * PEER_PERIOD;
            allow_error <= false;
        end if;
        for frame in DATA'range loop
            send_byte(DATA(frame), true, SCENARIO = 2);
        end loop;
        wait for 3 * PEER_PERIOD;
        assert received = DATA'length report "lost receive" severity failure;
        report "UART_RECEIVER_PASS";
        finish;
    end process;
    watchdog: process
    begin
        wait for 200 us;
        assert false report "receiver watchdog" severity failure;
    end process;
end;
