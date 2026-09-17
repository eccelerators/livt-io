library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- IMPORTS
entity uart_boundaries is end;
architecture test of uart_boundaries is
    signal clk: std_logic := '0';
    signal rst: std_logic := '1';
    signal context_value: t_icontext_in;
    signal wire: std_logic;
    signal permission: boolean := false;
    signal receive_count: signed(31 downto 0);
    signal frames: natural := 0;
    signal last_byte: std_logic_vector(7 downto 0) := x"00";
    -- DECLARATIONS
begin
    clk <= not clk after 5 ns;
    context_value <= (clk => clk, rst => rst,
        tickspersecond => to_unsigned(100000000, 32), periodns => to_unsigned(10, 32),
        hightimens => to_unsigned(5, 32), lowtimens => to_unsigned(5, 32));
    -- DUT
    -- Independent 8-N-1 decoder; reset intentionally aborts a physical frame.
    monitor: process
        variable position: natural := 0;
        variable data: std_logic_vector(7 downto 0);
    begin
        wait until rising_edge(clk);
        wait for 2 ns;
        if rst = '1' then
            position := 0;
            frames <= 0;
        elsif position = 0 then
            if wire = '0' then position := 1; end if;
        else
            if position = 50 then
                assert wire = '0' report "truncated start bit" severity failure;
            end if;
            for bit_index in 0 to 7 loop
                if position = 150 + bit_index * 100 then data(bit_index) := wire; end if;
            end loop;
            if position = 950 then
                assert wire = '1' report "invalid stop bit / truncated frame" severity failure;
                last_byte <= data;
                frames <= frames + 1;
            end if;
            if position = 999 then position := 0; else position := position + 1; end if;
        end if;
    end process;
    stimulus: process
        variable clear_seen, previous_frame: boolean;
        variable accepted: boolean;
        variable remaining: natural;
        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 3 ns;
        end;
        procedure reset_base is
        begin
            wait until falling_edge(clk);
            rst <= '1';
            permission <= false;
            trytransmit_in.run <= '0';
            tryreceive_in.run <= '0';
            cleartransmitbuffer_in.run <= '0';
            clearreceivebuffer_in.run <= '0';
            tick;
            tick;
            assert wire = '1' report "TX must be idle-high during reset" severity failure;
            assert trytransmit_out.busy = '0' and tryreceive_out.busy = '0'
                and cleartransmitbuffer_out.busy = '0'
                and clearreceivebuffer_out.busy = '0'
                report "reset did not release methods" severity failure;
            wait until falling_edge(clk);
            rst <= '0';
            tick;
        end;
        procedure call_method(signal run: out std_logic; signal busy: in std_logic;
                              label_text: string; measure: boolean := false) is
            variable seen: boolean := false;
        begin
            wait until falling_edge(clk);
            run <= '1';
            for cycles in 1 to 96 loop
                tick;
                run <= '0';
                if busy = '1' then seen := true; end if;
                if seen and busy = '0' then
                    if measure then report "MEASURE " & label_text & " cycles=" & integer'image(cycles); end if;
                    return;
                end if;
            end loop;
            assert false report "method completion timeout: " & label_text severity failure;
        end;
        procedure enqueue(data: std_logic_vector(7 downto 0)) is
        begin
            trytransmit_in.data <= data;
            call_method(trytransmit_in.run, trytransmit_out.busy, "transmit");
            assert trytransmit_out.return_value report "enqueue rejected" severity failure;
        end;
    begin
        reset_base;
        trytransmit_in.data <= x"A5";
        call_method(trytransmit_in.run, trytransmit_out.busy, "transmit", true);
        call_method(cleartransmitbuffer_in.run, cleartransmitbuffer_out.busy, "clear_tx", true);
        call_method(tryreceive_in.run, tryreceive_out.busy, "empty_receive", true);
        assert not tryreceive_out.return_value and tryreceive_out.data = x"00" severity failure;
        call_method(clearreceivebuffer_in.run, clearreceivebuffer_out.busy, "clear_rx", true);

        -- Move permission across the clear-request pipeline one edge at a time.
        previous_frame := true;
        for offset in 0 to 24 loop
            reset_base;
            enqueue(x"A5");
            enqueue(x"5A");
            enqueue(x"3C");
            wait until falling_edge(clk);
            cleartransmitbuffer_in.run <= '1';
            clear_seen := false;
            for phase in 0 to 1200 loop
                if phase = offset then permission <= true; end if;
                tick;
                cleartransmitbuffer_in.run <= '0';
                if cleartransmitbuffer_out.busy = '1' then clear_seen := true; end if;
                wait until falling_edge(clk);
            end loop;
            assert clear_seen and cleartransmitbuffer_out.busy = '0' severity failure;
            assert frames <= 1 report "clear allowed a second queued frame" severity failure;
            if frames = 1 then
                assert previous_frame report "non-monotonic launch/clear boundary" severity failure;
                assert last_byte = x"A5" report "committed byte corrupted" severity failure;
            else previous_frame := false;
            end if;
            if offset = 0 then assert frames = 1 report "initial launch did not commit" severity failure; end if;
            if offset = 24 then assert frames = 0 report "clear did not suppress late launch" severity failure; end if;
            assert receive_count = to_signed(frames, 32) report "loopback count differs" severity failure;
            report "LAUNCH_CLEAR offset=" & integer'image(offset) & " frames=" & integer'image(frames);
        end loop;

        -- Abort pending API operations at every relevant pipeline phase.
        for operation in 0 to 3 loop
            for offset in 0 to 24 loop
                reset_base;
                enqueue(x"11");
                wait until falling_edge(clk);
                case operation is
                    when 0 => trytransmit_in.data <= x"22"; trytransmit_in.run <= '1';
                    when 1 => tryreceive_in.run <= '1';
                    when 2 => cleartransmitbuffer_in.run <= '1';
                    when others => clearreceivebuffer_in.run <= '1';
                end case;
                for phase in 1 to offset loop
                    tick;
                    trytransmit_in.run <= '0'; tryreceive_in.run <= '0';
                    cleartransmitbuffer_in.run <= '0'; clearreceivebuffer_in.run <= '0';
                end loop;
                reset_base;
                for settle in 1 to 40 loop tick; end loop;
                assert wire = '1' and receive_count = 0 report "reset left visible work" severity failure;
                call_method(gettransmitspace_in.run, gettransmitspace_out.busy, "reset_space");
                assert gettransmitspace_out.return_value = 3 report "stale queued TX after reset" severity failure;
                enqueue(x"96");
                permission <= true;
                for settle in 1 to 1200 loop tick; end loop;
                assert frames = 1 and last_byte = x"96" report "reset recovery TX failed" severity failure;
                call_method(tryreceive_in.run, tryreceive_out.busy, "recovery_receive");
                assert tryreceive_out.return_value and tryreceive_out.data = x"96"
                    report "reset recovery RX failed" severity failure;
                assert receive_count = 0 severity failure;
            end loop;
        end loop;
        -- Reset during each part of an actual frame, then verify fresh traffic.
        for part in 0 to 10 loop
            reset_base;
            enqueue(x"A5");
            permission <= true;
            for phase in 1 to 1 + part * 100 loop tick; end loop;
            reset_base;
            for settle in 1 to 1100 loop tick; end loop;
            assert wire = '1' and frames = 0 and receive_count = 0
                report "reset retained physical-frame work" severity failure;
            enqueue(x"69");
            permission <= true;
            for settle in 1 to 1200 loop tick; end loop;
            assert frames = 1 and last_byte = x"69" severity failure;
            call_method(tryreceive_in.run, tryreceive_out.busy, "frame_reset_receive");
            assert tryreceive_out.return_value and tryreceive_out.data = x"69" severity failure;
        end loop;
        -- Sweep application receive/clear across arrival into an already full RX FIFO.
        for operation in 0 to 1 loop
            for offset in 0 to 60 loop
                reset_base;
                enqueue(x"11"); enqueue(x"22"); enqueue(x"33");
                permission <= true;
                for phase in 1 to 3400 loop tick; end loop;
                assert receive_count = 3 severity failure;
                permission <= false;
                enqueue(x"44");
                permission <= true;
                wait until falling_edge(wire);
                for phase in 1 to 930 + offset loop tick; end loop;
                if operation = 0 then
                    call_method(clearreceivebuffer_in.run, clearreceivebuffer_out.busy, "arrival_clear");
                else
                    call_method(tryreceive_in.run, tryreceive_out.busy, "arrival_pop");
                    assert tryreceive_out.return_value and tryreceive_out.data = x"11"
                        report "arrival contention lost old head" severity failure;
                end if;
                for phase in 1 to 150 loop tick; end loop;
                remaining := to_integer(receive_count);
                if operation = 0 then
                    assert remaining <= 1 report "RX clear retained old data" severity failure;
                    if offset = 0 then assert remaining = 1 severity failure; end if;
                    if offset = 60 then assert remaining = 0 severity failure; end if;
                    if remaining = 1 then
                        call_method(tryreceive_in.run, tryreceive_out.busy, "arrival_new");
                        assert tryreceive_out.return_value and tryreceive_out.data = x"44" severity failure;
                    end if;
                else
                    assert remaining = 2 or remaining = 3 severity failure;
                    if offset = 0 then assert remaining = 3 severity failure; end if;
                    if offset = 60 then assert remaining = 2 severity failure; end if;
                    call_method(getreceiveoverflowcount_in.run, getreceiveoverflowcount_out.busy, "arrival_overflow");
                    assert getreceiveoverflowcount_out.return_value = to_signed(3 - remaining, 32)
                        report "RX rejection and overflow count disagree" severity failure;
                    call_method(tryreceive_in.run, tryreceive_out.busy, "arrival_second");
                    assert tryreceive_out.return_value and tryreceive_out.data = x"22" severity failure;
                    call_method(tryreceive_in.run, tryreceive_out.busy, "arrival_third");
                    assert tryreceive_out.return_value and tryreceive_out.data = x"33" severity failure;
                    if remaining = 3 then
                        call_method(tryreceive_in.run, tryreceive_out.busy, "arrival_fourth");
                        assert tryreceive_out.return_value and tryreceive_out.data = x"44" severity failure;
                    end if;
                end if;
                assert receive_count = 0 severity failure;
                report "RX_ARRIVAL operation=" & integer'image(operation) & " offset=" & integer'image(offset)
                    & " remaining=" & integer'image(remaining);
            end loop;
        end loop;
        -- Full TX FIFO: a launch can free the slot used by the pending enqueue.
        for offset in 0 to 24 loop
            reset_base;
            enqueue(x"11"); enqueue(x"22"); enqueue(x"33");
            wait until falling_edge(clk);
            trytransmit_in.data <= x"44";
            trytransmit_in.run <= '1';
            clear_seen := false;
            for phase in 0 to 1200 loop
                if phase = offset then permission <= true; end if;
                tick;
                trytransmit_in.run <= '0';
                if trytransmit_out.busy = '1' then clear_seen := true; end if;
                wait until falling_edge(clk);
            end loop;
            assert clear_seen and trytransmit_out.busy = '0' severity failure;
            accepted := trytransmit_out.return_value;
            if offset = 0 then assert accepted severity failure; end if;
            if offset = 24 then assert not accepted severity failure; end if;
            call_method(tryreceive_in.run, tryreceive_out.busy, "launch_first");
            assert tryreceive_out.return_value and tryreceive_out.data = x"11" severity failure;
            for phase in 1 to 3400 loop tick; end loop;
            call_method(tryreceive_in.run, tryreceive_out.busy, "launch_second");
            assert tryreceive_out.return_value and tryreceive_out.data = x"22" severity failure;
            call_method(tryreceive_in.run, tryreceive_out.busy, "launch_third");
            assert tryreceive_out.return_value and tryreceive_out.data = x"33" severity failure;
            call_method(tryreceive_in.run, tryreceive_out.busy, "launch_fourth");
            assert tryreceive_out.return_value = accepted severity failure;
            if accepted then
                assert tryreceive_out.data = x"44" and frames = 4 severity failure;
            else
                assert tryreceive_out.data = x"00" and frames = 3 severity failure;
            end if;
            assert receive_count = 0 severity failure;
            report "TX_LAUNCH offset=" & integer'image(offset) & " accepted=" & boolean'image(accepted);
        end loop;
        report "UART_BOUNDARIES_PASS launch_offsets=25 reset_offsets=100 frame_reset_offsets=11 rx_offsets=122 tx_offsets=25";
        std.env.finish;
    end process;
    watchdog: process
    begin
        wait for 12 ms;
        assert false report "watchdog" severity failure;
    end process;
end;
