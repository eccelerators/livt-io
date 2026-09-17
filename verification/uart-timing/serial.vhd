library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.livt_lang_icontext_package.all;

entity serial_timing is
    generic (CLOCK_HZ: positive := 100000000; BAUD_HZ: positive := 115200;
             RX_PHASE_QUARTERS: natural := 1);
end;
architecture test of serial_timing is
    -- Use two representable half-periods, including clocks such as 12 MHz.
    constant CLOCK_PERIOD: time := 2 * (1 sec / CLOCK_HZ / 2);
    constant TICKS: positive := (CLOCK_HZ + BAUD_HZ / 2) / BAUD_HZ;
    constant BIT_PERIOD: time := TICKS * CLOCK_PERIOD;
    -- Peer stimulus uses ideal requested baud, not the DUT's rounded tick count.
    constant PEER_BIT_PERIOD: time := 1 sec / BAUD_HZ;
    signal clk: std_logic := '0';
    signal rst: std_logic := '1';
    signal rx: std_logic := '1';
    signal tx, tx_active, tx_done, rx_valid, rx_error: std_logic;
    signal tx_request: std_logic := '0';
    signal rx_byte: std_logic_vector(7 downto 0);
    signal request_time: time := 0 ns;
    signal tx_checked: boolean := false;
    signal rx_count: natural := 0;
    signal context_value: t_icontext_in;
begin
    clk <= not clk after CLOCK_PERIOD / 2;
    rst <= '0' after 20 * CLOCK_PERIOD;
    context_value <= (clk => clk, rst => rst, tickspersecond => to_unsigned(CLOCK_HZ, 32),
        periodns => to_unsigned(CLOCK_PERIOD / 1 ns, 32),
        hightimens => to_unsigned(CLOCK_PERIOD / 2 / 1 ns, 32),
        lowtimens => to_unsigned(CLOCK_PERIOD / 2 / 1 ns, 32));
    -- DUT_INSTANCES

    transmit: process
    begin
        wait until rst = '0';
        wait for BIT_PERIOD;
        for frame in 1 to 2 loop
            wait until falling_edge(clk);
            tx_request <= '1'; request_time <= now;
            wait until falling_edge(clk);
            tx_request <= '0';
            wait until rising_edge(tx_done);
            wait until tx_active = '0';
        end loop;
        wait;
    end process;

    check_transmit: process
        variable start_time, previous_start: time := 0 ns;
        constant DATA: std_logic_vector(7 downto 0) := x"55";
    begin
        wait until rst = '0';
        for frame in 1 to 2 loop
            wait until falling_edge(tx);
            start_time := now;
            report "UART_METRIC request_to_start_cycles=" & integer'image((now - request_time) / CLOCK_PERIOD);
            if frame = 2 then
                report "UART_METRIC start_to_start_cycles=" & integer'image((now - previous_start) / CLOCK_PERIOD);
                report "UART_METRIC interframe_gap_cycles=" & integer'image((now - previous_start - 10 * BIT_PERIOD) / CLOCK_PERIOD);
            end if;
            previous_start := now;
            -- 0x55 alternates on every data boundary, including start/stop.
            for boundary in 1 to 9 loop
                wait on tx;
                assert now - start_time = boundary * BIT_PERIOD report "Wrong bit duration" severity failure;
                if boundary mod 2 = 1 then
                    assert tx = '1' report "Wrong transmitted bit" severity failure;
                else
                    assert tx = '0' report "Wrong transmitted bit" severity failure;
                end if;
            end loop;
            report "UART_METRIC bit_cycles=" & integer'image(TICKS);
            report "UART_METRIC frame_cycles=" & integer'image(10 * TICKS);
            wait for BIT_PERIOD / 2;
            assert tx = '1' report "Invalid stop bit" severity failure;
        end loop;
        tx_checked <= true;
        wait;
    end process;

    receive: process
        procedure send_byte(data: std_logic_vector(7 downto 0)) is
        begin
            rx <= '0'; wait for PEER_BIT_PERIOD;
            for i in 0 to 7 loop
                rx <= data(i); wait for PEER_BIT_PERIOD;
            end loop;
            rx <= '1'; wait for PEER_BIT_PERIOD;
        end procedure;
    begin
        wait until rst = '0';
        -- Offset peer edges from the DUT clock; never feed it its own TX line.
        wait for BIT_PERIOD + RX_PHASE_QUARTERS * CLOCK_PERIOD / 4;
        send_byte(x"55");
        send_byte(x"A3");
        wait for BIT_PERIOD;
        assert rx_count = 2 report "Lost or duplicated receive" severity failure;
        if not tx_checked then wait until tx_checked for 20 * BIT_PERIOD; end if;
        assert tx_checked report "Transmit did not finish" severity failure;
        report "UART_MATRIX_PASS";
        finish;
    end process;

    check_receive: process
    begin
        wait until rising_edge(rx_valid);
        if rx_count = 0 then
            assert rx_byte = x"55" report "First receive differs" severity failure;
        elsif rx_count = 1 then
            assert rx_byte = x"A3" report "Second receive differs" severity failure;
        else
            assert false report "Unexpected extra receive" severity failure;
        end if;
        rx_count <= rx_count + 1;
    end process;

    check_error: process(clk)
    begin
        if rising_edge(clk) and rst = '0' then
            assert rx_error /= '1' report "Unexpected framing error" severity failure;
        end if;
    end process;
    watchdog: process
    begin
        wait for 50 * BIT_PERIOD;
        assert false report "UART matrix timed out" severity failure;
    end process;
end;
