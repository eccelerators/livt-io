library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;
use work.livt_io_@RAMTYPE@_package.all;

entity ram_scheduled is end;
architecture test of ram_scheduled is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal ctx : t_icontext_in;
  signal read_request : t_@RAMTYPE@_read_in := (run => '0', address => to_signed(0, 32));
  signal read_response : t_@RAMTYPE@_read_out;
  signal write_request : t_@RAMTYPE@_write_in := (run => '0', address => to_signed(0, 32), value => x"00");
  signal write_response : t_@RAMTYPE@_write_out;
begin
  clk <= not clk after 5 ns;
  ctx <= (clk, rst, to_unsigned(100000000, 32), to_unsigned(10, 32),
          to_unsigned(5, 32), to_unsigned(5, 32));
  dut: entity work.@RAM@
    port map(ctor_lvt_context_in => ctx,
      read_in => read_request, read_out => read_response,
      write_in => write_request, write_out => write_response,
      isvalidaddress_in => (run => '0', address => to_signed(0, 32)),
      isvalidaddress_out => open);

  process begin
    wait for 50 us;
    assert false report "Scheduled RAM timed out" severity failure;
  end process;

  process
    procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
    procedure reset(cycles: positive) is begin
      wait until falling_edge(clk); rst <= '1';
      read_request.run <= '0'; write_request.run <= '0';
      for i in 1 to cycles loop tick; end loop;
      assert read_response.busy = '0' and write_response.busy = '0'
        report "Reset did not cancel scheduled calls" severity failure;
      wait until falling_edge(clk); rst <= '0';
    end;
    procedure write_cell(address: integer; value: natural) is
      variable cycles: natural := 1;
    begin
      wait until falling_edge(clk);
      write_request <= (run => '1', address => to_signed(address, 32), value => std_logic_vector(to_unsigned(value, 8)));
      tick;
      wait until falling_edge(clk); write_request.run <= '0';
      for cycle in 1 to 8 loop
        tick; cycles := cycles + 1;
        exit when write_response.busy = '1';
        assert cycle < 8 report "Write request was not accepted" severity failure;
      end loop;
      while write_response.busy = '1' loop
        tick; cycles := cycles + 1;
        assert cycles < 100 report "Write failed to complete" severity failure;
      end loop;
      report "Write request-edge-to-completion cycles: " & integer'image(cycles - 1);
      if address >= 0 and address < 3 then
        assert cycles - 1 = 19 report "Valid write latency changed" severity failure;
      else
        assert cycles - 1 = 15 report "Invalid write latency changed" severity failure;
      end if;
    end;
    procedure read_cell(address: integer; expected: natural) is
      variable cycles: natural := 1;
    begin
      wait until falling_edge(clk);
      read_request <= (run => '1', address => to_signed(address, 32));
      tick;
      wait until falling_edge(clk); read_request.run <= '0';
      for cycle in 1 to 8 loop
        tick; cycles := cycles + 1;
        exit when read_response.busy = '1';
        assert cycle < 8 report "Read request was not accepted" severity failure;
      end loop;
      while read_response.busy = '1' loop
        tick; cycles := cycles + 1;
        assert cycles < 100 report "Read failed to complete" severity failure;
      end loop;
      assert read_response.return_value = std_logic_vector(to_unsigned(expected, 8))
        report "Wrong scheduled read payload" severity failure;
      report "Read request-edge-to-completion cycles: " & integer'image(cycles - 1);
      if address >= 0 and address < 3 then
        assert cycles - 1 = 21 report "Valid read latency changed" severity failure;
      else
        assert cycles - 1 = 16 report "Invalid read latency changed" severity failure;
      end if;
    end;
    procedure compete(value: natural; expected_read: natural) is
    begin
      wait until falling_edge(clk);
      read_request <= (run => '1', address => to_signed(0, 32));
      write_request <= (run => '1', address => to_signed(0, 32), value => std_logic_vector(to_unsigned(value, 8)));
      tick;
      wait until falling_edge(clk); read_request.run <= '0'; write_request.run <= '0';
      for cycle in 1 to 8 loop
        tick;
        exit when read_response.busy = '1' and write_response.busy = '1';
        assert cycle < 8 report "Competing requests were not accepted" severity failure;
      end loop;
      for cycle in 1 to 150 loop
        tick;
        exit when read_response.busy = '0' and write_response.busy = '0';
        assert cycle < 150 report "Competing requests starved" severity failure;
      end loop;
      assert read_response.return_value = std_logic_vector(to_unsigned(expected_read, 8))
        report "Simultaneous read/write ordering or read capture changed" severity failure;
    end;
  begin
    reset(1);
    write_cell(0, 16#12#);
    -- A previous write gives a simultaneous pending read priority.
    compete(16#34#, 16#12#);
    read_cell(0, 16#34#);
    -- A previous read gives a simultaneous pending write priority.
    compete(16#56#, 16#56#);
    read_cell(0, 16#56#);
    write_cell(2, 16#A5#);
    write_cell(-1, 16#FF#); write_cell(3, 16#FF#);
    read_cell(-1, 0); read_cell(3, 0); read_cell(2, 16#A5#);

    -- Reset immediately after acceptance, before the request reaches storage.
    wait until falling_edge(clk);
    write_request <= (run => '1', address => to_signed(2, 32), value => x"FF");
    tick;
    wait until falling_edge(clk); write_request.run <= '0';
    for cycle in 1 to 8 loop
      tick;
      exit when write_response.busy = '1';
      assert cycle < 8 severity failure;
    end loop;
    reset(1);
    read_cell(2, 16#A5#);
    -- A cancelled read must not leave a pending handshake after restart.
    wait until falling_edge(clk);
    read_request <= (run => '1', address => to_signed(2, 32));
    tick;
    wait until falling_edge(clk); read_request.run <= '0';
    for cycle in 1 to 8 loop
      tick;
      exit when read_response.busy = '1';
      assert cycle < 8 severity failure;
    end loop;
    reset(3);
    read_cell(0, 16#56#);
    write_cell(2, 16#80#); read_cell(2, 16#80#);
    report "Simulation finished: scheduled RAM arbitration, bounds and reset verified";
    std.env.finish;
  end process;
end;
