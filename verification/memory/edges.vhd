library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;

entity ram_edges is end;
architecture test of ram_edges is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal ctx : t_icontext_in;
    signal enable, write_enable : boolean := false;
    signal address : std_logic_vector(1 downto 0) := "00";
    signal data, sync_result, async_result : std_logic_vector(15 downto 0) := x"0000";
    signal fixed_address : std_logic_vector(3 downto 0);
    signal fixed_data, fixed_result : std_logic_vector(31 downto 0);
begin
    clk <= not clk after 5 ns;
    ctx <= (clk, rst, to_unsigned(100000000, 32), to_unsigned(10, 32),
        to_unsigned(5, 32), to_unsigned(5, 32));
    synchronous_ram : entity work.@SYNC@
        port map(ctor_lvt_context_in => ctx, ctor_enable => enable,
            ctor_writeenable => write_enable, ctor_address => address,
            ctor_writedata => data, ctor_readdata => sync_result);
    asynchronous_ram : entity work.@ASYNC@
        port map(ctor_lvt_context_in => ctx, ctor_writeenable => write_enable,
            ctor_address => address, ctor_writedata => data, ctor_readdata => async_result);
    fixed_address <= "00" & address;
    fixed_data <= data & data;
    fixed_ram : entity work.livt_io_asynchronousdistributedram32x16
        port map(ctor_lvt_context_in => ctx, ctor_writeenable => write_enable,
            ctor_address => fixed_address, ctor_writedata => fixed_data,
            ctor_readdata => fixed_result);

    process
    begin
        wait until falling_edge(clk);
        rst <= '0'; enable <= true; write_enable <= true; data <= x"8012";
        wait until rising_edge(clk); wait for 1 ns;
        assert async_result = x"8012" report "First write edge" severity failure;
        assert fixed_result = x"80128012" report "Inherited specialization first write edge" severity failure;
        assert sync_result = x"0000" report "Write must hold read response" severity failure;
        wait until falling_edge(clk); address <= "10"; data <= x"7EA5";
        wait until rising_edge(clk); wait for 1 ns;
        assert async_result = x"7EA5" report "Consecutive write acceptance" severity failure;
        assert fixed_result = x"7EA57EA5" report "Inherited specialization consecutive writes" severity failure;
        wait until falling_edge(clk); write_enable <= false; address <= "00";
        wait for 1 ns;
        assert async_result = x"8012" report "Read must be combinational" severity failure;
        assert fixed_result = x"80128012" report "Inherited specialization combinational read" severity failure;
        assert sync_result = x"0000" report "Read must wait for its edge" severity failure;
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"8012" report "One-edge response" severity failure;
        wait until falling_edge(clk); address <= "10";
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"7EA5" report "Consecutive read acceptance" severity failure;
        wait until falling_edge(clk); enable <= false; address <= "00";
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"7EA5" report "Disabled output hold" severity failure;
        wait until falling_edge(clk); rst <= '1'; write_enable <= true; data <= x"FFFF";
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"0000" report "Response reset" severity failure;
        assert async_result = x"8012" report "Reset suppresses writes and retains cells" severity failure;
        assert fixed_result = x"80128012" report "Inherited specialization reset retention" severity failure;
        wait until falling_edge(clk); rst <= '0'; enable <= true; write_enable <= false;
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"8012" report "Synchronous payload survives reset" severity failure;
        wait until falling_edge(clk); address <= "11"; write_enable <= true; data <= x"1234";
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"8012" report "Invalid write holds response" severity failure;
        assert async_result = x"0000" report "Invalid asynchronous address returns zero" severity failure;
        wait until falling_edge(clk); write_enable <= false;
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"8012" report "Invalid read holds response" severity failure;
        wait until falling_edge(clk); address <= "00";
        wait until rising_edge(clk); wait for 1 ns;
        assert sync_result = x"8012" and async_result = x"8012"
            report "Invalid writes must not alias cell zero" severity failure;
        report "Simulation finished: RAM edge contracts verified";
        std.env.finish;
    end process;

    process
    begin
        wait for 1 us;
        assert false report "RAM edge test timed out" severity failure;
    end process;
end;
